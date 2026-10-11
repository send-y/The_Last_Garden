extends Node

const Main := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"
var failures := 0

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func() -> void: get_tree().quit(1))
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames(count: int = 3) -> void:
	for _index: int in range(count):
		await get_tree().process_frame

func click(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await frames()
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	await frames(1)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func key(code: Key, unicode: int = 0, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.ctrl_pressed = control
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames(1)

func choose(option: OptionButton, index: int) -> void:
	await click(option)
	var popup := option.get_popup()
	var event := InputEventMouseButton.new()
	event.position = Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * (index + 0.5) / popup.item_count)
	var motion := InputEventMouseMotion.new()
	motion.position = event.position
	get_viewport().push_input(motion, true)
	await frames(1)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func _run() -> void:
	get_viewport().size = Vector2i(640,360)
	Session._save_store = SaveStore.new("user://resident_homes_ui_test.json")
	Session.set_paused(true, false)
	Session._start_new_simulation()
	for method: String in ["get_housing_rooms", "get_home_policy", "set_home_mode", "get_stock_reserve_report", "set_stock_reserve"]:
		check(Session.has_method(method), "Resident homes UI needs authoritative Session API: " + method)
	if failures > 0:
		get_tree().quit(1)
		return
	var fixture = load("res://tests/fixtures/resident_home_fixture.gd")
	var sim = fixture.create()
	fixture.stock(sim, 20)
	Session._replace_simulation(sim.export_state())
	Session._publish_reloaded_state(true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var hud = main.get_node("Hud/HudRoot")
	hud.open_character_needs(NPC)
	await frames()
	await click(hud._needs_panel._housing)
	var panel = hud._housing_panel
	var mode: OptionButton = panel.find_child("HomeMode", true, false)
	check(mode != null, "Housing modal offers selected room role through actual GUI")
	var reserve_tab: Button = hud._storage_panel.find_child("ReserveTab", true, false)
	check(reserve_tab != null, "Storage modal exposes a compact global reserve editor")
	if failures > 0:
		get_tree().quit(1)
		return
	var room_id := String(Session.get_home_policy(NPC).room_id)
	await choose(mode, 2)
	await click(panel.find_child("SetHomeMode", true, false))
	check(Session.get_home_policy(NPC).mode == "shared", "Real GUI role command updates authoritative assigned room")
	check(panel._members.text.contains("Мира"), "Role editor identifies actual room occupants")
	check(not panel._feedback.text.contains("home."), "Room mode command feedback is localized")
	await screenshot("housing-shared")
	await click(panel.find_child("CloseButton", true, false))
	hud.open_character_needs()
	await frames()
	await click(hud._needs_panel._housing)
	check(mode.disabled and panel._set_mode.disabled, "Starter house role is visibly fixed to settlement")
	await click(panel.find_child("CloseButton", true, false))
	var zone_cell: Array = Session.simulation.state.storage_zones[0].cells[0]
	hud.open_storage(Vector2i(int(zone_cell[0]), int(zone_cell[1])))
	await frames()
	check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hud._storage_panel.get_global_rect()), "Storage item grids still fit main viewport")
	await click(reserve_tab)
	var editor = hud._storage_panel._reserve_editor
	check(editor.visible and not hud._storage_panel._grids.visible, "Reserve editor replaces inventory grids in compact modal")
	var plank_index := -1
	for index: int in range(editor._items.item_count):
		if String(editor._items.get_item_metadata(index)) == "core:plank": plank_index = index
	check(plank_index >= 0, "Global report exposes stocked planks")
	if plank_index < 0:
		get_tree().quit(1)
		return
	await choose(editor._items, plank_index)
	await click(editor._amount.get_line_edit())
	await key(KEY_A, 0, true)
	await key(KEY_BACKSPACE)
	await key(KEY_1, 49)
	await key(KEY_5, 53)
	await key(KEY_ENTER)
	await click(editor._save)
	var entry: Dictionary = {}
	for row: Dictionary in Session.get_stock_reserve_report():
		if row.item_id == "core:plank": entry = row
	check(int(entry.get("reserved", -1)) == 15 and int(entry.get("available", -1)) == 5, "Real resource selection and numeric input protect 15 of 20 communal planks")
	check(editor._stock.text.contains("20") and editor._stock.text.contains("5"), "Reserve view shows authoritative stock and personal-project availability")
	check(not editor._feedback.text.contains("stock.reserve"), "Reserve command result is localized")
	await screenshot("stock-reserve")
	await click(editor._amount.get_line_edit())
	await key(KEY_A, 0, true)
	await key(KEY_BACKSPACE)
	await key(KEY_2, 50)
	await key(KEY_0, 48)
	await key(KEY_ENTER)
	await click(editor._save)
	for dimensions: Vector2i in [Vector2i(480,270), Vector2i(640,360), Vector2i(960,540)]:
		get_viewport().size = dimensions
		await frames()
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hud._storage_panel.get_global_rect()), "Reserve modal fits viewport " + str(dimensions))
		check(hud._storage_panel.scale == Vector2.ONE, "Reserve modal keeps readable font scale " + str(dimensions))
		await click(hud._storage_panel._items_tab)
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hud._storage_panel.get_global_rect()), "Storage grids scroll within viewport " + str(dimensions))
		await click(reserve_tab)
	await click(hud._storage_panel._close)
	get_viewport().size = Vector2i(640,360)
	Session.simulation.set_home_mode(room_id, "personal")
	Session.simulation.set_npc_work_enabled(NPC, "build", true)
	Session.simulation.advance_minutes(1)
	Session._publish_reloaded_state(true)
	hud.open_character_needs(NPC)
	await frames()
	await click(hud._needs_panel._tab_buttons.plans)
	var card = hud._needs_panel._goal_card
	check(hud._needs_panel.scale == Vector2.ONE, "Goal card keeps actual font sizes in main viewport")
	check(card._housing.text.contains("Личное"), "Goal card explains resident home role")
	check(card._details.text.contains("Защищённый запас"), "Goal card distinguishes protected stock from missing material")
	await screenshot("goal-reserve")
	var small = fixture.create(false, Vector2i(3,2))
	small.add_structure({"building_id": "core:torch", "cell": [42,30], "enabled": true})
	small.add_structure({"building_id": "core:torch", "cell": [40,31], "enabled": true})
	var resident_position := Content.cell_center(42,31)
	small.state.npcs[NPC].position = [resident_position.x, resident_position.y]
	small._sync_structure_navigation()
	small.set_npc_work_enabled(NPC, "build", true)
	small.advance_minutes(1)
	Session._replace_simulation(small.export_state())
	Session._publish_reloaded_state(true)
	hud.open_character_needs(NPC)
	await frames()
	await click(hud._needs_panel._tab_buttons.plans)
	check(not Session.get_npc_personal_goal(NPC).get("expansion", {}).is_empty(), "Small real room produces expansion request")
	check(card._details.text.contains("расшир") and card._details.text.contains("Стол"), "Goal card explains room expansion and wanted furniture")
	check(card._intent.text.contains("Хочу поставить стол"), "Expansion request keeps the concrete furniture intention visible")
	await screenshot("goal-expansion")
	for dimensions: Vector2i in [Vector2i(480,270), Vector2i(640,360), Vector2i(960,540)]:
		get_viewport().size = dimensions
		await frames()
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hud._needs_panel.get_global_rect()), "Goal card fits viewport " + str(dimensions))
		check(hud._needs_panel.scale == Vector2.ONE, "Goal card keeps actual font sizes " + str(dimensions))
		hud._needs_panel.hide()
		hud._housing_panel.present(NPC)
		await frames()
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(panel.get_global_rect()), "Housing role modal fits viewport " + str(dimensions))
		check(panel.scale == Vector2.ONE, "Housing modal keeps readable font scale " + str(dimensions))
		panel.hide()
		hud._needs_panel.show()
	Session.assign_sleep_place(NPC, "")
	card.refresh(NPC)
	check(card._housing.text.contains("не назначено") and not card._housing.text.contains("home.mode."), "Unassigned housing has a localized explanation")
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path("user://resident_homes_ui_test.json" + suffix)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if failures == 0: print("PASS: resident homes GUI roles, fixed settlement, reserve resource entry, protected stock, expansion, viewport bounds")
	get_tree().quit(0 if failures == 0 else 1)

func screenshot(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../artifacts/resident-homes")
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_viewport().get_texture().get_image().save_png(directory + "/" + id + ".png") == OK, "Screenshot saved: " + id)
