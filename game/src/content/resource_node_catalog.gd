class_name ResourceNodeCatalog
extends RefCounted

const FirstNightContent := preload(
	"res://src/content/first_night_content.gd"
)

const BOULDER_COUNT_MIN: int = 13
const BOULDER_COUNT_MAX: int = 15
const FIRST_CELL: int = 2
const LAST_CELL: int = 45
const BOULDER_SPACING: float = 96.0
const STATIC_OBJECT_CLEARANCE: float = 78.0
const MAX_PLACEMENT_ATTEMPTS: int = 4096


static func generate_surface_boulders(world_seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5EEDB0
	var target_count: int = rng.randi_range(
		BOULDER_COUNT_MIN,
		BOULDER_COUNT_MAX
	)
	var content := FirstNightContent.new()
	var static_objects: Array[Dictionary] = content.interactables()
	var result: Array[Dictionary] = []
	var positions: Array[Vector2] = []
	var attempts: int = 0

	while result.size() < target_count and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var cell := Vector2i(
			rng.randi_range(FIRST_CELL, LAST_CELL),
			rng.randi_range(FIRST_CELL, LAST_CELL)
		)
		if is_reserved_cell(cell):
			continue

		var position: Vector2 = FirstNightContent.cell_center(
			cell.x,
			cell.y
		)
		if _is_near_static_object(position, static_objects):
			continue
		if _is_near_boulder(position, positions):
			continue

		var index: int = result.size() + 1
		result.append(make_surface_boulder(index, cell))
		positions.append(position)

	return result


static func make_surface_boulder(index: int, cell: Vector2i) -> Dictionary:
	return {
		"id": "core:surface_boulder_%02d" % index,
		"kind": "stone",
		"label_key": "object.core.surface_boulder.name",
		"cell": [cell.x, cell.y],
	}


static func to_interactable(definition: Dictionary) -> Dictionary:
	var cell_value: Variant = definition.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
		return {}
	var cell := cell_value as Array
	if typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
		return {}
	return {
		"id": String(definition.get("id", "")),
		"kind": "stone",
		"label_key": "object.core.surface_boulder.name",
		"position": FirstNightContent.cell_center(
			int(cell[0]),
			int(cell[1])
		),
		"color": Color("626a6b"),
		"size": Vector2(64.0, 64.0),
		"presentation_id": "surface_boulder",
	}


static func is_reserved_cell(cell: Vector2i) -> bool:
	# Keep the lake, the common house and its entrance paths clear.
	if Rect2i(0, 19, 9, 17).has_point(cell):
		return true
	if Rect2i(17, 15, 15, 20).has_point(cell):
		return true
	if Rect2i(8, 29, 19, 4).has_point(cell):
		return true
	if Rect2i(23, 26, 5, 13).has_point(cell):
		return true
	return false


static func _is_near_static_object(
	position: Vector2,
	static_objects: Array[Dictionary]
) -> bool:
	for object: Dictionary in static_objects:
		var object_position: Vector2 = object.get(
			"position",
			Vector2.ZERO
		) as Vector2
		if position.distance_to(object_position) < STATIC_OBJECT_CLEARANCE:
			return true
	return false


static func _is_near_boulder(
	position: Vector2,
	other_positions: Array[Vector2]
) -> bool:
	for other_position: Vector2 in other_positions:
		if position.distance_to(other_position) < BOULDER_SPACING:
			return true
	return false
