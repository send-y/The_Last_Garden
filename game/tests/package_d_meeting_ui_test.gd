extends Node
const World := preload("res://src/simulation/world_simulation.gd")
const Main := preload("res://src/main/main.tscn")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func frames(count: int = 4) -> void:
	for i: int in range(count): await get_tree().process_frame
func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event,true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event,true)
	await frames()
func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-artifact-dir="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--test-artifact-dir=").path_join(name))
func _ready() -> void:
	get_tree().create_timer(40).timeout.connect(func() -> void: get_tree().quit(1))
	TranslationServer.set_locale("ru")
	Session.set_mechanics_lab_active(true)
	var sim := World.new(World.create_new_game_state())
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.active = true
	npc.needs.hunger = 1.0
	sim.state.player_needs.hunger = 1.0
	sim.set_player_position(sim.get_npc_position(String(npc.id),Vector2.ZERO)+Vector2(32,0))
	Session.apply_debug_state(sim.export_state(),"hungry first meeting",true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	hud.open_npc_conversation(String(npc.id))
	await frames(5)
	var panel = hud.get_node("NpcConversationPanel")
	check(panel.visible,"Hungry first meeting opens in ordinary HUD")
	check(not String(panel._body.text).contains("meeting."),"Translated first reply is rendered")
	await screenshot("first-meeting.png")
	for i: int in range(25):
		if Session.simulation.state.npcs[String(npc.id)].first_meeting_complete: break
		await click(panel._next_button)
	check(Session.simulation.state.npcs[String(npc.id)].first_meeting_complete,"All introductory pages are actually presented")
	var gift = panel._choices.get_node_or_null("Topic_take_supplies")
	check(gift != null,"Gift has an explicit player response")
	if gift != null:
		panel._topics.ensure_control_visible(gift)
		await frames()
		await click(gift)
		check(Session.simulation.get_item_count("core:food") == 10,"Actual GUI click transfers ten portions")
		await screenshot("welcome-gift.png")
	hud._close_npc_conversation()
	hud.open_npc_conversation(String(npc.id))
	await frames()
	check(Session.simulation.get_item_count("core:food") == 10,"Reopening HUD cannot grant food again")
	check(not String(panel._body.text).contains("meeting."),"Overview is translated")
	print("PACKAGE_D_MEETING_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
