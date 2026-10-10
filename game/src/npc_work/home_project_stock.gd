extends RefCounted

# Shared-project stock rules apply to every worker, including one helping a neighbour.
static func owner(sim, cell: Array) -> Dictionary:
	for npc: Dictionary in sim.state.npcs.values():
		var goal: Dictionary = npc.get("home_goal", {})
		if not goal.is_empty() and String(goal.get("status", "")) == "pending" and String(goal.get("action", "build")) == "build" and goal.get("cell", []) == cell:
			return npc
	return {}

static func can_work(sim, cell: Array) -> bool:
	var resident := owner(sim, cell)
	if resident.is_empty(): return true
	return bool(resident.get("work_options", {}).get("build", false)) and sim.HomePolicy.may_furnish(sim, resident, String(resident.home_goal.room_id))

static func withdrawal_limit(sim, npc: Dictionary, item_id: String) -> int:
	var cell: Array = npc.get("initiative_job", {}).get("cell", [])
	if owner(sim, cell).is_empty(): return 2147483647
	if not can_work(sim, cell): return 0
	return sim.StockReserves.available(sim, item_id)

static func report(sim, npc: Dictionary, goal: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	var protected: Dictionary = {}
	if goal.is_empty() or String(goal.action) == "light":
		return {"missing":missing, "protected":protected}
	var blueprint: Dictionary = sim._find_blueprint(goal.cell)
	if String(blueprint.get("building_id", "")) != String(goal.building_id): blueprint = {}
	var accessible: Dictionary = {}
	var reachable_cells: Dictionary = {}
	for record: Dictionary in sim.state.storage_items:
		var key := str(record.cell)
		if not reachable_cells.has(key):
			reachable_cells[key] = sim.NpcPracticalWork.Supply.work_cell(sim,npc,Vector2i(int(record.cell[0]),int(record.cell[1]))) != Vector2i(-1,-1)
		if bool(reachable_cells[key]):
			accessible[record.item_id] = int(accessible.get(record.item_id,0)) + int(record.amount)
	for item_id: String in sim.building_catalog.get_material_cost(String(goal.building_id)):
		var needed := int(sim.building_catalog.get_material_cost(String(goal.building_id))[item_id]) - int(blueprint.get("delivered_materials",{}).get(item_id,0)) - int(npc.work_cargo.get(item_id,0))
		var reachable := int(accessible.get(item_id,0))
		var usable := mini(reachable,sim.StockReserves.available(sim,item_id))
		if needed > usable:
			missing[item_id] = needed - usable
			var blocked := mini(needed - usable,reachable - usable)
			if blocked > 0: protected[item_id] = blocked
	return {"missing":missing, "protected":protected}
