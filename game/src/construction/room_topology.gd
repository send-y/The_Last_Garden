class_name RoomTopology
extends RefCounted

const STORAGE_ROOM_ID := "core:storage_room"
const LIVING_ROOM_ID := "core:living_room"
const ROOM_LIMITS := {
	STORAGE_ROOM_ID: Vector2i(4, 25),
	LIVING_ROOM_ID: Vector2i(6, 49),
}
const REQUIRED_ROLES := {
	"bed": true,
	"table": true,
	"lighting": true,
}
const ALLOWED_STORAGE_ROLES := ["storage_shelf", "storage_cabinet"]


static func find_room_at(
	target: Vector2i,
	structures: Array[Dictionary],
	catalog: BuildingCatalog,
	map_size: Vector2i
) -> Array[Vector2i]:
	var bounds := Rect2i(Vector2i.ZERO, map_size)
	if not bounds.has_point(target):
		return []
	var boundary_cells: Dictionary = {}
	for structure: Dictionary in structures:
		var building_id := String(structure.get("building_id", ""))
		if not bool(catalog.get_definition(building_id).get("room_boundary", false)):
			continue
		var raw_origin: Variant = structure.get("cell", [])
		if typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		for boundary_cell: Vector2i in catalog.get_footprint_cells(building_id, origin):
			boundary_cells[boundary_cell] = true
	if boundary_cells.has(target):
		return []
	var visited: Dictionary = {target: true}
	var queue: Array[Vector2i] = [target]
	var cells: Array[Vector2i] = []
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		cells.append(cell)
		if (
			cell.x == 0 or cell.y == 0
			or cell.x == map_size.x - 1 or cell.y == map_size.y - 1
		):
			return []
		for neighbor: Vector2i in [
			cell + Vector2i.LEFT,
			cell + Vector2i.RIGHT,
			cell + Vector2i.UP,
			cell + Vector2i.DOWN,
		]:
			if not bounds.has_point(neighbor) or visited.has(neighbor):
				continue
			visited[neighbor] = true
			if boundary_cells.has(neighbor):
				continue
			queue.append(neighbor)
	return cells


static func validate(
	room_type_id: String,
	cells: Array[Vector2i],
	structures: Array[Dictionary],
	catalog: BuildingCatalog
) -> Dictionary:
	if not ROOM_LIMITS.has(room_type_id):
		return _failure("core:room_type_unknown")
	var limits: Vector2i = ROOM_LIMITS[room_type_id]
	if cells.size() < limits.x:
		return _failure("core:room_too_small")
	if cells.size() > limits.y:
		return _failure("core:room_too_large")
	var inside: Dictionary = {}
	for cell: Vector2i in cells:
		inside[cell] = true
	if room_type_id == STORAGE_ROOM_ID and not _has_door_access(cells, structures, catalog):
		return _failure("core:room_door_required")
	var roles: Dictionary = {}
	for structure: Dictionary in structures:
		var building_id := String(structure.get("building_id", ""))
		if catalog.is_floor(building_id):
			continue
		var raw_origin: Variant = structure.get("cell", [])
		if typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		var footprint := catalog.get_footprint_cells(building_id, origin)
		var intersects := false
		var fully_inside := true
		for occupied_cell: Vector2i in footprint:
			if inside.has(occupied_cell):
				intersects = true
			else:
				fully_inside = false
		if not intersects:
			continue
		var role := String(catalog.get_definition(building_id).get("room_role", ""))
		if room_type_id == STORAGE_ROOM_ID:
			if not ALLOWED_STORAGE_ROLES.has(role):
				return _failure("core:room_storage_furniture_forbidden")
		elif fully_inside and REQUIRED_ROLES.has(role):
			roles[role] = true
	# A sleeping foundation admits residents; table and light remain comfort improvements.
	if room_type_id == LIVING_ROOM_ID and not roles.has("bed"):
		return _failure("core:room_missing_requirements")
	return {"success": true, "reason_id": "core:room_valid"}


static func _has_door_access(
	cells: Array[Vector2i],
	structures: Array[Dictionary],
	catalog: BuildingCatalog
) -> bool:
	var inside: Dictionary = {}
	for cell: Vector2i in cells:
		inside[cell] = true
	for structure: Dictionary in structures:
		if String(structure.get("building_id", "")) != "core:wood_door":
			continue
		var raw_origin: Variant = structure.get("cell", [])
		if typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		for boundary_cell: Vector2i in catalog.get_footprint_cells("core:wood_door", origin):
			for neighbor: Vector2i in [
				boundary_cell + Vector2i.LEFT,
				boundary_cell + Vector2i.RIGHT,
				boundary_cell + Vector2i.UP,
				boundary_cell + Vector2i.DOWN,
			]:
				if inside.has(neighbor):
					return true
	return false


static func _failure(reason_id: String) -> Dictionary:
	return {"success": false, "reason_id": reason_id}
