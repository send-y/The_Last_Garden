extends RefCounted

# Diagnostic snapshots of physical stocks, never save data or food authority.
static func amounts(sim, item_id: String) -> Dictionary:
	var result := {"player":sim.get_item_count(item_id),"npc_personal":0,"storage":0,"npc_cargo":0,"world_drops":0}
	for npc: Dictionary in sim.state.npcs.values():
		result.npc_personal += int(npc.get("personal_inventory",{}).get(item_id,0))
		result.npc_cargo += int(npc.get("work_cargo",{}).get(item_id,0))
	for stored: Dictionary in sim.state.storage_items:
		if String(stored.item_id)==item_id: result.storage += int(stored.amount)
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id)==item_id: result.world_drops += int(drop.amount)
	return result

static func total(locations: Dictionary) -> int:
	var count := 0
	for amount: int in locations.values(): count += amount
	return count

static func snapshot(sim) -> Dictionary:
	var result: Dictionary = {}
	for crop: Dictionary in sim.farming.catalog.crops:
		var seeds := amounts(sim,String(crop.seed_id))
		var products := amounts(sim,String(crop.product_id))
		var row := {"seed_id":String(crop.seed_id),"product_id":String(crop.product_id),"seeds_by_location":seeds,"products_by_location":products,"seeds_total":total(seeds),"products_total":total(products),"living_beds":0,"perennial_beds":0,"extraction_unlocked":sim.farming.extraction_unlocked(sim),"flags":[]}
		for bed: Dictionary in sim.state.farming.beds:
			if String(bed.crop_id)!=String(crop.id): continue
			row.living_beds += 1
			if String(crop.harvest_mode)=="perennial": row.perennial_beds += 1
		if int(row.seeds_total)==0: row.flags.append("no_seeds")
		if int(row.products_total)==0: row.flags.append("no_product_for_extraction")
		if not bool(row.extraction_unlocked): row.flags.append("extraction_unavailable")
		result[String(crop.id)] = row
	return result

static func day_balance(sim, start: Dictionary, end: Dictionary, day: int) -> Dictionary:
	var events: Dictionary = sim.work_metrics.farming_snapshot(day)
	var meals: Dictionary = sim.work_metrics.food_snapshot(day)
	var result: Dictionary = {}
	for crop_id: String in end:
		var row: Dictionary = end[crop_id].duplicate(true)
		var seed := String(row.seed_id); var product := String(row.product_id)
		row.start = start.get(crop_id,{}).duplicate(true)
		row.seeds_planted = 0; row.seeds_extracted = 0; row.products_used_for_seeds = 0; row.products_harvested = 0
		row.products_eaten_by_actor = {}
		for actor: String in events:
			var event: Dictionary = events[actor]
			row.seeds_planted += int(event.get("planted",{}).get(seed,0))
			row.seeds_extracted += int(event.get("extracted",{}).get(seed,0))
			row.products_used_for_seeds += int(event.get("extraction_inputs",{}).get(product,0))
			row.products_harvested += int(event.get("harvested",{}).get(product,0))
		var eaten := 0
		for actor: String in meals:
			var amount := int(meals[actor].get(product,0))
			if amount>0: row.products_eaten_by_actor[actor] = amount
			eaten += amount
		row.unexplained_seed_delta = int(row.seeds_total)-int(row.start.get("seeds_total",0))-int(row.seeds_extracted)+int(row.seeds_planted)
		row.unexplained_product_delta = int(row.products_total)-int(row.start.get("products_total",0))-int(row.products_harvested)+int(row.products_used_for_seeds)+eaten
		result[crop_id] = row
	return {"crops":result,"farming_events":events,"meals":meals}
