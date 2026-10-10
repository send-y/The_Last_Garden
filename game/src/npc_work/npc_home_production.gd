extends RefCounted

const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const RECIPE := "core:saw_planks"
const PHASES := ["craft_take", "craft"]

static func authorized(sim, npc: Dictionary) -> bool:
	var goal: Dictionary = npc.get("home_goal", {})
	return bool(npc.get("active", false)) and bool(npc.get("known", false)) and bool(npc.get("work_options", {}).get("build", false)) and not goal.is_empty() and String(goal.status) == "pending" and String(goal.action) == "build" and sim.HomePolicy.may_furnish(sim,npc,String(goal.room_id)) and matches_goal_blueprint(sim,goal)

static func matches_goal_blueprint(sim, goal: Dictionary) -> bool:
	if not bool(goal.get("tracked",false)): return true
	if bool(goal.get("placed",false)): return sim.NpcHomeProjects.owns_blueprint(sim,goal)
	# A resident may also supply an existing player blueprint in its own home.
	var blueprint: Dictionary = sim._find_blueprint(goal.cell)
	return String(blueprint.get("building_id","")) == String(goal.building_id)

static func release_invalid_projects(sim) -> void:
	for project: Dictionary in sim.state.crafting_projects:
		var id := String(project.get("owner_id", ""))
		if id.is_empty(): continue
		var npc: Dictionary = sim.state.npcs.get(id, {})
		if npc.is_empty() or not authorized(sim,npc) or npc.home_goal.cell != project.get("home_cell", []):
			# Keep the paid inputs and progress as a normal unfinished player project.
			project.erase("owner_id")
			project.erase("home_cell")

static func own_project(sim, npc: Dictionary) -> Dictionary:
	for project: Dictionary in sim.state.crafting_projects:
		if String(project.get("owner_id", "")) == String(npc.id) and project.get("home_cell", []) == npc.home_goal.get("cell", []) and String(project.recipe_id) == RECIPE:
			return project
	return {}

static func station_free(sim, npc: Dictionary, cell: Array) -> bool:
	var project: Dictionary = sim._find_crafting_project(cell)
	if not project.is_empty():
		return String(project.get("owner_id", "")) == String(npc.id) and project.get("home_cell", []) == npc.home_goal.get("cell", []) and String(project.recipe_id) == RECIPE
	for other: Dictionary in sim.state.npcs.values():
		var job: Dictionary = other.get("initiative_job", {})
		if String(other.get("id", "")) != String(npc.id) and authorized(sim,other) and PHASES.has(String(job.get("phase", ""))) and job.get("station_cell", []) == cell and job.get("cell",[]) == other.home_goal.cell:
			return false
	return true

static func find_station(sim, npc: Dictionary) -> Dictionary:
	var owned := own_project(sim,npc)
	var busy := false
	for structure: Dictionary in sim.state.structures:
		if String(sim.building_catalog.get_definition(String(structure.building_id)).get("station_type", "")) != "core:workbench": continue
		var cell: Array = structure.cell
		if Supply.work_cell(sim,npc,Vector2i(int(cell[0]),int(cell[1]))) == Vector2i(-1,-1): continue
		if not owned.is_empty() and owned.cell != cell: continue
		if station_free(sim,npc,cell): return {"cell":cell.duplicate(),"reason":"ready"}
		busy = true
	return {"reason":"busy" if busy else "station"}

static func report(sim, npc: Dictionary, missing: Dictionary) -> Dictionary:
	if not authorized(sim,npc): return {}
	var project := own_project(sim,npc)
	var job: Dictionary = npc.initiative_job
	if not project.is_empty() or PHASES.has(String(job.get("phase", ""))):
		return {"reason":"working", "current":int(project.get("work_progress_minutes",0)), "total":sim.crafting_catalog.get_work_minutes(RECIPE), "station_cell":project.get("cell",job.get("station_cell",[])).duplicate()}
	if int(missing.get("core:plank",0)) <= 0: return {}
	var station := find_station(sim,npc)
	if not station.has("cell"): return station
	var needed: int = int(sim.crafting_catalog.get_inputs(RECIPE).get("core:wood",0)) - int(npc.work_cargo.get("core:wood",0))
	if needed > sim.StockReserves.available(sim,"core:wood"):
		return {"reason":"wood_reserve" if sim.StockReserves.total(sim,"core:wood") >= needed else "wood", "amount":maxi(0,needed-sim.StockReserves.available(sim,"core:wood"))}
	if needed > 0 and Supply.find_stock(sim,npc,"core:wood").is_empty(): return {"reason":"wood", "amount":needed}
	return station

static func choose(sim, npc: Dictionary, missing: Dictionary) -> Dictionary:
	var readiness := report(sim,npc,missing)
	if readiness.is_empty() or readiness.reason not in ["ready","working"]: return {}
	var project := own_project(sim,npc)
	var station := find_station(sim,npc)
	if not station.has("cell"): return {}
	return {"kind":"build", "phase":"craft" if not project.is_empty() else "craft_take", "cell":npc.home_goal.cell.duplicate(), "station_cell":station.cell, "recipe_id":RECIPE, "drops":[]}

static func context(sim, npc: Dictionary) -> Dictionary:
	var job: Dictionary = npc.initiative_job
	var station: Array = job.get("station_cell", [])
	if not authorized(sim,npc) or station.size() != 2 or not station_free(sim,npc,station): return {}
	var structure: Dictionary = sim._find_structure(station)
	if String(structure.get("building_id","")) != "core:workbench": return {}
	if String(job.phase) == "craft_take":
		var needed: int = int(sim.crafting_catalog.get_inputs(RECIPE).get("core:wood",0)) - int(npc.work_cargo.get("core:wood",0))
		if needed <= 0:
			job.phase = "craft"
			return context(sim,npc)
		if needed > sim.StockReserves.available(sim,"core:wood"): return {}
		var source := Supply.find_stock(sim,npc,"core:wood")
		if source.is_empty(): return {}
		source.missing = needed
		source.travel_activity = "core:work_travel"
		source.arrival_activity = "core:work_craft_take"
		return source
	var target := Supply.work_cell(sim,npc,Vector2i(int(station[0]),int(station[1])))
	if target == Vector2i(-1,-1): return {}
	return {"target_cell":[target.x,target.y], "travel_activity":"core:work_travel", "arrival_activity":"core:work_craft"}

static func fulfil(sim, npc: Dictionary, context_data: Dictionary) -> bool:
	if not authorized(sim,npc): return false
	var job: Dictionary = npc.initiative_job
	if String(job.phase) == "craft_take":
		if not station_free(sim,npc,job.station_cell) or not Supply.take_material(sim,npc,context_data,int(context_data.missing)): return false
		if int(npc.work_cargo.get("core:wood",0)) >= int(sim.crafting_catalog.get_inputs(RECIPE)["core:wood"]): job.phase = "craft"
		return true
	var result: Dictionary = sim.CraftingSystem.work_npc_project(sim,npc,job.station_cell,RECIPE)
	if not bool(result.get("success",false)): return false
	if String(result.reason_id) == "core:crafting_completed": job.phase = "deliver"
	return true
