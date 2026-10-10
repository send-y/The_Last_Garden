extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Topology := preload("res://src/construction/room_topology.gd")
const State := preload("res://src/housing/housing_state.gd")
const HomePolicy := preload("res://src/housing/home_policy.gd")
const STARTER := State.STARTER
const STARTER_CELL := Vector2i(26, 23)
const BASE_ROOM := "core:base_house"
const BASE_INTERIOR := Rect2i(20, 18, 8, 7)
const INVALID := Vector2i(-1, -1)
var _geometry_snapshot: Array = []
var _places: Dictionary = {}
var _room_validity: Dictionary = {}

func normalize(sim) -> void:
	State.normalize(sim)
	refresh(sim)

static func is_starter_cell(cell: Vector2i) -> bool:
	return cell == STARTER_CELL

func refresh(sim) -> void:
	var geometry := [sim.state.structures, sim.state.room_assignments]
	if geometry == _geometry_snapshot:
		return
	_geometry_snapshot = geometry.duplicate(true)
	_room_validity.clear()
	for room: Dictionary in sim.state.room_assignments:
		if String(room.room_type_id) == Topology.LIVING_ROOM_ID:
			_room_validity[String(room.id)] = _validate_room(sim,room)
	_places = {STARTER: {"place_id": STARTER, "building_id": "core:bedroll", "cell": [26,23],
		"room_id": BASE_ROOM, "valid": true, "reason_key": "housing.base_temporary"}}
	for structure: Dictionary in sim.state.structures:
		var id := String(structure.get("building_id", ""))
		var raw_cell: Array = structure.cell
		var origin := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if not sim.building_catalog.is_floor(id) and sim.building_catalog.get_footprint_cells(id, origin).has(STARTER_CELL):
			_places[STARTER].valid = false
			_places[STARTER].reason_key = "housing.failure.obstructed"
		if not ["core:bed", "core:bedroll"].has(id):
			continue
		var data: Array = structure.cell
		var cell := Vector2i(int(data[0]), int(data[1]))
		var footprint: Array[Vector2i] = sim.building_catalog.get_footprint_cells(id, cell)
		var inside_base := true
		for occupied: Vector2i in footprint:
			inside_base = inside_base and BASE_INTERIOR.has_point(occupied)
		var room_id := BASE_ROOM if inside_base else ""
		if not inside_base:
			for room: Dictionary in sim.state.room_assignments:
				if String(room.room_type_id) != Topology.LIVING_ROOM_ID:
					continue
				var inside: Dictionary = sim._room_cells_set(room.cells)
				var fully_inside := true
				for occupied: Vector2i in footprint:
					fully_inside = fully_inside and inside.has(occupied)
				if not fully_inside:
					continue
				var candidate := String(room.id)
				if bool(_room_validity.get(candidate,false)):
					room_id = candidate
					break
		var place_id := "%s@%d,%d" % [id, cell.x, cell.y]
		_places[place_id] = {"place_id": place_id, "building_id": id, "cell": data.duplicate(),
			"room_id": room_id, "valid": not room_id.is_empty(),
			"reason_key": "housing.base_temporary" if room_id == BASE_ROOM else ("housing.valid" if not room_id.is_empty() else "housing.failure.room")}

func _validate_room(sim, room: Dictionary) -> bool:
	if room.cells.is_empty(): return false
	var first: Array = room.cells[0]
	var actual := Topology.find_room_at(Vector2i(int(first[0]),int(first[1])),sim.state.structures,sim.building_catalog,Content.MAP_SIZE)
	var inside: Dictionary = sim._room_cells_set(room.cells)
	if actual.size() != inside.size(): return false
	for cell: Vector2i in actual:
		if not inside.has(cell): return false
	return bool(Topology.validate(Topology.LIVING_ROOM_ID,actual,sim.state.structures,sim.building_catalog).success)

func room_valid(sim, room_id: String) -> bool:
	refresh(sim)
	return bool(_room_validity.get(room_id,false))

func place(sim, place_id: String) -> Dictionary:
	refresh(sim)
	return _places.get(place_id,{}).duplicate(true)

func places(sim) -> Array[Dictionary]:
	refresh(sim)
	var result: Array[Dictionary] = []
	for value: Dictionary in _places.values():
		var place := value.duplicate(true)
		place.owner_id = owner(sim, String(place.place_id))
		result.append(place)
	return result

func owner(sim, place_id: String) -> String:
	for id: String in sim.state.sleep_assignments:
		if String(sim.state.sleep_assignments[id]) == place_id:
			return id
	return ""

func assign(sim, character_id: String, place_id: String) -> Dictionary:
	if character_id != "core:player":
		var npc: Dictionary = sim.state.npcs.get(character_id, {})
		if npc.is_empty() or not bool(npc.get("active", false)) or not bool(npc.get("known", false)):
			return sim._emit_result(false, "housing.failure.character")
	if place_id.is_empty():
		sim.state.sleep_assignments[character_id] = ""
		return sim._emit_result(true, "housing.released", true)
	refresh(sim)
	var place: Dictionary = _places.get(place_id, {})
	if place.is_empty() or not bool(place.get("valid", false)):
		return sim._emit_result(false, "housing.failure.room")
	var occupied := owner(sim, place_id)
	if not occupied.is_empty() and occupied != character_id:
		return sim._emit_result(false, "housing.failure.occupied")
	if not HomePolicy.can_assign(sim, character_id, place):
		return sim._emit_result(false, "housing.failure.personal")
	if approach(sim, character_id, place) == INVALID:
		return sim._emit_result(false, "housing.failure.path")
	sim.state.sleep_assignments[character_id] = place_id
	return sim._emit_result(true, "housing.assigned", true)

func approach(sim, character_id: String, place: Dictionary) -> Vector2i:
	var source: Vector2 = sim.get_player_position() if character_id == "core:player" else sim.get_npc_position(character_id, Vector2.ZERO)
	var from: Vector2i = sim._world_position_to_cell(source)
	var cell := Vector2i(int(place.cell[0]), int(place.cell[1]))
	var blocker: Vector2i = INVALID if character_id == "core:player" else sim._world_position_to_cell(sim.get_player_position())
	var room_id := String(place.room_id)
	var inside: Dictionary = {}
	if room_id != BASE_ROOM:
		for room: Dictionary in sim.state.room_assignments:
			if String(room.id) == room_id:
				inside = sim._room_cells_set(room.cells)
	var best := INVALID
	var distance := 1000000
	# Consider every footprint edge: a wall beside the head must not hide the bed's foot.
	var footprint: Array[Vector2i] = [cell]
	if String(place.place_id) != STARTER:
		footprint = sim.building_catalog.get_footprint_cells(String(place.building_id), cell)
	for part: Vector2i in footprint:
		for direction: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
			var target := part + direction
			if (room_id == BASE_ROOM and not BASE_INTERIOR.has_point(target)) or (room_id != BASE_ROOM and not inside.has(target)) or target == blocker or not sim.npc_autonomy.is_cell_walkable(target):
				continue
			if not sim.npc_autonomy.can_reach(from, target, blocker):
				continue
			var current := absi(from.x - target.x) + absi(from.y - target.y)
			if current < distance:
				best = target
				distance = current
	return best

func home(sim, character_id: String) -> Dictionary:
	return profile(sim, character_id, String(sim.state.sleep_assignments.get(character_id, "")))

func profile(sim, character_id: String, id: String) -> Dictionary:
	refresh(sim)
	var place: Dictionary = _places.get(id, {})
	var result: Dictionary = place.duplicate(true) if not place.is_empty() else {"place_id": id, "room_id": "", "building_id": "", "cell": [], "valid": false, "reason_key": "housing.no_place"}
	var covered: bool = sim.is_roof_covered() if String(result.room_id) == BASE_ROOM or not bool(result.valid) else true
	var target := approach(sim, character_id, result) if bool(result.valid) else INVALID
	result.valid = bool(result.valid) and target != INVALID
	result.covered = covered
	result.speed = float(sim.needs.config.get("bed_sleep_speed", 1.35)) if String(result.building_id) == "core:bed" and bool(result.valid) else 1.0
	result.target_cell = [target.x, target.y]
	result.cap = 100.0 if covered and bool(result.valid) else float(sim.needs.config.poor_sleep_cap)
	if not bool(result.valid) and not place.is_empty():
		result.reason_key = "housing.failure.path" if bool(place.valid) else String(place.reason_key)
	return result

func contexts(sim) -> Dictionary:
	var result: Dictionary = {}
	for definition: Dictionary in sim.npc_catalog.get_definitions():
		var id := String(definition.id)
		var npc: Dictionary = sim.state.npcs.get(id, {})
		if not bool(npc.get("active", false)):
			continue
		var current := home(sim, id)
		if bool(current.valid):
			result[id] = current
	return result

func contains_player(sim, place: Dictionary) -> bool:
	var current: Vector2i = sim._world_position_to_cell(sim.get_player_position())
	if String(place.room_id) == BASE_ROOM:
		return BASE_INTERIOR.has_point(current)
	for room: Dictionary in sim.state.room_assignments:
		if String(room.id) == String(place.room_id):
			return sim._room_cells_set(room.cells).has(current)
	return false

func preview_status(sim, place_id: String) -> Dictionary:
	var current := profile(sim, "core:player", place_id)
	var occupied := owner(sim, place_id)
	if not occupied.is_empty() and occupied != "core:player":
		current.valid = false
		current.reason_key = "housing.failure.occupied"
	return current

func sleep_at(sim, place_id: String) -> Dictionary:
	refresh(sim)
	var place: Dictionary = _places.get(place_id, {})
	if place.is_empty() or not bool(place.get("valid", false)):
		return sim._emit_result(false, "housing.failure.room")
	var cell := Vector2i(int(place.cell[0]), int(place.cell[1]))
	if not contains_player(sim, place) or sim.get_player_position().distance_to(Content.cell_center(cell.x, cell.y)) > Content.INTERACTION_RANGE:
		return sim._emit_result(false, "interaction.failure.too_far")
	var previous_assignment: String = String(sim.state.sleep_assignments.get("core:player",""))
	var assigned := assign(sim, "core:player", place_id)
	if not bool(assigned.success):
		return assigned
	if not sim.furniture.leave_player(sim):
		sim.state.sleep_assignments["core:player"] = previous_assignment
		return sim._emit_result(false,"furniture.failure.approach")
	if sim.get_minute_of_day() >= sim.EVENING_MINUTE or sim.get_minute_of_day() < sim.MORNING_MINUTE:
		return sim._sleep_until_morning()
	return sim.rest_player(true)
