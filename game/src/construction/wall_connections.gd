extends RefCounted
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
static func index(structures: Array, catalog) -> Dictionary:
	var occupied: Dictionary = {}
	for structure: Dictionary in structures:
		if not bool(catalog.get_definition(String(structure.building_id)).get("room_boundary",false)): continue
		var at := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
		for cell: Vector2i in catalog.get_footprint_cells(String(structure.building_id),at): occupied[cell] = true
	return occupied
static func mask(cell: Vector2i, occupied: Dictionary) -> int:
	var result := 0
	for i: int in range(4):
		if occupied.has(cell+DIRECTIONS[i]): result |= 1 << i
	return result
static func vertical(connection_mask: int) -> bool:
	return (connection_mask & 10) != 0 and (connection_mask & 5) == 0
