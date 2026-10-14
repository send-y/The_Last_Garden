extends RefCounted

const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Content := preload("res://src/content/first_night_content.gd")
const INVALID := Vector2i(-1,-1)

static func reserved(sim, npc_id: String, cell: Array) -> bool:
	for other: Dictionary in sim.state.npcs.values():
		if String(other.id)==npc_id or not bool(other.get("active",false)): continue
		var job: Dictionary = other.get("initiative_job",{})
		if job.get("kind","")=="harvest" and job.get("phase","")=="work" and job.get("cell",[])==cell: return true
		var meal: Dictionary = other.get("crop_food_trip",{})
		if meal.get("phase","")=="harvest" and meal.get("cell",[])==cell: return true
	return false

static func storage_available(sim, npc: Dictionary, item_id: String) -> bool:
	for zone: Dictionary in sim.state.storage_zones:
		for value: Array in zone.cells:
			var cell := Vector2i(int(value[0]),int(value[1]))
			if Supply.has_capacity(sim,cell,item_id) and Supply.work_cell(sim,npc,cell)!=INVALID: return true
	return false

static func target_available(sim, npc: Dictionary, goal: Dictionary) -> bool:
	var value: Array = goal.get("cell",[])
	if value.size()!=2: return false
	var cell := Vector2i(int(value[0]),int(value[1]))
	var bed: Dictionary = sim.farming.bed_at(sim,cell)
	return bool(npc.get("work_options",{}).get("harvest",false)) and bool(bed.get("shared_harvest",false)) and String(bed.get("crop_id",""))==String(goal.get("crop_id","")) and int(bed.get("planting_id",0))==int(goal.get("planting_id",0)) and sim.farming.harvest_ready(sim,cell)

static func choose(sim, npc: Dictionary, for_meal: bool = false) -> Dictionary:
	if not bool(npc.get("work_options",{}).get("harvest",false)): return {}
	if not for_meal and Supply.cargo_size(npc)>=Supply.CARRY_LIMIT: return {}
	var position: Vector2 = sim.get_npc_position(String(npc.id),Vector2.ZERO)
	var beds: Array = sim.get_farm_beds()
	beds.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var da := position.distance_squared_to(Content.cell_center(int(a.cell[0]),int(a.cell[1])))
		var db := position.distance_squared_to(Content.cell_center(int(b.cell[0]),int(b.cell[1])))
		return da < db if not is_equal_approx(da,db) else (int(a.cell[1]) < int(b.cell[1]) if a.cell[1]!=b.cell[1] else int(a.cell[0]) < int(b.cell[0]))
	)
	for bed: Dictionary in beds:
		var cell := Vector2i(int(bed.cell[0]),int(bed.cell[1]))
		if not bool(bed.get("shared_harvest",false)) or not sim.farming.harvest_ready(sim,cell) or reserved(sim,String(npc.id),bed.cell): continue
		var crop: Dictionary = sim.farming.catalog.find(String(bed.crop_id))
		var item := String(crop.product_id)
		if for_meal and sim.needs.food_profile(item,sim.content).is_empty(): continue
		if not for_meal and not storage_available(sim,npc,item): continue
		var target := Supply.work_cell(sim,npc,cell)
		if target==INVALID: continue
		return {"cell":bed.cell.duplicate(),"crop_id":String(bed.crop_id),"planting_id":int(bed.get("planting_id",0)),"item_id":item,"target_cell":[target.x,target.y]}
	return {}
