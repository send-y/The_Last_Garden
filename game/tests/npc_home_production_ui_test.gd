extends Node
const Main := preload("res://src/main/main.tscn")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames() -> void:
	for i: int in range(3): await get_tree().process_frame
func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func():get_tree().quit(1))
	Session.set_mechanics_lab_active(true)
	var scenario: Dictionary = Scenarios.build(Scenarios.HOME_PRODUCTION)
	check(scenario.success,"Player-accessible laboratory production scenario builds")
	Session.apply_debug_state(scenario.state,"production UI",true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var id := ""
	for i: int in range(90):
		Session.advance_debug_minutes(1)
		for project: Dictionary in Session.simulation.state.crafting_projects:
			if not String(project.get("owner_id","")).is_empty() and int(project.work_progress_minutes) > 0: id = String(project.owner_id)
		if not id.is_empty(): break
	check(not id.is_empty(),"Live resident begins production without debug crafting commands")
	if id.is_empty():
		get_tree().quit(1)
		return
	var hud = main.get_node("Hud/HudRoot")
	hud.open_character_needs(id)
	await frames()
	var plans: Button = hud._needs_panel._tab_buttons.plans
	for pressed: bool in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = plans.get_global_rect().get_center()
		click.pressed = pressed
		get_viewport().push_input(click,true)
		await frames()
	await frames()
	var card = hud._needs_panel._goal_card
	check(card.visible and card._status.text.contains("доски"),"Plans card identifies production rather than only missing materials")
	check(card._details.text.contains("мин работы на верстаке"),"Actual plans show timed production progress")
	var before := JSON.stringify(Session.simulation.export_state())
	card.refresh(id)
	check(before == JSON.stringify(Session.simulation.export_state()),"Production reports are read-only")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/The_Last_Garden/artifacts/npc-home-production-2026-10-09/production-card.png")
	print("NPC_HOME_PRODUCTION_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
