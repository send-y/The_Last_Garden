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

static func can_acquire(sim, npc: Dictionary) -> bool:
	var autonomy = sim.npc_autonomy
	var minute: int = sim.get_minute_of_day()
	if not bool(npc.get("active",false)) or not bool(npc.get("known",false)) or minute>=autonomy.REST_START or minute<7*60 or float(npc.needs.energy)<=autonomy.CRITICAL_ENERGY_THRESHOLD: return false
	return not (String(npc.get("activity_id","")) in [autonomy.ACTIVITY_RESTING,autonomy.ACTIVITY_SLEEPING,autonomy.ACTIVITY_CHAIR_RESTING] and float(npc.needs.energy)<autonomy.RESTED_THRESHOLD)

static func find_drop(sim, id: String) -> Dictionary:
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.drop_id)==id: return drop
	return {}

static func pending_drop(sim, npc: Dictionary, trip: Dictionary) -> Dictionary:
	for id: String in trip.get("drops",[]).duplicate():
		var drop := find_drop(sim,id)
		if drop.is_empty() or String(drop.item_id)!=String(trip.get("item_id","")) or String(drop.get("source_id",""))!=String(npc.id):
			trip.drops.erase(id)
			continue
		var cell: Vector2i = sim._world_position_to_cell(Vector2(float(drop.position[0]),float(drop.position[1])))
		var target := Supply.work_cell(sim,npc,cell)
		if target!=INVALID: return {"drop":drop,"target_cell":[target.x,target.y]}
	return {}

static func find_meal(sim, npc: Dictionary) -> Dictionary:
	if not can_acquire(sim,npc): return {}
	var trip: Dictionary = npc.get("crop_food_trip",{})
	if trip.is_empty():
		var job: Dictionary = npc.get("initiative_job",{})
		if job.get("kind","")=="harvest" and job.get("phase","") in ["collect","return"]:
			var crop: Dictionary = sim.farming.catalog.find(String(job.get("crop_id","")))
			if not crop.is_empty():
				var item := String(crop.product_id)
				if int(npc.work_cargo.get(item,0))>0 or not job.get("drops",[]).is_empty():
					trip = {"cell":job.cell.duplicate(),"crop_id":String(crop.id),"planting_id":int(job.get("planting_id",0)),"item_id":item,"phase":"collect","drops":job.get("drops",[]).duplicate()}
					npc.crop_food_trip = trip
	if trip.get("phase","") in ["collect","delivery"]:
		var item := String(trip.get("item_id",""))
		if int(npc.work_cargo.get(item,0))>0:
			var at := Supply.cell_of(sim,npc)
			return {"source":"crop","phase":"cargo","item_id":item,"target_cell":[at.x,at.y],"carry":true,"acquiring":true}
		var context := pending_drop(sim,npc,trip)
		if not context.is_empty():
			return {"source":"crop","phase":"collect","item_id":item,"drop_id":String(context.drop.drop_id),"target_cell":context.target_cell,"carry":true,"acquiring":true}
		if not trip.get("drops",[]).is_empty(): return {}
		npc.crop_food_trip = {}; trip = {}
	if not trip.is_empty() and not target_available(sim,npc,trip):
		npc.crop_food_trip = {}; trip = {}
	if trip.is_empty():
		var goal := choose(sim,npc,true)
		if goal.is_empty(): return {}
		trip = goal.duplicate(true); trip.phase = "harvest"; trip.drops = []
		npc.crop_food_trip = trip
	var cell := Vector2i(int(trip.cell[0]),int(trip.cell[1]))
	var target := Supply.work_cell(sim,npc,cell)
	if target==INVALID: return {}
	return {"source":"crop","phase":"harvest","cell":trip.cell.duplicate(),"crop_id":trip.crop_id,"planting_id":int(trip.get("planting_id",0)),"item_id":trip.item_id,"target_cell":[target.x,target.y],"carry":true,"acquiring":true}

static func fulfil_meal(sim, npc: Dictionary, meal: Dictionary) -> bool:
	if not can_acquire(sim,npc): return false
	var trip: Dictionary = npc.get("crop_food_trip",{})
	var item := String(meal.get("item_id",""))
	if trip.is_empty() or item!=String(trip.get("item_id","")) or sim.needs.food_profile(item,sim.content).is_empty(): return false
	var phase := String(meal.get("phase",""))
	if phase=="harvest":
		if trip.get("phase","")!="harvest" or meal.get("cell",[])!=trip.cell or int(meal.get("planting_id",0))!=int(trip.get("planting_id",0)) or not target_available(sim,npc,trip) or reserved(sim,String(npc.id),trip.cell): return false
		var result: Dictionary = sim.farming.harvest_for_actor(sim,String(npc.id),Vector2i(int(trip.cell[0]),int(trip.cell[1])))
		if not bool(result.success): return false
		trip.drops = result.created_drop_ids.duplicate(); trip.phase = "collect"
		sim.work_metrics.record_work(sim,String(npc.id),1.0)
		return true
	if phase=="cargo":
		if int(npc.work_cargo.get(item,0))<=0: return false
		npc.work_cargo[item] = int(npc.work_cargo[item])-1
		if int(npc.work_cargo[item])==0: npc.work_cargo.erase(item)
	elif phase=="collect":
		var drop := find_drop(sim,String(meal.get("drop_id","")))
		if drop.is_empty() or not trip.get("drops",[]).has(String(drop.drop_id)) or String(drop.item_id)!=item or String(drop.get("source_id",""))!=String(npc.id): return false
		var position := Vector2(float(drop.position[0]),float(drop.position[1]))
		if sim.get_npc_position(String(npc.id),Vector2.ZERO).distance_to(position)>Content.INTERACTION_RANGE or int(drop.amount)<=0: return false
		drop.amount = int(drop.amount)-1
		if int(drop.amount)==0: sim.state.world_drops.erase(drop)
	else: return false
	npc.personal_inventory[item] = int(npc.personal_inventory.get(item,0))+1
	npc.meal_trip = {"item_id":item}
	# Leftovers stay physical; work cargo never overwrites an earlier paid batch.
	for id: String in trip.get("drops",[]).duplicate():
		var drop := find_drop(sim,id)
		if not drop.is_empty(): Supply.collect(sim,npc,drop)
		if find_drop(sim,id).is_empty(): trip.drops.erase(id)
	trip.phase = "delivery"
	return true

static func prepare_delivery(sim, npc: Dictionary) -> Dictionary:
	var trip: Dictionary = npc.get("crop_food_trip",{})
	if trip.is_empty() or trip.get("phase","")=="harvest": return {}
	var item := String(trip.get("item_id",""))
	var pending := pending_drop(sim,npc,trip)
	if not pending.is_empty() and Supply.cargo_size(npc)<Supply.CARRY_LIMIT:
		return {"crop_supply":"collect","drop_id":String(pending.drop.drop_id),"target_cell":pending.target_cell,"travel_activity":"core:work_travel","arrival_activity":"core:work_collect"}
	if int(npc.work_cargo.get(item,0))>0:
		for zone: Dictionary in sim.state.storage_zones:
			for value: Array in zone.cells:
				var cell := Vector2i(int(value[0]),int(value[1]))
				if not Supply.has_capacity(sim,cell,item): continue
				var target := Supply.work_cell(sim,npc,cell)
				if target!=INVALID:
					trip.erase("blocked_reason")
					return {"crop_supply":"deliver","deposit_cell":value.duplicate(),"target_cell":[target.x,target.y],"travel_activity":"core:work_travel","arrival_activity":"core:work_return"}
		trip.blocked_reason = "storage_full_or_unreachable"
		return {}
	if trip.get("drops",[]).is_empty(): npc.crop_food_trip = {}
	return {}

static func fulfil_delivery(sim, npc: Dictionary, context: Dictionary) -> bool:
	var trip: Dictionary = npc.get("crop_food_trip",{})
	if trip.is_empty(): return false
	if context.get("crop_supply","")=="collect":
		var id := String(context.get("drop_id",""))
		if not trip.get("drops",[]).has(id): return false
		var drop := find_drop(sim,id)
		if drop.is_empty(): return false
		if not Supply.collect(sim,npc,drop): return false
		if find_drop(sim,id).is_empty(): trip.drops.erase(id)
		return true
	if context.get("crop_supply","")=="deliver":
		var value: Array = context.get("deposit_cell",[])
		if value.size()!=2: return false
		var cell := Vector2i(int(value[0]),int(value[1]))
		if sim._storage_zone_index_at_cell(cell)<0 or not sim._storage_cell_has_floor(cell) or sim._storage_cell_has_blocking_structure(cell): return false
		var item := String(trip.item_id)
		var amount := int(npc.work_cargo.get(item,0))
		var stored := Supply.store(sim,npc,cell,item,amount)
		if stored<=0: return false
		npc.work_cargo[item] = amount-stored
		if int(npc.work_cargo[item])==0: npc.work_cargo.erase(item)
		return true
	return false
