extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const Placement := preload("res://src/inventory/inventory_placement_rules.gd")
const Water := preload("res://src/world/water_map.gd")
const HomeStock := preload("res://src/npc_work/home_project_stock.gd")
const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
const CARRY_LIMIT := 20

static func cell_of(sim, npc: Dictionary) -> Vector2i:
	return sim._world_position_to_cell(sim.get_npc_position(String(npc.id), Vector2.ZERO))

static func work_cell(sim, npc: Dictionary, target: Vector2i) -> Vector2i:
	return sim.work_queries.work_cell(sim,npc,target)

static func build_work_cell(sim, npc: Dictionary, target: Vector2i) -> Vector2i:
	var blueprint: Dictionary = sim._find_blueprint([target.x, target.y])
	var occupied: Array[Vector2i] = sim.building_catalog.get_footprint_cells(String(blueprint.get("building_id", "")), target)
	return sim.work_queries.work_cell(sim, npc, target, occupied)

# One bounded flood search finds an accessible bank, including enclosed gardens.
# Avoid running an A* search for each of the river's many water cells.
static func find_water(sim, npc: Dictionary) -> Array:
	var water: Dictionary = {}
	for cell: Vector2i in Water.surface_cells():
		water[cell] = true
	var start := cell_of(sim, npc)
	var blocker: Vector2i = sim._world_position_to_cell(sim.get_player_position())
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
			var candidate := current + direction
			if water.has(candidate):
				return [candidate.x, candidate.y]
			if candidate == blocker or visited.has(candidate) or not sim.npc_autonomy.is_cell_walkable(candidate):
				continue
			visited[candidate] = true
			queue.append(candidate)
	return []

static func nearby(sim, npc: Dictionary, cell: Vector2i) -> bool:
	return sim.get_npc_position(String(npc.id), Vector2.ZERO).distance_to(Content.cell_center(cell.x, cell.y)) <= Content.INTERACTION_RANGE

static func tool(sim, npc: Dictionary) -> Dictionary:
	var instance: Dictionary = sim.get_item_instance(String(npc.get("carried_instance_id", "")))
	var location: Dictionary = instance.get("location", {})
	return instance if String(location.get("kind", "")) == "npc" and String(location.get("id", "")) == String(npc.id) else {}

static func find_stock(sim, npc: Dictionary, id: String) -> Dictionary:
	var span := Diagnostic.begin("npc_work.find_stock") if Diagnostic.enabled else 0
	var result := _find_stock(sim,npc,id)
	Diagnostic.end(span)
	return result

static func _find_stock(sim, npc: Dictionary, id: String) -> Dictionary:
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) != id or int(record.amount) <= 0:
			continue
		var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
		var target := work_cell(sim, npc, cell)
		if target != Vector2i(-1, -1):
			return {"record": record, "target_cell": [target.x, target.y]}
	return {}

static func find_tool_stock(sim, npc: Dictionary, action_id: String) -> Dictionary:
	for record: Dictionary in sim.state.storage_items:
		if int(record.get("amount", 0)) != 1 or not sim.content.item_tool_supports(String(record.get("item_id", "")), action_id):
			continue
		var instance: Dictionary = sim.get_item_instance(String(record.get("instance_id", "")))
		var location: Dictionary = instance.get("location", {})
		if instance.is_empty() or String(instance.item_id) != String(record.item_id) or String(location.get("kind", "")) != "storage" or String(location.get("id", "")) != String(record.get("placement_id", "")):
			continue
		var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
		if sim._storage_zone_index_at_cell(cell) < 0 or not sim._storage_cell_has_floor(cell) or sim._storage_cell_has_blocking_structure(cell): continue
		var target := work_cell(sim, npc, cell)
		if target != Vector2i(-1, -1):
			return {"record": record.duplicate(true), "target_cell": [target.x, target.y]}
	return {}

static func borrow_tool(sim, npc: Dictionary, source: Dictionary, action_id: String) -> bool:
	if not String(npc.carried_instance_id).is_empty() or source.is_empty(): return false
	var record: Dictionary = source.get("record", {})
	if not sim.state.storage_items.has(record) or int(record.get("amount", 0)) != 1: return false
	var id := String(record.get("item_id", ""))
	if not sim.content.item_tool_supports(id, action_id): return false
	var instance: Dictionary = sim.get_item_instance(String(record.get("instance_id", "")))
	var location: Dictionary = instance.get("location", {})
	if instance.is_empty() or String(instance.item_id) != id or String(location.get("kind", "")) != "storage" or String(location.get("id", "")) != String(record.get("placement_id", "")): return false
	var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
	if sim._storage_zone_index_at_cell(cell) < 0 or not sim._storage_cell_has_floor(cell) or sim._storage_cell_has_blocking_structure(cell) or not nearby(sim, npc, cell): return false
	npc.carried_instance_id = String(instance.instance_id)
	sim.state.storage_items.erase(record)
	sim._set_instance_location(npc.carried_instance_id, "npc", String(npc.id))
	return true

static func borrow(sim, npc: Dictionary, source: Dictionary) -> bool:
	if not String(npc.carried_instance_id).is_empty() or source.is_empty():
		return false
	var record: Dictionary = source.record
	var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
	if not nearby(sim, npc, cell) or not sim.state.storage_items.has(record):
		return false
	var instance: Dictionary = sim.get_item_instance(String(record.get("instance_id", "")))
	if instance.is_empty() or String(instance.get("location", {}).get("kind", "")) != "storage":
		return false
	npc.carried_instance_id = String(instance.instance_id)
	sim.state.storage_items.erase(record)
	sim._set_instance_location(npc.carried_instance_id, "npc", String(npc.id))
	return true

static func cargo_size(npc: Dictionary) -> int:
	var count := 0
	for amount: Variant in npc.work_cargo.values():
		count += int(amount)
	return count

static func take_material(sim, npc: Dictionary, source: Dictionary, missing: int) -> bool:
	if source.is_empty():
		return false
	var record: Dictionary = source.record
	var cell := Vector2i(int(record.cell[0]), int(record.cell[1]))
	if not nearby(sim, npc, cell) or not sim.state.storage_items.has(record) or sim.content.item_is_instance_based(String(record.item_id)):
		return false
	var amount := mini(HomeStock.withdrawal_limit(sim,npc,String(record.item_id)), mini(missing, mini(int(record.amount), CARRY_LIMIT - cargo_size(npc))))
	if amount <= 0:
		return false
	npc.work_cargo[record.item_id] = int(npc.work_cargo.get(record.item_id, 0)) + amount
	record.amount = int(record.amount) - amount
	if int(record.amount) == 0:
		sim.state.storage_items.erase(record)
	return true

static func collect(sim, npc: Dictionary, drop: Dictionary) -> bool:
	var id := String(drop.get("item_id", ""))
	var pos: Array = drop.get("position", [])
	if pos.size() != 2 or sim.content.item_is_instance_based(id) or not sim.state.world_drops.has(drop):
		return false
	if sim.get_npc_position(String(npc.id), Vector2.ZERO).distance_to(Vector2(float(pos[0]), float(pos[1]))) > Content.INTERACTION_RANGE:
		return false
	var amount := mini(int(drop.amount), CARRY_LIMIT - cargo_size(npc))
	if amount <= 0:
		return false
	npc.work_cargo[id] = int(npc.work_cargo.get(id, 0)) + amount
	drop.amount = int(drop.amount) - amount
	if int(drop.amount) == 0:
		sim.state.world_drops.erase(drop)
	return true

# Adds to existing stacks without moving any warehouse placement.
static func store(sim, npc: Dictionary, cell: Vector2i, id: String, amount: int, instance_id: String = "") -> int:
	if not nearby(sim, npc, cell):
		return 0
	var remaining := amount
	var used: Dictionary = {}
	var next_index := 0
	var grid: Vector2i = sim.get_storage_grid_size(cell)
	for record: Dictionary in sim.state.storage_items:
		if record.cell != [cell.x, cell.y]:
			continue
		Placement.occupy(sim.content.item_footprint(String(record.item_id), int(record.rotation)), Vector2i(int(record.origin[0]), int(record.origin[1])), used, String(record.placement_id))
		if String(record.item_id) == id:
			next_index = maxi(next_index, int(record.stack_index) + 1)
			if instance_id.is_empty():
				var added := mini(remaining, sim.content.item_max_stack(id) - int(record.amount))
				record.amount = int(record.amount) + added
				remaining -= added
	while remaining > 0:
		var fit := Placement.find_first_fit(sim.content.item_footprint(id), used, grid.x, grid.y)
		var origin: Vector2i = fit.origin
		if origin == Placement.INVALID_ORIGIN:
			break
		var added := mini(remaining, sim.content.item_max_stack(id))
		var placement_id := "%s:%d" % [id, next_index]
		# Placement IDs are historically per-cell; instance registry uses the same contract.
		var record := {"cell": [cell.x, cell.y], "item_id": id, "amount": added,
			"origin": [origin.x, origin.y], "rotation": int(fit.rotation), "stack_index": next_index, "placement_id": placement_id}
		if not instance_id.is_empty():
			record.instance_id = instance_id
			sim._set_instance_location(instance_id, "storage", placement_id)
		sim.state.storage_items.append(record)
		Placement.occupy(sim.content.item_footprint(id, int(fit.rotation)), origin, used, placement_id)
		next_index += 1
		remaining -= added
	return amount - remaining

static func deposit_at(sim, npc: Dictionary, cell: Vector2i) -> void:
	# Put the borrowed shared tool back before filling remaining space with output.
	var instance := tool(sim, npc)
	if not instance.is_empty() and store(sim, npc, cell, String(instance.item_id), 1, String(instance.instance_id)) == 1:
		npc.carried_instance_id = ""
	for id: String in npc.work_cargo.keys():
		var amount := int(npc.work_cargo[id])
		var stored := store(sim, npc, cell, id, amount)
		npc.work_cargo[id] = amount - stored
		if int(npc.work_cargo[id]) == 0:
			npc.work_cargo.erase(id)

static func has_capacity(sim, cell: Vector2i, id: String) -> bool:
	var used: Dictionary = {}
	for record: Dictionary in sim.state.storage_items:
		if record.cell != [cell.x, cell.y]:
			continue
		if String(record.item_id) == id and not sim.content.item_is_instance_based(id) and int(record.amount) < sim.content.item_max_stack(id):
			return true
		Placement.occupy(sim.content.item_footprint(String(record.item_id), int(record.rotation)), Vector2i(int(record.origin[0]), int(record.origin[1])), used, String(record.placement_id))
	var grid: Vector2i = sim.get_storage_grid_size(cell)
	return Placement.find_first_fit(sim.content.item_footprint(id), used, grid.x, grid.y).origin != Placement.INVALID_ORIGIN

static func drop_remaining(sim, npc: Dictionary) -> void:
	var position: Vector2 = sim.get_npc_position(String(npc.id), Vector2.ZERO)
	for id: String in npc.work_cargo.keys():
		var ids: Array[String] = sim._create_resource_drops(String(npc.id), id, int(npc.work_cargo[id]), position)
		for drop: Dictionary in sim.state.world_drops:
			if ids.has(String(drop.drop_id)):
				drop.npc_recovery = true
	npc.work_cargo = {}
	var instance := tool(sim, npc)
	if not instance.is_empty():
		var serial := int(sim.state.next_drop_serial)
		sim.state.next_drop_serial = serial + 1
		var drop_id := "core:drop_%06d" % serial
		sim.state.world_drops.append({"drop_id": drop_id, "item_id": instance.item_id, "amount": 1,
			"position": [position.x, position.y], "source_id": String(npc.id), "instance_id": instance.instance_id,
			"npc_recovery": true, "expires_at_game_minute": sim.get_elapsed_game_minutes() + sim.WORLD_DROP_LIFETIME_MINUTES})
		sim._set_instance_location(String(instance.instance_id), "world_drop", drop_id)
	npc.carried_instance_id = ""
