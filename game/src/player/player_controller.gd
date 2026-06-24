class_name PlayerController
extends CharacterBody2D

const MOVE_SPEED: float = 118.0
const MAP_LIMIT: Vector2 = Vector2(1536.0, 1536.0)

var _facing: Vector2 = Vector2.DOWN
var _walk_time: float = 0.0
var _walk_frame: int = 0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	position = Session.get_player_position()
	queue_redraw()


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if not Session.is_paused():
		input_vector = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	velocity = input_vector * MOVE_SPEED
	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_walk_time += delta
		if _walk_time >= 0.16:
			_walk_time -= 0.16
			_walk_frame = 1 - _walk_frame
			queue_redraw()
	else:
		_walk_time = 0.0
		if _walk_frame != 0:
			_walk_frame = 0
			queue_redraw()

	move_and_slide()
	position.x = clampf(position.x, 12.0, MAP_LIMIT.x - 12.0)
	position.y = clampf(position.y, 14.0, MAP_LIMIT.y - 14.0)
	Session.set_player_position(position)


func apply_loaded_position() -> void:
	position = Session.get_player_position()
	velocity = Vector2.ZERO


func _update_facing(direction: Vector2) -> void:
	var new_facing: Vector2
	if absf(direction.x) > absf(direction.y):
		new_facing = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	else:
		new_facing = Vector2.DOWN if direction.y > 0.0 else Vector2.UP
	if new_facing != _facing:
		_facing = new_facing
		queue_redraw()


func _draw() -> void:
	var bob: float = -1.0 if _walk_frame == 1 and velocity != Vector2.ZERO else 0.0
	draw_set_transform(Vector2(0.0, bob))
	draw_set_transform(Vector2(0.0, 9.0), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 9.0, Color(0.08, 0.09, 0.08, 0.40))
	draw_set_transform(Vector2(0.0, bob))

	var coat_color := Color("b45f45")
	var skin_color := Color("d6aa78")
	var hair_color := Color("4c3a31")
	draw_rect(Rect2(-6.0, -3.0, 12.0, 13.0), coat_color)
	draw_rect(Rect2(-5.0, -11.0, 10.0, 9.0), skin_color)
	draw_rect(Rect2(-5.0, -12.0, 10.0, 4.0), hair_color)

	var left_foot_y: float = 10.0 + (2.0 if _walk_frame == 1 else 0.0)
	var right_foot_y: float = 10.0 + (0.0 if _walk_frame == 1 else 2.0)
	draw_rect(Rect2(-5.0, left_foot_y, 3.0, 4.0), Color("34353a"))
	draw_rect(Rect2(2.0, right_foot_y, 3.0, 4.0), Color("34353a"))

	var facing_mark: Vector2 = _facing * 5.0 + Vector2(0.0, -6.0)
	draw_rect(Rect2(facing_mark - Vector2.ONE, Vector2(2.0, 2.0)), Color("29211d"))
	draw_set_transform(Vector2.ZERO)
