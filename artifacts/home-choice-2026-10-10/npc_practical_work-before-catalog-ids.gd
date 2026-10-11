extends RefCounted

const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Planner := preload("res://src/npc_work/npc_work_planner.gd")
const Water := preload("res://src/world/water_map.gd")
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
const INVALID := Vector2i(-1, -1)

static func set_enabled(sim, npc_id: String, kind: String, enabled: bool) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(npc_id, {})
	if npc.is_empty() or not bool(npc.get("active", false)) or not bool(npc.get("known", false)) or not ["water", "gather", "build"].has(kind):
		return {"success": false}
	npc.work_options[kind] = enabled
	npc.next_initiative_minute = 0
	if not enabled and String(npc.initiative_job.get("kind", "")) == kind:
		cancel(npc)
	sim.event_emitted.emit({"type": "state_changed"})
	return {"success": true}

static func status(sim, npc_id: String) -> Dictionary:
	var npc: Dictionary = sim.state.npcs.get(npc_id, {})
	if npc.is_empty():
		return {}
	return {"options": npc.work_options.duplicate(), "job": npc.initiative_job.duplicate(true),
		"cargo": npc.work_cargo.duplicate(), "tool_instance_id": String(npc.carried_instance_id)}

static func cancel(npc: Dictionary) -> void:
	if not String(npc.carried_instance_id).is_empty() or not npc.work_cargo.is_empty():
		npc.initiative_job = {"kind": String(npc.initiative_job.get("kind", "gather")), "phase": "return", "cell": [0, 0], "drops": []}
	else:
		npc.initiative_job = {}

static func prepare(sim) -> Dictionary:
	var contexts: Dictionary = {}
	sim.work_queries.prune_inactive(sim)
	sim.NpcHomeProjects.Production.release_invalid_projects(sim)
	for definition: Dictionary in sim.npc_catalog.get_definitions():
		var npc: Dictionary = sim.state.npcs.get(String(definition.id), {})
		if npc.is_empty() or not bool(npc.active) or not bool(npc.known):
			continue
		var span := Diagnostic.begin("npc_work.authority") if Diagnostic.enabled else 0
		sim.NpcHomeProjects.refresh_authority(sim,npc)
		Diagnostic.end(span)
		var job: Dictionary = npc.initiative_job
		var urgent_need: bool = float(npc.needs.hunger) <= 55 or float(npc.needs.energy) <= 18 or sim.get_minute_of_day() >= 21 * 60 or sim.get_minute_of_day() < 7 * 60
		if urgent_need and (not job.is_empty() or not String(npc.carried_instance_id).is_empty() or not npc.work_cargo.is_empty()):
			# Needs interrupt work without trapping communal supplies on a hungry resident.
			for zone: Dictionary in sim.state.storage_zones:
				for value: Array in zone.cells:
					Supply.deposit_at(sim, npc, Vector2i(int(value[0]), int(value[1])))
			Supply.drop_remaining(sim, npc)
			finish(sim, npc)
			continue
		if not job.is_empty() and String(job.phase) != "return" and not bool(npc.work_options.get(String(job.kind), false)):
			cancel(npc)
			job = npc.initiative_job
		if job.is_empty() and (not String(npc.carried_instance_id).is_empty() or not npc.work_cargo.is_empty()):
			cancel(npc)
			job = npc.initiative_job
		if job.is_empty():
			var minute: int = sim.get_minute_of_day()
			if sim.get_elapsed_game_minutes() < int(npc.next_initiative_minute) or minute < 9 * 60 or minute >= 19 * 60 or float(npc.needs.hunger) <= 55 or float(npc.needs.energy) < 30 or float(npc.needs.restedness) < 25 or not npc.work_commitment.is_empty():
				continue
			span = Diagnostic.begin("npc_work.choose") if Diagnostic.enabled else 0
			npc.initiative_job = sim.NpcHomeProjects.prepare(sim,npc) if bool(npc.work_options.build) else {}
			if npc.initiative_job.is_empty(): npc.initiative_job = Planner.choose(sim, npc)
			Diagnostic.end(span)
			npc.next_initiative_minute = sim.get_elapsed_game_minutes() + 30
			job = npc.initiative_job
		if job.is_empty():
			continue
		var context := context_for(sim, npc)
		if not context.is_empty():
			contexts[String(npc.id)] = context
	return contexts

static func context_for(sim, npc: Dictionary) -> Dictionary:
	var span := Diagnostic.begin("npc_work.context") if Diagnostic.enabled else 0
	var result := _context_for(sim,npc)
	Diagnostic.end(span)
	return result

static func _context_for(sim, npc: Dictionary) -> Dictionary:
	var job: Dictionary = npc.initiative_job
	if String(job.get("kind", "")) == "build" and not Supply.HomeStock.can_work(sim,job.get("cell",[])):
		cancel(npc)
		return context_for(sim,npc) if not npc.initiative_job.is_empty() else {}
	var phase := String(job.phase)
	if sim.NpcHomeProjects.Production.PHASES.has(phase):
		var production_context: Dictionary = sim.NpcHomeProjects.Production.context(sim,npc)
		if production_context.is_empty(): cancel(npc)
		return production_context
	var cell := Vector2i(int(job.cell[0]), int(job.cell[1]))
	var context: Dictionary = {}
	var target := INVALID
	match phase:
		"borrow":
			context = Supply.find_stock(sim, npc, String(job.tool_id))
			if context.is_empty():
				cancel(npc)
				return {}
		"refill":
			var source: Array = job.get("water_cell", [])
			if source.size() == 2:
				var water_cell := Vector2i(int(source[0]), int(source[1]))
				target = Supply.work_cell(sim, npc, water_cell) if Water.contains_cell(water_cell) else INVALID
				context.water_cell = source.duplicate()
		"work", "deliver", "build", "switch_on":
			if String(job.kind) == "build" and phase != "switch_on" and sim._find_blueprint(job.cell).is_empty():
				cancel(npc)
				return {}
			var goal: Dictionary = npc.home_goal
			if not goal.is_empty() and String(goal.status) == "pending" and goal.cell == job.cell:
				if sim.NpcHomeProjects.Layout.territory(sim,npc).get("id","") != String(goal.room_id) or (phase != "switch_on" and String(sim._find_blueprint(job.cell).get("building_id","")) != String(goal.building_id)):
					cancel(npc)
					return {}
			target = Supply.work_cell(sim, npc, cell)
		"take_materials":
			var blueprint: Dictionary = sim._find_blueprint(job.cell)
			if blueprint.is_empty():
				cancel(npc)
				return {}
			if sim._blueprint_has_all_materials(blueprint):
				job.phase = "build"
				return context_for(sim, npc)
			context = Planner.material_source(sim, npc, blueprint)
			if context.is_empty():
				if not npc.work_cargo.is_empty():
					job.phase = "deliver"
					return context_for(sim, npc)
				cancel(npc)
				return {}
		"collect":
			for id: String in job.drops.duplicate():
				var drop := find_drop(sim, id)
				if drop.is_empty():
					job.drops.erase(id)
					continue
				cell = sim._world_position_to_cell(Vector2(float(drop.position[0]), float(drop.position[1])))
				target = Supply.work_cell(sim, npc, cell)
				if target != INVALID:
					context.drop = drop
					break
			if target == INVALID or Supply.cargo_size(npc) >= Supply.CARRY_LIMIT:
				job.phase = "return"
				return context_for(sim, npc)
		"return":
			# Try every warehouse cell; partial deposits preserve placement and cargo.
			var instance := Supply.tool(sim, npc)
			var wanted: Array = [String(instance.item_id)] if not instance.is_empty() else []
			for id: String in npc.work_cargo:
				if int(npc.work_cargo[id]) > 0:
					wanted.append(id)
			if wanted.is_empty():
				finish(sim, npc)
				return {}
			for zone: Dictionary in sim.state.storage_zones:
				for value: Array in zone.cells:
					cell = Vector2i(int(value[0]), int(value[1]))
					var fits := false
					for id: String in wanted:
						fits = fits or Supply.has_capacity(sim, cell, id)
					if not fits:
						continue
					target = Supply.work_cell(sim, npc, cell)
					if target != INVALID:
						context.deposit_cell = value.duplicate()
						break
				if target != INVALID:
					break
			if target == INVALID:
				Supply.drop_remaining(sim, npc)
				finish(sim, npc)
				return {}
	if context.has("target_cell"):
		target = Vector2i(int(context.target_cell[0]), int(context.target_cell[1]))
	if target == INVALID:
		cancel(npc)
		return {}
	context.target_cell = [target.x, target.y]
	context.travel_activity = "core:work_travel"
	context.arrival_activity = "core:work_" + phase
	if phase == "work":
		context.arrival_activity = "core:work_watering" if String(job.kind) == "water" else ("core:work_chopping" if String(job.resource_item) == "core:wood" else "core:work_mining")
	return context

static func fulfil(sim, effect: Dictionary) -> bool:
	var npc: Dictionary = sim.state.npcs.get(String(effect.get("npc_id", "")), {})
	var context: Dictionary = effect.get("context", {})
	if npc.is_empty() or not bool(npc.active) or npc.initiative_job.is_empty() or context.is_empty():
		return false
	var current := Supply.cell_of(sim, npc)
	if context.target_cell != [current.x, current.y]:
		return false
	var job: Dictionary = npc.initiative_job
	var phase := String(job.phase)
	if String(job.kind) == "build" and phase != "return" and not Supply.HomeStock.can_work(sim,job.cell):
		cancel(npc)
		return false
	var cell := Vector2i(int(job.cell[0]), int(job.cell[1]))
	if sim.NpcHomeProjects.Production.PHASES.has(phase):
		if not sim.NpcHomeProjects.Production.fulfil(sim,npc,context):
			cancel(npc)
			return false
		return true
	match phase:
		"borrow":
			if Supply.borrow(sim, npc, context):
				job.phase = "refill" if String(job.kind) == "water" and int(Supply.tool(sim, npc).get("state", {}).get("charges", 0)) == 0 else "work"
				if String(job.phase) == "refill" and job.get("water_cell", []).is_empty():
					job.water_cell = Supply.find_water(sim, npc)
					if job.water_cell.is_empty():
						cancel(npc)
			else:
				cancel(npc)
		"refill":
			var water_cell := Vector2i(int(context.water_cell[0]), int(context.water_cell[1]))
			if sim.EquipmentSystem.fill_bucket_for_actor(sim, String(npc.id), water_cell).success:
				job.phase = "work"
			else:
				cancel(npc)
		"work":
			if String(job.kind) == "water":
				if sim.farming.water_for_actor(sim, String(npc.id), cell).success:
					sim.needs.spend_work(npc.needs)
				job.phase = "return"
			else:
				var result: Dictionary = sim.execute_resource_work(String(npc.id), String(job.target_id))
				for id: String in result.get("created_drop_ids", []):
					if not job.drops.has(id):
						job.drops.append(id)
				if String(result.get("reason_id", "")) == "core:resource_depleted":
					job.phase = "collect"
				elif not bool(result.get("success", false)):
					job.phase = "collect" if not job.drops.is_empty() else "return"
		"collect":
			Supply.collect(sim, npc, context.drop)
		"take_materials":
			if Supply.take_material(sim, npc, context, int(context.missing)):
				job.phase = "deliver"
			else:
				cancel(npc)
		"deliver":
			var blueprint: Dictionary = sim._find_blueprint(job.cell)
			if not blueprint.is_empty() and Supply.nearby(sim, npc, cell):
				var transfer: Dictionary = sim._calculate_material_transfer(blueprint, npc.work_cargo)
				sim._apply_material_transfer(blueprint, npc.work_cargo, transfer)
				for id: String in npc.work_cargo.keys():
					if int(npc.work_cargo[id]) <= 0:
						npc.work_cargo.erase(id)
				job.phase = "build" if sim._blueprint_has_all_materials(blueprint) else "take_materials"
			else:
				cancel(npc)
		"build":
			if not Supply.nearby(sim, npc, cell):
				cancel(npc)
			else:
				var goal: Dictionary = npc.home_goal
				if not goal.is_empty() and String(goal.status) == "pending" and goal.cell == job.cell and not sim.NpcHomeProjects.Layout.can_place(sim,npc,String(goal.building_id),cell,job.cell):
					cancel(npc)
					return false
				var result: Dictionary = sim._advance_blueprint_work(job.cell,String(npc.id))
				if bool(result.get("changed", false)):
					sim.needs.spend_work(npc.needs)
				if String(result.get("reason_id", "")) == "core:structure_completed":
					if String(result.get("building_id", "")) == "core:wood_wall":
						sim._record_first_shared_wall_memory(npc, job.cell, sim.get_minute_of_day())
					cancel(npc)
				elif not bool(result.get("changed", false)):
					cancel(npc)
		"switch_on":
			var goal: Dictionary = npc.home_goal
			var structure: Dictionary = sim.NpcHomeProjects.matching_structure(sim,goal) if not goal.is_empty() else {}
			if not goal.is_empty() and goal.cell == job.cell and String(goal.status) == "pending" and String(structure.get("building_id","")) == "core:torch" and Supply.nearby(sim,npc,cell):
				sim.set_structure_state(structure,"lit",true)
			cancel(npc)
		"return":
			# One arrival permits only cells within real interaction range.
			for zone: Dictionary in sim.state.storage_zones:
				for value: Array in zone.cells:
					Supply.deposit_at(sim, npc, Vector2i(int(value[0]), int(value[1])))
			if npc.work_cargo.is_empty() and String(npc.carried_instance_id).is_empty():
				finish(sim, npc)
	return true

static func find_drop(sim, id: String) -> Dictionary:
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.drop_id) == id:
			return drop
	return {}

static func finish(sim, npc: Dictionary) -> void:
	npc.initiative_job = {}
	npc.next_initiative_minute = sim.get_elapsed_game_minutes() + 15
