class_name StructureLayer
extends Node2D

const CELL_SIZE: int = 32
const WALL_COLOR := Color(0.38, 0.27, 0.18, 1.0)
const OUTLINE_COLOR := Color(0.18, 0.12, 0.08, 1.0)

var _collision_bodies: Array[StaticBody2D] = []


func _ready() -> void:
	Session.state_changed.connect(_refresh)
	Session.state_reloaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for body: StaticBody2D in _collision_bodies:
		if not is_instance_valid(body):
			continue
		remove_child(body)
		body.queue_free()

	_collision_bodies.clear()

	for structure_value: Variant in Session.get_structures():
		var structure: Dictionary = structure_value as Dictionary
		var cell_data: Array = structure.get("cell", []) as Array
		var cell := Vector2i(
			int(cell_data[0]),
			int(cell_data[1])
		)

		var body := StaticBody2D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = Vector2(
			(cell.x + 0.5) * CELL_SIZE,
			(cell.y + 0.5) * CELL_SIZE
		)

		var shape := RectangleShape2D.new()
		shape.size = Vector2(CELL_SIZE, CELL_SIZE)

		var collision := CollisionShape2D.new()
		collision.shape = shape

		body.add_child(collision)
		add_child(body)
		_collision_bodies.append(body)

	queue_redraw()


func _draw() -> void:
	for structure_value: Variant in Session.get_structures():
		var structure: Dictionary = structure_value as Dictionary
		var cell_data: Array = structure.get("cell", []) as Array
		var cell := Vector2i(
			int(cell_data[0]),
			int(cell_data[1])
		)

		var rect := Rect2(
			Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE),
			Vector2(CELL_SIZE, CELL_SIZE)
		).grow(-2.0)

		draw_rect(rect, WALL_COLOR, true)
		draw_rect(rect, OUTLINE_COLOR, false, 2.0)
		draw_line(
			Vector2(rect.position.x, rect.get_center().y),
			Vector2(rect.end.x, rect.get_center().y),
			OUTLINE_COLOR,
			2.0
		)
