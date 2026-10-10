class_name WaterMap
extends RefCounted

const MAP_PATH: String = "res://content/core/water_map.json"
const Content := preload("res://src/content/first_night_content.gd")

static var _surface_cells_cache: Array[Vector2i] = []


static func surface_cells() -> Array[Vector2i]:
	if _surface_cells_cache.is_empty():
		var file := FileAccess.open(MAP_PATH, FileAccess.READ)
		if file == null:
			push_error("Could not read water map: %s" % MAP_PATH)
			return []
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Water map must contain a JSON object: %s" % MAP_PATH)
			return []
		_surface_cells_cache = cells_from_regions(
			(parsed as Dictionary).get("regions", []) as Array
		)
	return _surface_cells_cache.duplicate()


static func cells_from_regions(regions: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for region_value: Variant in regions:
		if typeof(region_value) != TYPE_DICTIONARY:
			continue
		var region := region_value as Dictionary
		var from_value: Variant = region.get("from", [])
		var to_value: Variant = region.get("to", [])
		if (
			typeof(from_value) != TYPE_ARRAY or (from_value as Array).size() != 2
			or typeof(to_value) != TYPE_ARRAY or (to_value as Array).size() != 2
		):
			continue
		var from := Vector2i(int(from_value[0]), int(from_value[1]))
		var to := Vector2i(int(to_value[0]), int(to_value[1]))
		if to.x < from.x or to.y < from.y:
			continue
		for y: int in range(from.y, to.y + 1):
			for x: int in range(from.x, to.x + 1):
				var cell := Vector2i(x, y)
				if seen.has(cell):
					continue
				seen[cell] = true
				result.append(cell)
	return result


static func contains_cell(cell: Vector2i, water_cells: Array[Vector2i] = []) -> bool:
	var cells := water_cells if not water_cells.is_empty() else surface_cells()
	return cells.has(cell)


static func cell_rect(cell: Vector2i) -> Rect2:
	var tile_size := float(Content.CELL_SIZE)
	return Rect2(Vector2(cell) * tile_size, Vector2.ONE * tile_size)
