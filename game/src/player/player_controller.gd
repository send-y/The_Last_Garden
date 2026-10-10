class_name PlayerController
extends CharacterBody2D

const CharacterVisualScene := preload("res://src/characters/character_visual.gd")
const PlaceholderIcon := preload("res://src/items/item_placeholder_icon.gd")
const FirstNightContentScript := preload(
	"res://src/content/first_night_content.gd"
)

const MOVE_SPEED: float = 118.0
const MAP_LIMIT: Vector2 = Vector2(
	FirstNightContentScript.MAP_SIZE * FirstNightContentScript.CELL_SIZE
)
const DEPTH_SORT_FOOT_OFFSET: float = 12.0
const DEPTH_SORT_Z_INDEX: int = 10

var _facing: Vector2 = Vector2.DOWN
var _walk_time: float = 0.0
var _walk_frame: int = 0
var _visual
var _content := FirstNightContentScript.new()
var _held_icon_cache: Dictionary = {}


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	z_index = DEPTH_SORT_Z_INDEX
	position = Session.get_player_position()
	_visual = CharacterVisualScene.new()
	add_child(_visual)
	_visual.set_pose(_facing, _walk_frame, false)
	Session.state_changed.connect(_refresh_held_item)
	Session.state_reloaded.connect(_refresh_held_item)
	_refresh_held_item()


func _refresh_held_item() -> void:
	var item := Session.get_held_item()
	var item_id := String(item.get("item_id", ""))
	var texture: Texture2D = null
	if not item_id.is_empty():
		var path := _content.item_icon_path(item_id, item.get("state", {}) as Dictionary)
		if not path.is_empty() and ResourceLoader.exists(path):
			if not _held_icon_cache.has(path):
				_held_icon_cache[path] = load(path)
			texture = _held_icon_cache[path] as Texture2D
		else:
			texture = PlaceholderIcon.texture_for(item_id)
	_visual.set_held_item(item_id, texture)
	var was_seated: bool = _visual._sitting
	var seated: bool = not Session.simulation.furniture.comfort(Session.simulation,"core:player").is_empty()
	_visual.set_sitting(seated)
	if seated or was_seated:
		position = Session.get_player_position()


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if not Session.is_paused():
		input_vector = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if not Session.simulation.state.get("player_furniture_use",{}).is_empty():
		if input_vector == Vector2.ZERO:
			velocity = Vector2.ZERO
			return
		if not Session.simulation.leave_player_seat():
			velocity = Vector2.ZERO
			return
		apply_loaded_position()
		_visual.set_sitting(false)

	velocity = input_vector * MOVE_SPEED
	if input_vector != Vector2.ZERO:
		_update_facing(input_vector)
		_walk_time += delta
		if _walk_time >= 0.16:
			_walk_time -= 0.16
			_walk_frame = (_walk_frame + 1) % 4
			_update_visual_pose()
	else:
		_walk_time = 0.0
		if _walk_frame != 0:
			_walk_frame = 0
			_update_visual_pose()

	move_and_slide()
	position.x = clampf(position.x, 12.0, MAP_LIMIT.x - 12.0)
	position.y = clampf(position.y, 14.0, MAP_LIMIT.y - 14.0)
	Session.set_player_position(position)


func apply_loaded_position() -> void:
	position = Session.get_player_position()
	velocity = Vector2.ZERO


func get_depth_sort_y() -> float:
	return global_position.y + DEPTH_SORT_FOOT_OFFSET


func _update_facing(direction: Vector2) -> void:
	var new_facing: Vector2
	if absf(direction.x) > absf(direction.y):
		new_facing = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	else:
		new_facing = Vector2.DOWN if direction.y > 0.0 else Vector2.UP
	if new_facing != _facing:
		_facing = new_facing
		_update_visual_pose()


func _update_visual_pose() -> void:
	if _visual == null:
		return
	_visual.set_pose(_facing, _walk_frame, velocity != Vector2.ZERO)
