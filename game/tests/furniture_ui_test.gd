extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for _frame: int in range(count):
		await get_tree().process_frame

func click(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	get_viewport().push_input(motion,true)
	await frames(1)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = motion.position
	event.pressed = true
	get_viewport().push_input(event,true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event,true)
	await frames(2)

func _run() -> void:
	Session._save_store = SaveStore.new("user://furniture_ui_test.json")
	Session.set_paused(true,false)
	Session._start_new_simulation()
	var state: Dictionary = Session.get_state()
	state.day = 2
	state.minute_of_day = 12 * 60
	state.flags.repair_stage = 2
	state.flags.first_night_complete = true
	state.structures.append({"building_id":"core:table","cell":[22,20]})
	state.structures.append({"building_id":"core:chair","cell":[22,21]})
	state.structures.append({"building_id":"core:torch","cell":[24,20]})
	state.structures.append({"building_id":"core:bedroll","cell":[23,21]})
	state.inventory["core:carrot"] = 2
	state.player_energy = 10.0
	state.player_needs.hunger = 30.0
	state.player_needs.restedness = 30.0
	state.player_position = [Content.cell_center(22,22).x,Content.cell_center(22,22).y]
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	var world = main.get_node("World")
	var player = main.get_node("Player")
	Session.set_paused(false,false)
	world._selected_cell = Vector2i(22,21)
	world.interact_with_selection(false)
	await frames()
	var panel = hud._furniture_panel
	check(panel.visible and Session.is_paused(), "World chair interaction opens the furniture modal")
	var carrot_index: int = panel._food_ids.find("core:carrot")
	check(carrot_index >= 0, "Carried carrot appears in the real meal menu")
	if carrot_index >= 0:
		panel._foods.select(carrot_index)
	await click(panel._eat)
	check(Session.simulation.get_item_count("core:carrot") == 1 and Session.get_player_needs().hunger > 50, "Real menu click consumes and feeds exactly one product")
	check(player._visual._sitting and player.position == Session.get_player_position(), "Player presentation follows the occupied chair")
	var energy: float = Session.get_player_energy()
	var restedness: float = Session.get_player_needs().restedness
	await click(panel._rest)
	check(Session.get_player_energy() > energy + 6 and Session.get_player_needs().restedness <= restedness, "Rest button recovers chair energy without sleep debt recovery")
	check(not panel._feedback.text.contains("furniture."), "Furniture feedback is localized")
	for size: Vector2i in [Vector2i(480,270),Vector2i(640,360),Vector2i(960,540)]:
		get_viewport().size = size
		await frames()
		check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "Furniture menu fits " + str(size))
	await screenshot("chair-menu")
	Session.save_game(false)
	await click(panel.get_node("Margin/Column/CloseButton"))
	check(not panel.visible and not Session.is_paused(), "Closing furniture restores the running world")
	Session.set_paused(true,false)
	hud.open_furniture(Vector2i(22,20))
	await frames()
	await click(panel.get_node("Margin/Column/CloseButton"))
	check(Session.is_paused(), "Closing table preserves an existing pause")
	Session.set_paused(false,false)
	Input.action_press("move_down")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_down")
	check(Session.simulation.state.player_furniture_use.is_empty() and not player._visual._sitting and player.position.y > Content.cell_center(22,21).y, "Movement leaves the chair into accessible space")
	Session.load_game()
	Session.set_paused(true,false)
	await frames()
	check(not panel.visible and player._visual._sitting and not Session.simulation.state.player_furniture_use.is_empty(), "Disk reload restores seating and closes stale furniture UI")
	world._selected_cell = Vector2i(23,21)
	world.interact_with_selection(false)
	check(Session.simulation.state.player_furniture_use.is_empty() and player.position == Session.get_player_position() and not player._visual._sitting, "Adjacent bed interaction synchronizes the player after leaving a chair")
	await get_tree().physics_frame
	check(player.position == Session.get_player_position() and Session.simulation.is_navigation_cell_walkable(Session.simulation._world_position_to_cell(player.position)), "Physics cannot restore the old solid chair position after bed rest")
	player.global_position = Content.cell_center(24,19)
	Session.set_player_position(player.global_position)
	player.get_node("Camera2D").position_smoothing_enabled = false
	player.get_node("Camera2D").force_update_scroll()
	Session.simulation.state.minute_of_day = 22 * 60
	Session.time_changed.emit()
	await frames(8)
	check(float(main._lighting_material.get_shader_parameter("night_alpha")) > 0.4, "Night shade remains active")
	check(Session.simulation.is_cell_lit(Vector2i(22,21)), "Torch lights the dining seat")
	await screenshot("torch-on")
	var before_image: Image = null
	if DisplayServer.get_name() != "headless":
		before_image = get_viewport().get_texture().get_image()
	world._selected_cell = Vector2i(24,20)
	world.interact_with_selection(false)
	await frames(8)
	check(not Session.simulation.is_cell_lit(Vector2i(22,21)), "World torch interaction changes actual light")
	var layer = main.get_node("World/StructureLayer")
	check(layer._structure_sprites.any(func(sprite: Sprite2D) -> bool: return sprite.texture.resource_path.ends_with("torch_off.png")), "Disabled torch uses its off sprite")
	await screenshot("torch-off")
	if before_image != null:
		var after_image := get_viewport().get_texture().get_image()
		var point: Vector2 = get_viewport().get_stretch_transform() * get_viewport().get_canvas_transform() * Content.cell_center(23,19)
		print("LIGHT SAMPLE: ",point," ",before_image.get_pixelv(Vector2i(point))," / ",after_image.get_pixelv(Vector2i(point)))
		check(before_image.get_pixelv(Vector2i(point)).get_luminance() > after_image.get_pixelv(Vector2i(point)).get_luminance() + 0.03, "Rendered torch brightens its surroundings")
	Session.save_game(false)
	Session.load_game()
	Session.set_paused(true,false)
	await frames()
	check(not Session.simulation.is_cell_lit(Vector2i(22,21)), "Disk save/load retains the disabled torch")
	await _test_work_transition(main)
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://furniture_ui_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("PASS: furniture UI clicks, real meal, chair movement, pause, bounds, disk persistence and rendered lighting")
	get_tree().quit(0 if failures == 0 else 1)

func _test_work_transition(main) -> void:
	var state: Dictionary = Session.get_state()
	state.minute_of_day = 12 * 60
	state.structures.append({"building_id":"core:chair","cell":[24,23]})
	state.structures.append({"building_id":"core:workbench","cell":[25,23]})
	state.player_position = [Content.cell_center(24,22).x,Content.cell_center(24,22).y]
	state.player_furniture_use = {}
	state.player_needs = {"hunger":100.0,"restedness":100.0}
	state.inventory["core:wood"] = 10
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	await frames()
	Session.execute_furniture_command(Vector2i(24,23),"rest")
	Session.simulation.state.player_energy = 40.0
	var command := preload("res://src/crafting/crafting_command.gd")
	check(Session.execute_crafting_command(command.start_project(Vector2i(25,23),"core:split_firewood")).success, "Adjacent workbench has a real crafting project")
	main._on_structure_interaction_requested(Vector2i(25,23),true)
	check(Session.simulation.state.player_furniture_use.is_empty() and not main.get_node("Player")._visual._sitting, "Starting actual work immediately releases chair rest before the first work tick")
	Input.action_press("interact")
	Session.set_paused(false,false)
	for _minute: int in range(6):
		Session.simulation.advance_minutes(1)
		main._process_player_crafting(1.0 / main.PLAYER_WORK_MINUTES_PER_SECOND)
	Input.action_release("interact")
	Session.set_paused(true,false)
	check(is_equal_approx(Session.get_player_energy(),34.0), "Six crafting steps spend energy without simultaneous chair recovery")

func screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshots=") + "/" + id + ".png") == OK, "Screenshot saved")
