class_name InteractableView
extends Area2D

const CharacterVisualScene := preload("res://src/characters/character_visual.gd")

var object_id: String
var kind: String
var base_label: String
var selection_radius: float = 22.0
var _base_color: Color = Color.WHITE
var _draw_size: Vector2 = Vector2(24.0, 20.0)
var _is_selected: bool = false
var _character_visual


func configure(definition: Dictionary) -> void:
	object_id = String(definition["id"])
	kind = String(definition["kind"])
	base_label = String(definition["label"])
	position = definition["position"] as Vector2
	_base_color = definition["color"] as Color
	_draw_size = definition.get("size", Vector2(24.0, 20.0)) as Vector2
	selection_radius = maxf(_draw_size.x, _draw_size.y) * 0.7 + 8.0
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	var shape := CircleShape2D.new()
	shape.radius = selection_radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	if kind == "npc":
		_character_visual = CharacterVisualScene.new()
		add_child(_character_visual)
	refresh_from_state()


func refresh_from_state() -> void:
	if kind == "npc":
		visible = Session.is_npc_visible(object_id)
		position = Session.get_npc_position(object_id, position)
		if _character_visual != null:
			_character_visual.set_appearance(Session.get_npc_appearance(object_id))
			_character_visual.set_pose(Vector2.UP, 0, false)
		queue_redraw()
		return

	visible = not Session.should_hide_interactable(object_id, kind)
	queue_redraw()


func get_display_label() -> String:
	return Session.get_object_label(kind, base_label, object_id)


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	queue_redraw()


func contains_world_point(world_point: Vector2) -> bool:
	return visible and global_position.distance_to(world_point) <= selection_radius


func _draw() -> void:
	if not visible:
		return

	var rect := Rect2(-_draw_size * 0.5, _draw_size)
	if kind == "npc":
		if _is_selected:
			draw_rect(rect.grow(4.0), Color("f1d66b"), false, 2.0)
		return

	draw_ellipse_shadow()
	draw_rect(rect, _base_color)
	draw_rect(rect.grow(-3.0), _base_color.lightened(0.16))

	match kind:
		"water":
			draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Color("b8e2dc"), 2.0)
		"campfire":
			if Session.get_object_stage(kind) >= 2:
				draw_circle(Vector2(0.0, -4.0), 7.0, Color("f2b84b"))
		"repair":
			draw_line(Vector2(-8.0, 6.0), Vector2(8.0, -6.0), Color("ead6b8"), 2.0)
		"bed":
			draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Color("d1c3d9"), 3.0)

	if _is_selected:
		draw_rect(rect.grow(4.0), Color("f1d66b"), false, 2.0)


func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0.0, _draw_size.y * 0.45), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, _draw_size.x * 0.45, Color(0.08, 0.09, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
