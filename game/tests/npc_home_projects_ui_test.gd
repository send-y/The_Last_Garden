extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const NPC := Fixture.NPC
var failures := 0
var save_path := "user://npc_home_projects_ui_test.json"

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func() -> void: get_tree().quit(1))
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for _frame: int in range(count): await get_tree().process_frame

func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event,true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event,true)
	await frames()

func _run() -> void:
	if DisplayServer.get_name() != "headless": save_path = "user://npc_home_projects_graphical_ui_test.json"
	Session._save_store = SaveStore.new(save_path)
	Session.set_paused(true,false)
	Session._replace_simulation(Fixture.create().export_state())
	Session._publish_reloaded_state(true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	hud.open_character_needs(NPC)
	await frames()
	var panel = hud._needs_panel
	await click(panel._work_buttons.build)
	check(Session.get_npc_work_status(NPC).options.build,"Real card enables construction")
	Session.simulation.advance_minutes(1)
	await frames()
	var before := JSON.stringify(Session.simulation.export_state())
	await click(panel._tab_buttons.plans)
	check(panel._goal_card.visible and panel._goal_card._intent.text.begins_with("Хочу"),"Resident explains self-chosen plan in actual UI")
	check(panel._goal_card._status.text.contains("материал") and panel._goal_card._details.text.contains("Не хватает"),"Missing real planks are visible")
	check(before == JSON.stringify(Session.simulation.export_state()),"Reading plans does not modify simulation")
	await screenshot("waiting-project")
	await click(panel._goal_card._defer)
	check(not Session.get_npc_personal_goal(NPC).declined.is_empty(),"Declining by real click persists")
	check(panel._goal_card._resume.visible,"Deferred projects can be allowed again")
	await click(panel._goal_card._resume)
	check(Session.get_npc_personal_goal(NPC).declined.is_empty(),"Real click clears declined projects")
	Session.simulation.advance_minutes(35)
	await frames()
	var report: Dictionary = Session.get_npc_personal_goal(NPC)
	Session.save_game(false)
	Session.load_game()
	await frames()
	check(not panel.visible,"Loading closes stale goal card")
	hud.open_character_needs(NPC)
	await frames()
	await click(panel._tab_buttons.plans)
	check(Session.get_npc_personal_goal(NPC) == report,"Disk reload retains chosen goal")
	Fixture.stock(Session.simulation,40)
	Session.simulation.advance_minutes(180)
	await frames()
	check(not Session.get_npc_personal_goal(NPC).completed.is_empty() and panel._goal_card._details.text.contains("Завершённые проекты"),"Completed physical project leaves a visible persistent result")
	await screenshot("finished-project")
	for dimensions: Vector2i in [Vector2i(480,270),Vector2i(640,360),Vector2i(960,540)]:
		get_viewport().size = dimensions
		for tab: String in ["state","household","plans"]:
			await click(panel._tab_buttons[tab])
			await frames()
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()),"Goal and previous tabs fit " + str(dimensions) + tab)
	hud.open_character_needs()
	await frames()
	check(not panel._tabs.visible and not panel._goal_card.visible,"Player gets no NPC goal system")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(save_path + suffix)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if failures == 0: print("PASS: NPC project card, permissions, intent, shortages, decline, resume, disk reload and compact layout")
	get_tree().quit(0 if failures == 0 else 1)

func screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshots=") + "/" + id + ".png") == OK,"Project screenshot saved")
