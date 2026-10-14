class_name InventoryGrid
extends Control

signal selection_changed(placement: Dictionary)
signal equip_requested(placement: Dictionary)
signal context_requested(placement: Dictionary, pointer: Vector2)
signal layout_changed(layout: Array[Dictionary])
signal drop_requested(placement: Dictionary)
signal cross_grid_drop_requested(placement: Dictionary, target_cell: Vector2i)
signal quick_transfer_requested(placement: Dictionary)
signal hotbar_drop_requested(placement: Dictionary, slot_index: int)

const CELL_SIZE: float = 64.0
const CELL_GAP: float = 0.0
const FirstNightContent := preload("res://src/content/first_night_content.gd")
const PlacementRules := preload("res://src/inventory/inventory_placement_rules.gd")
const PlaceholderIcon := preload("res://src/items/item_placeholder_icon.gd")
const IconPresentation := preload("res://src/items/inventory_icon_presentation.gd")
const CursorVisual := preload("res://src/ui/inventory_cursor_visual.gd")

const AMOUNT_BADGE_COLOR := Color8(35, 27, 31, 235)
const AMOUNT_TEXT_COLOR := Color8(239, 226, 207)

const SLOT_TEXTURES: Dictionary = {
	"regular": {
		0: preload("res://assets/sprites/ui/inv_slot_regular_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_regular_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_regular_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_regular_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_regular_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_regular.png"),
	},
	"hover": {
		0: preload("res://assets/sprites/ui/inv_slot_hover_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_hover_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_hover_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_hover_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_hover_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_hover.png"),
	},
	"selected": {
		0: preload("res://assets/sprites/ui/inv_slot_selected_0side.png"),
		1: preload("res://assets/sprites/ui/inv_slot_selected_1side.png"),
		2: preload("res://assets/sprites/ui/inv_slot_selected_2side.png"),
		"2_parallel": preload("res://assets/sprites/ui/inv_slot_selected_2side_parallel.png"),
		3: preload("res://assets/sprites/ui/inv_slot_selected_3side.png"),
		4: preload("res://assets/sprites/ui/inv_slot_selected.png"),
	},
}

var _placements: Array[Dictionary] = []
var _cell_to_placement: Dictionary = {}
var _icon_cache: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _selected_placement_index: int = -1
var _selected_key: String = ""
var _dragged_placement_index: int = -1
var _drag_rotation: int = 0
var _drag_mouse_position := Vector2.ZERO
var _drag_start_origin := Vector2i.ZERO
var _drag_start_rotation: int = 0
var _drag_grab_cell := Vector2i.ZERO
var _drag_grab_offset := Vector2.ZERO
var _cursor_pointer_global := Vector2.ZERO
var _cursor_visual: Control
var _content: FirstNightContent
var grid_columns: int = 4
var grid_rows: int = 4
var external_drop_boundary: Control
var external_transfer_target: Control
var external_hotbar_target: Control


func _ready() -> void:
	_update_grid_minimum_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_exited.connect(_on_mouse_exited)
	var cursor_layer := CanvasLayer.new()
	cursor_layer.layer = 40
	add_child(cursor_layer)
	_cursor_visual = CursorVisual.new()
	cursor_layer.add_child(_cursor_visual)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_cancel_hand()
	)
	queue_redraw()


func configure_grid(columns: int, rows: int) -> void:
	grid_columns = maxi(1, columns)
	grid_rows = maxi(1, rows)
	_update_grid_minimum_size()
	queue_redraw()


func _update_grid_minimum_size() -> void:
	custom_minimum_size = Vector2(
		grid_columns * CELL_SIZE + (grid_columns - 1) * CELL_GAP,
		grid_rows * CELL_SIZE + (grid_rows - 1) * CELL_GAP
	)
	set_process_input(true)


func present(placements: Array[Dictionary], item_content: FirstNightContent = null) -> void:
	if item_content != null:
		_content = item_content
	elif _content == null:
		_content = FirstNightContent.new()
	var held: Dictionary = _placements[_dragged_placement_index].duplicate(true) if _dragged_placement_index >= 0 else {}
	_placements.clear()
	_cell_to_placement.clear()
	_selected_placement_index = -1
	_dragged_placement_index = -1
	if is_instance_valid(_cursor_visual):
		_cursor_visual.hide()

	for placement: Dictionary in placements:
		var placement_copy := placement.duplicate(true)
		placement_copy["icon_scale"] = _content.item_inventory_icon_scale(String(placement_copy.get("item_id", "")))
		var placement_index := _placements.size()
		_placements.append(placement_copy)
		_cache_placement_icon(placement_copy)
		_index_placement_cells(placement_copy, placement_index)

		if not held.is_empty() and _placement_key(placement_copy) == _placement_key(held) and String(placement_copy.get("instance_id", "")) == String(held.get("instance_id", "")) and placement_copy.get("origin") == held.get("origin") and placement_copy.get("rotation", 0) == held.get("rotation", 0) and placement_copy.get("footprint") == held.get("footprint"):
			_dragged_placement_index = placement_index
		if _placement_key(placement_copy) == _selected_key:
			_selected_placement_index = placement_index

	if _selected_placement_index < 0:
		_selected_key = ""

	if _dragged_placement_index >= 0:
		_update_cursor_visual()
	selection_changed.emit(get_selected_placement())
	queue_redraw()


func get_selected_placement() -> Dictionary:
	if _selected_placement_index < 0:
		return {}
	if _selected_placement_index >= _placements.size():
		return {}
	return _placements[_selected_placement_index].duplicate(true)


func _draw() -> void:
	for row: int in range(grid_rows):
		for column: int in range(grid_columns):
			var cell := Vector2i(column, row)
			var placement_index := int(
				_cell_to_placement.get(cell, -1)
			)
			if placement_index < 0:
				var empty_state := (
					"hover" if cell == _hover_cell else "regular"
				)
				_draw_slot(cell, empty_state, [cell])
				continue

			var state := _placement_state(placement_index)
			var occupied_cells := _placement_cells(
				_placements[placement_index]
			)
			_draw_slot(cell, state, occupied_cells)

	for placement_index: int in range(_placements.size()):
		if placement_index == _dragged_placement_index:
			continue
		var placement: Dictionary = _placements[placement_index]
		_draw_placement_icon(placement)
		_draw_placement_amount(placement)
	if _dragged_placement_index >= 0:
		_draw_dragged_placement()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.physical_keycode == KEY_R
			and _dragged_placement_index >= 0
		):
			var old_size := _footprint_bounds(_dragged_footprint()).size
			_drag_grab_cell = Vector2i(old_size.y - 1 - _drag_grab_cell.y, _drag_grab_cell.x)
			_drag_rotation = posmod(_drag_rotation + 1, 4)
			_update_cursor_visual()
			queue_redraw()
			accept_event()
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragged_placement_index >= 0:
			_drag_mouse_position = motion.position
			queue_redraw()
			accept_event()
			return
		_set_hover_cell(_cell_at_position(motion.position))
		return

	if event is not InputEventMouseButton:
		return

	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		if _dragged_placement_index >= 0:
			_cancel_hand()
		else:
			_select_placement(int(_cell_to_placement.get(_cell_at_position(mouse_button.position), -1)))
			context_requested.emit(get_selected_placement(), get_global_transform() * mouse_button.position)
		accept_event()
		return
	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := _cell_at_position(mouse_button.position)
	if _dragged_placement_index < 0:
		var placement_index := int(_cell_to_placement.get(cell, -1))
		_select_placement(placement_index)
		if placement_index >= 0:
			if mouse_button.shift_pressed:
				quick_transfer_requested.emit(_placements[placement_index].duplicate(true))
				accept_event()
				return
		equip_requested.emit(get_selected_placement())
		if _selected_placement_index >= 0:
			_begin_hand(_selected_placement_index, mouse_button.position)
		grab_focus()
		accept_event()
		return

	if cell.x < 0:
		return
	_finish_drag(cell - _drag_grab_cell)
	accept_event()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _dragged_placement_index < 0:
		return
	if event is InputEventMouseMotion:
		update_hand_position((event as InputEventMouseMotion).global_position)
		return
	if event is not InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	var pointer := mouse_button.global_position
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		_cancel_hand()
		get_viewport().set_input_as_handled()
	elif mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
		update_hand_position(pointer)
		if external_hotbar_target != null and external_hotbar_target.get_global_rect().has_point(pointer):
			var hotbar_slot := _hotbar_slot_at_global_position(pointer)
			if hotbar_slot >= 0:
				var placement := _placements[_dragged_placement_index].duplicate(true)
				placement["rotation"] = _drag_rotation
				placement["footprint"] = _dragged_footprint()
				if not String(placement.get("instance_id", "")).is_empty():
					hotbar_drop_requested.emit(placement, hotbar_slot)
			_cancel_hand()
			get_viewport().set_input_as_handled()
			return
		if _point_is_visible_in(external_transfer_target, pointer):
			var target_grid := external_transfer_target as InventoryGrid
			var target_pointer := external_transfer_target.get_global_transform_with_canvas().affine_inverse() * pointer
			var target_cell := _origin_for_pointer(target_pointer)
			# Bounds are geometric; stacking and occupancy are decided by the
			# simulation. The caller clears the cursor only after acceptance.
			if PlacementRules.can_place(_dragged_footprint(), target_cell, {}, target_grid.grid_columns, target_grid.grid_rows):
				var placement := _placements[_dragged_placement_index].duplicate(true)
				placement["rotation"] = _drag_rotation
				placement["footprint"] = _dragged_footprint()
				cross_grid_drop_requested.emit(placement, target_cell)
			get_viewport().set_input_as_handled()
			return
		if _point_is_visible_in(self, pointer):
			if _is_drag_target_valid(_cursor_target_cell()):
				_finish_drag(_cursor_target_cell())
				_cancel_hand()
			get_viewport().set_input_as_handled()
			return
		if external_drop_boundary != null and external_drop_boundary.get_global_rect().has_point(pointer):
			return
		var placement := _placements[_dragged_placement_index].duplicate(true)
		drop_requested.emit(placement)
		_cancel_hand()
		get_viewport().set_input_as_handled()


static func _point_is_visible_in(target: Control, point: Vector2) -> bool:
	if target == null or not target.is_visible_in_tree() or not target.get_global_rect().has_point(point):
		return false
	# _input runs before GUI clipping. Hidden rows of a scrolled grid must not
	# receive placements or transfers merely because its full rect contains them.
	var ancestor := target.get_parent()
	while ancestor != null:
		var control := ancestor as Control
		if control != null and control.clip_contents and not control.get_global_rect().has_point(point):
			return false
		ancestor = ancestor.get_parent()
	return true


func _hotbar_slot_at_global_position(global_position: Vector2) -> int:
	if external_hotbar_target == null:
		return -1
	for slot_index: int in range(5):
		var slot := external_hotbar_target.get_node_or_null("Slot%d" % (slot_index + 1)) as Control
		if slot != null and slot.get_global_rect().has_point(global_position):
			return slot_index
	return -1


func _finish_drag(target_cell: Vector2i) -> void:
	var dragged := _placements[_dragged_placement_index]
	var swapped_index := _swap_target_index(target_cell)
	if swapped_index >= 0:
		var displaced := _placements[swapped_index].duplicate(true)
		var old_origin: Vector2i = dragged.origin
		var original_grab := _drag_grab_cell
		var original_offset := _drag_grab_offset
		var candidate: Array[Dictionary] = []
		for index: int in range(_placements.size()):
			var entry := _layout_entry(_placements[index])
			if index == _dragged_placement_index:
				entry.origin = [target_cell.x,target_cell.y]
				entry.rotation = _drag_rotation
			elif index == swapped_index: entry.origin = [old_origin.x,old_origin.y]
			candidate.append(entry)
		_swap_in_flight = true
		layout_changed.emit(candidate)
		_swap_in_flight = false
		# Re-presentation comes only after simulation accepts both placements.
		for index: int in range(_placements.size()):
			if _placement_key(_placements[index]) == _placement_key(displaced) and _placements[index].origin == old_origin:
				_begin_hand(index,Vector2(old_origin+original_grab)*CELL_SIZE+original_offset)
				return
		return
	var candidate_layout: Array[Dictionary] = []
	for index: int in range(_placements.size()):
		if index == _dragged_placement_index:
			continue
		var placement: Dictionary = _placements[index]
		candidate_layout.append(_layout_entry(placement))
	if _is_drag_target_valid(target_cell):
		var moved := dragged.duplicate(true)
		moved["origin"] = target_cell
		moved["rotation"] = _drag_rotation
		moved["footprint"] = _dragged_footprint()
		candidate_layout.append(_layout_entry(moved))
		layout_changed.emit(candidate_layout)
	queue_redraw()


func _cancel_hand() -> void:
	if is_instance_valid(_cursor_visual):
		_cursor_visual.hide()
	if _dragged_placement_index < 0:
		return
	_dragged_placement_index = -1
	_drag_rotation = 0
	queue_redraw()


func _is_drag_target_valid(target_cell: Vector2i) -> bool:
	if (
		_dragged_placement_index < 0
		or target_cell.x < 0 or target_cell.y < 0
	):
		return false
	if _swap_target_index(target_cell) >= 0: return true
	var occupied: Dictionary = {}
	for index: int in range(_placements.size()):
		if index == _dragged_placement_index:
			continue
		var placement: Dictionary = _placements[index]
		var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
		for local_cell: Vector2i in placement.get("footprint", []):
			occupied[origin + local_cell] = true
	return PlacementRules.can_place(
		_dragged_footprint(), target_cell, occupied,
		grid_columns, grid_rows
	)


var _swap_in_flight := false
func is_swapping() -> bool: return _swap_in_flight

func _swap_target_index(target_cell: Vector2i) -> int:
	if _dragged_placement_index < 0: return -1
	var dragged := _placements[_dragged_placement_index]
	var candidate_index := int(_cell_to_placement.get(target_cell+_drag_grab_cell,-1))
	if candidate_index < 0 or candidate_index == _dragged_placement_index: return -1
	var displaced := _placements[candidate_index]
	var shape := _dragged_footprint()
	var other_shape: Array = displaced.footprint
	if shape.size() != other_shape.size(): return -1
	for cell: Vector2i in shape:
		if not other_shape.has(cell): return -1
	var used := {}
	for index: int in range(_placements.size()):
		if index == candidate_index or index == _dragged_placement_index: continue
		for cell: Vector2i in _placement_cells(_placements[index]): used[cell] = true
	var old_origin: Vector2i = dragged.origin
	if not PlacementRules.can_place(shape,target_cell,used,grid_columns,grid_rows): return -1
	for cell: Vector2i in shape: used[target_cell+cell] = true
	if not PlacementRules.can_place(_content.item_footprint(String(displaced.item_id),int(displaced.rotation)),old_origin,used,grid_columns,grid_rows): return -1
	return candidate_index


func _dragged_footprint() -> Array[Vector2i]:
	var dragged: Dictionary = _placements[_dragged_placement_index]
	return _content.item_footprint(String(dragged.get("item_id", "")), _drag_rotation)


func _begin_hand(placement_index: int, mouse_position: Vector2) -> void:
	_dragged_placement_index = placement_index
	var placement := _placements[placement_index]
	_drag_rotation = int(placement.get("rotation", 0))
	_drag_start_rotation = _drag_rotation
	_drag_start_origin = placement.get("origin", Vector2i.ZERO)
	_drag_mouse_position = mouse_position
	_cursor_pointer_global = get_global_transform_with_canvas() * mouse_position
	_drag_grab_cell = _cell_at_position(mouse_position) - _drag_start_origin
	_drag_grab_offset = mouse_position - Vector2(_drag_start_origin + _drag_grab_cell) * CELL_SIZE
	_update_cursor_visual()
	queue_redraw()


func _cursor_target_cell() -> Vector2i:
	return _origin_for_pointer(_drag_mouse_position)


func _origin_for_pointer(pointer: Vector2) -> Vector2i:
	# Snap the grabbed cell to the pointer cell, not the item's pixel corner.
	return Vector2i(floori(pointer.x / CELL_SIZE), floori(pointer.y / CELL_SIZE)) - _drag_grab_cell


func _process(_delta: float) -> void:
	if _dragged_placement_index >= 0:
		_update_cursor_visual()


func _update_cursor_visual() -> void:
	if not is_instance_valid(_cursor_visual) or _dragged_placement_index < 0:
		return
	var screen_scale := get_global_transform_with_canvas().get_scale().abs()
	_drag_mouse_position = get_global_transform_with_canvas().affine_inverse() * _cursor_pointer_global
	var extent := Vector2(_footprint_bounds(_dragged_footprint()).size) * CELL_SIZE * screen_scale
	_cursor_visual.size = extent
	_cursor_visual.position = _cursor_pointer_global - (Vector2(_drag_grab_cell) * CELL_SIZE + _drag_grab_offset) * screen_scale
	_cursor_visual.set("texture", _placement_icon(_placements[_dragged_placement_index]))
	_cursor_visual.set("rotation_steps", _drag_rotation)
	_cursor_visual.set("icon_scale", _placements[_dragged_placement_index].get("icon_scale", Vector2.ZERO))
	_cursor_visual.set("inset", 5.0 * screen_scale.x)
	_cursor_visual.set("amount", int(_placements[_dragged_placement_index].get("amount", 1)))
	_cursor_visual.show()
	_cursor_visual.queue_redraw()


func _layout_entry(placement: Dictionary) -> Dictionary:
	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	return {
		"item_id": String(placement.get("item_id", "")),
		"stack_index": int(placement.get("stack_index", 0)),
		"origin": [origin.x, origin.y],
		"rotation": int(placement.get("rotation", 0)),
	}


func _draw_dragged_placement() -> void:
	var cell := _cursor_target_cell()
	var preview_color := (
		Color(0.85, 0.95, 0.65, 0.34)
		if _is_drag_target_valid(cell)
		else Color(0.95, 0.35, 0.3, 0.38)
	)
	for local_cell: Vector2i in _dragged_footprint():
		var target_cell := cell + local_cell
		if target_cell.x < 0 or target_cell.y < 0 or target_cell.x >= grid_columns or target_cell.y >= grid_rows:
			continue
		var rect := _cell_rect(target_cell)
		draw_rect(rect, preview_color, true)
	if cell == _drag_start_origin and _drag_rotation == _drag_start_rotation:
		return


func return_held_item() -> void:
	_cancel_hand()


func is_holding_item() -> bool:
	return _dragged_placement_index >= 0


func cell_at_global_position(global_position: Vector2) -> Vector2i:
	return _control_cell_at_global_position(self, global_position)


func _control_cell_at_global_position(control: Control, global_position: Vector2) -> Vector2i:
	var local_position := control.get_global_transform_with_canvas().affine_inverse() * global_position
	return (control as InventoryGrid)._cell_at_position(local_position)


func update_hand_position(global_position: Vector2) -> void:
	if _dragged_placement_index < 0:
		return
	_cursor_pointer_global = global_position
	_drag_mouse_position = get_global_transform_with_canvas().affine_inverse() * global_position
	_update_cursor_visual()
	queue_redraw()


func _draw_slot(
	cell: Vector2i,
	state: String,
	occupied_cells: Array[Vector2i]
) -> void:
	var exposed := {
		"left": not occupied_cells.has(cell + Vector2i.LEFT),
		"top": not occupied_cells.has(cell + Vector2i.UP),
		"right": not occupied_cells.has(cell + Vector2i.RIGHT),
		"bottom": not occupied_cells.has(cell + Vector2i.DOWN),
	}
	var exposed_count: int = 0
	for value: bool in exposed.values():
		if value:
			exposed_count += 1

	var texture_key: Variant = exposed_count
	var rotation := 0.0
	if exposed_count == 1:
		rotation = _single_side_rotation(exposed)
	elif exposed_count == 2:
		if bool(exposed.left) and bool(exposed.right):
			texture_key = "2_parallel"
		elif bool(exposed.top) and bool(exposed.bottom):
			texture_key = "2_parallel"
			rotation = PI / 2.0
		else:
			rotation = _adjacent_sides_rotation(exposed)
	elif exposed_count == 3:
		rotation = _three_sides_rotation(exposed)

	var state_textures := SLOT_TEXTURES.get(
		state,
		SLOT_TEXTURES["regular"]
	) as Dictionary
	var texture := state_textures.get(texture_key) as Texture2D
	if texture == null:
		return

	var cell_rect := _cell_rect(cell)
	var center := cell_rect.get_center()
	draw_set_transform(center, rotation, Vector2.ONE)
	draw_texture_rect(
		texture,
		Rect2(-cell_rect.size / 2.0, cell_rect.size),
		false
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _placement_state(placement_index: int) -> String:
	if placement_index == _selected_placement_index:
		return "selected"
	var hovered_index := int(
		_cell_to_placement.get(_hover_cell, -1)
	)
	if placement_index == hovered_index:
		return "hover"
	return "regular"


func _draw_placement_amount(placement: Dictionary) -> void:
	var amount := int(placement.get("amount", 1))
	if amount <= 1:
		return

	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var bounds := _footprint_bounds(placement.get("footprint", []) as Array)
	var footprint_rect := Rect2(
		_cell_rect(origin + bounds.position).position,
		Vector2(bounds.size) * CELL_SIZE + (Vector2(bounds.size) - Vector2.ONE) * CELL_GAP
	)
	var badge_rect := Rect2(
		footprint_rect.end - Vector2(20.0, 16.0),
		Vector2(18.0, 14.0)
	)
	draw_rect(badge_rect, AMOUNT_BADGE_COLOR, true)
	draw_string(
		ThemeDB.fallback_font,
		badge_rect.position + Vector2(3.0, 11.0),
		str(amount),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		11,
		AMOUNT_TEXT_COLOR
	)


func _draw_placement_icon(placement: Dictionary) -> void:
	var texture := _placement_icon(placement)
	if texture == null:
		return

	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var bounds := _footprint_bounds(placement.get("footprint", []) as Array)
	var footprint_rect := Rect2(
		_cell_rect(origin + bounds.position).position,
		Vector2(bounds.size) * CELL_SIZE + (Vector2(bounds.size) - Vector2.ONE) * CELL_GAP
	)
	_draw_rotated_icon(texture, footprint_rect, int(placement.get("rotation", 0)), Color.WHITE, placement.get("icon_scale", Vector2.ZERO))


func _draw_rotated_icon(
	texture: Texture2D,
	footprint_rect: Rect2,
	quarter_turns: int,
	modulate: Color = Color.WHITE,
	icon_scale: Vector2 = Vector2.ZERO
) -> void:
	IconPresentation.draw_icon(self, texture, footprint_rect, quarter_turns, 5.0, modulate, icon_scale)


func _footprint_bounds(footprint: Array) -> Rect2i:
	if footprint.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var min_cell := Vector2i(9999, 9999)
	var max_cell := Vector2i(-9999, -9999)
	for cell_variant: Variant in footprint:
		if not cell_variant is Vector2i:
			continue
		var cell: Vector2i = cell_variant
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _cache_placement_icon(placement: Dictionary) -> void:
	var icon_path := String(placement.get("icon_path", ""))
	if icon_path.is_empty() or _icon_cache.has(icon_path):
		return
	if not ResourceLoader.exists(icon_path):
		return

	var texture := load(icon_path) as Texture2D
	if texture != null:
		_icon_cache[icon_path] = texture


func _placement_icon(placement: Dictionary) -> Texture2D:
	var icon_path := String(placement.get("icon_path", ""))
	if not icon_path.is_empty() and _icon_cache.has(icon_path):
		return _icon_cache[icon_path] as Texture2D
	return PlaceholderIcon.texture_for(String(placement.get("item_id", "")))


func _index_placement_cells(
	placement: Dictionary,
	placement_index: int
) -> void:
	for cell: Vector2i in _placement_cells(placement):
		_cell_to_placement[cell] = placement_index


func _placement_cells(placement: Dictionary) -> Array[Vector2i]:
	var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
	var footprint := placement.get("footprint", []) as Array
	var cells: Array[Vector2i] = []
	for local_cell_variant: Variant in footprint:
		var local_cell: Vector2i = local_cell_variant
		cells.append(origin + local_cell)
	return cells


func _select_placement(placement_index: int) -> void:
	_selected_placement_index = placement_index
	if placement_index < 0:
		_selected_key = ""
	else:
		_selected_key = _placement_key(_placements[placement_index])
	selection_changed.emit(get_selected_placement())
	queue_redraw()


func _placement_key(placement: Dictionary) -> String:
	return "%s:%d" % [
		String(placement.get("item_id", "")),
		int(placement.get("stack_index", 0)),
	]


func _set_hover_cell(cell: Vector2i) -> void:
	if _hover_cell == cell:
		return
	_hover_cell = cell
	queue_redraw()


func _on_mouse_exited() -> void:
	_set_hover_cell(Vector2i(-1, -1))


func _cell_at_position(local_position: Vector2) -> Vector2i:
	if local_position.x < 0.0 or local_position.y < 0.0:
		return Vector2i(-1, -1)
	var stride := CELL_SIZE + CELL_GAP
	var cell := Vector2i(
		int(floor(local_position.x / stride)),
		int(floor(local_position.y / stride))
	)
	if cell.x < 0 or cell.x >= grid_columns:
		return Vector2i(-1, -1)
	if cell.y < 0 or cell.y >= grid_rows:
		return Vector2i(-1, -1)
	var within_cell := local_position - Vector2(cell) * stride
	if within_cell.x >= CELL_SIZE or within_cell.y >= CELL_SIZE:
		return Vector2i(-1, -1)
	return cell


func _cell_rect(cell: Vector2i) -> Rect2:
	var position := Vector2(cell) * (CELL_SIZE + CELL_GAP)
	return Rect2(position, Vector2(CELL_SIZE, CELL_SIZE))


func _single_side_rotation(exposed: Dictionary) -> float:
	if bool(exposed.top):
		return PI / 2.0
	if bool(exposed.right):
		return PI
	if bool(exposed.bottom):
		return -PI / 2.0
	return 0.0


func _adjacent_sides_rotation(exposed: Dictionary) -> float:
	if bool(exposed.top) and bool(exposed.right):
		return PI / 2.0
	if bool(exposed.right) and bool(exposed.bottom):
		return PI
	if bool(exposed.bottom) and bool(exposed.left):
		return -PI / 2.0
	return 0.0


func _three_sides_rotation(exposed: Dictionary) -> float:
	if not bool(exposed.left):
		return PI / 2.0
	if not bool(exposed.top):
		return PI
	if not bool(exposed.right):
		return -PI / 2.0
	return 0.0
