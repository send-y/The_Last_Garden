extends RefCounted

const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

const Content := preload("res://src/content/first_night_content.gd")
const Lighting := preload("res://src/furniture/lighting_field.gd")
const INVALID := Vector2i(-1,-1)
const MAX_SEAT_DISTANCE := 12 * Content.CELL_SIZE
var lighting := Lighting.new()
var _index: RefCounted
var _geometry_revision := -1
var _seats: Array[Dictionary] = []

func normalize(sim) -> void:
	refresh(sim)
	var raw: Variant = sim.state.get("player_furniture_use",{})
	sim.state.player_furniture_use = _use(raw)
	for id: String in sim.state.npcs:
		# Preserve unknown/modded resident records until their catalog is available.
		if sim.npc_catalog.get_definition(id).is_empty():
			continue
		var npc: Dictionary = sim.state.npcs[id]
		npc.furniture_use = _use(npc.get("furniture_use",{}))
		npc.furniture_target = _cell_array(npc.get("furniture_target",[]))
		raw = npc.get("meal_trip",{})
		npc.meal_trip = {}
		if raw is Dictionary:
			var item := String(raw.get("item_id",""))
			if int(npc.personal_inventory.get(item,0)) > 0 and not sim.needs.food_profile(item,sim.content).is_empty():
				npc.meal_trip = {"item_id":item}
		if not npc.furniture_target.is_empty() and seat_at(sim,npc.furniture_target).is_empty():
			npc.furniture_target = []
		if not npc.furniture_use.is_empty() and seat_at(sim,npc.furniture_use.chair_cell).is_empty():
			npc.furniture_use = {}
	if not sim.state.player_furniture_use.is_empty() and seat_at(sim,sim.state.player_furniture_use.chair_cell).is_empty():
		sim.state.player_furniture_use = {}

func _cell_array(raw: Variant) -> Array:
	if not raw is Array or raw.size() != 2:
		return []
	for value: Variant in raw:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) >= 128:
			return []
	return [int(raw[0]),int(raw[1])]

func _use(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not ["meal","rest"].has(String(raw.get("kind",""))):
		return {}
	var cell := _cell_array(raw.get("chair_cell",[]))
	if cell.is_empty():
		return {}
	var until: Variant = raw.get("until",0)
	return {"chair_cell":cell,"kind":String(raw.kind),"until":maxi(0,int(until)) if (until is int or until is float) and is_finite(float(until)) else 0,
		"approach":_cell_array(raw.get("approach",[]))}

func refresh(sim) -> void:
	if _index == sim.structure_index and _geometry_revision == sim.structure_index.geometry_revision: return
	var span := Diagnostic.begin("furniture.rebuild") if Diagnostic.enabled else 0
	_index = sim.structure_index
	_geometry_revision = _index.geometry_revision
	_seats.clear()
	var tables: Dictionary = {}
	for structure: Dictionary in _index.of_type("core:table"):
		var origin := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
		for cell: Vector2i in sim.building_catalog.get_footprint_cells("core:table",origin):
			tables[cell] = structure.cell.duplicate()
	for structure: Dictionary in _index.of_type("core:chair"):
		var chair := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
		var table: Array = []
		for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if tables.has(chair + direction):
				table = tables[chair + direction]
				break
		_seats.append({"chair_cell":structure.cell.duplicate(),"table_cell":table.duplicate()})
	Diagnostic.end(span)

func seat_at(sim, cell: Array) -> Dictionary:
	refresh(sim)
	for seat: Dictionary in _seats:
		if seat.chair_cell == cell:
			return seat.duplicate(true)
	return {}

func owner(sim, cell: Array) -> String:
	var use: Dictionary = sim.state.get("player_furniture_use",{})
	if use.get("chair_cell",[]) == cell:
		return "core:player"
	for id: String in sim.state.npcs:
		var npc: Dictionary = sim.state.npcs[id]
		if not bool(npc.get("active",false)) or sim.npc_catalog.get_definition(id).is_empty():
			continue
		if npc.get("furniture_target",[]) == cell or npc.get("furniture_use",{}).get("chair_cell",[]) == cell:
			return id
		var current: Vector2i = sim._world_position_to_cell(sim.get_npc_position(id,Vector2.ZERO))
		if cell == [current.x,current.y]:
			return id
	return ""

func approach(sim, id: String, seat: Dictionary) -> Vector2i:
	var source: Vector2 = sim.get_player_position() if id == "core:player" else sim.get_npc_position(id,Vector2.ZERO)
	var from: Vector2i = sim._world_position_to_cell(source)
	var blocker: Vector2i = INVALID if id == "core:player" else sim._world_position_to_cell(sim.get_player_position())
	return _approach_in_context(sim,id,seat,_approach_context(sim,id,from,blocker))

func _approach_context(sim, id: String, from: Vector2i, blocker: Vector2i) -> Dictionary:
	var occupied: Dictionary = {}
	for other: String in sim.state.npcs:
		if other != id and bool(sim.state.npcs[other].get("active",false)):
			occupied[sim._world_position_to_cell(sim.get_npc_position(other,Vector2.ZERO))] = true
	return {"from":from,"blocker":blocker,"occupied":occupied}

func _approach_in_context(sim, id: String, seat: Dictionary, context: Dictionary) -> Vector2i:
	var chair := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
	var from: Vector2i = context.from
	var blocker: Vector2i = context.blocker
	if from == chair and owner(sim,seat.chair_cell) == id: return chair
	var best := INVALID
	var distance := 1000000
	for direction: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
		var target := chair + direction
		if target == blocker or not sim.npc_autonomy.can_reach(from,target,blocker):
			continue
		if context.occupied.has(target): continue
		var cost := absi(from.x-target.x) + absi(from.y-target.y)
		if cost < distance:
			best = target
			distance = cost
	return best

func find_seat(sim, id: String, meal: bool, at: Vector2i = INVALID, evening: bool = false) -> Dictionary:
	refresh(sim)
	var source: Vector2 = sim.get_player_position() if id == "core:player" else sim.get_npc_position(id,Vector2.ZERO)
	var best: Dictionary = {}
	var score := INF
	var context: Dictionary = {}
	for seat: Dictionary in _seats:
		if meal and seat.table_cell.is_empty():
			continue
		if at != INVALID and seat.chair_cell != [at.x,at.y] and seat.table_cell != [at.x,at.y]:
			continue
		# Every approach is at most one cell from the chair. Outside this
		# conservative radius no reachable approach could pass the limit below.
		var chair_position := Content.cell_center(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
		if id != "core:player" and source.distance_to(chair_position) > MAX_SEAT_DISTANCE + Content.CELL_SIZE:
			continue
		var occupied := owner(sim,seat.chair_cell)
		if not occupied.is_empty() and occupied != id:
			continue
		# This synchronous query cannot move residents. Read occupancy once for
		# all candidate chairs, while every new query sees current positions.
		if context.is_empty():
			context = _approach_context(sim,id,sim._world_position_to_cell(source),INVALID if id == "core:player" else sim._world_position_to_cell(sim.get_player_position()))
		var target := _approach_in_context(sim,id,seat,context)
		if target == INVALID:
			continue
		var distance := source.distance_to(Content.cell_center(target.x,target.y))
		# A distant dining area must not make a starving resident cross the map.
		if id != "core:player" and distance > MAX_SEAT_DISTANCE:
			continue
		var chair := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
		var lit := lighting.has_artificial_light(sim,chair) if evening else lighting.is_lit(sim,chair)
		var current := distance + (0 if lit else 8 * Content.CELL_SIZE)
		if current < score:
			score = current
			best = seat.duplicate(true)
			best.target_cell = [target.x,target.y]
	return best

func dining_seats(sim) -> Array[Dictionary]:
	refresh(sim)
	var result: Array[Dictionary] = []
	for seat: Dictionary in _seats:
		if not seat.table_cell.is_empty():
			result.append(seat.duplicate(true))
	return result

func sit_npc(sim, npc: Dictionary, seat: Dictionary, kind: String) -> bool:
	var actual := seat_at(sim,seat.get("chair_cell",[]))
	if actual.is_empty() or (kind == "meal" and actual.table_cell.is_empty()):
		return false
	var occupied := owner(sim,actual.chair_cell)
	if not occupied.is_empty() and occupied != String(npc.id):
		return false
	var cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO))
	var target: Array = seat.get("target_cell",[])
	if target != [cell.x,cell.y]:
		return false
	npc.furniture_target = actual.chair_cell.duplicate()
	npc.furniture_use = {"chair_cell":actual.chair_cell,"kind":kind,"until":sim.get_elapsed_game_minutes() + 5 if kind == "meal" else 0,"approach":[cell.x,cell.y]}
	npc.position = [Content.cell_center(int(actual.chair_cell[0]),int(actual.chair_cell[1])).x,Content.cell_center(int(actual.chair_cell[0]),int(actual.chair_cell[1])).y]
	return true

func npc_contexts(sim) -> Dictionary:
	var result: Dictionary = {}
	for id: String in sim.state.npcs:
		var npc: Dictionary = sim.state.npcs[id]
		if not bool(npc.get("active",false)) or sim.npc_catalog.get_definition(id).is_empty():
			continue
		var use: Dictionary = npc.furniture_use
		var holding_meal: bool = not use.is_empty() and String(use.kind) == "meal" and int(use.until) > sim.get_elapsed_game_minutes()
		var day: bool = sim.get_minute_of_day() >= 7 * 60 and sim.get_minute_of_day() < 21 * 60
		var resting := float(npc.needs.energy) <= 18 or (String(npc.activity_id) in ["core:chair_resting","core:resting","core:going_to_rest"] and float(npc.needs.energy) < 72)
		var actual := seat_at(sim,use.get("chair_cell",[]))
		if holding_meal and not actual.is_empty() and not actual.table_cell.is_empty() and not comfort(sim,id).is_empty():
			result[id] = {"kind":"meal","chair_cell":use.chair_cell,"target_cell":use.chair_cell}
			continue
		if not use.is_empty() and (String(use.kind) == "meal" or not day or not resting or seat_at(sim,use.chair_cell).is_empty()):
			npc.furniture_use = {}
			npc.furniture_target = []
		if not day or not resting:
			if npc.meal_trip.is_empty() and npc.furniture_use.is_empty():
				npc.furniture_target = []
			continue
		var seat := find_seat(sim,id,false)
		if not seat.is_empty():
			npc.furniture_target = seat.chair_cell.duplicate()
			seat.kind = "rest"
			result[id] = seat
	return result

func comfort(sim, id: String) -> Dictionary:
	var use: Dictionary = sim.state.get("player_furniture_use",{}) if id == "core:player" else sim.state.npcs.get(id,{}).get("furniture_use",{})
	if use.is_empty() or seat_at(sim,use.get("chair_cell",[])).is_empty():
		return {}
	var cell := Vector2i(int(use.chair_cell[0]),int(use.chair_cell[1]))
	var position: Vector2 = sim.get_player_position() if id == "core:player" else sim.get_npc_position(id,Vector2.ZERO)
	if sim._world_position_to_cell(position) != cell or owner(sim,use.chair_cell) != id:
		return {}
	return {"seated":true,"lit":lighting.is_lit(sim,cell),"dark":sim.get_minute_of_day() < 7 * 60 or sim.get_minute_of_day() >= 18 * 60}

func leave_player(sim) -> bool:
	var use: Dictionary = sim.state.get("player_furniture_use",{})
	if use.is_empty():
		return true
	var chair := Vector2i(int(use.chair_cell[0]),int(use.chair_cell[1]))
	var exits: Array[Vector2i] = []
	var original: Array = use.get("approach",[])
	if original.size() == 2:
		exits.append(Vector2i(int(original[0]),int(original[1])))
	for direction: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
		var next := chair + direction
		if not exits.has(next):
			exits.append(next)
	for exit: Vector2i in exits:
		if chair.distance_to(exit) != 1.0 or not sim.npc_autonomy.is_cell_walkable(exit):
			continue
		var occupied := false
		for id: String in sim.state.npcs:
			if bool(sim.state.npcs[id].get("active",false)) and sim._world_position_to_cell(sim.get_npc_position(id,Vector2.ZERO)) == exit:
				occupied = true
		if not occupied:
			sim.state.player_furniture_use = {}
			sim.set_player_position(Content.cell_center(exit.x,exit.y))
			return true
	return false

func options(sim, cell: Vector2i) -> Dictionary:
	var id := ""
	for structure: Dictionary in sim.state.structures:
		if structure.cell == [cell.x,cell.y]:
			id = String(structure.building_id)
			if not sim.building_catalog.is_floor(id):
				break
	var foods: Array[String] = []
	for item: String in sim.get_inventory():
		if sim.get_item_count(item) > 0 and not sim.needs.food_profile(item,sim.content).is_empty():
			foods.append(item)
	var rest := find_seat(sim,"core:player",false,cell)
	var light_cell := cell if rest.is_empty() else Vector2i(int(rest.chair_cell[0]),int(rest.chair_cell[1]))
	return {"building_id":id,"foods":foods,"meal":find_seat(sim,"core:player",true,cell),"rest":rest,"lit":lighting.is_lit(sim,light_cell)}

func execute(sim, cell: Vector2i, action: String, item: String = "") -> Dictionary:
	var data := options(sim,cell)
	if sim.get_player_position().distance_to(Content.cell_center(cell.x,cell.y)) > Content.INTERACTION_RANGE:
		return sim._emit_result(false,"interaction.failure.too_far")
	if action == "toggle_light" and String(data.building_id) == "core:torch":
		for structure: Dictionary in sim.state.structures:
			if structure.cell == [cell.x,cell.y] and String(structure.building_id) == "core:torch":
				var lit := not bool(structure.get("lit",true))
				sim.set_structure_state(structure,"lit",lit)
				return sim._emit_result(true,"furniture.light.on" if lit else "furniture.light.off",true,true)
	if not ["eat","rest"].has(action) or not ["core:chair","core:table"].has(String(data.building_id)):
		return sim._emit_result(false,"interaction.failure.unsupported_target")
	var seat: Dictionary = data.meal if action == "eat" else data.rest
	if seat.is_empty():
		return sim._emit_result(false,"furniture.failure.seat")
	var target := Vector2i(int(seat.target_cell[0]),int(seat.target_cell[1]))
	var current: Vector2i = sim._world_position_to_cell(sim.get_player_position())
	if current != target or sim.get_player_position().distance_to(Content.cell_center(int(seat.chair_cell[0]),int(seat.chair_cell[1]))) > Content.INTERACTION_RANGE:
		return sim._emit_result(false,"furniture.failure.approach")
	if action == "eat" and (not data.foods.has(item) or not sim._consume_items({item:1})):
		return sim._emit_result(false,"ui.inventory.food.none")
	var previous: Dictionary = sim.state.player_furniture_use
	var approach_cell: Array = previous.get("approach",[current.x,current.y])
	sim.state.player_furniture_use = {"chair_cell":seat.chair_cell,"approach":approach_cell,"kind":"rest","until":0}
	sim.set_player_position(Content.cell_center(int(seat.chair_cell[0]),int(seat.chair_cell[1])))
	if action == "eat":
		var physical: Dictionary = sim.get_player_needs()
		sim.needs.feed(physical,sim.needs.food_profile(item,sim.content))
		sim.work_metrics.record_meal(sim,"core:player",item)
		sim.state.player_energy = physical.energy
		sim.state.player_needs.hunger = physical.hunger
		sim.WorldCalendarSystem._advance_clock(sim,5,true,"resting_on_chair")
	else:
		sim.WorldCalendarSystem._advance_clock(sim,15,true,"resting_on_chair")
	return sim._emit_result(true,"furniture.ate" if action == "eat" else "furniture.rested",true,true)
