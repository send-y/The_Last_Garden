class_name InventoryShape
extends RefCounted


static func from_raw(raw_footprint: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for raw_cell_variant: Variant in raw_footprint:
		if typeof(raw_cell_variant) != TYPE_ARRAY:
			continue

		var raw_cell := raw_cell_variant as Array
		if raw_cell.size() != 2:
			continue

		var cell := Vector2i(
			int(raw_cell[0]),
			int(raw_cell[1])
		)
		if not cells.has(cell):
			cells.append(cell)

	return normalized(cells)


static func rotated(
	footprint: Array[Vector2i],
	quarter_turns: int
) -> Array[Vector2i]:
	var result := normalized(footprint)
	var turns: int = posmod(quarter_turns, 4)

	for _turn: int in range(turns):
		var next_rotation: Array[Vector2i] = []

		for cell: Vector2i in result:
			next_rotation.append(
				Vector2i(-cell.y, cell.x)
			)

		result = normalized(next_rotation)

	return result


static func normalized(
	footprint: Array[Vector2i]
) -> Array[Vector2i]:
	if footprint.is_empty():
		return []

	var minimum := footprint[0]
	for cell: Vector2i in footprint:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)

	var result: Array[Vector2i] = []
	for cell: Vector2i in footprint:
		result.append(cell - minimum)

	return result


static func bounds_size(
	footprint: Array[Vector2i]
) -> Vector2i:
	if footprint.is_empty():
		return Vector2i.ZERO

	var maximum := Vector2i.ZERO
	for cell: Vector2i in normalized(footprint):
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)

	return maximum + Vector2i.ONE
