extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
var failures := 0

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _ready() -> void:
	call_deferred("_run")

func click(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
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
	Session._save_store = SaveStore.new("user://npc_practical_work_ui_test.json")
	Session.set_paused(true, false)
	Session._start_new_simulation()
	var state: Dictionary = Session.get_state()
	state.day = 2
	state.minute_of_day = 9 * 60
	state.flags.first_night_complete = true
	state.npcs["core:first_neighbor"].known = true
	Session._replace_simulation(state)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = main.get_node("Hud/HudRoot")
	hud.open_character_needs("core:first_neighbor")
	await get_tree().process_frame
	var panel = hud._needs_panel
	for kind: String in ["water", "gather", "build"]:
		check(not panel._work_buttons[kind].button_pressed, "New work permission is off: " + kind)
		await click(panel._work_buttons[kind])
		check(bool(Session.get_npc_work_status("core:first_neighbor").options[kind]), "Real UI click enables work: " + kind)
	var restored = preload("res://src/simulation/world_simulation.gd").new(Session.get_state())
	check(restored.get_npc_work_status("core:first_neighbor").options == Session.get_npc_work_status("core:first_neighbor").options, "UI permissions persist")
	for dimensions: Vector2i in [Vector2i(640, 360), Vector2i(480, 270), Vector2i(960, 540)]:
		get_viewport().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "Work card fits: " + str(dimensions))
		for button: CheckButton in panel._work_buttons.values():
			check(panel.get_global_rect().encloses(button.get_global_rect()), "Permission is inside the card")
		if dimensions == Vector2i(640, 360) and DisplayServer.get_name() != "headless":
			for argument: String in OS.get_cmdline_user_args():
				if argument.begins_with("--screenshots="):
					await RenderingServer.frame_post_draw
					check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--screenshots=") + "/npc-work.png") == OK, "Screenshot saved")
	for minute: int in range(60):
		Session.simulation.advance_minutes(1)
		if not String(Session.get_npc_work_status("core:first_neighbor").tool_instance_id).is_empty():
			break
	var held: Dictionary = Session.simulation.get_actor_tool("core:first_neighbor")
	check(not held.is_empty(), "NPC borrows its physical tool after UI permission")
	# Batched world refresh occurs after the synchronous minute loop.
	await get_tree().process_frame
	await get_tree().process_frame
	var found_visual := false
	for view: InteractableView in main.get_node("World")._interactables:
		if String(view.object_id) == "core:first_neighbor":
			found_visual = true
			check(view._character_visual._held_item_id == String(held.get("item_id", "")), "NPC displays the same tool it physically borrowed")
			check(view._character_visual._held_grip == Session.simulation.content.item_tool_grip(String(held.get("item_id", ""))), "NPC receives catalog grip")
	check(found_visual, "Live scene contains the working resident")
	Session.simulation.state.npcs["core:first_neighbor"].known = false
	panel.refresh()
	check(panel._work_buttons.water.disabled, "Unknown resident cannot be assigned permissions")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://npc_practical_work_ui_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("PASS: NPC work permission clicks, persistence, acquaintance and compact layout")
	get_tree().quit(0 if failures == 0 else 1)
