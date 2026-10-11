extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
const Housing := preload("res://src/housing/housing_system.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const ALLOWED := ["core:table", "core:chair", "core:torch"]
const DIRECTIONS := [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]

static func territory(sim, npc: Dictionary) -> Dictionary:
	var span := Diagnostic.begin("home_layout.territory") if Diagnostic.enabled else 0
	var result := _territory(sim,npc)
	Diagnostic.end(span)
	return result

static func _territory(sim, npc: Dictionary) -> Dictionary:
	var home: Dictionary = sim.housing.home(sim, String(npc.id))
	# A person standing at the bed's edge is not loss of room ownership.
	var suitable := bool(sim.housing.place(sim,String(home.place_id)).get("valid",false))
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

static func furnishings(sim, room: Dictionary, blueprints: bool = false, include_floors: bool = true) -> Array[Dictionary]:
	var span := Diagnostic.begin("home_layout.furnishings") if Diagnostic.enabled else 0
	var found: Array[Dictionary] = []
	var cells: Array[Vector2i] = []
	cells.assign(room.cells.keys())
	var candidates: Array = sim.state.blueprints if blueprints else sim.structure_index.in_cells(cells,include_floors)
	for entity: Dictionary in candidates:
		if not include_floors and sim.building_catalog.is_floor(String(entity.building_id)): continue
		if inside(sim,entity,room.cells): found.append(entity)
	Diagnostic.end(span)
	return found

# Read-only local connectivity check. Do not swap the authoritative navigator.
static func can_place(sim, npc: Dictionary, building: String, origin: Vector2i, ignore_blueprint: Array = [], ignore_actors: bool = false) -> bool:
	var span := Diagnostic.begin("home_layout.can_place") if Diagnostic.enabled else 0
	var result := _can_place(sim,npc,building,origin,ignore_blueprint,ignore_actors)
	Diagnostic.end(span)
	return result

static func _can_place(sim, npc: Dictionary, building: String, origin: Vector2i, ignore_blueprint: Array, ignore_actors: bool) -> bool:
	if not ALLOWED.has(building): return false
	var room := territory(sim,npc)
	if room.is_empty(): return false
	return _can_place_in_context(sim,npc,building,origin,_placement_context(sim,npc,room),ignore_blueprint,ignore_actors)

# A synchronous search only: no context survives a command, minute or world reload.
# Keep actor occupancy and work approaches live for each proposed position.
static func _placement_context(sim, npc: Dictionary, room: Dictionary) -> Dictionary:
	var policy: Dictionary = sim.HomePolicy.for_character(sim,String(npc.id))
	var entities := furnishings(sim,room,false,false)
	var furniture_cells: Dictionary = {}
	var parts: Array = []
	for entity: Dictionary in entities:
		if sim.building_catalog.is_floor(String(entity.building_id)): continue
		var footprint: Array[Vector2i] = sim.building_catalog.get_footprint_cells(String(entity.building_id),Vector2i(int(entity.cell[0]),int(entity.cell[1])))
		parts.append({"building_id":entity.building_id,"cells":footprint})
		for cell: Vector2i in footprint: furniture_cells[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in room.cells:
		if sim.npc_autonomy.is_cell_walkable(cell) and not furniture_cells.has(cell): free[cell] = true
	var blueprints: Array = []
	for blueprint: Dictionary in sim.state.blueprints:
		blueprints.append({"cell":blueprint.cell,"building_id":blueprint.building_id,
			"cells":sim.building_catalog.get_footprint_cells(String(blueprint.building_id),Vector2i(int(blueprint.cell[0]),int(blueprint.cell[1]))),
			"blocks":bool(sim.building_catalog.get_definition(String(blueprint.building_id)).get("blocks_movement",false))})
	return {"room":room,"allowed":String(policy.mode) in ["personal","shared"],"entities":entities,"parts":parts,"free":free,"blueprints":blueprints}

static func _can_place_in_context(sim, npc: Dictionary, building: String, origin: Vector2i, context: Dictionary, ignore_blueprint: Array, ignore_actors: bool) -> bool:
	if not ALLOWED.has(building) or not bool(context.allowed): return false
	var room: Dictionary = context.room
	var footprint: Array[Vector2i] = sim.building_catalog.get_footprint_cells(building,origin)
	var excluded: Dictionary = {}
	for cell: Vector2i in footprint:
		if not room.cells.has(cell) or not sim.npc_autonomy.is_cell_walkable(cell) or Housing.is_starter_cell(cell) or sim._storage_zone_index_at_cell(cell) >= 0 or not sim.farming.bed_at(sim,cell).is_empty(): return false
		if not ignore_actors and sim._is_actor_in_cell([cell.x,cell.y]): return false
		excluded[cell] = true
	for structure: Dictionary in sim.structure_index.in_cells(footprint):
		if not sim.building_catalog.is_floor(String(structure.building_id)):
			return false
	for blueprint: Dictionary in context.blueprints:
		if blueprint.cell == ignore_blueprint and String(blueprint.building_id) == building: continue
		for cell: Vector2i in blueprint.cells:
			if excluded.has(cell): return false
			if bool(blueprint.blocks): excluded[cell] = true
	# Keep every remaining walkable interior cell connected, including every
	# approach to existing beds, stations, chairs and warehouse cells.
	var free: Dictionary = {}
	for cell: Vector2i in context.free:
		# A passable bedroll is still furniture, not the standing area needed to use a table.
		if not excluded.has(cell): free[cell] = true
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
	var all: Array = context.parts.duplicate()
	all.append({"building_id":building,"cells":footprint})
	for entity: Dictionary in all:
		var usable := false
		for cell: Vector2i in entity.cells:
			for direction: Vector2i in DIRECTIONS:
				usable = usable or free.has(cell + direction)
		if not usable: return false
	if building == "core:chair":
		var adjacent := false
		for entity: Dictionary in all:
			if String(entity.building_id) == "core:table":
				for cell: Vector2i in entity.cells:
					adjacent = adjacent or absi(cell.x-origin.x) + absi(cell.y-origin.y) == 1
		if not adjacent: return false
	if ignore_actors:
		return sim.npc_autonomy.find_construction_work_cell(origin,Supply.cell_of(sim,npc),Vector2i(-1,-1)) != Vector2i(-1,-1)
	return Supply.work_cell(sim,npc,origin) != Vector2i(-1,-1)

static func choose_cell(sim, npc: Dictionary, building: String, rng: RandomNumberGenerator, ignore_actors: bool = false) -> Vector2i:
	var room := territory(sim,npc)
	if room.is_empty(): return Vector2i(-1,-1)
	var context := _placement_context(sim,npc,room)
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
		for entity: Dictionary in context.entities:
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
		var span := Diagnostic.begin("home_layout.can_place") if Diagnostic.enabled else 0
		var valid := _can_place_in_context(sim,npc,building,cell,context,[],ignore_actors)
		Diagnostic.end(span)
		if valid: return cell
	return Vector2i(-1,-1)
