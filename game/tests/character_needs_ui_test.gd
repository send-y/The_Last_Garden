extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _run() -> void:
	Session._save_store = SaveStore.new("user://character_needs_ui_test.json")
	Session.set_paused(true, false)
	Session._start_new_simulation()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = main.get_node("Hud/HudRoot")
	check(hud._needs_hud.labels.size() == 3, "HUD has only three physical player stats")
	check(hud._needs_hud.buttons.hunger.tooltip_text.contains("Еда"), "Satiety explains how to recover")
	await _screenshot("hud")
	Session.set_paused(false, false)
	await _click(hud._needs_hud.buttons.energy)
	check(hud._needs_panel.visible and Session.is_paused(), "Clicking physical HUD opens details and pauses world")
	check(not hud._needs_panel._rows.mood.row.visible and not hud._needs_panel._rows.wellbeing.row.visible, "Player card has no psychology")
	await _screenshot("player")
	Session.simulation.state.player_energy = 20.0
	var before: int = Session.simulation.get_elapsed_game_minutes()
	await _click(hud._needs_panel._rest)
	check(not hud._needs_panel.visible and not Session.is_paused(), "Rest closes card and restores running world")
	check(Session.simulation.get_elapsed_game_minutes() >= before + 15 and Session.get_player_energy() > 20, "Rest button advances actual world and recovers energy")
	Session.set_paused(true, false)
	var state: Dictionary = Session.get_state()
	state.day = 2
	state.minute_of_day = 9 * 60
	state.flags.first_night_complete = true
	state.npcs["core:first_neighbor"].known = true
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	await get_tree().process_frame
	hud.set_selection({"kind": "interactable", "object_id": "core:first_neighbor", "label": "Мира", "in_range": true})
	check(hud._npc_needs_button.visible, "Selected visible NPC exposes a state button")
	await _click(hud._npc_needs_button)
	check(hud._needs_panel.npc_id == "core:first_neighbor" and hud._needs_panel._rows.mood.row.visible, "NPC card shows its own five stats")
	check(not hud._needs_panel._rest.visible and not hud._needs_panel._reasons.text.is_empty(), "NPC reasons are visible, player rest is absent")
	await _screenshot("npc")
	for dimensions: Vector2i in [Vector2i(640, 360), Vector2i(480, 270), Vector2i(960, 540)]:
		get_viewport().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		check(bounds.encloses(hud._needs_panel.get_global_rect()), "Needs card fits viewport " + str(dimensions))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	check(not hud._needs_panel.visible and Session.is_paused(), "Escape closes card and preserves prior manual pause")
	hud.open_character_needs()
	Session._publish_reloaded_state(true)
	check(not hud._needs_panel.visible, "Loading closes stale character details")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://character_needs_ui_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("PASS: physical HUD input, player/NPC details, rest, pause, reload and bounds")
	get_tree().quit(0 if failures == 0 else 1)

func _screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--screenshots=") + "/" + id + ".png"
			check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot saved: " + id)
