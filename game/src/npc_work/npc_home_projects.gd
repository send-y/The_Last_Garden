extends RefCounted

const Layout := preload("res://src/npc_work/home_furnishing_layout.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Command := preload("res://src/construction/construction_command.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const HomeStock := preload("res://src/npc_work/home_project_stock.gd")
const Production := preload("res://src/npc_work/npc_home_production.gd")
const INVALID := Vector2i(-1,-1)
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

static func normalize(npc: Dictionary) -> void:
	npc.home_goal = clean_goal(npc.get("home_goal",{}))
	npc.home_expansion = clean_expansion(npc.get("home_expansion",{}))
	var results: Array[Dictionary] = []
	var raw: Variant = npc.get("home_goals_completed",[])
	if raw is Array:
		for result: Variant in raw:
			var clean := clean_goal(result)
			if not clean.is_empty() and String(clean.status) == "done": results.append(clean)
	npc.home_goals_completed = results.slice(maxi(0,results.size()-4))
	raw = npc.get("home_goals_declined",[])
	npc.home_goals_declined = []
	if raw is Array:
		for key: Variant in raw:
			if key is String and key.length() < 120 and not npc.home_goals_declined.has(key): npc.home_goals_declined.append(key)
	npc.next_home_goal_minute = preload("res://src/npc_work/npc_work_state.gd").number(npc.get("next_home_goal_minute",0))

static func clean_goal(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not Layout.ALLOWED.has(String(raw.get("building_id",""))): return {}
	var cell: Variant = raw.get("cell",[])
	if not cell is Array or cell.size() != 2: return {}
	for value: Variant in cell:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) >= 128: return {}
	var status := String(raw.get("status","pending"))
	if not ["pending","done","declined"].has(status): status = "pending"
	return {"building_id":String(raw.building_id),"cell":[int(cell[0]),int(cell[1])],"room_id":String(raw.get("room_id","")),"place_id":String(raw.get("place_id","")),"tracked":bool(raw.get("tracked",raw.get("placed",false))),
		"status":status,"placed":bool(raw.get("placed",false)),"action": "light" if String(raw.get("action","")) == "light" else "build",
		"reason_key":"npc.goal.reason." + String(raw.building_id).trim_prefix("core:"),
		"project_id":raw.get("project_id", "") if raw.get("project_id", "") is String else "",
		"created_minute":preload("res://src/npc_work/npc_work_state.gd").number(raw.get("created_minute",0))}

static func key(goal: Dictionary) -> String:
	return String(goal.room_id) + "|" + String(goal.building_id)

static func clean_expansion(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	if not raw.get("building_id", "") is String or not raw.get("room_id", "") is String: return {}
	if not Layout.ALLOWED.has(raw.get("building_id", "")): return {}
	var room_id := String(raw.get("room_id", ""))
	if not room_id.begins_with("core:") or room_id.length() > 128: return {}
	var building_id := String(raw.building_id)
	return {"room_id":room_id,"building_id":building_id,
		"reason_key":"npc.home.expansion.chair" if building_id == "core:chair" else "npc.home.expansion.space",
		"created_minute":preload("res://src/npc_work/npc_work_state.gd").number(raw.get("created_minute",0))}

static func missing(sim, npc: Dictionary, goal: Dictionary) -> Dictionary:
	return HomeStock.report(sim,npc,goal).missing

static func status(sim, id: String) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(id,{})
	if npc.is_empty() or not sim.npc_catalog.has_definition(id): return {}
	var goal: Dictionary = npc.home_goal
	var state := "idle"
	var lacks: Dictionary = {}
	var protected: Dictionary = {}
	var production: Dictionary = {}
	var policy: Dictionary = sim.HomePolicy.for_character(sim,id)
	var expansion: Dictionary = npc.get("home_expansion",{}).duplicate(true)
	if String(expansion.get("room_id","")) != String(policy.room_id) or String(policy.mode) not in ["personal","shared"]:
		expansion = {}
	if not bool(npc.get("known",false)): state = "unknown"
	elif not bool(npc.get("active",false)): state = "inactive"
	elif not bool(npc.work_options.build): state = "permission"
	elif String(policy.mode) == "settlement": state = "communal"
	elif Layout.territory(sim,npc).is_empty(): state = "home"
	elif not bool(policy.may_furnish): state = "home"
	elif not goal.is_empty():
		state = String(goal.status)
		if state == "pending":
			var materials := HomeStock.report(sim,npc,goal)
			lacks = materials.missing
			protected = materials.protected
			production = Production.report(sim,npc,lacks)
			if float(npc.needs.hunger) <= 55 or float(npc.needs.energy) < 30 or float(npc.needs.restedness) < 25: state = "needs"
			elif not npc.work_commitment.is_empty(): state = "request"
			elif sim.get_minute_of_day() < 9*60 or sim.get_minute_of_day() >= 19*60: state = "later"
			elif String(production.get("reason","")) == "working": state = "producing"
			elif not lacks.is_empty(): state = "reserve" if not protected.is_empty() else "materials"
			elif not npc.initiative_job.is_empty() and npc.initiative_job.get("cell",[]) == goal.cell: state = "working"
			elif String(goal.action) == "build" and not Layout.can_place(sim,npc,String(goal.building_id),Vector2i(int(goal.cell[0]),int(goal.cell[1])),goal.cell): state = "space"
			elif String(goal.action) == "light" and matching_structure(sim,goal).is_empty(): state = "space"
	if state in ["idle", "done", "declined"] and not expansion.is_empty(): state = "expansion"
	return {"goal":goal.duplicate(true),"status":state,"missing":lacks,"protected":protected,"production":production,"housing":policy,
		"expansion":expansion,"completed":npc.home_goals_completed.duplicate(true),"declined":npc.home_goals_declined.duplicate()}

static func choose(sim, npc: Dictionary) -> Dictionary:
	var span := Diagnostic.begin("home_project.choose") if Diagnostic.enabled else 0
	var result := _choose(sim,npc)
	Diagnostic.end(span)
	return result

static func _choose(sim, npc: Dictionary) -> Dictionary:
	if String(npc.get("residency","resident")) == "visitor": return {}
	var room := Layout.territory(sim,npc)
	if room.is_empty(): return {}
	if not sim.HomePolicy.may_furnish(sim,npc,String(room.id)): return {}
	var furnishings: Array[Dictionary] = Layout.furnishings(sim,room,false,false)
	var planned: Array[Dictionary] = Layout.furnishings(sim,room,true,false)
	var has_table := false
	var chair_count := 0
	var has_light := false
	var off_torch: Dictionary = {}
	for entity: Dictionary in furnishings:
		match String(entity.building_id):
			"core:table": has_table = true
			"core:torch":
				has_light = has_light or bool(entity.get("lit",true))
				if not bool(entity.get("lit",true)): off_torch = entity
	for seat: Dictionary in sim.furniture.dining_seats(sim):
		if room.cells.has(Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))): chair_count += 1
	var policy: Dictionary = sim.HomePolicy.for_character(sim,String(npc.id))
	var wanted_chairs := maxi(1,policy.members.size())
	var wanted: Array[String] = []
	if not has_table: wanted.append("core:table")
	elif chair_count < wanted_chairs: wanted.append("core:chair")
	if not has_light: wanted.append("core:torch")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("home:%s:%s:%s" % [sim.state.seed,npc.id,npc.initiative_choice_index])
	var preferences := preload("res://src/characters/npc_preferences.gd")
	var profile: Dictionary = sim.state.get("npc_profiles",{}).get(String(npc.id),{})
	if profile.is_empty():
		# Keep the established authored NPC's seeded choice and existing-project behavior.
		if wanted.size() > 1 and rng.randi_range(0,1) == 1: wanted.reverse()
	else:
		var ranking: Dictionary = {}
		for building: String in wanted:
			ranking[building] = preferences.score(profile,{"kind":"build","building_id":building},{}) * rng.randf()
		wanted.sort_custom(func(a: String,b: String) -> bool: return float(ranking[a]) > float(ranking[b]))
	var blocked_building := ""
	for building: String in wanted:
		var candidate := {"building_id":building,"room_id":String(room.id)}
		if npc.home_goals_declined.has(key(candidate)): continue
		var reserved := false
		for other: Dictionary in sim.state.npcs.values():
			var other_goal: Dictionary = other.get("home_goal",{})
			if String(other.get("id","")) != String(npc.id) and sim.npc_catalog.has_definition(String(other.get("id",""))) and bool(other.get("active",false)) and not other_goal.is_empty() and String(other_goal.status) == "pending" and key(other_goal) == key(candidate): reserved = true
		if reserved: continue
		var cell := INVALID
		var placed := false
		var tracked := false
		var action := "build"
		if building == "core:torch" and not off_torch.is_empty():
			cell = Vector2i(int(off_torch.cell[0]),int(off_torch.cell[1]))
			action = "light"
		else:
			for blueprint: Dictionary in planned:
				if String(blueprint.building_id) == building:
					cell = Vector2i(int(blueprint.cell[0]),int(blueprint.cell[1]))
					tracked = true
					break
			if cell == INVALID: cell = Layout.choose_cell(sim,npc,building,rng)
			if cell == INVALID and blocked_building.is_empty():
				# A person standing in the proposed spot or doorway is not a small house.
				var probe_rng := RandomNumberGenerator.new()
				probe_rng.seed = rng.seed
				if Layout.choose_cell(sim,npc,building,probe_rng,true) == INVALID:
					blocked_building = building
		if cell == INVALID or Supply.work_cell(sim,npc,cell) == INVALID: continue
		npc.initiative_choice_index = int(npc.initiative_choice_index) + 1
		npc.home_expansion = {}
		return clean_goal({"building_id":building,"room_id":String(room.id),"place_id":String(room.home.place_id),"cell":[cell.x,cell.y],"placed":placed,"tracked":tracked,"action":action,"created_minute":sim.get_elapsed_game_minutes()})
	if not blocked_building.is_empty():
		request_expansion(sim,npc,String(room.id),blocked_building)
	else:
		npc.home_expansion = {}
	return {}

static func request_expansion(sim, npc: Dictionary, room_id: String, building_id: String) -> void:
	var previous: Dictionary = npc.get("home_expansion",{})
	if String(previous.get("room_id","")) == room_id and String(previous.get("building_id","")) == building_id: return
	npc.home_expansion = clean_expansion({"room_id":room_id,"building_id":building_id,"created_minute":sim.get_elapsed_game_minutes()})
	sim._emit_result(true,"npc.home.expansion.requested",true,false,{"name":Localized.text_reference(sim.npc_catalog.get_label_key(sim.state.npcs,String(npc.id),"npc.generic.traveler.name")),
		"item":Localized.text_reference(sim.building_catalog.get_definition(building_id).label_key)},false)

static func refresh_authority(sim, npc: Dictionary) -> void:
	var goal: Dictionary = npc.get("home_goal",{})
	var policy: Dictionary = sim.HomePolicy.for_character(sim,String(npc.id))
	var expansion: Dictionary = npc.get("home_expansion",{})
	if not expansion.is_empty() and (String(expansion.room_id) != String(policy.room_id) or String(policy.mode) == "settlement"):
		npc.home_expansion = {}
	if goal.is_empty() or String(goal.status) != "pending": return
	if String(sim.state.sleep_assignments.get(String(npc.id),"")) != String(goal.place_id) or String(policy.room_id) != String(goal.room_id):
		# Rehousing abandons our own blueprint but never cancels a player's adopted plan.
		if owns_blueprint(sim, goal):
			sim.execute_construction_command(Command.cancel_blueprint(Vector2i(int(goal.cell[0]),int(goal.cell[1]))))
		if npc.initiative_job.get("cell",[]) == goal.cell: sim.NpcPracticalWork.cancel(npc)
		npc.home_goal = {}
		npc.next_home_goal_minute = 0
	elif not bool(policy.may_furnish) and npc.initiative_job.get("cell",[]) == goal.cell:
		sim.NpcPracticalWork.cancel(npc)

static func matching_structure(sim, goal: Dictionary) -> Dictionary:
	var cell: Array = goal.get("cell",[])
	if cell.size() != 2: return {}
	for structure: Dictionary in sim.structure_index.at(Vector2i(int(cell[0]),int(cell[1]))):
		if structure.cell == goal.cell and String(structure.building_id) == String(goal.building_id): return structure
	return {}

static func owns_blueprint(sim, goal: Dictionary) -> bool:
	var project_id := String(goal.get("project_id", ""))
	if not bool(goal.get("placed", false)) or project_id.is_empty(): return false
	var blueprint: Dictionary = sim._find_blueprint(goal.cell)
	return String(blueprint.get("building_id", "")) == String(goal.building_id) and String(blueprint.get("home_project_id", "")) == project_id

static func observe(sim, npc: Dictionary) -> void:
	var goal: Dictionary = npc.home_goal
	var now: int = sim.get_elapsed_game_minutes()
	if not goal.is_empty() and String(goal.status) == "pending":
		var structure: Dictionary = matching_structure(sim,goal)
		if not structure.is_empty() and String(structure.building_id) == String(goal.building_id) and (String(goal.action) != "light" or bool(structure.get("lit",true))):
			goal.status = "done"
			npc.home_goals_completed.append(goal.duplicate(true))
			if npc.home_goals_completed.size() > 4: npc.home_goals_completed.pop_front()
			npc.next_home_goal_minute = now + 60
			sim._emit_result(true,"npc.goal.finished",true,false,{"name":Localized.text_reference(sim.npc_catalog.get_label_key(sim.state.npcs,String(npc.id),"npc.generic.traveler.name")),"item":Localized.text_reference(sim.building_catalog.get_definition(String(goal.building_id)).label_key)},false)
		elif bool(goal.tracked) and String(sim._find_blueprint(goal.cell).get("building_id","")) != String(goal.building_id):
			decline(sim,npc,false)

# Returns a physical job for the existing worker, preserving the higher-level goal.
static func prepare(sim, npc: Dictionary) -> Dictionary:
	var span := Diagnostic.begin("home_project.prepare") if Diagnostic.enabled else 0
	var result := _prepare(sim,npc)
	Diagnostic.end(span)
	return result

static func _prepare(sim, npc: Dictionary) -> Dictionary:
	refresh_authority(sim,npc)
	observe(sim,npc)
	var goal: Dictionary = npc.home_goal
	var now: int = sim.get_elapsed_game_minutes()
	if not npc.initiative_job.is_empty(): return {}
	if not goal.is_empty() and String(goal.status) == "pending" and not String(goal.place_id).is_empty() and String(sim.state.sleep_assignments.get(String(npc.id),"")) != String(goal.place_id):
		decline(sim,npc,false)
	if (goal.is_empty() or String(goal.status) != "pending") and now >= int(npc.next_home_goal_minute):
		npc.home_goal = choose(sim,npc)
		goal = npc.home_goal
		npc.next_home_goal_minute = now + 30
		if not goal.is_empty(): sim._emit_result(true,"npc.goal.chosen",true,false,{"name":Localized.text_reference(sim.npc_catalog.get_label_key(sim.state.npcs,String(npc.id),"npc.generic.traveler.name")),"item":Localized.text_reference(sim.building_catalog.get_definition(String(goal.building_id)).label_key)},false)
	if goal.is_empty() or String(goal.status) != "pending": return {}
	var current_status := status(sim,String(npc.id))
	var production_job: Dictionary = {}
	if String(current_status.status) in ["materials", "reserve", "producing"]:
		production_job = Production.choose(sim,npc,current_status.missing)
	if String(current_status.status) not in ["pending","working"] and production_job.is_empty(): return {}
	var cell := Vector2i(int(goal.cell[0]),int(goal.cell[1]))
	if String(goal.action) == "light": return {"kind":"build","phase":"switch_on","cell":goal.cell.duplicate(),"drops":[]}
	var blueprint: Dictionary = sim._find_blueprint(goal.cell)
	if blueprint.is_empty():
		var command := {"actor_id":String(npc.id),"action_id":Command.ACTION_PLACE_BLUEPRINT,"building_id":String(goal.building_id),"cell":goal.cell.duplicate()}
		if not sim.execute_construction_command(command).success: return {}
		goal.placed = true
		goal.tracked = true
		blueprint = sim._find_blueprint(goal.cell)
		goal.project_id = "%s:%s:%s" % [npc.id, npc.initiative_choice_index, sim.get_elapsed_game_minutes()]
		blueprint.home_project_id = goal.project_id
	if not production_job.is_empty(): return production_job
	return {"kind":"build","phase":"build" if sim._blueprint_has_all_materials(blueprint) else "take_materials","cell":[cell.x,cell.y],"drops":[]}

static func decline(sim, npc: Dictionary, cancel_blueprint: bool = true) -> void:
	var goal: Dictionary = npc.home_goal
	if goal.is_empty(): return
	if not npc.home_goals_declined.has(key(goal)): npc.home_goals_declined.append(key(goal))
	goal.status = "declined"
	if cancel_blueprint and owns_blueprint(sim, goal):
		sim.execute_construction_command(Command.cancel_blueprint(Vector2i(int(goal.cell[0]),int(goal.cell[1]))))
	if npc.initiative_job.get("cell",[]) == goal.cell: sim.NpcPracticalWork.cancel(npc)
	npc.next_home_goal_minute = sim.get_elapsed_game_minutes() + 60

static func defer(sim, id: String, resume: bool = false) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(id,{})
	if npc.is_empty() or sim.npc_catalog.get_definition(id).is_empty() or not bool(npc.get("active",false)) or not bool(npc.get("known",false)): return {"success":false}
	if resume:
		npc.home_goals_declined = []
		if not npc.home_goal.is_empty() and String(npc.home_goal.status) == "declined": npc.home_goal = {}
		npc.next_home_goal_minute = 0
	else:
		if npc.home_goal.is_empty() or String(npc.home_goal.status) != "pending": return {"success":false}
		decline(sim,npc)
	sim.event_emitted.emit({"type":"state_changed"})
	return {"success":true}

static func can_place_command(sim, command: Dictionary) -> bool:
	var id := String(command.get("actor_id",""))
	var npc: Dictionary = sim.state.npcs.get(id,{})
	if npc.is_empty() or sim.npc_catalog.get_definition(id).is_empty() or not bool(npc.get("active",false)) or not bool(npc.get("known",false)) or not bool(npc.work_options.build): return false
	var goal: Dictionary = npc.home_goal
	if goal.is_empty() or String(goal.status) != "pending" or String(goal.action) != "build" or command.get("cell",[]) != goal.cell or String(command.get("building_id","")) != String(goal.building_id): return false
	return Layout.can_place(sim,npc,String(goal.building_id),Vector2i(int(goal.cell[0]),int(goal.cell[1])))

static func safe_to_build(sim, blueprint: Dictionary) -> bool:
	if not HomeStock.can_work(sim,blueprint.cell): return false
	for npc: Dictionary in sim.state.npcs.values():
		if sim.npc_catalog.get_definition(String(npc.get("id",""))).is_empty(): continue
		var goal: Dictionary = npc.get("home_goal",{})
		if goal.is_empty() or String(goal.status) != "pending" or goal.cell != blueprint.cell or String(goal.building_id) != String(blueprint.building_id): continue
		return Layout.can_place(sim,npc,String(goal.building_id),Vector2i(int(goal.cell[0]),int(goal.cell[1])),goal.cell)
	return true
