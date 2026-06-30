class_name CharacterVisual
extends Node2D

const Appearance := preload("res://src/characters/character_appearance.gd")

var _catalog := Appearance.new()
var _appearance: Dictionary = {}
var _facing: Vector2 = Vector2.DOWN
var _walk_frame: int = 0
var _is_moving: bool = false


func _ready() -> void:
	if _appearance.is_empty():
		set_appearance(_catalog.get_default_player_appearance())


func set_appearance(value: Dictionary) -> void:
	var errors: Array[String] = _catalog.validate_appearance(value)
	for error: String in errors:
		push_warning("Character appearance warning: %s" % error)
	_appearance = value.duplicate(true)
	queue_redraw()


func get_appearance() -> Dictionary:
	return _appearance.duplicate(true)


func set_pose(facing: Vector2, walk_frame: int, is_moving: bool) -> void:
	var changed: bool = facing != _facing or walk_frame != _walk_frame or is_moving != _is_moving
	_facing = facing
	_walk_frame = walk_frame
	_is_moving = is_moving
	if changed:
		queue_redraw()


func _draw() -> void:
	if _appearance.is_empty():
		return

	_draw_shadow()
	var bob: float = -1.0 if _is_moving and _walk_frame % 2 == 1 else 0.0
	draw_set_transform(Vector2(0.0, bob))
	for part: Dictionary in _catalog.get_layered_parts(_appearance):
		_draw_part(part)
	draw_set_transform(Vector2.ZERO)


func _draw_shadow() -> void:
	draw_set_transform(Vector2(0.0, 10.0), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 10.0, Color(0.08, 0.09, 0.08, 0.40))
	draw_set_transform(Vector2.ZERO)


func _draw_part(part: Dictionary) -> void:
	var slot_id: String = String(part.get("slot", ""))
	match slot_id:
		"cloak":
			_draw_cloak(part)
		"pants":
			_draw_pants(part)
		"boots":
			_draw_boots(part)
		"body":
			_draw_body(part)
		"shirt":
			_draw_shirt(part)
		"hair":
			_draw_hair(part)
		"scarf":
			_draw_scarf(part)
		"held_item":
			_draw_held_item(part)


func _draw_cloak(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var direction: String = _direction_name()
	if direction == "up":
		draw_colored_polygon(PackedVector2Array([
			Vector2(-8.0, -8.0),
			Vector2(8.0, -8.0),
			Vector2(10.0, 9.0),
			Vector2(6.0, 14.0),
			Vector2(-6.0, 14.0),
			Vector2(-10.0, 9.0),
		]), color)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, -6.0),
			Vector2(9.0, -6.0),
			Vector2(11.0, 8.0),
			Vector2(7.0, 13.0),
			Vector2(-7.0, 13.0),
			Vector2(-11.0, 8.0),
		]), color)
	draw_line(Vector2(-8.0, -5.0), Vector2(-10.0, 8.0), shadow, 1.5)
	draw_line(Vector2(8.0, -5.0), Vector2(10.0, 8.0), shadow, 1.5)


func _draw_pants(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var left_y: float = 5.0 + (2.0 if _is_moving and _walk_frame == 1 else 0.0)
	var right_y: float = 5.0 + (2.0 if _is_moving and _walk_frame == 3 else 0.0)
	draw_rect(Rect2(-5.0, left_y, 4.0, 8.0), color)
	draw_rect(Rect2(1.0, right_y, 4.0, 8.0), color)
	draw_rect(Rect2(-5.0, left_y + 5.0, 4.0, 3.0), shadow)
	draw_rect(Rect2(1.0, right_y + 5.0, 4.0, 3.0), shadow)


func _draw_boots(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var left_y: float = 12.0 + (2.0 if _is_moving and _walk_frame == 1 else 0.0)
	var right_y: float = 12.0 + (2.0 if _is_moving and _walk_frame == 3 else 0.0)
	draw_rect(Rect2(-6.0, left_y, 5.0, 3.0), color)
	draw_rect(Rect2(1.0, right_y, 5.0, 3.0), color)
	draw_rect(Rect2(-6.0, left_y + 2.0, 5.0, 1.0), shadow)
	draw_rect(Rect2(1.0, right_y + 2.0, 5.0, 1.0), shadow)


func _draw_body(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var highlight: Color = _part_color(part, "highlight", color.lightened(0.18))
	var direction: String = _direction_name()

	draw_rect(Rect2(-5.0, -15.0, 10.0, 10.0), color)
	draw_rect(Rect2(-5.0, -7.0, 10.0, 2.0), shadow)
	if direction != "up":
		draw_rect(Rect2(-2.0, -11.0, 1.0, 1.0), Color("1e1b18"))
		draw_rect(Rect2(3.0, -11.0, 1.0, 1.0), Color("1e1b18"))
		draw_rect(Rect2(1.0, -8.0, 2.0, 1.0), shadow)
	if direction == "right":
		draw_rect(Rect2(4.0, -11.0, 2.0, 4.0), highlight)
	elif direction == "left":
		draw_rect(Rect2(-6.0, -11.0, 2.0, 4.0), shadow)


func _draw_shirt(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var highlight: Color = _part_color(part, "highlight", color.lightened(0.18))
	draw_rect(Rect2(-6.0, -5.0, 12.0, 11.0), color)
	draw_rect(Rect2(-6.0, 3.0, 12.0, 3.0), shadow)
	draw_rect(Rect2(-2.0, -5.0, 4.0, 11.0), highlight)


func _draw_hair(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var highlight: Color = _part_color(part, "highlight", color.lightened(0.18))
	var direction: String = _direction_name()
	draw_rect(Rect2(-5.0, -16.0, 10.0, 4.0), color)
	draw_rect(Rect2(-6.0, -14.0, 3.0, 5.0), shadow)
	draw_rect(Rect2(3.0, -14.0, 3.0, 5.0), shadow)
	if direction != "up":
		draw_rect(Rect2(-3.0, -13.0, 3.0, 3.0), color)
		draw_rect(Rect2(1.0, -15.0, 2.0, 2.0), highlight)
	else:
		draw_rect(Rect2(-4.0, -12.0, 8.0, 4.0), color)


func _draw_scarf(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var shadow: Color = _part_color(part, "shadow", color.darkened(0.25))
	var highlight: Color = _part_color(part, "highlight", color.lightened(0.18))
	draw_rect(Rect2(-7.0, -6.0, 14.0, 3.0), color)
	draw_rect(Rect2(-6.0, -4.0, 12.0, 2.0), shadow)
	draw_rect(Rect2(3.0, -6.0, 4.0, 2.0), highlight)


func _draw_held_item(part: Dictionary) -> void:
	var color: Color = _part_color(part)
	var highlight: Color = _part_color(part, "highlight", color.lightened(0.25))
	var direction: String = _direction_name()
	var side: float = -1.0 if direction == "left" else 1.0
	if direction == "up":
		return
	draw_line(Vector2(8.0 * side, -1.0), Vector2(11.0 * side, 7.0), color, 2.0)
	draw_rect(Rect2(Vector2(10.0 * side - 1.0, 5.0), Vector2(2.0, 5.0)), highlight)


func _part_color(part: Dictionary, key: String = "color", fallback: Color = Color.WHITE) -> Color:
	var value: String = String(part.get(key, ""))
	if value.is_empty():
		return fallback
	return Color(value)


func _direction_name() -> String:
	if absf(_facing.x) > absf(_facing.y):
		return "right" if _facing.x > 0.0 else "left"
	return "down" if _facing.y >= 0.0 else "up"
