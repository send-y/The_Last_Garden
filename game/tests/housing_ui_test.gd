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

func _click(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = motion.position
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _run() -> void:
	Session._save_store = SaveStore.new("user://housing_ui_test.json")
	Session.set_paused(true, false)
	Session._start_new_simulation()
	var state: Dictionary = Session.get_state()
	state.day = 2
	state.minute_of_day = 20 * 60
	state.flags.first_night_complete = true
	state.npcs["core:first_neighbor"].known = true
	state.structures.append({"building_id":"core:bedroll", "cell":[20,23]})
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = main.get_node("Hud/HudRoot")
	Session.set_paused(false, false)
	hud.open_character_needs("core:first_neighbor")
	await get_tree().process_frame
	await _click(hud._needs_panel._housing)
	var panel = hud._housing_panel
	check(panel.visible and not hud._needs_panel.visible and Session.is_paused(), "Housing button opens a paused modal from NPC details")
	check(panel._choices.is_item_disabled(0), "Player's occupied starter bedroll is disabled for NPC")
	check(panel._ids[panel._choices.selected] == "core:bedroll@20,23", "Free personal bedroll is selected")
	await _click(panel._assign)
	check(String(Session.get_character_home("core:first_neighbor").place_id) == "core:bedroll@20,23", "Real mouse click assigns the selected sleep place")
	check(not panel._status.text.contains("housing."), "Housing status is localized")
	await _screenshot("shared-house")
	Session.save_game(false)
	await _click(panel._release)
	check(String(Session.get_character_home("core:first_neighbor").place_id).is_empty(), "Release button removes personal assignment")
	Session.load_game()
	check(not panel.visible and not hud._needs_panel.visible, "Loading closes stale housing UI")
	check(String(Session.get_character_home("core:first_neighbor").place_id) == "core:bedroll@20,23", "Real save/load restores bedroll ownership")
	Session.set_paused(true, false)
	hud.open_character_needs()
	await get_tree().process_frame
	await _click(hud._needs_panel._housing)
	for dimensions: Vector2i in [Vector2i(640,360),Vector2i(480,270),Vector2i(960,540)]:
		get_viewport().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "Housing panel fits " + str(dimensions))
	await _screenshot("player-house")
	await _click(panel.get_node("Margin/Column/CloseButton"))
	check(not panel.visible and Session.is_paused(), "Closing housing preserves existing manual pause")
	Session.set_paused(false,false)
	hud.open_character_needs()
	await get_tree().process_frame
	await _click(hud._needs_panel._housing)
	hud.toggle_inventory()
	check(not panel.visible and not Session.is_paused(), "Inventory toggle closes housing and restores running world")
	Session.set_paused(true,false)
	var player = main.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Content.cell_center(20,22)
	Session.set_player_position(player.global_position)
	var world = main.get_node("World")
	world._selected_cell = Vector2i(21,23)
	var before: int = Session.simulation.get_elapsed_game_minutes()
	world.interact_with_selection(false)
	check(Session.simulation.get_elapsed_game_minutes() == before, "World interaction cannot steal NPC's bedroll")
	Session.assign_sleep_place("core:first_neighbor", "")
	world.interact_with_selection(false)
	check(Session.simulation.get_elapsed_game_minutes() > before and String(Session.get_character_home("core:player").place_id) == "core:bedroll@20,23", "Clicking either bedroll footprint cell uses a real constructed sleep place")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://housing_ui_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("PASS: housing UI clicks, shared ownership, physical interaction, save/load, pause and viewport bounds")
	get_tree().quit(0 if failures == 0 else 1)

func _screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--screenshots=") + "/" + id + ".png") == OK, "Screenshot saved")
