class_name ConstructionCursor
extends Node2D

signal cell_selected(cell: Vector2i)
signal cell_cancel_requested(cell: Vector2i)
signal cell_completion_requested(cell: Vector2i)

const CELL_SIZE: int = 32

var _cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	z_index = 20


func _process(_delta: float) -> void:
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
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		cell_selected.emit(_cell)
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		cell_cancel_requested.emit(_cell)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		cell_completion_requested.emit(_cell)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var rect := Rect2(
		Vector2.ZERO,
		Vector2(CELL_SIZE, CELL_SIZE)
	)
	draw_rect(rect, Color(0.95, 0.78, 0.25, 0.22), true)
	draw_rect(rect, Color(0.95, 0.78, 0.25, 0.95), false, 2.0)
