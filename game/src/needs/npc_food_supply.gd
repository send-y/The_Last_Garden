extends RefCounted

# A meal is a request, not an inventory copy. Fulfilment revalidates real stock.
static func find_meal(sim, npc: Dictionary) -> Dictionary:
	var use: Dictionary = npc.get("furniture_use",{})
	if String(use.get("kind","")) == "meal" and int(use.get("until",0)) > sim.get_elapsed_game_minutes() and not sim.furniture.comfort(sim,String(npc.id)).is_empty():
		return {}
	var trip: Dictionary = npc.get("meal_trip",{})
	if not trip.is_empty() and int(npc.personal_inventory.get(String(trip.item_id),0)) > 0:
		return _personal_meal(sim,npc,String(trip.item_id))
	for id: String in npc.personal_inventory:
		if int(npc.personal_inventory[id]) > 0 and not sim.needs.food_profile(id, sim.content).is_empty():
			return _personal_meal(sim,npc,id)
	var npc_cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id), Vector2.ZERO))
	var player_cell: Vector2i = sim._world_position_to_cell(sim.get_player_position())
	for stored: Dictionary in sim.state.storage_items:
		var id := String(stored.item_id)
		if int(stored.amount) <= 0 or sim.needs.food_profile(id, sim.content).is_empty():
			continue
		var cell := Vector2i(int(stored.cell[0]), int(stored.cell[1]))
		var target: Vector2i = sim.npc_autonomy.find_construction_work_cell(cell, npc_cell, player_cell)
		if target != sim.npc_autonomy.INVALID_CELL:
			var seat: Dictionary = sim.furniture.find_seat(sim,String(npc.id),true)
			return {"source": "storage", "item_id": id, "cell": stored.cell.duplicate(),
				"placement_id": stored.placement_id, "target_cell": [target.x, target.y],"seat":seat,"carry":not seat.is_empty()}
	return _wild_meal(sim,npc,npc_cell,player_cell)

static func _wild_meal(sim, npc: Dictionary, from: Vector2i, player_cell: Vector2i) -> Dictionary:
	var bushes: Array[Dictionary] = sim.get_surface_berry_bushes()
	var position: Vector2 = sim.get_npc_position(String(npc.id),Vector2.ZERO)
	bushes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
	for bush: Dictionary in bushes:
		if position.distance_squared_to(bush.position) > pow(24*sim.content.CELL_SIZE,2): break
		if sim.should_hide_interactable(String(bush.id),"food") or not sim.farming.berry_ready(sim,String(bush.id)): continue
		var cell: Vector2i = sim._world_position_to_cell(bush.position)
		var at: Vector2i = sim.npc_autonomy.find_construction_work_cell(cell,from,player_cell)
		if at == sim.npc_autonomy.INVALID_CELL: continue
		return {"source":"wild","object_id":String(bush.id),"item_id":String(sim.content.get_collect_rule("food").item_id),"cell":[cell.x,cell.y],"target_cell":[at.x,at.y],"carry":true}
	return {}

static func _personal_meal(sim, npc: Dictionary, item_id: String) -> Dictionary:
	var seat: Dictionary = sim.furniture.find_seat(sim,String(npc.id),true)
	var cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO))
	var target: Array = [cell.x,cell.y]
	if not seat.is_empty():
		npc.furniture_target = seat.chair_cell.duplicate()
		npc.meal_trip = {"item_id":item_id}
		target = seat.target_cell
	else:
		var autonomy: Dictionary = sim.npc_catalog.get_definition(String(npc.id)).get("autonomy",{})
		var preferred: Array = autonomy.get("meal_cell",[20,28])
		var blocker: Vector2i = sim._world_position_to_cell(sim.get_player_position())
		var safe: Vector2i = sim.npc_autonomy.find_temporary_rest_cell(Vector2i(int(preferred[0]),int(preferred[1])),cell,blocker)
		target = [safe.x,safe.y]
		npc.furniture_target = []
	return {"source":"personal","item_id":item_id,"target_cell":target,"seat":seat}

static func fulfil(sim, effect: Dictionary) -> bool:
	var npc: Dictionary = sim.state.npcs.get(String(effect.get("npc_id", "")), {})
	var meal: Dictionary = effect.get("meal", {})
	if npc.is_empty() or meal.is_empty() or not bool(npc.active):
		return false
	var target: Array = meal.get("target_cell", [])
	if target.size() != 2:
		return false
	var current_cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id), Vector2.ZERO))
	if current_cell != Vector2i(int(target[0]), int(target[1])):
		return false
	var id := String(meal.get("item_id", ""))
	var profile: Dictionary = sim.needs.food_profile(id, sim.content)
	if profile.is_empty():
		return false
	if String(meal.get("source","")) == "wild":
		return bool(preload("res://src/needs/wild_food_harvest.gd").harvest(sim,String(npc.id),String(meal.get("object_id",""))).success)
	if String(meal.get("source", "")) == "personal":
		if int(npc.personal_inventory.get(id, 0)) <= 0:
			return false
		npc.personal_inventory[id] = int(npc.personal_inventory[id]) - 1
	elif String(meal.get("source", "")) == "storage":
		var source: Array = meal.get("cell", [])
		if source.size() != 2 or current_cell.distance_to(Vector2i(int(source[0]), int(source[1]))) > 1.0:
			return false
		var consumed := false
		var stored_items: Array = sim.state.storage_items
		for index: int in range(stored_items.size()):
			var stored: Dictionary = stored_items[index]
			if stored.cell != source or String(stored.placement_id) != String(meal.get("placement_id", "")) or String(stored.item_id) != id or int(stored.amount) <= 0:
				continue
			stored.amount = int(stored.amount) - 1
			if int(stored.amount) == 0:
				stored_items.remove_at(index)
			consumed = true
			break
		if not consumed:
			return false
	else:
		return false
	var seat: Dictionary = meal.get("seat",{})
	if String(meal.source) == "storage" and not seat.is_empty():
		# Transfer to the real personal inventory; do not feed remotely at the table.
		npc.personal_inventory[id] = int(npc.personal_inventory.get(id,0)) + 1
		npc.meal_trip = {"item_id":id}
		var actual: Dictionary = sim.furniture.find_seat(sim,String(npc.id),true)
		if not actual.is_empty():
			npc.furniture_target = actual.chair_cell.duplicate()
		return true
	if not seat.is_empty() and sim.furniture.sit_npc(sim,npc,seat,"meal"):
		sim.needs.add_effect(npc,"table_meal",sim.get_elapsed_game_minutes())
		npc.activity_id = "core:table_eating"
	npc.meal_trip = {}
	if seat.is_empty():
		npc.furniture_target = []
	sim.needs.feed(npc.needs, profile)
	return true
