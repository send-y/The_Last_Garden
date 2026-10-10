class_name ResourceNodeCatalog
extends RefCounted

const FirstNightContent := preload(
	"res://src/content/first_night_content.gd"
)
const WaterMapScript := preload("res://src/world/water_map.gd")

const LEGACY_LAYOUT_VERSION: int = 1
const STARTER_LAYOUT_VERSION: int = 2
const CURRENT_LAYOUT_VERSION: int = 3
const PREVIOUS_STARTER_TREE_COUNT: int = 4
const PREVIOUS_STARTER_BOULDER_COUNT: int = 2
const PREVIOUS_STARTER_TREE_REGION := Rect2i(32, 31, 9, 8)
const PREVIOUS_STARTER_BOULDER_REGION := Rect2i(32, 24, 7, 5)
const STARTER_TREE_COUNT: int = 16
const STARTER_BOULDER_COUNT: int = 8
const STARTER_TREE_REGION := Rect2i(32, 31, 13, 12)
const STARTER_BOULDER_REGION := Rect2i(32, 21, 12, 9)
const FIRST_TREE_REGION := Rect2i(32, 31, 3, 3)
const FIRST_BOULDER_REGION := Rect2i(32, 26, 3, 3)

const PREVIOUS_BOULDER_COUNT_MIN: int = 30
const PREVIOUS_BOULDER_COUNT_MAX: int = 35
const PREVIOUS_TREE_COUNT_MIN: int = 40
const PREVIOUS_TREE_COUNT_MAX: int = 45
const BOULDER_COUNT_MIN: int = 90
const BOULDER_COUNT_MAX: int = 110
const TREE_COUNT_MIN: int = 180
const TREE_COUNT_MAX: int = 220
const BERRY_BUSH_COUNT_MIN: int = 18
const BERRY_BUSH_COUNT_MAX: int = 24
const BOULDER_GROUP_MIN: int = 1
const BOULDER_GROUP_MAX: int = 3
const TREE_GROUP_MIN: int = 3
const TREE_GROUP_MAX: int = 6
const PREVIOUS_BOULDER_GROUP_MIN: int = 3
const PREVIOUS_BOULDER_GROUP_MAX: int = 5
const PREVIOUS_TREE_GROUP_MIN: int = 8
const PREVIOUS_TREE_GROUP_MAX: int = 12
const CURRENT_BOULDER_GROUP_MIN: int = 6
const CURRENT_BOULDER_GROUP_MAX: int = 10
const CURRENT_TREE_GROUP_MIN: int = 12
const CURRENT_TREE_GROUP_MAX: int = 18
const FIRST_CELL: int = 2
const STATIC_OBJECT_CLEARANCE: float = 96.0
const MAX_PLACEMENT_ATTEMPTS: int = 8192
const CLUSTER_SPREAD_CELLS: int = 3
const CLUSTER_SEPARATION_CELLS: int = 7


static func generate_surface_boulders(
	world_seed: int,
	layout_version: int = CURRENT_LAYOUT_VERSION
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5EEDB0
	var count_range := boulder_count_range(layout_version)
	var target_count := rng.randi_range(count_range.x, count_range.y)
	return _generate_clustered_nodes(
		rng,
		target_count,
		CURRENT_BOULDER_GROUP_MIN if layout_version >= CURRENT_LAYOUT_VERSION else PREVIOUS_BOULDER_GROUP_MIN if layout_version >= STARTER_LAYOUT_VERSION else BOULDER_GROUP_MIN,
		CURRENT_BOULDER_GROUP_MAX if layout_version >= CURRENT_LAYOUT_VERSION else PREVIOUS_BOULDER_GROUP_MAX if layout_version >= STARTER_LAYOUT_VERSION else BOULDER_GROUP_MAX,
		"boulder",
		FirstNightContent.new().interactables(),
		[],
		layout_version
	)


static func generate_surface_trees(
	world_seed: int,
	boulders: Array[Dictionary],
	layout_version: int = CURRENT_LAYOUT_VERSION
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x7EE5
	var count_range := tree_count_range(layout_version)
	var target_count := rng.randi_range(count_range.x, count_range.y)
	var occupied: Array[Vector2] = []
	for boulder: Dictionary in boulders:
		occupied.append(_position_from_node(boulder))
	return _generate_clustered_nodes(
		rng,
		target_count,
		CURRENT_TREE_GROUP_MIN if layout_version >= CURRENT_LAYOUT_VERSION else PREVIOUS_TREE_GROUP_MIN if layout_version >= STARTER_LAYOUT_VERSION else TREE_GROUP_MIN,
		CURRENT_TREE_GROUP_MAX if layout_version >= CURRENT_LAYOUT_VERSION else PREVIOUS_TREE_GROUP_MAX if layout_version >= STARTER_LAYOUT_VERSION else TREE_GROUP_MAX,
		"tree",
		FirstNightContent.new().interactables(),
		occupied,
		layout_version
	)


static func generate_berry_bushes(
	world_seed: int,
	boulders: Array = [],
	trees: Array = [],
	layout_version: int = CURRENT_LAYOUT_VERSION
) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0xBE221E5
	var target_count := rng.randi_range(
		BERRY_BUSH_COUNT_MIN,
		BERRY_BUSH_COUNT_MAX
	)
	var occupied: Array[Vector2] = []
	for node: Dictionary in boulders:
		occupied.append(_position_from_node(node))
	for node: Dictionary in trees:
		occupied.append(_position_from_node(node))
	return _generate_clustered_nodes(
		rng,
		target_count,
		2,
		4,
		"food",
		FirstNightContent.new().interactables(),
		occupied,
		layout_version
	)


static func boulder_count_range(layout_version: int) -> Vector2i:
	if layout_version >= CURRENT_LAYOUT_VERSION:
		return Vector2i(BOULDER_COUNT_MIN, BOULDER_COUNT_MAX)
	return Vector2i(PREVIOUS_BOULDER_COUNT_MIN, PREVIOUS_BOULDER_COUNT_MAX)


static func tree_count_range(layout_version: int) -> Vector2i:
	if layout_version >= CURRENT_LAYOUT_VERSION:
		return Vector2i(TREE_COUNT_MIN, TREE_COUNT_MAX)
	return Vector2i(PREVIOUS_TREE_COUNT_MIN, PREVIOUS_TREE_COUNT_MAX)


static func _generate_clustered_nodes(
	rng: RandomNumberGenerator,
	target_count: int,
	group_min: int,
	group_max: int,
	kind: String,
	static_objects: Array[Dictionary],
	initial_occupied_positions: Array[Vector2],
	layout_version: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occupied_positions := initial_occupied_positions.duplicate()
	var occupied_cells: Dictionary = {}
	var cluster_centers: Array[Vector2i] = []
	var water_cells: Array[Vector2i] = []
	if layout_version >= STARTER_LAYOUT_VERSION:
		water_cells = WaterMapScript.surface_cells()
		_place_starter_nodes(
			rng, kind, static_objects, occupied_positions, occupied_cells, result, water_cells,
			layout_version
		)
		if not result.is_empty():
			var first_cell: Array = result[0].get("cell", []) as Array
			cluster_centers.append(Vector2i(int(first_cell[0]), int(first_cell[1])))
	var target_cell_max: int = mini(
		FirstNightContent.MAP_SIZE.x,
		FirstNightContent.MAP_SIZE.y
	) - FIRST_CELL - 1
	var attempts: int = 0
	while result.size() < target_count and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1
		var center := Vector2i(
			rng.randi_range(FIRST_CELL, target_cell_max),
			rng.randi_range(FIRST_CELL, target_cell_max)
		)
		if is_reserved_cell(center) or water_cells.has(center):
			continue
		if _is_near_cluster(center, cluster_centers):
			continue
		var center_position := FirstNightContent.cell_center(center.x, center.y)
		if _is_near_static_object(center_position, static_objects):
			continue
		if _is_near_position(center_position, occupied_positions, 64.0):
			continue
		cluster_centers.append(center)
		var remaining := target_count - result.size()
		var group_size := mini(remaining, rng.randi_range(group_min, group_max))
		var placed_in_cluster := 0
		var cluster_attempts := 0
		while placed_in_cluster < group_size and cluster_attempts < 80:
			cluster_attempts += 1
			var cell := center + Vector2i(
				rng.randi_range(-CLUSTER_SPREAD_CELLS, CLUSTER_SPREAD_CELLS),
				rng.randi_range(-CLUSTER_SPREAD_CELLS, CLUSTER_SPREAD_CELLS)
			)
			if (
				cell.x < FIRST_CELL
				or cell.y < FIRST_CELL
				or cell.x > target_cell_max
				or cell.y > target_cell_max
				or is_reserved_cell(cell)
				or water_cells.has(cell)
			):
				continue
			var cell_key := "%d,%d" % [cell.x, cell.y]
			if occupied_cells.has(cell_key):
				continue
			var position := FirstNightContent.cell_center(cell.x, cell.y)
			if _is_near_static_object(position, static_objects):
				continue
			if _is_near_position(position, initial_occupied_positions, 64.0):
				continue
			if _is_near_position(position, occupied_positions, 34.0):
				continue
			occupied_cells[cell_key] = true
			occupied_positions.append(position)
			var index := result.size() + 1
			if kind == "boulder":
				result.append(make_surface_boulder(index, cell, rng.randi_range(9, 12)))
			elif kind == "food":
				result.append(make_berry_bush(index, cell))
			else:
				result.append(make_surface_tree(index, cell, rng.randi_range(12, 13)))
			placed_in_cluster += 1
	return result


static func _place_starter_nodes(
	rng: RandomNumberGenerator,
	kind: String,
	static_objects: Array[Dictionary],
	occupied_positions: Array[Vector2],
	occupied_cells: Dictionary,
	result: Array[Dictionary],
	water_cells: Array[Vector2i],
	layout_version: int
) -> void:
	if kind != "wood" and kind != "tree" and kind != "boulder":
		return
	var is_tree := kind == "tree" or kind == "wood"
	var region := STARTER_TREE_REGION if is_tree else STARTER_BOULDER_REGION
	var first_region := FIRST_TREE_REGION if is_tree else FIRST_BOULDER_REGION
	var count := STARTER_TREE_COUNT if is_tree else STARTER_BOULDER_COUNT
	if layout_version < CURRENT_LAYOUT_VERSION:
		region = PREVIOUS_STARTER_TREE_REGION if is_tree else PREVIOUS_STARTER_BOULDER_REGION
		count = PREVIOUS_STARTER_TREE_COUNT if is_tree else PREVIOUS_STARTER_BOULDER_COUNT
	for node_index: int in range(count):
		var candidate_region := first_region if node_index == 0 else region
		var candidates: Array[Vector2i] = []
		for y: int in range(candidate_region.position.y, candidate_region.end.y):
			for x: int in range(candidate_region.position.x, candidate_region.end.x):
				candidates.append(Vector2i(x, y))
		while not candidates.is_empty():
			var candidate_index := rng.randi_range(0, candidates.size() - 1)
			var cell := candidates[candidate_index]
			candidates.remove_at(candidate_index)
			var key := "%d,%d" % [cell.x, cell.y]
			var position := FirstNightContent.cell_center(cell.x, cell.y)
			if (
				is_reserved_cell(cell) or water_cells.has(cell) or occupied_cells.has(key)
				or _is_near_static_object(position, static_objects)
				or _is_near_position(position, occupied_positions, 64.0)
			):
				continue
			occupied_cells[key] = true
			occupied_positions.append(position)
			var index := result.size() + 1
			if is_tree:
				result.append(make_surface_tree(index, cell, rng.randi_range(12, 13)))
			else:
				result.append(make_surface_boulder(index, cell, rng.randi_range(9, 12)))
			break


static func make_surface_boulder(
	index: int,
	cell: Vector2i,
	yield_amount: int = 9
) -> Dictionary:
	return {
		"id": "core:surface_boulder_%02d" % index,
		"kind": "stone",
		"label_key": "object.core.surface_boulder.name",
		"cell": [cell.x, cell.y],
		"yield_amount": yield_amount,
	}


static func make_surface_tree(
	index: int,
	cell: Vector2i,
	yield_amount: int = 12,
	stage_id: String = "tree"
) -> Dictionary:
	return {
		"id": "core:surface_tree_%02d" % index,
		"kind": "wood",
		"label_key": "object.core.surface_tree.name",
		"cell": [cell.x, cell.y],
		"yield_amount": yield_amount,
		"stage_id": stage_id,
	}


static func make_berry_bush(index: int, cell: Vector2i) -> Dictionary:
	return {
		"id": "core:berry_bush_%02d" % index,
		"kind": "food",
		"label_key": "object.core.berry_bush.name",
		"cell": [cell.x, cell.y],
	}


static func to_interactable(definition: Dictionary) -> Dictionary:
	var cell_value: Variant = definition.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
		return {}
	var cell := cell_value as Array
	if typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
		return {}
	var kind := String(definition.get("kind", "stone"))
	var is_tree := kind == "wood"
	var is_food := kind == "food"
	var stage_id := String(definition.get("stage_id", "tree"))
	return {
		"id": String(definition.get("id", "")),
		"kind": kind,
		"label_key": String(definition.get(
			"label_key",
			"object.core.surface_tree.name" if is_tree
			else "object.core.berry_bush.name" if is_food
			else "object.core.surface_boulder.name"
		)),
		"position": FirstNightContent.cell_center(int(cell[0]), int(cell[1])),
		"color": Color("526d3d" if is_food else "626a6b" if not is_tree else "456342"),
		"size": Vector2(30.0, 24.0) if is_food else Vector2(64.0, 64.0) if not is_tree else Vector2(72.0, 88.0),
		"yield_amount": int(definition.get("yield_amount", 9 if not is_tree else 12)),
		"stage_id": stage_id,
		"presentation_id": (
			"surface_stump" if is_tree and stage_id == "stump"
			else "surface_tree" if is_tree
			else "berry_bush" if is_food
			else "surface_boulder"
		),
	}


static func position_in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= FIRST_CELL
		and cell.y >= FIRST_CELL
		and cell.x < FirstNightContent.MAP_SIZE.x - FIRST_CELL
		and cell.y < FirstNightContent.MAP_SIZE.y - FIRST_CELL
	)


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


static func _position_from_node(node: Dictionary) -> Vector2:
	var cell_value: Variant = node.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() < 2:
		return Vector2.ZERO
	var cell := cell_value as Array
	return FirstNightContent.cell_center(int(cell[0]), int(cell[1]))


static func _is_near_cluster(
	cell: Vector2i,
	centers: Array[Vector2i]
) -> bool:
	for center: Vector2i in centers:
		if Vector2(cell).distance_to(Vector2(center)) < CLUSTER_SEPARATION_CELLS:
			return true
	return false


static func _is_near_static_object(
	position: Vector2,
	static_objects: Array[Dictionary]
) -> bool:
	for object: Dictionary in static_objects:
		var object_position: Vector2 = object.get("position", Vector2.ZERO) as Vector2
		if position.distance_to(object_position) < STATIC_OBJECT_CLEARANCE:
			return true
	return false


static func _is_near_position(
	position: Vector2,
	other_positions: Array[Vector2],
	clearance: float
) -> bool:
	for other_position: Vector2 in other_positions:
		if position.distance_to(other_position) < clearance:
			return true
	return false
