class_name BlueprintLayer
extends Node2D

const CELL_SIZE: int = 32
const FILL_COLOR := Color(0.25, 0.75, 0.95, 0.28)
const OUTLINE_COLOR := Color(0.20, 0.85, 1.00, 0.95)
const MATERIAL_COLOR := Color("9b6a42")
const WORK_COLOR := Color("b7bcc5")
const BADGE_COLOR := Color(0.05, 0.07, 0.06, 0.88)
const TEXT_COLOR := Color("f4ead7")


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
		var required_work: int = int(blueprint.get("required_work_minutes", 0))
		var work_progress: int = mini(
			int(blueprint.get("work_progress_minutes", 0)),
			required_work
		)
		var work_badge := Rect2(origin + Vector2(3.0, 3.0), Vector2(26.0, 11.0))
		draw_rect(work_badge, BADGE_COLOR, true)
		draw_rect(
			Rect2(work_badge.position + Vector2(2.0, 2.0), Vector2(7.0, 7.0)),
			WORK_COLOR,
			true
		)
		draw_string(
			ThemeDB.fallback_font,
			work_badge.position + Vector2(10.0, 9.0),
			"%d/%d" % [work_progress, required_work],
			HORIZONTAL_ALIGNMENT_LEFT,
			14.0,
			8,
			TEXT_COLOR
		)

		var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
		var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
		var required_total: int = 0
		var delivered_total: int = 0
		for item_variant: Variant in required.keys():
			var item_id: String = String(item_variant)
			required_total += int(required[item_variant])
			delivered_total += mini(
				int(delivered.get(item_id, 0)),
				int(required[item_variant])
			)
		var badge := Rect2(origin + Vector2(3.0, 19.0), Vector2(26.0, 11.0))
		draw_rect(badge, BADGE_COLOR, true)
		draw_rect(
			Rect2(badge.position + Vector2(2.0, 2.0), Vector2(7.0, 7.0)),
			MATERIAL_COLOR,
			true
		)
		draw_string(
			ThemeDB.fallback_font,
			badge.position + Vector2(10.0, 9.0),
			"%d/%d" % [delivered_total, required_total],
			HORIZONTAL_ALIGNMENT_LEFT,
			14.0,
			8,
			TEXT_COLOR
		)
