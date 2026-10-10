extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")

class ResourceViewProbe extends "res://src/world/interactable_view.gd":
	var configuration_calls: int = 0
	var refresh_calls: int = 0
	func configure(definition: Dictionary) -> void:
		configuration_calls += 1
		super.configure(definition)
	func refresh_from_state(snap: bool = false) -> void:
		refresh_calls += 1
		super.refresh_from_state(snap)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	Session.apply_debug_state(Simulation.create_new_game_state(), "pickup refresh regression", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var world := main.get_node("World") as FirstNightWorld
	var definition := Session.get_surface_trees()[0]
	var tree := ResourceViewProbe.new()
	for index: int in range(world._interactables.size()):
		var original := world._interactables[index]
		if original.object_id != String(definition["id"]):
			continue
		world.remove_child(original)
		original.queue_free()
		world.add_child(tree)
		tree.configure(definition)
		world._interactables[index] = tree
		break
	tree.configuration_calls = 0
	tree.refresh_calls = 0
	var ids := Session.simulation._create_resource_drops("test", "core:wood", 12, Vector2(2000.0, 2000.0))
	for id: String in ids:
		if not bool(Session.try_pickup_world_drop(id).get("success", false)):
			_fail("wood pickup failed")
			return
	if tree.configuration_calls != 0 or tree.refresh_calls != 0:
		_fail("picking up wood updates an unchanged tree %d/%d times" % [tree.configuration_calls, tree.refresh_calls])
		return
	if Session.simulation.get_item_count("core:wood") != 12 or not world._drop_views.is_empty():
		_fail("pickup did not update inventory and remove drop views")
		return
	Session.simulation.try_pickup_item("core:axe", 1)
	Session.assign_hotbar_slot(0, Session.simulation.get_inventory_instance_id("core:axe", 0))
	Session.select_hotbar_slot(0)
	Session.set_player_position(tree.position)
	var player := main.get_node("Player") as PlayerController
	player.global_position = tree.position
	for index: int in range(8):
		if not bool(Session.execute_resource_work("core:player", tree.object_id).get("success", false)):
			_fail("real tree work failed")
			return
	if tree.configuration_calls == 0 or tree.presentation_id != "surface_stump" or tree._blocking_body.collision_layer != 0:
		_fail("resource refresh skipped a felled tree or retained its collider")
		return
	print("PASS: pickup skips unchanged resource views; real felling updates the stump and collider")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
