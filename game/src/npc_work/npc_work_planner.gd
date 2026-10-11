extends RefCounted

const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Content := preload("res://src/content/first_night_content.gd")
const HomeStock := preload("res://src/npc_work/home_project_stock.gd")
const STOCK_TARGETS := {"core:wood": 20, "core:stone": 15}

static func choose(sim, npc: Dictionary) -> Dictionary:
	var choices: Array[Dictionary] = []
	var bucket_source: Dictionary = Supply.find_tool_stock(sim, npc, "water") if bool(npc.work_options.water) else {}
	var refill: Array = []
	var bucket_ready := false
	if not bucket_source.is_empty():
		var bucket: Dictionary = sim.get_item_instance(String(bucket_source.record.get("instance_id", "")))
		bucket_ready = int(bucket.get("state", {}).get("charges", 0)) > 0
		if not bucket_ready:
			refill = Supply.find_water(sim, npc)
	if not bucket_source.is_empty() and (bucket_ready or not refill.is_empty()):
		for bed: Dictionary in sim.get_farm_beds():
			if String(bed.get("crop_id", "")).is_empty() or int(bed.wet_until) > sim.get_elapsed_game_minutes() or reserved(sim, npc, "water", bed.cell):
				continue
			var cell := Vector2i(int(bed.cell[0]), int(bed.cell[1]))
			if Supply.work_cell(sim, npc, cell) != Vector2i(-1, -1):
				choices.append({"kind": "water", "phase": "borrow", "tool_id": String(bucket_source.record.item_id), "cell": bed.cell.duplicate(), "water_cell": refill, "drops": []})
				break
	if bool(npc.work_options.gather):
		for item_id: String in STOCK_TARGETS:
			if stock(sim, item_id) >= int(STOCK_TARGETS[item_id]):
				continue
			var action_id := "chop" if item_id == "core:wood" else "mine"
			var tool_source := Supply.find_tool_stock(sim, npc, action_id)
			if tool_source.is_empty():
				continue
			var targets: Array = sim.get_surface_trees() if item_id == "core:wood" else sim.get_surface_boulders()
			var position: Vector2 = sim.get_npc_position(String(npc.id), Vector2.ZERO)
			targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
			var examined := 0
			for target: Dictionary in targets:
				if String(target.get("presentation_id", "")) == "surface_stump" or sim.is_collected(String(target.id)) or reserved(sim, npc, "gather", String(target.id)):
					continue
				examined += 1
				if examined > 8:
					break
				var cell: Vector2i = sim._world_position_to_cell(target.position)
				if Supply.work_cell(sim, npc, cell) != Vector2i(-1, -1):
					choices.append({"kind": "gather", "phase": "borrow", "tool_id": String(tool_source.record.item_id),
						"resource_item": item_id, "target_id": String(target.id), "cell": [cell.x, cell.y], "drops": []})
					break
	if bool(npc.work_options.build):
		for blueprint: Dictionary in sim.state.blueprints:
			if not HomeStock.can_work(sim,blueprint.cell): continue
			if reserved(sim, npc, "build", blueprint.cell):
				continue
			var cell := Vector2i(int(blueprint.cell[0]), int(blueprint.cell[1]))
			if Supply.work_cell(sim, npc, cell) == Vector2i(-1, -1):
				continue
			var ready: bool = sim._blueprint_has_all_materials(blueprint)
			if ready or not material_source(sim, npc, blueprint).is_empty():
				choices.append({"kind": "build", "phase": "build" if ready else "take_materials", "cell": blueprint.cell.duplicate(), "drops": []})
				break
	if choices.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%s" % [sim.state.seed, npc.id, npc.initiative_choice_index])
	npc.initiative_choice_index = int(npc.initiative_choice_index) + 1
	# Reproducible variety across available work, with stable goals once chosen.
	var profile: Dictionary = sim.state.get("npc_profiles",{}).get(String(npc.id),{})
	var preferences := preload("res://src/characters/npc_preferences.gd")
	var total := 0.0
	for choice: Dictionary in choices: total += preferences.score(profile,choice,{})
	var roll := rng.randf()*total
	for choice: Dictionary in choices:
		roll -= preferences.score(profile,choice,{})
		if roll <= 0: return choice
	return choices[-1]

static func stock(sim, item_id: String) -> int:
	var count := 0
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == item_id:
			count += int(record.amount)
	for npc: Dictionary in sim.state.npcs.values():
		count += int(npc.get("work_cargo", {}).get(item_id, 0))
	return count

static func reserved(sim, worker: Dictionary, kind: String, target: Variant) -> bool:
	for npc: Dictionary in sim.state.npcs.values():
		if String(npc.get("id", "")) == String(worker.id) or not bool(npc.get("active", false)):
			continue
		var job: Dictionary = npc.get("initiative_job", {})
		if String(job.get("kind", "")) == kind and job.get("target_id" if kind == "gather" else "cell") == target:
			return true
		if kind == "build" and npc.get("work_commitment", {}).get("target_cell") == target:
			return true
	return false

static func material_source(sim, npc: Dictionary, blueprint: Dictionary) -> Dictionary:
	var cargo: Dictionary = npc.work_cargo
	for id: String in blueprint.get("required_materials", {}):
		var missing := int(blueprint.required_materials[id]) - int(blueprint.delivered_materials.get(id, 0)) - int(cargo.get(id, 0))
		if missing > 0:
			if not HomeStock.owner(sim,blueprint.cell).is_empty() and sim.StockReserves.available(sim,id) <= 0: continue
			var source := Supply.find_stock(sim, npc, id)
			if not source.is_empty():
				source.missing = missing
				return source
	return {}

static func tool_action(job: Dictionary) -> String:
	if String(job.get("kind", "")) == "water": return "water"
	if String(job.get("kind", "")) == "gather": return "chop" if String(job.get("resource_item", "")) == "core:wood" else "mine"
	return ""
