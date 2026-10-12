extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")


func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	var state := Simulation.create_new_state()
	var inventory: Dictionary = state["inventory"] as Dictionary
	inventory["core:wood"] = 1
	inventory["core:raw_water"] = 1
	inventory["core:food"] = 1
	state["item_instances"] = [{
		"instance_id": "core:item_instance_000001",
		"item_id": "core:bucket",
		"state": {"charges": 1},
		"location": {"kind": "inventory", "id": ""},
	}]
	state["next_item_instance_serial"] = 2
	Session.apply_debug_state(state, "inventory and marker integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var inventory_panel := hud.get_node("InventoryPanel") as InventoryPanel
	var hotbar := hud.get_node("Hotbar") as Control
	var grid := inventory_panel.get_node(
		"ContentMargin/ContentColumn/GridCenter/InventoryGrid"
	) as InventoryGrid
	hud.toggle_inventory()
	await get_tree().process_frame
	var panel_rect := inventory_panel.get_global_rect()
	var hotbar_rect := hotbar.get_global_rect()
	if panel_rect.intersects(hotbar_rect) or not is_equal_approx(panel_rect.get_center().x, hotbar_rect.get_center().x):
		_fail("Inventory panel is not centered above the accessible hotbar. panel=%s hotbar=%s" % [panel_rect, hotbar_rect])
		return
	if panel_rect.end.y > hotbar_rect.position.y or hotbar_rect.position.y - panel_rect.end.y > 12.0:
		_fail("Inventory panel is not positioned just above the hotbar. panel=%s hotbar=%s" % [panel_rect, hotbar_rect])
		return
	var bucket_cell := _placement_cell(grid, "core:bucket")
	if bucket_cell == Vector2i(-1, -1):
		_fail("The individual bucket instance is missing from the backpack UI.")
		return
	_send_mouse_button(_cell_center(grid, bucket_cell), true)
	_send_mouse_button(_cell_center(grid, bucket_cell), false)
	_send_key(KEY_1)
	await get_tree().process_frame
	var assigned_bucket_id := Session.get_hotbar_slots()[0]
	if assigned_bucket_id != "core:item_instance_000001":
		_fail("Number 1 did not assign the selected bucket instance to the hotbar.")
		return
	# Assignment keeps the click-to-carry cursor; finish that gesture before
	# starting an independent transfer to another hotbar slot.
	grid.return_held_item()
	_send_mouse_button(_cell_center(grid, bucket_cell), true)
	_send_mouse_button(_cell_center(grid, bucket_cell), false)
	var slot_two := hud.get_node("Hotbar/Slot2") as Button
	var slot_two_position := slot_two.get_global_rect().get_center()
	_send_mouse_motion(slot_two_position)
	_send_mouse_button(slot_two_position, true)
	_send_mouse_button(slot_two_position, false)
	await get_tree().process_frame
	var hotbar_slots := Session.get_hotbar_slots()
	if hotbar_slots[0] != "" or hotbar_slots[1] != assigned_bucket_id:
		_fail("Dragging onto hotbar slot 2 did not move the bucket assignment.")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	var hotbar_slot := hud.get_node("Hotbar/Slot2") as Button
	hotbar_slot.pressed.emit()
	await get_tree().process_frame
	if Session.get_active_hotbar_slot() != 1:
		_fail("Clicking hotbar slot 2 did not select it.")
		return
	var shoreline_position := Content.cell_center(7, 27)
	Session.set_player_position(shoreline_position)
	(main.get_node("Player") as PlayerController).global_position = shoreline_position
	var raw_water_before := int(Session.get_inventory().get("core:raw_water", 0))
	var world := main.get_node("World") as FirstNightWorld
	world.select_at_world_position(shoreline_position)
	world.interact_with_selection(false)
	await get_tree().process_frame
	var filled_bucket := Session.get_item_instance(assigned_bucket_id)
	if int((filled_bucket.get("state", {}) as Dictionary).get("charges", 0)) != 2:
		_fail("Interacting with the shore while the bucket is selected did not fill it.")
		return
	if int(Session.get_inventory().get("core:raw_water", 0)) != raw_water_before:
		_fail("Bucket filling also granted legacy raw water, duplicating the interaction reward.")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	var wood_cell := _placement_cell(grid, "core:wood")
	var water_cell := _placement_cell(grid, "core:raw_water")
	_send_mouse_button(_cell_center(grid, wood_cell), true)
	_send_mouse_button(_cell_center(grid, wood_cell), false)
	_send_mouse_motion(_cell_center(grid, Vector2i(3, 3)))
	_send_mouse_button(_cell_center(grid, Vector2i(3, 3)), true)
	_send_mouse_button(_cell_center(grid, Vector2i(3, 3)), false)
	await get_tree().process_frame
	if not _layout_has("core:wood", Vector2i(3, 3), 0):
		_fail("Drag-and-release did not preserve the new inventory position.")
		return

	_send_mouse_button(_cell_center(grid, water_cell), true)
	_send_mouse_button(_cell_center(grid, water_cell), false)
	var rotated_target := Vector2i(0, 2)
	_send_key(KEY_R)
	var rotated_point := grid.get_global_transform_with_canvas() * ((Vector2(rotated_target + grid._drag_grab_cell) + Vector2.ONE * 0.5) * grid.CELL_SIZE)
	_send_mouse_motion(rotated_point)
	_send_mouse_button(rotated_point, true)
	_send_mouse_button(rotated_point, false)
	await get_tree().process_frame
	if not _layout_has("core:raw_water", rotated_target, 1):
		_fail("R did not rotate and place the two-cell water item.")
		return

	var food_cell := _placement_cell(grid, "core:food")
	_send_mouse_button(_cell_center(grid, food_cell), true, MOUSE_BUTTON_RIGHT)
	_send_mouse_button(_cell_center(grid, food_cell), false, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	var eat_button := inventory_panel._eat_button
	if not eat_button.visible:
		_fail("Food selection did not reveal the eat button.")
		return
	_send_mouse_button(eat_button.get_global_rect().get_center(), true)
	_send_mouse_button(eat_button.get_global_rect().get_center(), false)
	await get_tree().process_frame
	if Session.get_inventory().get("core:food", 0) != 0:
		_fail("Eating berries did not consume one serving.")
		return

	wood_cell = _placement_cell(grid, "core:wood")
	_send_mouse_button(_cell_center(grid, wood_cell), true)
	_send_mouse_button(_cell_center(grid, wood_cell), false)
	var inventory_rect := inventory_panel.get_global_rect()
	var outside_inventory := inventory_rect.position + Vector2(-6.0, inventory_rect.size.y * 0.5)
	_send_mouse_motion(outside_inventory)
	_send_mouse_button(outside_inventory, true)
	_send_mouse_button(outside_inventory, false)
	await get_tree().process_frame
	if Session.get_inventory().get("core:wood", 0) != 0:
		_fail("Clicking outside the open inventory did not drop the held item.")
		return
	var world_drops := Session.get_world_drops()
	if world_drops.is_empty() or int((world_drops.back() as Dictionary).get("amount", 0)) != 1:
		_fail("The dropped inventory item did not become one world-loot stack.")
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
	print("PASS: inventory move, bucket hotbar drag assignment, R rotation, berry consumption, and marker shortcuts work")
	get_tree().quit(0)


func _placement_cell(grid: InventoryGrid, item_id: String) -> Vector2i:
	for placement: Dictionary in Session.get_inventory_layout():
		if String(placement.get("item_id", "")) == item_id:
			var origin := placement.get("origin", []) as Array
			if origin.size() == 2:
				return Vector2i(int(origin[0]), int(origin[1]))
	return Vector2i(-1, -1)


func _cell_center(grid: InventoryGrid, cell: Vector2i) -> Vector2:
	var stride := InventoryGrid.CELL_SIZE + InventoryGrid.CELL_GAP
	return grid.get_global_transform_with_canvas() * (Vector2(cell) * stride + Vector2.ONE * InventoryGrid.CELL_SIZE * 0.5)


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


func _send_mouse_button(position: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
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
