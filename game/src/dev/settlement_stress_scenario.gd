extends RefCounted

# Debug-only settlement fixtures. The resulting state uses real housing,
# inventory placement, identities and work permissions; no NPC AI is replaced.
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Rooms := preload("res://src/dev/resident_homes_scenario.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Placement := preload("res://src/inventory/inventory_placement_rules.gd")
const Resources := preload("res://src/content/resource_node_catalog.gd")
const HOUSE_COUNT := 30
const COLUMNS := 6
const WAREHOUSE := Rect2i(34, 31, 16, 14)
const CLEARING := Rect2i(13, 30, 99, 86)
const MODES := ["full", "production", "gather"]
const TOOLS := ["core:axe", "core:pickaxe", "core:hoe", "core:bucket", "core:mallet"]

static func origin(index: int) -> Vector2i:
	return Vector2i(15 + (index % COLUMNS) * 16, 48 + (index / COLUMNS) * 14)

static func build(resident_count: int = HOUSE_COUNT, mode: String = "full") -> Dictionary:
	var started := Time.get_ticks_usec()
	if resident_count < 1 or resident_count > HOUSE_COUNT or not MODES.has(mode):
		return {"success": false, "message": "Invalid settlement stress configuration"}
	var initial := World.create_new_game_state()
	initial.day = 2
	initial.minute_of_day = 9 * 60
	initial.elapsed_game_minutes = 1980
	initial.flags.first_night_complete = true
	initial.flags.repair_stage = 2
	initial.structures.clear()
	initial.blueprints.clear()
	initial.storage_zones.clear()
	initial.storage_items.clear()
	initial.room_assignments.clear()
	initial.sleep_assignments = {"core:player": "core:starter_bedroll"}
	initial.item_instances = []
	initial.inventory = {}
	initial.inventory_layout = []
	initial.hotbar_slots = []
	initial.npcs["core:first_neighbor"].active = false
	# Keep generator-compatible counts and IDs while moving obstacles off the
	# settlement. Deleting nodes would cause legacy validation to regenerate them.
	_clear_foundations(initial)
	# A fixed thirty-house map also serves as the baseline with fewer occupants.
	for index: int in range(HOUSE_COUNT):
		var cell := origin(index)
		Rooms._add_room(initial, "core:room_%04d" % (index + 1), cell, Vector2i(6, 6))
		# Alternating complete homes and foundations exercise both comfort and goals.
		if index % 2 == 0 or mode == "gather":
			for furniture: Dictionary in [
				{"building_id": "core:table", "cell": [cell.x + 3, cell.y + 2]},
				{"building_id": "core:chair", "cell": [cell.x + 3, cell.y + 3]},
				{"building_id": "core:torch", "cell": [cell.x + 5, cell.y], "lit": true},
			]: initial.structures.append(furniture)
		for offset: int in range(2):
			initial.farming.beds.append({"cell": [cell.x + 2 + offset, cell.y + 8],
				"crop_id": ["carrot", "cabbage", "potato", "strawberry"][index % 4],
				"growth": 0.0, "wet_until": 0, "last_update": 1980, "harvests": 0})
	initial.next_room_serial = HOUSE_COUNT + 1
	var warehouse_cells: Array = []
	for y: int in range(WAREHOUSE.position.y, WAREHOUSE.end.y):
		for x: int in range(WAREHOUSE.position.x, WAREHOUSE.end.x):
			warehouse_cells.append([x, y])
			initial.structures.append({"building_id": "core:wood_floor", "cell": [x, y]})
	initial.storage_zones = [{"id": "core:storage_zone_0001", "cells": warehouse_cells}]
	initial.next_storage_zone_serial = 2
	for index: int in range(COLUMNS):
		initial.structures.append({"building_id": "core:workbench", "cell": [34 + index * 3, 43], "stage_id": "core:complete"})
	var player := Content.cell_center(32, 44)
	initial.player_position = [player.x, player.y]
	var sim := World.new(initial)
	if sim.state.storage_zones.is_empty() or sim.state.storage_zones[0].cells.size() < sim.content.item_ids().size() + HOUSE_COUNT * TOOLS.size():
		return {"success": false, "message": "Warehouse has insufficient valid cells"}
	var participants: Array[String] = []
	for index: int in range(resident_count):
		var cell := origin(index) + Vector2i(-2, 3)
		var id := "core:first_neighbor"
		if index > 0:
			var generated: Dictionary = sim.create_generated_npc(30000 + index, cell)
			if not bool(generated.get("ok", false)): return {"success": false, "message": "NPC generation failed"}
			id = String(generated.npc_id)
		if not bool(sim.state.npcs[id].active):
			if not bool(sim.arrive_npc(id, cell).get("ok", false)): return {"success": false, "message": "NPC arrival failed"}
		var npc: Dictionary = sim.state.npcs[id]
		var arrival := Content.cell_center(cell.x, cell.y)
		npc.position = [arrival.x, arrival.y]
		npc.target_cell = [cell.x, cell.y]
		npc.known = true
		if not bool(sim.set_npc_resident(id, true).get("ok", false)): return {"success": false, "message": "Resident admission failed"}
		npc.personal_inventory = {}
		npc.needs = {"hunger": 58.0 + float(index % 11) * 3.0,
			"energy": 85.0 + float(index % 4) * 4.0, "restedness": 80.0 + float(index % 5) * 4.0}
		var bed := origin(index)
		if not bool(sim.assign_sleep_place(id, "core:bedroll@%d,%d" % [bed.x, bed.y]).get("success", false)):
			return {"success": false, "message": "Personal bed assignment failed"}
		for kind: String in ["water", "gather", "build"]:
			sim.set_npc_work_enabled(id, kind, true)
		# Stagger normal decisions, but preserve deterministic personality choices.
		npc.next_initiative_minute = 1980 + index % 15
		participants.append(id)
	# Nonconsumable tools form a real shared pool; borrowing never clones a tool.
	var slot := sim.content.item_ids().size()
	for tool_id: String in TOOLS:
		for _index: int in range(HOUSE_COUNT):
			var cell := warehouse_cell(sim, slot)
			slot += 1
			var ids: Array[String] = sim._create_item_instances(tool_id, 1, "inventory", "", {"charges": 2} if tool_id == "core:bucket" else {})
			if _store(sim, cell, tool_id, 1, ids[0]) != 1:
				return {"success": false, "message": "Tool pool does not fit warehouse"}
	replenish(sim, mode)
	return {"success": true, "simulation": sim, "state": sim.export_state(),
		"participants": participants, "mode": mode, "houses": HOUSE_COUNT,
		"build_ms": float(Time.get_ticks_usec() - started) / 1000.0}

static func warehouse_cell(sim, index: int) -> Vector2i:
	var raw: Array = sim.state.storage_zones[0].cells[index]
	return Vector2i(int(raw[0]), int(raw[1]))

static func replenish(sim, mode: String = "full") -> bool:
	var changed := false
	var index := 0
	for item_id: String in sim.content.item_ids():
		var cell := warehouse_cell(sim, index)
		index += 1
		if sim.content.item_is_instance_based(item_id): continue
		if mode != "full" and item_id == "core:plank": continue
		if mode == "gather" and item_id in ["core:wood", "core:stone"]: continue
		# Top up only existing real stacks; refill holes using normal footprint rules.
		var amount := 0
		var used: Dictionary = {}
		for record: Dictionary in sim.state.storage_items:
			if record.cell != [cell.x, cell.y]: continue
			Placement.occupy(sim.content.item_footprint(String(record.item_id), int(record.rotation)), Vector2i(int(record.origin[0]), int(record.origin[1])), used, String(record.placement_id))
			if String(record.item_id) == item_id:
				if int(record.amount) != sim.content.item_max_stack(item_id):
					record.amount = sim.content.item_max_stack(item_id)
					changed = true
				amount += int(record.amount)
		var added := 0
		if Placement.find_first_fit(sim.content.item_footprint(item_id), used, 3, 3).origin != Placement.INVALID_ORIGIN:
			added = _store(sim, cell, item_id, sim.content.item_max_stack(item_id) * 9 - amount)
		changed = added > 0 or changed
	return changed

static func _clear_foundations(state: Dictionary) -> void:
	var used: Dictionary = {}
	for key: String in ["resource_nodes", "tree_nodes"]:
		for node: Dictionary in state[key]:
			var cell := Vector2i(int(node.cell[0]), int(node.cell[1]))
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]: used[cell + offset] = true
	for key: String in ["resource_nodes", "tree_nodes"]:
		for node: Dictionary in state[key]:
			if not CLEARING.has_point(Vector2i(int(node.cell[0]), int(node.cell[1]))): continue
			var chosen := Vector2i(-1, -1)
			for y: int in range(2, 126, 2):
				for x: int in range(10, 126, 2):
					var candidate := Vector2i(x, y)
					if not CLEARING.has_point(candidate) and not used.has(candidate) and not Resources.is_reserved_cell(candidate):
						chosen = candidate
						break
				if chosen.x >= 0: break
			if chosen.x < 0:
				push_error("No free border cell for stress fixture resource")
				return
			node.cell = [chosen.x, chosen.y]
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]: used[chosen + offset] = true
	for bush: Dictionary in Resources.generate_berry_bushes(int(state.seed), state.resource_nodes, state.tree_nodes, int(state.resource_generation_version)):
		if CLEARING.has_point(Vector2i(int(bush.cell[0]), int(bush.cell[1]))): state.removed_bushes[String(bush.id)] = true

static func _store(sim, cell: Vector2i, item_id: String, amount: int, instance_id: String = "") -> int:
	if amount <= 0: return 0
	# Administrative fixture placement still uses the real packing contract.
	var actor: Dictionary = sim.state.npcs["core:first_neighbor"]
	var saved: Array = actor.position.duplicate()
	var position := Content.cell_center(cell.x, cell.y)
	actor.position = [position.x, position.y]
	var stored := Supply.store(sim, actor, cell, item_id, amount, instance_id)
	actor.position = saved
	return stored
