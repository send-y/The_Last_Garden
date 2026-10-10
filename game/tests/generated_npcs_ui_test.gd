extends Node
const Main := preload("res://src/main/main.tscn")
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames(count: int = 3) -> void:
	for index: int in range(count): await get_tree().process_frame
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
func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func() -> void: get_tree().quit(1))
	Session.set_mechanics_lab_active(true)
	var sim := World.new()
	var created: Dictionary = sim.create_generated_npc(94,Vector2i(24,29))
	var id: String = created.npc_id
	sim.arrive_npc(id,Vector2i(24,29))
	sim.set_player_position(sim.get_npc_position(id,Vector2.ZERO)+Vector2(32,0))
	Session.apply_debug_state(sim.export_state(),"conversation UI",false)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud: Control = main.get_node("Hud/HudRoot")
	if not hud.has_method("open_npc_conversation"):
		push_error("Missing conversation HUD")
		get_tree().quit(1)
		return
	hud.open_npc_conversation(id)
	await frames(5)
	var panel: Control = hud.get_node("NpcConversationPanel")
	check(panel.visible and hud.is_modal_open() and Session.is_paused(),"Conversation modal pauses world")
	check(Session.simulation.state.npcs[id].known and not Session.simulation.state.npcs[id].known_facts.has("experience_id"),"Only first displayed page learned")
	check(panel.get_node("Margin/Column/FreeInputRow/FreeInput").editable == false,"Free input disabled")
	check(panel.get_node("Margin/Column/FreeInputRow/SendButton").disabled,"Sending disabled")
	panel._toggle_history()
	await frames()
	check(Session.simulation.state.npcs[id].known_facts.size() == 1,"History does not reveal an unread reply page")
	panel._toggle_history()
	await frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../artifacts/procedural-residents")
		DirAccess.make_dir_recursive_absolute(directory)
		get_viewport().get_texture().get_image().save_png(directory+"/conversation-greeting.png")
	await click(panel.get_node("Margin/Column").find_child("NextButton",true,false))
	await frames(5)
	check(Session.simulation.state.npcs[id].known_facts.has("experience_id"),"Second page learned")
	var topics: Node = panel.get_node("Margin/Column/Topics/Choices")
	check(topics.get_child_count() >= 2,"Prepared topics shown")
	var before_history: int = Session.simulation.state.npcs[id].conversation_history.size()
	await click(panel.get_node("Margin/Column/FreeInputRow/SendButton"))
	check(Session.simulation.state.npcs[id].conversation_history.size() == before_history,"Disabled sending has no conversation effect")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/procedural-residents/conversation-topics.png"))
	var invitation: Control = topics.get_node("Topic_stay")
	panel.get_node("Margin/Column/Topics").ensure_control_visible(invitation)
	await frames()
	await click(invitation)
	for index: int in range(12):
		if panel._page_complete: break
		panel._next()
		await frames()
	check(Session.simulation.state.npcs[id].residency == "resident","Prepared invitation works through actual GUI clicks")
	for dimensions: Vector2i in [Vector2i(640,360),Vector2i(480,320),Vector2i(1280,720)]:
		get_window().size = dimensions
		panel.fit_to_viewport(Vector2(dimensions))
		await frames()
		check(panel.get_rect().position.x >= 0 and panel.get_rect().end.x <= dimensions.x and panel.get_rect().end.y <= dimensions.y,"Panel within viewport")
		check(panel.scale == Vector2.ONE,"Responsive layout without shrinking type")
	panel.present({"npc_id":id,"name_key":"npc.generic.traveler.name","appearance":Session.get_npc_appearance(id),"utterance_id":"test-long","pages":[{"text_key":"","text":"Очень длинная реплика с подробным рассказом. ".repeat(50),"text_args":{}}]})
	await frames()
	check(panel._chunks.size() > 1,"Long dialogue paginated")
	check(not panel._page_complete,"Long page not acknowledged before last chunk")
	panel.set_text_font_size(18)
	await frames()
	check(panel._body.get_theme_font_size("font_size") == 18 and panel._chunks.size() > 1,"Enlarged text uses pagination at actual font size")
	check(panel._split_text("Длинноеслово".repeat(80),120,52).size() > 1,"Long unbroken word paginated without clipping")
	hud._close_npc_conversation()
	check(not Session.is_paused(),"Prior playing state restored")
	Session.set_paused(true,false)
	hud.open_npc_conversation(id)
	await frames()
	hud._close_npc_conversation()
	check(Session.is_paused(),"Prior paused state restored")
	Session.set_paused(false,false)
	hud.open_npc_conversation(id)
	await frames()
	Session.apply_debug_state(sim.export_state(),"reload while talking",true)
	await frames()
	check(not panel.visible and Session.is_paused(),"Reload closes stale conversation and preserves new pause state")
	if failures == 0: print("PASS: conversation HUD, progressive pages, responsive layout, placeholder and pause lifecycle")
	get_tree().quit(0 if failures == 0 else 1)
