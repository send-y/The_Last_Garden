extends RefCounted

const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Wild := preload("res://src/needs/wild_food_harvest.gd")
const INVALID := Vector2i(-1,-1)

static func eligible(sim, npc: Dictionary, bed: Dictionary) -> bool:
	return bool(npc.get("active",false)) and bool(npc.get("known",false)) and bool(npc.get("work_options",{}).get("sow",false)) and not bed.is_empty() and bool(bed.get("shared_harvest",false)) and bool(bed.get("maintain_crop",false)) and String(bed.get("crop_id","")).is_empty() and not sim.farming.catalog.find(String(bed.get("planned_crop_id",""))).is_empty()

static func available(sim, npc: Dictionary, job: Dictionary) -> bool:
	var values: Array = job.get("cell",[])
	if values.size()!=2: return false
	var bed: Dictionary = sim.farming.bed_at(sim,Vector2i(int(values[0]),int(values[1])))
	return eligible(sim,npc,bed) and String(bed.planned_crop_id)==String(job.get("crop_id",""))

static func deposit_possible(sim, npc: Dictionary, item_id: String) -> bool:
	for zone: Dictionary in sim.state.storage_zones:
		for values: Array in zone.cells:
			var cell := Vector2i(int(values[0]),int(values[1]))
			if Supply.has_capacity(sim,cell,item_id) and Supply.work_cell(sim,npc,cell)!=INVALID: return true
	return false

static func choose(sim, npc: Dictionary) -> Dictionary:
	for bed: Dictionary in sim.get_farm_beds():
		if not eligible(sim,npc,bed): continue
		var reserved := false
		for other: Dictionary in sim.state.npcs.values():
			var job: Dictionary = other.get("initiative_job",{})
			if other.id!=npc.id and bool(other.get("active",false)) and String(job.get("kind",""))=="sow" and String(job.get("phase",""))!="return" and job.get("cell",[])==bed.cell and available(sim,other,job): reserved = true
		if reserved: continue
		var cell := Vector2i(int(bed.cell[0]),int(bed.cell[1]))
		if Supply.work_cell(sim,npc,cell)==INVALID: continue
		var crop: Dictionary = sim.farming.catalog.find(String(bed.planned_crop_id))
		var job := {"kind":"sow","phase":"take_seed","cell":bed.cell.duplicate(),"crop_id":String(crop.id),"seed_id":String(crop.seed_id),"drops":[]}
		if not Supply.find_stock(sim,npc,String(crop.seed_id)).is_empty(): return job
		var food := food_source(sim,npc)
		if not food.is_empty():
			job.merge(food,true)
			return job
	return {}

static func table_target(sim, npc: Dictionary) -> Array:
	for structure: Dictionary in sim.get_structures():
		if String(structure.get("building_id",""))!="core:study_table": continue
		var at := Supply.work_cell(sim,npc,Vector2i(int(structure.cell[0]),int(structure.cell[1])))
		if at!=INVALID: return [at.x,at.y]
	return []

static func food_source(sim, npc: Dictionary) -> Dictionary:
	# Every possible random result must have a delivery route before new forage.
	for crop: Dictionary in sim.farming.catalog.crops:
		if not deposit_possible(sim,npc,String(crop.seed_id)): return {}
	var position: Vector2 = sim.get_npc_position(String(npc.id),Vector2.ZERO)
	var drops: Array = sim.state.world_drops.duplicate()
	drops.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return position.distance_squared_to(Vector2(a.position[0],a.position[1]))<position.distance_squared_to(Vector2(b.position[0],b.position[1])))
	for drop: Dictionary in drops:
		var id := String(drop.item_id)
		if bool(drop.get("npc_recovery",false)) or int(drop.amount)<=0 or not sim.farming.can_extract_seeds(id) or sim.needs.food_profile(id,sim.content).is_empty(): continue
		if id!=sim.content.FOOD_ID and table_target(sim,npc).is_empty(): continue
		var at := Supply.work_cell(sim,npc,sim._world_position_to_cell(Vector2(drop.position[0],drop.position[1])))
		if at!=INVALID: return {"phase":"seed_collect","drop_id":String(drop.drop_id),"food_id":id}
	var bushes: Array[Dictionary] = sim.get_surface_berry_bushes()
	bushes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return position.distance_squared_to(a.position)<position.distance_squared_to(b.position))
	var food_id := String(sim.content.get_collect_rule("food").get("item_id",""))
	if not sim.farming.can_extract_seeds(food_id) or sim.needs.food_profile(food_id,sim.content).is_empty() or not deposit_possible(sim,npc,food_id): return {}
	if food_id!=sim.content.FOOD_ID and table_target(sim,npc).is_empty(): return {}
	for bush: Dictionary in bushes:
		if sim.should_hide_interactable(String(bush.id),"food") or not sim.farming.berry_ready(sim,String(bush.id)): continue
		if Supply.work_cell(sim,npc,sim._world_position_to_cell(bush.position))!=INVALID:
			return {"phase":"seed_forage","target_id":String(bush.id),"food_id":food_id}
	return {}

static func context(sim, npc: Dictionary) -> Dictionary:
	var job: Dictionary = npc.initiative_job
	if not available(sim,npc,job): return {}
	var result: Dictionary = {}
	var at := INVALID
	match String(job.phase):
		"take_seed":
			if int(npc.work_cargo.get(String(job.seed_id),0))>0:
				job.phase = "sow"
				return context(sim,npc)
			result = Supply.find_stock(sim,npc,String(job.seed_id))
			if result.is_empty(): return {}
		"sow":
			at = Supply.work_cell(sim,npc,Vector2i(int(job.cell[0]),int(job.cell[1])))
		"seed_forage":
			var bush: Dictionary = sim._resolve_interaction_target(String(job.get("target_id","")))
			if bush.is_empty() or sim.should_hide_interactable(String(job.target_id),"food") or not sim.farming.berry_ready(sim,String(job.target_id)): return {}
			at = Supply.work_cell(sim,npc,sim._world_position_to_cell(bush.position))
		"seed_collect":
			for drop: Dictionary in sim.state.world_drops:
				if String(drop.drop_id)==String(job.get("drop_id","")) and String(drop.item_id)==String(job.food_id) and not bool(drop.get("npc_recovery",false)):
					result.drop = drop
					at = Supply.work_cell(sim,npc,sim._world_position_to_cell(Vector2(drop.position[0],drop.position[1])))
		"seed_extract":
			if int(npc.work_cargo.get(String(job.food_id),0))<=0: return {}
			if String(job.food_id)==sim.content.FOOD_ID: at = Supply.cell_of(sim,npc)
			else:
				var table := table_target(sim,npc)
				if table.size()==2: at = Vector2i(int(table[0]),int(table[1]))
	if result.has("target_cell"): at = Vector2i(int(result.target_cell[0]),int(result.target_cell[1]))
	if at==INVALID: return {}
	result.target_cell = [at.x,at.y]
	result.travel_activity = "core:work_travel"
	result.arrival_activity = "core:work_"+String(job.phase)
	return result

static func fulfil(sim, npc: Dictionary, supplied: Dictionary) -> bool:
	var job: Dictionary = npc.initiative_job
	# Rebuild from authoritative sources; stale UI/context cannot withdraw remotely.
	var current := context(sim,npc)
	if current.is_empty() or current.target_cell!=supplied.get("target_cell",[]) or current.target_cell!=[Supply.cell_of(sim,npc).x,Supply.cell_of(sim,npc).y]: return false
	match String(job.phase):
		"take_seed":
			if not Supply.take_material(sim,npc,current,1): return false
			job.phase = "sow"
		"sow":
			if not sim.farming.plant_for_actor(sim,String(npc.id),Vector2i(int(job.cell[0]),int(job.cell[1])),String(job.seed_id)).success: return false
			job.phase = "return"
		"seed_forage":
			if not Wild.harvest(sim,String(npc.id),String(job.target_id),"cargo").success: return false
			job.phase = "seed_extract"
		"seed_collect":
			if not Supply.collect(sim,npc,current.drop,1): return false
			job.phase = "seed_extract"
		"seed_extract":
			if not sim.farming.extract_for_worker(sim,String(npc.id),String(job.food_id)).success: return false
			job.phase = "return"
	sim.work_metrics.record_work(sim,String(npc.id),1.0)
	return true

static func waiting_reason(sim, bed: Dictionary) -> String:
	if not bool(bed.get("shared_harvest",false)) or not bool(bed.get("maintain_crop",false)) or not String(bed.get("crop_id","")).is_empty(): return ""
	var crop: Dictionary = sim.farming.catalog.find(String(bed.get("planned_crop_id","")))
	if crop.is_empty(): return "farming.maintain.choose"
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id)==String(crop.seed_id) and int(record.amount)>0: return "farming.maintain.wait_worker"
	return "farming.maintain.no_seeds"
