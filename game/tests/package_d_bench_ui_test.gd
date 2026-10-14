extends "res://tests/package_d_meeting_ui_test.gd"
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
func _ready() -> void:
	get_tree().create_timer(40).timeout.connect(func() -> void: get_tree().quit(1))
	TranslationServer.set_locale("ru")
	Session.set_mechanics_lab_active(true)
	var built := Scenarios.build(&"missing_workbench")
	check(bool(built.get("success",false)),"Request lab scenario builds")
	if not bool(built.get("success",false)): get_tree().quit(1); return
	var sim = built.simulation
	sim.advance_minutes(60)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	check(String(npc.workbench_request.get("status","")) == "offered","Missing station creates actual offered request")
	sim.set_player_position(sim.get_npc_position(String(npc.id),Vector2.ZERO)+Vector2(32,0))
	Session.apply_debug_state(sim.export_state(),"workshop request",true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	hud.open_npc_conversation(String(npc.id))
	await frames(6)
	var panel = hud.get_node("NpcConversationPanel")
	check(panel.visible and not String(panel._body.text).contains("workshop."),"Request explanation is translated in normal conversation HUD")
	for i: int in range(15):
		if panel._choices.get_node_or_null("Topic_bench_accept") != null: break
		await click(panel._next_button)
	var accept = panel._choices.get_node_or_null("Topic_bench_accept")
	check(accept != null,"Request offers a concrete acceptance response")
	if accept != null:
		panel._topics.ensure_control_visible(accept)
		await frames()
		await screenshot("workbench-request.png")
		await click(panel._choices.get_node("Topic_bench_accept"))
		check(String(Session.simulation.state.npcs[String(npc.id)].workbench_request.status) == "accepted","Actual GUI response accepts request")
	print("PACKAGE_D_BENCH_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
