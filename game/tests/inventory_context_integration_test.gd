extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
var _panel: InventoryPanel
var _hud: FirstNightHud


func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	var state := Simulation.create_new_state()
	state.inventory = {"core:food": 2, "core:wood": 2, "core:carrot": 1}
	state.player_energy = 0.0
	Session.apply_debug_state(state, "context menu integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_hud = main.get_node("Hud/HudRoot") as FirstNightHud
	_panel = _hud.get_node("InventoryPanel") as InventoryPanel
	_hud.toggle_inventory()
	await get_tree().process_frame
	if not _check(_panel.has_node("ContextLayer/ItemContextMenu"), "backpack provides a context menu instead of the persistent plaque"):
		return
	var menu := _panel.get_node("ContextLayer/ItemContextMenu") as Control
	if not _check(not menu.visible and not _panel.has_node("ContentMargin/ContentColumn/DetailsPanel"), "no details plaque or menu before right click"):
		return
	await _click_item("core:food", MOUSE_BUTTON_RIGHT)
	if not _check(menu.visible and not _panel._inventory_grid.is_holding_item(), "right click opens actions without lifting item"):
		return
	var eat := _panel.get("_eat_button") as Button
	var extract := _panel.get("_extract_button") as Button
	if not _check(eat.visible and extract.visible and not extract.disabled, "berry actions available"):
		return
	await _click_item("core:carrot", MOUSE_BUTTON_RIGHT)
	if not _check(menu.visible and extract.disabled and String((_panel.get("_context_placement") as Dictionary).item_id) == "core:carrot", "right click switches menu to another item"):
		return
	for window_size: Vector2i in [Vector2i(640, 360), Vector2i(1270, 640)]:
		get_window().size = window_size
		await get_tree().process_frame
		await get_tree().process_frame
		_panel.call("_open_context_menu", _placement("core:food"), _hud.size - Vector2.ONE)
		await get_tree().process_frame
		await get_tree().process_frame
		if not _check(Rect2(Vector2.ZERO, _hud.size).encloses(menu.get_global_rect()), "context menu fits viewport corner after resize"):
			return
	await _click(eat.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	if not _check(Session.simulation.get_item_count("core:food") == 1 and is_equal_approx(Session.get_player_energy(), 5.0) and not menu.visible, "menu action consumes selected food and closes"):
		return
	await _click_item("core:carrot", MOUSE_BUTTON_RIGHT)
	if not _check(extract.visible and extract.disabled and not extract.tooltip_text.is_empty(), "ordinary crop keeps study-table gate and explanation"):
		return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	if not _check(not menu.visible and _hud.is_inventory_open() and Session.is_paused(), "Escape closes only context menu"):
		return
	await _click_item("core:wood", MOUSE_BUTTON_RIGHT)
	var outside := _panel._inventory_grid.get_global_rect().position - Vector2(10, 10)
	await _click(outside, MOUSE_BUTTON_LEFT)
	if not _check(not menu.visible and not _panel._inventory_grid.is_holding_item(), "outside click dismisses without starting a transfer"):
		return
	var wood_placement: Dictionary = {}
	for placement: Dictionary in _panel._inventory_grid._placements:
		if placement.item_id == "core:wood":
			wood_placement = placement
	var wood_point := _panel._inventory_grid.get_global_transform_with_canvas() * (Vector2(wood_placement.origin) * _panel._inventory_grid.CELL_SIZE + Vector2.ONE * _panel._inventory_grid.CELL_SIZE * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = wood_point
	press.global_position = wood_point
	get_viewport().push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = wood_point + Vector2(8, 0)
	drag.global_position = drag.position
	get_viewport().push_input(drag, true)
	if not _check(_panel._inventory_grid.is_holding_item(), "dragging starts a transfer"):
		return
	await _click_item("core:wood", MOUSE_BUTTON_RIGHT)
	if not _check(not menu.visible and not _panel._inventory_grid.is_holding_item(), "right click while holding cancels transfer"):
		return
	await _click_item("core:food", MOUSE_BUTTON_RIGHT)
	_hud._refresh_inventory_panel()
	if not _check(not menu.visible, "refresh invalidates stale menu target"):
		return
	await _click_item("core:wood", MOUSE_BUTTON_RIGHT)
	var drop := _panel.get("_drop_button") as Button
	await _click(drop.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	if not _check(Session.simulation.get_item_count("core:wood") == 0 and Session.get_world_drops().size() == 1, "drop menu uses real stack command"):
		return
	await _click_item("core:food", MOUSE_BUTTON_RIGHT)
	_hud.toggle_inventory()
	if not _check(not menu.visible, "closing backpack closes context menu"):
		return
	_hud.toggle_inventory()
	get_window().size = Vector2i(640, 360)
	await get_tree().process_frame
	await get_tree().process_frame
	await _click_item("core:food", MOUSE_BUTTON_RIGHT)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot-path=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--screenshot-path=")) == OK, "render screenshot"):
				return
	await _click(extract.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	if not _check(Session.simulation.get_item_count("core:food") == 0 and int(Session.simulation.state.farming.roll_index) == 1 and not menu.visible, "seed action consumes the context target via real mouse input"):
		return
	print("PASS: inventory context mouse actions, food, seeds, study gate, drop, cancellation, stale targets, modal pause and viewport edges")
	get_tree().quit(0)


func _placement(item_id: String) -> Dictionary:
	for placement: Dictionary in _panel._inventory_grid._placements:
		if String(placement.item_id) == item_id:
			return placement
	return {}


func _click_item(item_id: String, button: MouseButton) -> void:
	var placement := _placement(item_id)
	assert(not placement.is_empty())
	var origin: Vector2i = placement.origin
	var cell: Vector2i = placement.footprint[0]
	await _click(_panel._inventory_grid.get_global_transform_with_canvas() * (Vector2(origin + cell) * InventoryGrid.CELL_SIZE + Vector2.ONE * 21), button)


func _click(position: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func _check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		get_tree().quit(1)
	return value
