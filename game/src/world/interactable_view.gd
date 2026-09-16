class_name InteractableView
extends Area2D

const CharacterVisualScene := preload("res://src/characters/character_visual.gd")
const NPC_PRESENTATION_SPEED: float = 30.0
const NPC_SNAP_DISTANCE: float = 96.0
const Localized := preload(
	"res://src/localization/localized_text.gd"
)

var object_id: String
var kind: String
var base_label_key: String
var selection_radius: float = 22.0
var _base_color: Color = Color.WHITE
var _draw_size: Vector2 = Vector2(24.0, 20.0)
var _is_selected: bool = false
var _character_visual
var _target_position: Vector2
var _walk_time: float = 0.0
var _walk_frame: int = 0
var _physical_body: AnimatableBody2D


func configure(definition: Dictionary) -> void:
	object_id = String(definition["id"])
	kind = String(definition["kind"])
	base_label_key = String(definition["label_key"])
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
		_physical_body = AnimatableBody2D.new()
		_physical_body.collision_layer = 0
		_physical_body.collision_mask = 0
		var body_shape := CapsuleShape2D.new()
		body_shape.radius = 6.0
		body_shape.height = 20.0
		var body_collision := CollisionShape2D.new()
		body_collision.position = Vector2(0.0, 2.0)
		body_collision.shape = body_shape
		_physical_body.add_child(body_collision)
		add_child(_physical_body)
		_physical_body.top_level = true
		_sync_physical_body()
		set_physics_process(true)
	else:
		set_physics_process(false)
	refresh_from_state(true)


func _physics_process(delta: float) -> void:
	if kind != "npc" or not visible or Session.is_paused():
		return
	var distance: float = position.distance_to(_target_position)
	if distance <= 0.25:
		position = _target_position
		_sync_physical_body()
		_walk_time = 0.0
		_walk_frame = 0
		if _character_visual != null:
			_character_visual.set_pose(Session.get_npc_facing(object_id), 0, false)
		return

	var direction: Vector2 = position.direction_to(_target_position)
	position = position.move_toward(_target_position, NPC_PRESENTATION_SPEED * delta)
	_sync_physical_body()
	_walk_time += delta
	if _walk_time >= 0.16:
		_walk_time -= 0.16
		_walk_frame = (_walk_frame + 1) % 4
	if _character_visual != null:
		_character_visual.set_pose(direction, _walk_frame, true)


func refresh_from_state(snap: bool = false) -> void:
	if kind == "npc":
		visible = Session.is_npc_visible(object_id)
		if _physical_body != null:
			_physical_body.collision_layer = 2 if visible else 0
		_target_position = Session.get_npc_position(object_id, position)
		if snap or position.distance_to(_target_position) > NPC_SNAP_DISTANCE:
			position = _target_position
		_sync_physical_body()
		if _character_visual != null:
			_character_visual.set_appearance(Session.get_npc_appearance(object_id))
			_character_visual.set_pose(
				Session.get_npc_facing(object_id),
				_walk_frame,
				Session.is_npc_moving(object_id)
			)
		queue_redraw()
		return

	visible = not Session.should_hide_interactable(object_id, kind)
	queue_redraw()


func _sync_physical_body() -> void:
	if _physical_body == null:
		return
	_physical_body.global_position = global_position


func get_display_label() -> String:
	return Session.get_object_label(kind, base_label_key, object_id)


func get_status_text() -> String:
	if kind == "npc":
		return Session.get_npc_activity(object_id)

	var required: int = (
		Session.get_resource_work_required(object_id)
	)

	if required <= 0:
		return ""

	return Localized.resolve(
		"resource.selection.work_progress",
		{
			"progress": Session.get_resource_work_progress(
				object_id
			),
			"required": required,
		}
	)


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
