extends Node

const Main := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/world_simulation.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i: int in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(25).timeout.connect(func(): get_tree().quit(1))
	Session.set_mechanics_lab_active(true)
	var state := Simulation.create_new_game_state()
	state.world_drops = []
	state.player_position = [784.0, 976.0]
	Session.apply_debug_state(state, "world drop scene regression", true)
	var main := Main.instantiate()
	add_child(main)
	await settle()
	var world := main.get_node("World")
	var drops := main.get_node("World/DroppedItems")
	check(drops.get_child_count() == 0, "An empty authoritative drop list must not render a phantom item at (25, 28)")
	Session.state_changed.emit()
	await settle()
	check(drops.get_child_count() == 0, "State refresh must keep the scene free of unregistered drops")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/The_Last_Garden/artifacts/phantom-drop-2026-10-09/cleared-cell.png")
	# Real drops at the reported position must be created, collected by physics,
	# added to inventory exactly once and removed from both state and scene.
	var sim = Session.simulation
	var player = main.get_node("Player")
	for item_id: String in ["core:wood", "core:firewood"]:
		var before: int = int(sim.get_inventory().get(item_id, 0))
		var drop_id := "regression:" + item_id
		sim.state.world_drops.append({
			"drop_id": drop_id, "item_id": item_id, "amount": 1,
			"position": [814.0, 924.0], "source_id": "core:player",
			"expires_at_game_minute": sim.get_elapsed_game_minutes() + 100,
		})
		Session.state_changed.emit()
		await settle()
		check(drops.get_child_count() == 1, "A real drop must have exactly one scene view: " + item_id)
		var view = world._drop_views.get(drop_id)
		check(view != null and view.drop_id == drop_id, "Real view must carry its authoritative ID")
		sim.set_player_position(Vector2(814, 924))
		player.apply_loaded_position()
		await settle()
		check(sim.get_world_drops().is_empty(), "Physics overlap must collect real drop: " + item_id)
		check(int(sim.get_inventory().get(item_id, 0)) == before + 1, "Pickup must add exactly one item: " + item_id)
		check(drops.get_child_count() == 0, "Collected drop must disappear from scene: " + item_id)
		sim.set_player_position(Vector2(784, 976))
		player.apply_loaded_position()
		await settle()
	print("WORLD_DROP_SCENE: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
