extends RefCounted
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Planner := preload("res://src/npc_work/npc_work_planner.gd")

# Continue the same useful activity with the same owned tool, not a new borrow trip.
static func next_target(sim, npc: Dictionary) -> bool:
	var job: Dictionary = npc.initiative_job
	var was_borrowing := String(job.get("phase","")) == "borrow"
	var kind := String(job.get("kind",""))
	if not bool(npc.work_options.get(kind,false)): return false
	var candidates: Array[Dictionary] = []
	if kind == "harvest":
		var crop: Dictionary = preload("res://src/npc_work/npc_crop_harvest.gd").choose(sim,npc)
		if crop.is_empty(): return false
		job.cell = crop.cell; job.crop_id = crop.crop_id; job.planting_id = crop.planting_id
		job.phase = "work"; job.drops = []
		return true
	if kind == "water":
		for bed: Dictionary in sim.get_farm_beds():
			if String(bed.crop_id).is_empty() or int(bed.wet_until) > sim.get_elapsed_game_minutes() or Planner.reserved(sim,npc,"water",bed.cell): continue
			candidates.append({"cell":bed.cell.duplicate()})
	elif kind == "gather":
		var item := String(job.get("resource_item",""))
		if Supply.cargo_size(npc) >= Supply.CARRY_LIMIT or Planner.stock(sim,item) >= int(Planner.STOCK_TARGETS.get(item,0)): return false
		var nodes: Array = sim.get_surface_trees() if item == "core:wood" else sim.get_surface_boulders()
		for target: Dictionary in nodes:
			if sim.is_collected(String(target.id)) or String(target.get("presentation_id","")) == "surface_stump" or Planner.reserved(sim,npc,"gather",String(target.id)): continue
			var cell: Vector2i = sim._world_position_to_cell(target.position)
			candidates.append({"cell":[cell.x,cell.y],"target_id":String(target.id)})
	elif kind == "build":
		for blueprint: Dictionary in sim.state.blueprints:
			if not Supply.HomeStock.can_work(sim,blueprint.cell) or Planner.reserved(sim,npc,"build",blueprint.cell): continue
			var ready: bool = sim._blueprint_has_all_materials(blueprint)
			if ready or not Planner.material_source(sim,npc,blueprint).is_empty():
				candidates.append({"cell":blueprint.cell.duplicate(),"phase":"build" if ready else "take_materials"})
	else: return false
	var position: Vector2 = sim.get_npc_position(String(npc.id),Vector2.ZERO)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return position.distance_squared_to(sim.content.cell_center(int(a.cell[0]),int(a.cell[1]))) < position.distance_squared_to(sim.content.cell_center(int(b.cell[0]),int(b.cell[1])))
	)
	var examined := 0
	for candidate: Dictionary in candidates:
		examined += 1
		if examined > 8: break
		var cell := Vector2i(int(candidate.cell[0]),int(candidate.cell[1]))
		var work_cell: Vector2i = Supply.build_work_cell(sim,npc,cell) if kind == "build" else Supply.work_cell(sim,npc,cell)
		if work_cell == Vector2i(-1,-1): continue
		job.cell = candidate.cell
		if candidate.has("target_id"): job.target_id = candidate.target_id
		job.phase = candidate.get("phase","work")
		job.drops = []
		if kind == "water" and not was_borrowing and int(Supply.tool(sim,npc).get("state",{}).get("charges",0)) <= 0:
			job.water_cell = Supply.find_water(sim,npc)
			if job.water_cell.is_empty(): return false
			job.phase = "refill"
		if was_borrowing: job.phase = "borrow"
		return true
	return false

static func target_available(sim, job: Dictionary) -> bool:
	if String(job.kind) == "water":
		for bed: Dictionary in sim.get_farm_beds():
			if bed.cell == job.cell: return not String(bed.crop_id).is_empty() and int(bed.wet_until) <= sim.get_elapsed_game_minutes()
		return false
	if String(job.kind) == "gather":
		var id := String(job.get("target_id",""))
		var target: Dictionary = sim._resolve_interaction_target(id)
		return not target.is_empty() and not sim.is_collected(id) and String(target.get("presentation_id","")) != "surface_stump"
	return true
