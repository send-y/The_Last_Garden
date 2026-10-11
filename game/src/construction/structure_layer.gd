class_name StructureLayer
extends Node2D

const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

const CELL_SIZE: int = 32
const WALL_COLOR := Color(0.38, 0.27, 0.18, 1.0)
const OUTLINE_COLOR := Color(0.18, 0.12, 0.08, 1.0)
const WORKBENCH_COLOR := Color(0.50, 0.32, 0.17, 1.0)
const WOOD_FLOOR_COLOR := Color(0.48, 0.34, 0.23, 1.0)
const BRICK_FLOOR_COLOR := Color(0.50, 0.34, 0.30, 1.0)
const BuildingCatalogScript := preload(
	"res://src/construction/building_catalog.gd"
)
const PlayerControllerScript := preload("res://src/player/player_controller.gd")

const Connections := preload("res://src/construction/wall_connections.gd")
const WallVisual := preload("res://src/construction/connected_wall_visual.gd")

var _collision_bodies: Array[StaticBody2D] = []
var _structure_sprites: Array[Sprite2D] = []
var _texture_cache: Dictionary = {}
var _building_catalog := BuildingCatalogScript.new()
var _player: PlayerController
var _refresh_queued: bool = false
# Static drawing uses geometry only; current source appearance lives in sprites.
var _structure_snapshot: Array[Dictionary] = []
var _index: RefCounted
var _revision := -1
var _geometry_revision := -1
var _door_revision := -1
var _torch_entries: Dictionary = {}


func _ready() -> void:
	_player = get_node_or_null("../Player") as PlayerController
	Session.state_changed.connect(_refresh)
	Session.state_reloaded.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if _player == null:
		return
	var player_foot_y := _player.get_depth_sort_y()
	var span := Diagnostic.begin("scene.structure_depth") if Diagnostic.enabled else 0
	for sprite: Sprite2D in _structure_sprites:
		if not is_instance_valid(sprite):
			continue
		var sort_y := float(sprite.get_meta("sort_y", 0.0))
		sprite.z_index = (
			PlayerControllerScript.DEPTH_SORT_Z_INDEX - 1
			if player_foot_y > sort_y
			else PlayerControllerScript.DEPTH_SORT_Z_INDEX + 1
		)
	Diagnostic.end(span)


func _refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_deferred")


func _refresh_deferred() -> void:
	_refresh_queued = false
	var index = Session.simulation.structure_index
	if _index == index and _revision == index.revision: return
	if _index == index and _geometry_revision == index.geometry_revision and _door_revision == index.door_revision:
		_revision = index.revision
		_refresh_lights(index)
		return
	var span := Diagnostic.begin("scene.structure_refresh") if Diagnostic.enabled else 0
	_index = index
	_revision = index.revision
	_geometry_revision = index.geometry_revision
	_door_revision = index.door_revision
	var structures: Array[Dictionary] = Session.get_structures()
	_structure_snapshot = structures
	for body: StaticBody2D in _collision_bodies:
		if not is_instance_valid(body):
			continue
		remove_child(body)
		body.queue_free()
	_collision_bodies.clear()
	_torch_entries.clear()

	for sprite: Sprite2D in _structure_sprites:
		if not is_instance_valid(sprite):
			continue
		remove_child(sprite)
		sprite.queue_free()
	_structure_sprites.clear()

	var boundaries := Connections.index(structures,_building_catalog)
	for structure_value: Variant in structures:
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue
		var structure := structure_value as Dictionary
		var building_id := String(structure.get("building_id", ""))
		if _building_catalog.is_floor(building_id):
			continue
		var cell_data: Array = structure.get("cell", []) as Array
		if cell_data.size() != 2:
			continue
		var origin := Vector2i(int(cell_data[0]), int(cell_data[1]))
		var footprint := _building_catalog.get_footprint_size(building_id)
		var texture := _get_building_texture(building_id)
		if building_id == "core:torch":
			texture = _get_torch_texture(bool(structure.get("lit",true)))
		if texture != null:
			var wall := String(_building_catalog.get_definition(building_id).get("category_id","")) == "core:wall"
			var sprite: Sprite2D = WallVisual.new() if wall else Sprite2D.new()
			sprite.texture = null if wall else texture
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = Vector2(origin * CELL_SIZE)
			var connections := Connections.mask(origin,boundaries)
			if wall:
				sprite.source_texture = texture
				sprite.connection_mask = connections if connections else 5
				sprite.position += Vector2(16,16)
				if Connections.vertical(connections):
					sprite.rotation = PI/2
					sprite.connection_mask = ((connections >> 1) | ((connections & 1) << 3)) & 15
			elif building_id == "core:wood_door":
				sprite.centered = true
				sprite.position += Vector2(16,16)
				if Connections.vertical(connections): sprite.rotation = PI/2
				sprite.visible = not bool(structure.get("open",true))
			sprite.set_meta("cell",origin)
			sprite.set_meta("connections",connections)
			sprite.z_as_relative = false
			sprite.set_meta(
				"sort_y",
				float((origin.y + footprint.y) * CELL_SIZE - 4)
			)
			add_child(sprite)
			_structure_sprites.append(sprite)
			if building_id == "core:torch":
				_torch_entries[origin] = sprite

		var definition := _building_catalog.get_definition(building_id)
		var blocks := bool(definition.get("blocks_movement",false)) or (building_id == "core:wood_door" and not bool(structure.get("open",true)))
		if not blocks:
			continue
		var body := StaticBody2D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = Vector2(
			(origin.x + footprint.x * 0.5) * CELL_SIZE,
			(origin.y + footprint.y * 0.5) * CELL_SIZE
		)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(footprint * CELL_SIZE)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		_collision_bodies.append(body)

	queue_redraw()
	Diagnostic.end(span)


func _refresh_lights(index) -> void:
	var span := Diagnostic.begin("scene.structure_lights") if Diagnostic.enabled else 0
	# Only source records are read. Static draw commands and physics bodies survive.
	for structure: Dictionary in index.of_type("core:torch"):
		var cell := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
		if not _torch_entries.has(cell): continue
		var lit := bool(structure.get("lit",true))
		var sprite: Sprite2D = _torch_entries[cell]
		var texture := _get_torch_texture(lit)
		if sprite.texture != texture: sprite.texture = texture
	Diagnostic.end(span)


func _get_torch_texture(lit: bool) -> Texture2D:
	return _get_texture("res://assets/sprites/structures/torch_on.png" if lit else "res://assets/sprites/structures/torch_off.png")


func _get_building_texture(building_id: String) -> Texture2D:
	return _get_texture(_building_catalog.get_texture_path(building_id))


func _get_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Missing construction texture: %s" % path)
		return null
	_texture_cache[path] = texture
	return texture


func _draw() -> void:
	var span := Diagnostic.begin("scene.structure_draw") if Diagnostic.enabled else 0
	for structure_value: Variant in _structure_snapshot:
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue
		var structure := structure_value as Dictionary
		var building_id := String(structure.get("building_id", ""))
		var cell_data: Array = structure.get("cell", []) as Array
		if cell_data.size() != 2:
			continue
		var origin := Vector2(int(cell_data[0]) * CELL_SIZE, int(cell_data[1]) * CELL_SIZE)
		var footprint := _building_catalog.get_footprint_size(building_id)
		var size := Vector2(footprint * CELL_SIZE)
		if _building_catalog.is_floor(building_id):
			var floor_texture := _get_building_texture(building_id)
			if floor_texture != null:
				draw_texture_rect(floor_texture, Rect2(origin, size), true)
			else:
				var floor_color := BRICK_FLOOR_COLOR if building_id == "core:brick_floor" else WOOD_FLOOR_COLOR
				draw_rect(Rect2(origin, size), floor_color, true)
			continue

		if _get_building_texture(building_id) != null:
			continue
		# Workbench has no player-authored sprite yet; keep a restrained placeholder.
		var rect := Rect2(origin + Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
		if building_id == "core:bedroll":
			var fabric := Rect2(origin + Vector2(4, 8), size - Vector2(8, 16))
			draw_rect(fabric, Color("867b64"))
			draw_rect(fabric, OUTLINE_COLOR, false, 2)
			draw_rect(Rect2(fabric.position + Vector2(3, 3), Vector2(11, 10)), Color("c2b290"))
			draw_line(fabric.position + Vector2(18, 2), fabric.position + Vector2(18, 14), Color("554a3a"), 2)
			continue
		var fill_color := WORKBENCH_COLOR if building_id == "core:workbench" else WALL_COLOR
		draw_rect(rect, fill_color, true)
		draw_rect(rect, OUTLINE_COLOR, false, 2.0)
		if building_id == "core:workbench":
			draw_rect(rect.grow(-5.0), Color(0.64, 0.43, 0.23, 1.0), true)
			draw_line(rect.position + Vector2(5.0, 7.0), rect.end - Vector2(5.0, 7.0), OUTLINE_COLOR, 2.0)
	Diagnostic.end(span)
