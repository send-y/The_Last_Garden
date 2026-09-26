class_name ConstructionCursor
extends Node2D

signal cell_selected(cell: Vector2i)
signal cell_cancel_requested(cell: Vector2i)
signal cell_completion_requested(cell: Vector2i)
signal storage_area_selected(from_cell: Vector2i, to_cell: Vector2i)
signal storage_zone_cancel_requested(cell: Vector2i)

const CELL_SIZE: int = 32

var _cell: Vector2i = Vector2i(-1, -1)
var _build_mode_active: bool = false
var _storage_mode_active: bool = false
var _storage_drag_active: bool = false
var _storage_drag_start := Vector2i(-1, -1)
var _storage_drag_end := Vector2i(-1, -1)


func _ready() -> void:
	z_index = 20
	set_build_mode_active(false)


func set_build_mode_active(active: bool) -> void:
	_build_mode_active = active
	visible = active
	set_process(active)
	if not active:
		_storage_drag_active = false
		queue_redraw()


func set_storage_mode_active(active: bool) -> void:
	_storage_mode_active = active
	_storage_drag_active = false
	queue_redraw()


func _process(_delta: float) -> void:
	_update_cell_from_mouse()


func _update_cell_from_mouse() -> void:
	var mouse_position: Vector2 = get_global_mouse_position()
	var next_cell := Vector2i(
		floori(mouse_position.x / CELL_SIZE),
		floori(mouse_position.y / CELL_SIZE)
	)

	if next_cell == _cell:
		return

	_cell = next_cell
	position = Vector2(
		_cell.x * CELL_SIZE,
		_cell.y * CELL_SIZE
	)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _build_mode_active:
		return
	_update_cell_from_mouse()
	var hud := get_node_or_null("../Hud/HudRoot")
	if hud != null and bool(hud.call("is_modal_open")):
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton):
		if _storage_mode_active and event is InputEventMouseMotion:
			_storage_drag_end = _cell
			queue_redraw()
		return

	var mouse_event := event as InputEventMouseButton
	if _storage_mode_active:
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_storage_drag_start = _cell
				_storage_drag_end = _cell
				_storage_drag_active = true
			else:
				if _storage_drag_active:
					_storage_drag_end = _cell
					storage_area_selected.emit(
						_storage_drag_start,
						_storage_drag_end
					)
				_storage_drag_active = false
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			storage_zone_cancel_requested.emit(_cell)
			get_viewport().set_input_as_handled()
			return
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		cell_selected.emit(_cell)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		cell_cancel_requested.emit(_cell)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		cell_completion_requested.emit(_cell)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _storage_mode_active and _storage_drag_active:
		var first := Vector2i(
			mini(_storage_drag_start.x, _storage_drag_end.x),
			mini(_storage_drag_start.y, _storage_drag_end.y)
		)
		var last := Vector2i(
			maxi(_storage_drag_start.x, _storage_drag_end.x),
			maxi(_storage_drag_start.y, _storage_drag_end.y)
		)
		var selection_rect := Rect2(
			Vector2((first - _cell) * CELL_SIZE),
			Vector2((last - first + Vector2i.ONE) * CELL_SIZE)
		)
		draw_rect(selection_rect, Color(0.36, 0.72, 0.62, 0.25), true)
		draw_rect(selection_rect, Color(0.55, 0.9, 0.75, 0.95), false, 2.0)
	var rect := Rect2(
		Vector2.ZERO,
		Vector2(CELL_SIZE, CELL_SIZE)
	)
	draw_rect(rect, Color(0.95, 0.78, 0.25, 0.22), true)
	draw_rect(rect, Color(0.95, 0.78, 0.25, 0.95), false, 2.0)
