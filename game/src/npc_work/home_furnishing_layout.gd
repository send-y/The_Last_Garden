extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Housing := preload("res://src/housing/housing_system.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const ALLOWED := ["core:table", "core:chair", "core:torch"]
const DIRECTIONS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]

static func territory(sim, npc: Dictionary) -> Dictionary:
	var home: Dictionary = sim.housing.home(sim, String(npc.id))
	# A person standing at the bed's edge is not loss of room ownership.
	var suitable := false
	for place: Dictionary in sim.housing.places(sim):
		if String(place.place_id) == String(home.place_id): suitable = bool(place.valid)
	if not suitable: return {}
	var cells: Dictionary = {}
	if String(home.room_id) == Housing.BASE_ROOM:
		for y: int in range(Housing.BASE_INTERIOR.position.y, Housing.BASE_INTERIOR.end.y):
			for x: int in range(Housing.BASE_INTERIOR.position.x, Housing.BASE_INTERIOR.end.x):
				cells[Vector2i(x,y)] = true
	else:
		for room: Dictionary in sim.state.room_assignments:
			if String(room.id) == String(home.room_id):
				cells = sim._room_cells_set(room.cells)
	return {"id":String(home.room_id),"cells":cells,"home":home} if not cells.is_empty() else {}

static func inside(sim, entity: Dictionary, cells: Dictionary) -> bool:
	var origin := Vector2i(int(entity.cell[0]),int(entity.cell[1]))
	for cell: Vector2i in sim.building_catalog.get_footprint_cells(String(entity.building_id),origin):
		if not cells.has(cell): return false
	return true

static func furnishings(sim, room: Dictionary, blueprints: bool = false) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entity: Dictionary in sim.state.blueprints if blueprints else sim.state.structures:
		if inside(sim,entity,room.cells): found.append(entity)
	return found

# Read-only local connectivity check. Do not swap the authoritative navigator.
static func can_place(sim, npc: Dictionary, building: String, origin: Vector2i, ignore_blueprint: Array = [], ignore_actors: bool = false) -> bool:
	if not ALLOWED.has(building): return false
	var room := territory(sim,npc)
	if room.is_empty(): return false
	var policy: Dictionary = sim.HomePolicy.for_character(sim,String(npc.id))
	if String(policy.mode) not in ["personal", "shared"]: return false
	var footprint: Array[Vector2i] = sim.building_catalog.get_footprint_cells(building,origin)
	var excluded: Dictionary = {}
	for cell: Vector2i in footprint:
		if not room.cells.has(cell) or not sim.npc_autonomy.is_cell_walkable(cell) or Housing.is_starter_cell(cell) or sim._storage_zone_index_at_cell(cell) >= 0 or not sim.farming.bed_at(sim,cell).is_empty(): return false
		if not ignore_actors and sim._is_actor_in_cell([cell.x,cell.y]): return false
		excluded[cell] = true
	for structure: Dictionary in sim.state.structures:
		if not sim.building_catalog.is_floor(String(structure.building_id)):
			for cell: Vector2i in sim.building_catalog.get_footprint_cells(String(structure.building_id),Vector2i(int(structure.cell[0]),int(structure.cell[1]))):
				if excluded.has(cell): return false
	for blueprint: Dictionary in sim.state.blueprints:
		if blueprint.cell == ignore_blueprint and String(blueprint.building_id) == building: continue
		for cell: Vector2i in sim.building_catalog.get_footprint_cells(String(blueprint.building_id),Vector2i(int(blueprint.cell[0]),int(blueprint.cell[1]))):
			if excluded.has(cell): return false
			if bool(sim.building_catalog.get_definition(String(blueprint.building_id)).get("blocks_movement",false)): excluded[cell] = true
	# Keep every remaining walkable interior cell connected, including every
	# approach to existing beds, stations, chairs and warehouse cells.
	var free: Dictionary = {}
	var furniture_cells: Dictionary = {}
	for entity: Dictionary in furnishings(sim,room):
		if sim.building_catalog.is_floor(String(entity.building_id)): continue
		for part: Vector2i in sim.building_catalog.get_footprint_cells(String(entity.building_id),Vector2i(int(entity.cell[0]),int(entity.cell[1]))):
			furniture_cells[part] = true
	for cell: Vector2i in room.cells:
		# A passable bedroll is still furniture, not the standing area needed to use a table.
		if sim.npc_autonomy.is_cell_walkable(cell) and not excluded.has(cell) and not furniture_cells.has(cell): free[cell] = true
	if free.is_empty(): return false
	var queue: Array[Vector2i] = [free.keys()[0]]
	var visited: Dictionary = {queue[0]:true}
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction: Vector2i in DIRECTIONS:
			var target := current + direction
			if free.has(target) and not visited.has(target):
				visited[target] = true
				queue.append(target)
	if visited.size() != free.size(): return false
	# Every doorway/old connection out of the interior must still have an edge.
	for cell: Vector2i in footprint:
		for direction: Vector2i in DIRECTIONS:
			var outside := cell + direction
			if not room.cells.has(outside) and sim.npc_autonomy.is_cell_walkable(outside): return false
	var proposed := {"building_id":building,"cell":[origin.x,origin.y]}
	var all: Array[Dictionary] = furnishings(sim,room)
	all.append(proposed)
	for entity: Dictionary in all:
		if sim.building_catalog.is_floor(String(entity.building_id)): continue
		var usable := false
		for cell: Vector2i in sim.building_catalog.get_footprint_cells(String(entity.building_id),Vector2i(int(entity.cell[0]),int(entity.cell[1]))):
			for direction: Vector2i in DIRECTIONS:
				usable = usable or free.has(cell + direction)
		if not usable: return false
	if building == "core:chair":
		var adjacent := false
		for entity: Dictionary in all:
			if String(entity.building_id) == "core:table":
				for cell: Vector2i in sim.building_catalog.get_footprint_cells("core:table",Vector2i(int(entity.cell[0]),int(entity.cell[1]))):
					adjacent = adjacent or absi(cell.x-origin.x) + absi(cell.y-origin.y) == 1
		if not adjacent: return false
	if ignore_actors:
		return sim.npc_autonomy.find_construction_work_cell(origin,Supply.cell_of(sim,npc),Vector2i(-1,-1)) != Vector2i(-1,-1)
	return Supply.work_cell(sim,npc,origin) != Vector2i(-1,-1)

static func choose_cell(sim, npc: Dictionary, building: String, rng: RandomNumberGenerator, ignore_actors: bool = false) -> Vector2i:
	var room := territory(sim,npc)
	if room.is_empty(): return Vector2i(-1,-1)
	var cells: Array = room.cells.keys()
	# Seeded ordering avoids identical automatic arrangements in every house.
	for index: int in range(cells.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var value: Vector2i = cells[index]
		cells[index] = cells[other]
		cells[other] = value
	var profile: Dictionary = sim.state.get("npc_profiles", {}).get(String(npc.id), {})
	var values: Array = profile.get("value_ids", [])
	if values.has("core:care") or values.has("core:order") or values.has("core:independence"):
		var beds: Array[Vector2i] = []
		for entity: Dictionary in furnishings(sim,room):
			if String(entity.building_id) in ["core:bedroll", "core:bed"]:
				beds.append(Vector2i(int(entity.cell[0]),int(entity.cell[1])))
		var boundary: Array[Vector2i] = []
		for cell: Vector2i in cells:
			for direction: Vector2i in DIRECTIONS:
				if not room.cells.has(cell + direction):
					boundary.append(cell)
					break
		var scores: Dictionary = {}
		for cell: Vector2i in cells:
			var bed_distance := 0.0
			for bed: Vector2i in beds:
				bed_distance += absi(cell.x-bed.x) + absi(cell.y-bed.y)
			bed_distance /= maxi(1,beds.size())
			var wall_distance := 128
			for edge: Vector2i in boundary:
				wall_distance = mini(wall_distance,absi(cell.x-edge.x)+absi(cell.y-edge.y))
			# Provisional spatial tastes bias safe choices, never override connectivity.
			var score := rng.randf() * 0.15
			if values.has("core:care"): score -= bed_distance * 0.5
			if values.has("core:independence") and building != "core:torch": score += bed_distance * 0.5
			if values.has("core:order"): score -= float(wall_distance) * 0.75
			scores[cell] = score
		cells.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return float(scores[a]) > float(scores[b]))
	for cell: Vector2i in cells:
		if can_place(sim,npc,building,cell,[],ignore_actors): return cell
	return Vector2i(-1,-1)
