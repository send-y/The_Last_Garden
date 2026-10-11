extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Topology := preload("res://src/construction/room_topology.gd")
const Localized := preload("res://src/localization/localized_text.gd")

# Derived feedback only. Never call find_meal here: it can reserve a seat/portion.
static func describe(sim, id: String) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(id,{})
	if npc.is_empty() or not bool(npc.get("active",false)) or sim.npc_catalog.get_definition(id).is_empty():
		return {}
	var home: Dictionary = sim.housing.home(sim,id)
	var dining: Dictionary = sim.furniture.find_seat(sim,id,true)
	var rows: Array[Dictionary] = [_sleep(sim,home),_food(sim,npc),_dining(sim,id,dining),_light(sim,id)]
	return {"home":home,"rows":rows}

static func _row(id: String, status: String, severity: String, hint: String = "", args: Dictionary = {}) -> Dictionary:
	return {"id":id,"status":status,"severity":severity,"text_key":"household." + id + "." + status,
		"hint_key":"" if hint.is_empty() else "household.hint." + hint,"hint_args":args}

static func _sleep(sim, home: Dictionary) -> Dictionary:
	if String(home.place_id).is_empty():
		return _row("sleep","unassigned","problem","assign")
	if String(home.building_id).is_empty():
		return _row("sleep","missing","problem","replace")
	if not bool(home.valid):
		match String(home.reason_key):
			"housing.failure.path": return _row("sleep","blocked","problem","sleep_path")
			"housing.failure.obstructed": return _row("sleep","obstructed","problem","sleep_obstructed")
		return _room_problem(sim,home)
	if not bool(home.covered):
		return _row("sleep","poor_roof","problem","roof")
	return _row("sleep","ready","good")

static func _room_problem(sim, home: Dictionary) -> Dictionary:
	var cell := Vector2i(int(home.cell[0]),int(home.cell[1]))
	var cells: Array[Vector2i] = Topology.find_room_at(cell,sim.state.structures,sim.building_catalog,Content.MAP_SIZE)
	if cells.is_empty():
		return _row("sleep","room_open","problem","room_close")
	var validation := Topology.validate(Topology.LIVING_ROOM_ID,cells,sim.state.structures,sim.building_catalog)
	if String(validation.reason_id) in ["core:room_too_small","core:room_too_large"]:
		var limits: Vector2i = Topology.ROOM_LIMITS[Topology.LIVING_ROOM_ID]
		return _row("sleep","room_size","problem","room_size",{"min":limits.x,"max":limits.y})
	if String(validation.reason_id) == "core:room_missing_requirements":
		var inside: Dictionary = {}
		for part: Vector2i in cells:
			inside[part] = true
		var roles: Dictionary = {}
		for structure: Dictionary in sim.state.structures:
			var bid := String(structure.building_id)
			var origin := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
			var full := true
			for part: Vector2i in sim.building_catalog.get_footprint_cells(bid,origin):
				full = full and inside.has(part)
			if full:
				roles[String(sim.building_catalog.get_definition(bid).get("room_role",""))] = true
		var missing: Array[String] = []
		for role: String in Topology.REQUIRED_ROLES:
			if not roles.has(role):
				missing.append("household.room_role." + role)
		return _row("sleep","room_furniture","problem","room_furniture",{"items":Localized.text_reference_list(missing)})
	return _row("sleep","room","problem","room_define")

static func _food(sim, npc: Dictionary) -> Dictionary:
	for item: String in npc.personal_inventory:
		if int(npc.personal_inventory[item]) > 0 and not sim.needs.food_profile(item,sim.content).is_empty():
			return _row("food","carrying" if not npc.get("meal_trip",{}).is_empty() else "personal","good")
	var source: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO))
	var blocker: Vector2i = sim._world_position_to_cell(sim.get_player_position())
	var has_food := false
	for stored: Dictionary in sim.state.storage_items:
		if int(stored.amount) <= 0 or sim.needs.food_profile(String(stored.item_id),sim.content).is_empty():
			continue
		has_food = true
		var cell := Vector2i(int(stored.cell[0]),int(stored.cell[1]))
		if sim.npc_autonomy.find_construction_work_cell(cell,source,blocker) != sim.npc_autonomy.INVALID_CELL:
			return _row("food","storage","good")
	return _row("food","blocked","problem","food_path") if has_food else _row("food","missing","problem","food")

static func _dining(sim, id: String, chosen: Dictionary) -> Dictionary:
	if not chosen.is_empty():
		return _row("dining","ready","good")
	var seats: Array[Dictionary] = sim.furniture.dining_seats(sim)
	if seats.is_empty():
		return _row("dining","missing","improvement","table")
	var source: Vector2 = sim.get_npc_position(id,Vector2.ZERO)
	var nearby := 0
	var busy := 0
	for seat: Dictionary in seats:
		var chair := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
		# Same distance horizon as actual selection, measured at the approach.
		var occupied: String = sim.furniture.owner(sim,seat.chair_cell)
		var target: Vector2i = sim.furniture.approach(sim,id,seat)
		var distance := source.distance_to(Content.cell_center(chair.x,chair.y)) if target == sim.furniture.INVALID else source.distance_to(Content.cell_center(target.x,target.y))
		if distance > sim.furniture.MAX_SEAT_DISTANCE:
			continue
		nearby += 1
		if not occupied.is_empty() and occupied != id:
			busy += 1
	if nearby == 0:
		return _row("dining","far","improvement","table_near")
	if busy == nearby:
		return _row("dining","busy","improvement","seat_free")
	return _row("dining","blocked","improvement","table_path")

static func _light(sim, id: String) -> Dictionary:
	# Probe the same choice with evening light, without changing the world clock.
	var seat: Dictionary = sim.furniture.find_seat(sim,id,true,sim.furniture.INVALID,true)
	if seat.is_empty():
		seat = sim.furniture.find_seat(sim,id,false,sim.furniture.INVALID,true)
	if seat.is_empty():
		return _row("light","no_place","improvement","light_place")
	var cell := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
	return _row("light","ready","good") if sim.furniture.lighting.has_artificial_light(sim,cell) else _row("light","dark","improvement","light")
