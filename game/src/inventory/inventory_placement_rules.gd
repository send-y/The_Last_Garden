class_name InventoryPlacementRules
extends RefCounted

const ShapeRules := preload(
	"res://src/inventory/inventory_shape.gd"
)

const INVALID_ORIGIN := Vector2i(-1, -1)


static func cells_at(
	footprint: Array[Vector2i],
	origin: Vector2i
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell: Vector2i in footprint:
		result.append(origin + cell)

	return result


static func can_place(
	footprint: Array[Vector2i],
	origin: Vector2i,
	occupied_cells: Dictionary,
	columns: int,
	rows: int
) -> bool:
	if footprint.is_empty():
		return false

	for cell: Vector2i in cells_at(footprint, origin):
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x >= columns
			or cell.y >= rows
		):
			return false

		if occupied_cells.has(cell):
			return false

	return true


static func find_first_fit(
	base_footprint: Array[Vector2i],
	occupied_cells: Dictionary,
	columns: int,
	rows: int
) -> Dictionary:
	for quarter_turns: int in range(4):
		var footprint: Array[Vector2i] = ShapeRules.rotated(
			base_footprint,
			quarter_turns
		)

		for row: int in range(rows):
			for column: int in range(columns):
				var origin := Vector2i(column, row)

				if can_place(
					footprint,
					origin,
					occupied_cells,
					columns,
					rows
				):
					return {
						"origin": origin,
						"rotation": quarter_turns,
					}

	return {
		"origin": INVALID_ORIGIN,
		"rotation": 0,
	}


static func occupy(
	footprint: Array[Vector2i],
	origin: Vector2i,
	occupied_cells: Dictionary,
	placement_id: String
) -> void:
	for cell: Vector2i in cells_at(footprint, origin):
		occupied_cells[cell] = placement_id
