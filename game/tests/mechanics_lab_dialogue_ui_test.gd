extends Node

const LabScene := preload("res://src/dev/mechanics_lab.tscn")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames(count: int = 4) -> void:
	for index: int in range(count):
		await get_tree().process_frame

func click_at(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func finish_reply(panel: Control) -> void:
	for index: int in range(15):
		if panel.get("_page_complete") and int(panel.get("_page")) == panel.get("_view").pages.size() - 1:
			return
		panel._next()
		await frames()
	check(false, "Reply did not finish")

func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func() -> void: get_tree().quit(1))
	get_window().size = Vector2i(640, 360)
	Session.set_mechanics_lab_active(true)
	var lab := LabScene.instantiate()
	add_child(lab)
	await frames()
	lab._load_scenario(Scenarios.GENERATED_RESIDENTS)
	await frames()
	var id := "core:resident_1"
	check(Session.simulation.state.npcs.has(id), "Generated residents scenario contains a visitor")
	if not Session.simulation.state.npcs.has(id):
		get_tree().quit(1)
		return
	Session.set_player_position(Session.get_npc_position(id, Vector2.ZERO) + Vector2(32, 0))
	var hud: Control = lab.get_node("Game/Hud/HudRoot")
	var panel: Control = hud.get_node("NpcConversationPanel")
	var lab_panel: Control = lab.get_node("DevUi").find_child("MechanicsPanel", true, false)
	var toggle: Button = lab.get_node("DevUi").find_child("MechanicsToggle", true, false)
	if toggle != null and lab_panel != null:
		check(not lab_panel.visible, "Laboratory starts collapsed")
		await click_at(toggle.get_global_rect().get_center())
		check(lab_panel.visible, "Laboratory opens with its button")
		check(get_viewport().get_visible_rect().encloses(lab_panel.get_global_rect()),
			"Open laboratory panel fits inside the viewport")
		await click_at(toggle.get_global_rect().get_center())
		check(not lab_panel.visible, "Same button closes laboratory")
		await click_at(toggle.get_global_rect().get_center())
		check(lab_panel.visible, "Laboratory can reopen before a conversation")
		var minute_before := Session.get_minute_of_day()
		for child: Node in lab_panel.get_children():
			if child is Button and child.text == "+10 мин":
				await click_at(child.get_global_rect().get_center())
				break
		check(Session.get_minute_of_day() == minute_before + 10, "Debug time button still works")
	# Time advancement lets visitors walk; return within conversation range.
	Session.set_player_position(Session.get_npc_position(id, Vector2.ZERO) + Vector2(32, 0))
	lab.get_node("Game/Player").apply_loaded_position()
	hud.open_npc_conversation(id)
	await frames(6)
	check(panel.visible, "Conversation opens for the nearby visitor")
	if not panel.visible:
		get_tree().quit(1)
		return
	await finish_reply(panel)
	if lab_panel != null:
		check(not lab_panel.visible, "Starting conversation collapses laboratory")
	var choice: Button = panel.get_node("Margin/Column/Topics/Choices/Topic_work")
	panel.get_node("Margin/Column/Topics").ensure_control_visible(choice)
	await frames()
	var rect := choice.get_global_rect()
	# The right side is exactly where the old debug panel swallowed dialogue clicks.
	await click_at(Vector2(rect.end.x - 12, rect.get_center().y))
	await finish_reply(panel)
	check(Session.simulation.state.npcs[id].known_facts.has("aspiration_id"),
		"Clicking the right side of a dialogue option selects and completes its reply in MechanicsLab")
	check(toggle != null, "Compact laboratory toggle exists")
	if toggle != null and lab_panel != null:
		hud._close_npc_conversation()
		var key := InputEventKey.new()
		key.keycode = KEY_F2
		key.pressed = true
		get_viewport().push_input(key, true)
		await frames()
		check(lab_panel.visible, "F2 opens laboratory")
		key.pressed = false
		get_viewport().push_input(key, true)
		key.pressed = true
		get_viewport().push_input(key, true)
		await frames()
		check(not lab_panel.visible, "F2 closes laboratory")
		# Hidden debug controls must not intercept a second conversation either.
		hud.open_npc_conversation(id)
		await frames(6)
		var home: Button = panel.get_node("Margin/Column/Topics/Choices/Topic_home")
		rect = home.get_global_rect()
		await click_at(Vector2(rect.end.x - 12, rect.get_center().y))
		await finish_reply(panel)
		check(String(Session.simulation.state.npcs[id].conversation_history.back().topic_id) == "home",
			"Home dialogue also receives clicks")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory := ProjectSettings.globalize_path("res://../artifacts/mechanics-lab-ui")
			DirAccess.make_dir_recursive_absolute(directory)
			get_viewport().get_texture().get_image().save_png(directory + "/conversation.png")
	# User regression: first conversation by the house after loading the homes scenario.
	hud._close_npc_conversation()
	lab._load_scenario(Scenarios.RESIDENT_HOMES)
	await frames()
	var mira: Dictionary = Session.simulation.state.npcs["core:first_neighbor"]
	mira.active = true
	mira.known = false
	for resident_id: String in ["core:first_neighbor", "core:resident_1", "core:resident_2"]:
		Session.set_player_position(Session.get_npc_position(resident_id,Vector2.ZERO)+Vector2(32,0))
		lab.get_node("Game/Player").apply_loaded_position()
		hud.open_npc_conversation(resident_id)
		await frames(6)
		check(panel.visible, "First conversation opens for " + resident_id + " beside the house")
		if not panel.visible: continue
		await finish_reply(panel)
		var resident: Dictionary = Session.simulation.state.npcs[resident_id]
		check(resident.known and resident.get("known_facts",{}).has("name"), "Actual conversation HUD learns name without a missing knowledge error: " + resident_id)
		hud._close_npc_conversation()
	if failures == 0:
		print("PASS: MechanicsLab dialogue clicks, compact button, default collapse, automatic hiding and F2")
	get_tree().quit(0 if failures == 0 else 1)
