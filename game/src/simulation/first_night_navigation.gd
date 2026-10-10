class_name FirstNightNavigation
extends RefCounted

const MAP_SIZE: Vector2i = Vector2i(128, 128)
const CELL_SIZE: int = 32
const WaterMapScript := preload("res://src/world/water_map.gd")


static func blocked_cells(water_cells: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var resolved_water_cells := water_cells
	if resolved_water_cells.is_empty():
		resolved_water_cells = WaterMapScript.surface_cells()
	result.append_array(resolved_water_cells)

	for x: int in range(19, 29):
		result.append(Vector2i(x, 17))
	for y: int in range(18, 26):
		result.append(Vector2i(19, y))
		result.append(Vector2i(28, y))
	for x: int in range(19, 24):
		result.append(Vector2i(x, 25))
	for x: int in range(25, 29):
		result.append(Vector2i(x, 25))

	return result
