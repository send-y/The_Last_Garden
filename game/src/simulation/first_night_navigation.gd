class_name FirstNightNavigation
extends RefCounted

const MAP_SIZE: Vector2i = Vector2i(48, 48)
const CELL_SIZE: int = 32


static func blocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for y: int in range(20, 35):
		for x: int in range(0, 7):
			result.append(Vector2i(x, y))

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
