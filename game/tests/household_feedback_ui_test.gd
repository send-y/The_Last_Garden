extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"
var failures := 0

func _ready() -> void:
	get_tree().create_timer(25).timeout.connect(func() -> void:
		push_error("Household UI test timed out")
		get_tree().quit(1)
	)
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
	await frames()

func _run() -> void:
	Session._save_store = SaveStore.new("user://household_feedback_ui_test.json")
	Session.set_paused(true,false)
	Session._start_new_simulation()
	var state: Dictionary = Session.get_state()
	state.day = 2
	state.minute_of_day = 12 * 60
	state.flags.first_night_complete = true
	state.npcs[NPC].known = true
	state.npcs[NPC].personal_inventory = {"core:food":0}
	state.npcs[NPC].needs = {"hunger":30.0,"energy":12.0,"restedness":20.0}
	state.npcs[NPC].position = [Content.cell_center(22,23).x,Content.cell_center(22,23).y]
	state.structures.append({"building_id":"core:bedroll","cell":[20,23]})
	state.structures.append({"building_id":"core:table","cell":[22,20]})
	state.structures.append({"building_id":"core:chair","cell":[22,21]})
	state.structures.append({"building_id":"core:torch","cell":[24,20]})
	Session._replace_simulation(state)
	Session._publish_reloaded_state(true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	hud.open_character_needs(NPC)
	await frames()
	var panel = hud._needs_panel
	check(panel._home_summary.visible and panel._home_summary.text.contains("не назначено"), "NPC card immediately shows unassigned sleep")
	await screenshot("state-card")
	var before := JSON.stringify(Session.simulation.export_state())
	await click(panel._tab_buttons.household)
	check(panel._household.visible and not panel._stats_content.visible, "Real click opens the household tab")
	check(panel._household._rows.sleep.hint.text.contains("закрепите") and panel._household._rows.food.hint.text.contains("склад"), "Missing sleep and food explain concrete remedies")
	check(panel._household._current.text.contains("хочет есть") and panel._household._current.text.contains("не выспался"), "Household preserves current physical needs alongside provisions")
	check(JSON.stringify(Session.simulation.export_state()) == before, "Opening and reading the household tab is read-only")
	await screenshot("missing-provisions")
	await click(panel._housing)
	check(hud._housing_panel.visible and not panel.visible, "Existing housing action is reachable from household feedback")
	await click(hud._housing_panel._assign)
	check(Session.get_character_home(NPC).place_id == "core:bedroll@20,23", "Real housing click assigns the free bedroll")
	await click(hud._housing_panel.get_node("Margin/Column/CloseButton"))
	hud.open_character_needs(NPC)
	await frames()
	await click(panel._tab_buttons.household)
	check(panel._home_summary.text.contains("20, 23") and panel._home_summary.text.contains("Общий дом"), "NPC card names the real bedroll and its room/location")
	check(panel._household._rows.sleep.hint.text.contains("кровлю"), "Unfinished roof has a useful explanation")
	Session.simulation.state.flags.repair_stage = 2
	Session.simulation.state.npcs[NPC].personal_inventory["core:carrot"] = 1
	Session.state_changed.emit()
	await frames()
	check(not panel._household._rows.sleep.hint.visible and not panel._household._rows.food.hint.visible, "Resolved sleep and food problems disappear from the open card")
	check(panel._household._rows.sleep.text.text.contains("полноценный сон"), "Covered cheap bedroll satisfies sleep without requiring a bed upgrade")
	await screenshot("comfortable-household")
	var player = main.get_node("Player")
	player.global_position = Content.cell_center(24,21)
	Session.set_player_position(player.global_position)
	Session.execute_furniture_command(Vector2i(24,20),"toggle_light")
	await frames()
	check(panel._household._rows.light.text.text.contains("без света вечером") and panel._household._rows.light.hint.visible, "Daytime card reflects missing evening light immediately")
	var scroll: ScrollContainer = panel._household.get_node("Provisions")
	scroll.scroll_vertical = 10000
	await frames()
	await screenshot("evening-light")
	for dimensions: Vector2i in [Vector2i(480,270),Vector2i(640,360),Vector2i(960,540)]:
		get_viewport().size = dimensions
		for tab: String in ["state","household"]:
			await click(panel._tab_buttons[tab])
			await frames()
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "Both NPC tabs fit " + str(dimensions) + " / " + tab)
	Session.save_game(false)
	Session.load_game()
	await frames()
	check(not panel.visible, "Loading closes stale household feedback")
	hud.open_character_needs(NPC)
	await frames()
	await click(panel._tab_buttons.household)
	check(panel._home_summary.text.contains("20, 23") and panel._household._rows.light.hint.visible, "Reloaded feedback uses persisted housing and light")
	await click(panel._tab_buttons.state)
	hud.open_character_needs()
	await frames()
	check(not panel._tabs.visible and not panel._home_summary.visible and not panel._household.visible, "Player card keeps physical state without NPC household psychology")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://household_feedback_ui_test.json" + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures == 0:
		print("PASS: NPC household tabs, real housing clicks, live remedies, read-only UI, compact layout and save reload")
	get_tree().quit(0 if failures == 0 else 1)

func screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshots=") + "/" + id + ".png") == OK, "Screenshot saved")
