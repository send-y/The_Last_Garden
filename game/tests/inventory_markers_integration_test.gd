extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")


func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	var state := Simulation.create_new_state()
	var inventory: Dictionary = state["inventory"] as Dictionary
	inventory["core:wood"] = 1
	inventory["core:raw_water"] = 1
	inventory["core:food"] = 1
	Session.apply_debug_state(state, "inventory and marker integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var inventory_panel := hud.get_node("InventoryPanel") as InventoryPanel
	var grid := inventory_panel.get_node(
		"ContentMargin/ContentColumn/GridCenter/InventoryGrid"
	) as InventoryGrid
	hud.toggle_inventory()
	await get_tree().process_frame
	var wood_cell := _placement_cell(grid, "core:wood")
	var water_cell := _placement_cell(grid, "core:raw_water")
	_send_mouse_button(_cell_center(grid, wood_cell), true)
	_send_mouse_motion(_cell_center(grid, Vector2i(3, 3)))
	_send_mouse_button(_cell_center(grid, Vector2i(3, 3)), false)
	await get_tree().process_frame
	if not _layout_has("core:wood", Vector2i(3, 3), 0):
		_fail("Dragging an item did not preserve its new inventory position.")
		return

	_send_mouse_button(_cell_center(grid, water_cell), true)
	var rotated_target := Vector2i(0, 2)
	_send_mouse_motion(_cell_center(grid, rotated_target))
	_send_key(KEY_R)
	_send_mouse_button(_cell_center(grid, rotated_target), false)
	await get_tree().process_frame
	if not _layout_has("core:raw_water", rotated_target, 1):
		_fail("R did not rotate and place the two-cell water item.")
		return

	var food_cell := _placement_cell(grid, "core:food")
	_send_mouse_button(_cell_center(grid, food_cell), true)
	_send_mouse_button(_cell_center(grid, food_cell), false)
	await get_tree().process_frame
	var eat_button := inventory_panel.get_node(
		"ContentMargin/ContentColumn/DetailsPanel/DetailsMargin/DetailsRow/EatButton"
	) as Button
	if not eat_button.visible:
		_fail("Food selection did not reveal the eat button.")
		return
	_send_mouse_button(eat_button.get_global_rect().get_center(), true)
	_send_mouse_button(eat_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	if Session.get_inventory().get("core:food", 0) != 0:
		_fail("Eating berries did not consume one serving.")
		return

	var close_button := inventory_panel.get_node(
		"ContentMargin/ContentColumn/HeaderRow/CloseButton"
	) as Button
	_send_mouse_button(close_button.get_global_rect().get_center(), true)
	_send_mouse_button(close_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	_send_key(KEY_L, true)
	await get_tree().process_frame
	if not hud.is_modal_open():
		_fail("Shift+L did not open the marker list.")
		return
	_send_key(KEY_L, true)
	await get_tree().process_frame
	if hud.is_modal_open():
		_fail("Shift+L did not close the marker list when toggled again.")
		return
	_send_key(KEY_L)
	await get_tree().process_frame
	var marker_name_input := hud.get_node_or_null("MarkerPanel/MarkerContentMargin/MarkerColumn/MarkerNameRow/MarkerNameInput") as LineEdit
	if marker_name_input == null:
		_fail("Marker creation dialog is missing its name field.")
		return
	marker_name_input.text = "Camp"
	var save_button := marker_name_input.get_parent().get_node("MarkerSaveButton") as Button
	_send_mouse_button(save_button.get_global_rect().get_center(), true)
	_send_mouse_button(save_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	var markers := Session.get_markers()
	if markers.size() != 1 or String(markers[0].get("name", "")) != "Camp":
		_fail("L did not create a named marker. count=%d mode=%s input=%s button=%s result=%s" % [
			markers.size(), hud.is_modal_open(), marker_name_input.text,
			save_button.get_global_rect(), Session.get_state().get("markers", []),
		])
		return
	_send_key(KEY_L, true)
	await get_tree().process_frame
	var marker_list := hud.get_node(
		"MarkerPanel/MarkerContentMargin/MarkerColumn/MarkerScroll/MarkerList"
	) as VBoxContainer
	if marker_list.get_child_count() != 1:
		_fail("Marker list did not show the created marker.")
		return
	var marker_row := marker_list.get_child(0) as HBoxContainer
	var rename_button := marker_row.get_child(2) as Button
	var button_position := rename_button.get_global_rect().get_center()
	_send_mouse_motion(button_position)
	_send_mouse_button(button_position, true)
	_send_mouse_button(button_position, false)
	await get_tree().process_frame
	marker_name_input.text = "Camp entrance"
	_send_mouse_button(save_button.get_global_rect().get_center(), true)
	_send_mouse_button(save_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	if Session.get_markers().size() != 1 or String(Session.get_markers()[0].get("name", "")) != "Camp entrance":
		_fail("Marker list rename did not save the new name.")
		return
	_send_key(KEY_L, true)
	await get_tree().process_frame
	if not hud.is_marker_list_open():
		_fail("Shift+L did not reopen the list for marker deletion.")
		return
	marker_row = marker_list.get_child(0) as HBoxContainer
	var marker_toggle_button := marker_row.get_child(3) as Button
	marker_toggle_button.pressed.emit()
	await get_tree().process_frame
	if bool(Session.get_markers()[0].get("enabled", true)):
		_fail("Temporarily disabling a marker did not hide it in saved state.")
		return
	marker_row = marker_list.get_child(0) as HBoxContainer
	marker_toggle_button = marker_row.get_child(3) as Button
	marker_toggle_button.pressed.emit()
	await get_tree().process_frame
	if not bool(Session.get_markers()[0].get("enabled", false)):
		_fail("A disabled marker could not be enabled again.")
		return
	marker_row = marker_list.get_child(0) as HBoxContainer
	var delete_button := marker_row.get_child(4) as Button
	delete_button.pressed.emit()
	await get_tree().process_frame
	if not Session.get_markers().is_empty():
		_fail("Delete from marker list did not remove the marker.")
		return
	print("PASS: inventory move, R rotation, berry consumption, and marker shortcuts work")
	get_tree().quit(0)


func _placement_cell(grid: InventoryGrid, item_id: String) -> Vector2i:
	for placement: Dictionary in Session.get_inventory_layout():
		if String(placement.get("item_id", "")) == item_id:
			var origin := placement.get("origin", []) as Array
			if origin.size() == 2:
				return Vector2i(int(origin[0]), int(origin[1]))
	return Vector2i(-1, -1)


func _cell_center(grid: InventoryGrid, cell: Vector2i) -> Vector2:
	return grid.get_global_rect().position + Vector2(cell) * 44.0 + Vector2(21.0, 21.0)


func _layout_has(item_id: String, origin: Vector2i, rotation: int) -> bool:
	for placement: Dictionary in Session.get_inventory_layout():
		var raw_origin := placement.get("origin", []) as Array
		if (
			String(placement.get("item_id", "")) == item_id
			and raw_origin.size() == 2
			and Vector2i(int(raw_origin[0]), int(raw_origin[1])) == origin
			and int(placement.get("rotation", 0)) == rotation
		):
			return true
	return false


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	get_viewport().push_input(event, true)


func _send_mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	get_viewport().push_input(event, true)


func _send_key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	get_viewport().push_input(event, true)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
