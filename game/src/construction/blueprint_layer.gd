class_name BlueprintLayer
extends Node2D

const CELL_SIZE: int = 32
const FILL_COLOR := Color(0.25, 0.75, 0.95, 0.28)
const OUTLINE_COLOR := Color(0.20, 0.85, 1.00, 0.95)


func _ready() -> void:
	Session.state_changed.connect(queue_redraw)
	Session.state_reloaded.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	for blueprint_value: Variant in Session.get_blueprints():
		var blueprint: Dictionary = blueprint_value as Dictionary
		var cell_data: Array = blueprint.get("cell", []) as Array

		var origin := Vector2(
			int(cell_data[0]) * CELL_SIZE,
			int(cell_data[1]) * CELL_SIZE
		)
		var rect := Rect2(
			origin + Vector2(3.0, 3.0),
			Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
		)

		draw_rect(rect, FILL_COLOR, true)
		draw_rect(rect, OUTLINE_COLOR, false, 2.0)
		draw_line(rect.position, rect.end, OUTLINE_COLOR, 2.0)
		draw_line(
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.position.x, rect.end.y),
			OUTLINE_COLOR,
			2.0
		)
