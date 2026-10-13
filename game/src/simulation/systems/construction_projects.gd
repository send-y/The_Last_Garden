extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func _sync_structure_navigation(sim) -> void:
	var state: Dictionary = sim.state
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	var building_catalog: BuildingCatalog = sim.building_catalog
	var structure_cells: Array[Vector2i] = []
	# Match solid resource bodies conservatively on the NPC's cell grid.
	# Tree trunks are below their sprite origin; wide boulders span three cells.
	for target: Dictionary in sim.get_surface_trees():
		if String(target.get("presentation_id", "")) != "surface_tree":
			continue
		var cell: Vector2i = sim._world_position_to_cell(target.position)
		structure_cells.append(cell)
		structure_cells.append(cell + Vector2i.DOWN)
	for target: Dictionary in sim.get_surface_boulders():
		if sim.is_collected(String(target.id)):
			continue
		var cell: Vector2i = sim._world_position_to_cell(target.position)
		structure_cells.append_array([cell + Vector2i.LEFT, cell, cell + Vector2i.RIGHT])

	for structure_value: Variant in (state["structures"] as Array):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var structure: Dictionary = structure_value as Dictionary
		var cell_data: Array = structure.get("cell", []) as Array
		if cell_data.size() != 2:
			continue
		var definition := building_catalog.get_definition(
			String(structure.get("building_id", ""))
		)
		if not bool(definition.get("blocks_movement", false)):
			continue
		var origin := Vector2i(int(cell_data[0]), int(cell_data[1]))
		structure_cells.append_array(building_catalog.get_footprint_cells(
			String(structure.get("building_id", "")), origin
		))

	npc_autonomy.set_structure_cells(structure_cells)


static func _get_blueprint_cells(sim) -> Array[Vector2i]:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	var result: Array[Vector2i] = []
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue
		var cell_data: Array = (blueprint_value as Dictionary).get("cell", []) as Array
		if cell_data.size() != 2:
			continue
		result.append_array(building_catalog.get_footprint_cells(
			String((blueprint_value as Dictionary).get("building_id", "")),
			Vector2i(int(cell_data[0]), int(cell_data[1]))
		))
	return result


static func _is_actor_in_cell(sim, cell_data: Array) -> bool:
	var target_cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
	if _world_position_to_cell(sim.get_player_position()) == target_cell:
		return true

	for npc_value: Variant in sim._npcs_mutable().values():
		if typeof(npc_value) != TYPE_DICTIONARY:
			continue

		var npc: Dictionary = npc_value as Dictionary
		if not bool(npc.get("active", false)):
			continue

		var position_data: Array = npc.get("position", []) as Array
		if position_data.size() < 2:
			continue
		var npc_position := Vector2(
			float(position_data[0]),
			float(position_data[1])
		)
		if _world_position_to_cell(npc_position) == target_cell:
			return true

	return false


static func _is_actor_in_blueprint(sim, blueprint: Dictionary) -> bool:
	var building_catalog: BuildingCatalog = sim.building_catalog
	var cells := building_catalog.get_footprint_cells(
		String(blueprint.get("building_id", "")),
		Vector2i(
			int((blueprint.get("cell", []) as Array)[0]),
			int((blueprint.get("cell", []) as Array)[1])
		)
	)
	for cell: Vector2i in cells:
		if sim._is_actor_in_cell([cell.x, cell.y]):
			return true
	return false


static func _entity_occupies_cell(sim, entity: Dictionary, cell_data: Array) -> bool:
	var building_catalog: BuildingCatalog = sim.building_catalog
	if cell_data.size() != 2:
		return false
	var entity_cell: Array = entity.get("cell", []) as Array
	if entity_cell.size() != 2:
		return false
	var occupied := Vector2i(int(cell_data[0]), int(cell_data[1]))
	var origin := Vector2i(int(entity_cell[0]), int(entity_cell[1]))
	return building_catalog.get_footprint_cells(
		String(entity.get("building_id", "")), origin
	).has(occupied)


static func _building_footprints_overlap(sim,
	first_building_id: String,
	first_cell: Array,
	second_building_id: String,
	second_cell: Array
) -> bool:
	var building_catalog: BuildingCatalog = sim.building_catalog
	if first_cell.size() != 2 or second_cell.size() != 2:
		return false
	var occupied: Dictionary = {}
	for cell: Vector2i in building_catalog.get_footprint_cells(
		first_building_id, Vector2i(int(first_cell[0]), int(first_cell[1]))
	):
		occupied[cell] = true
	for cell: Vector2i in building_catalog.get_footprint_cells(
		second_building_id, Vector2i(int(second_cell[0]), int(second_cell[1]))
	):
		if occupied.has(cell):
			return true
	return false


static func _blueprint_has_all_materials(sim, blueprint: Dictionary) -> bool:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in required.keys():
		var item_id: String = String(item_variant)
		if int(delivered.get(item_id, 0)) < int(required[item_variant]):
			return false
	return not required.is_empty()


static func _calculate_material_transfer(sim,
	blueprint: Dictionary,
	source_inventory: Dictionary
) -> Dictionary:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	var transfer: Dictionary = {}
	var item_ids: Array[String] = []
	for item_variant: Variant in required.keys():
		item_ids.append(String(item_variant))
	item_ids.sort()
	for item_id: String in item_ids:
		var missing: int = maxi(
			0,
			int(required.get(item_id, 0)) - int(delivered.get(item_id, 0))
		)
		var amount: int = mini(missing, maxi(0, int(source_inventory.get(item_id, 0))))
		if amount > 0:
			transfer[item_id] = amount
	return transfer


static func _transfer_completes_blueprint(sim,
	blueprint: Dictionary,
	transfer: Dictionary
) -> bool:
	var required: Dictionary = blueprint.get("required_materials", {}) as Dictionary
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in required.keys():
		var item_id: String = String(item_variant)
		if (
			int(delivered.get(item_id, 0)) + int(transfer.get(item_id, 0))
			< int(required[item_variant])
		):
			return false
	return not required.is_empty()


static func _apply_material_transfer(sim,
	blueprint: Dictionary,
	source_inventory: Dictionary,
	transfer: Dictionary
) -> void:
	var delivered: Dictionary = blueprint.get("delivered_materials", {}) as Dictionary
	for item_variant: Variant in transfer.keys():
		var item_id: String = String(item_variant)
		var amount: int = int(transfer[item_variant])
		source_inventory[item_id] = maxi(
			0,
			int(source_inventory.get(item_id, 0)) - amount
		)
		delivered[item_id] = int(delivered.get(item_id, 0)) + amount
	blueprint["delivered_materials"] = delivered


static func _add_items_to_inventory(sim, items: Dictionary, target_inventory: Dictionary) -> void:
	for item_variant: Variant in items.keys():
		var item_id: String = String(item_variant)
		var amount: int = maxi(0, int(items[item_variant]))
		target_inventory[item_id] = int(target_inventory.get(item_id, 0)) + amount


static func _return_cancelled_materials(sim,
	materials: Dictionary,
	blueprint_cell: Vector2i
) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var dropped: Dictionary = {}
	var drop_position := FirstNightContent.cell_center(blueprint_cell.x, blueprint_cell.y)
	var map_pixels := Vector2(FirstNightContent.MAP_SIZE) * FirstNightContent.CELL_SIZE
	drop_position.x = clampf(drop_position.x, 8.0, map_pixels.x - 8.0)
	drop_position.y = clampf(drop_position.y, 8.0, map_pixels.y - 8.0)
	for item_variant: Variant in materials.keys():
		var item_id := content.normalize_item_id(String(item_variant))
		var amount := maxi(0, _safe_int(materials[item_variant], 0))
		if amount <= 0 or not content.has_item(item_id):
			continue
		var low := 0
		var high := amount
		var best_layout: Array = state.get("inventory_layout", []) as Array
		while low < high:
			var candidate_amount := (low + high + 1) / 2
			var candidate_inventory: Dictionary = sim.get_inventory()
			candidate_inventory[item_id] = int(candidate_inventory.get(item_id, 0)) + candidate_amount
			var candidate_pack := InventoryPackerScript.pack_with_layout(
				candidate_inventory,
				content,
				state.get("inventory_layout", []) as Array,
				4,
				4
			)
			if (candidate_pack.get("overflow", {}) as Dictionary).is_empty():
				low = candidate_amount
				best_layout = candidate_pack.get("layout", [])
			else:
				high = candidate_amount - 1
		if low > 0:
			sim._add_item(item_id, low)
			if best_layout.is_empty():
				best_layout = InventoryPackerScript.pack_with_layout(
					sim.get_inventory(),
					content,
					state.get("inventory_layout", []) as Array,
					4,
					4
				).get("layout", [])
			state["inventory_layout"] = best_layout
		var overflow_amount := amount - low
		if overflow_amount > 0:
			dropped[item_id] = overflow_amount
			sim._create_resource_drops(
				"core:construction_cancellation",
				item_id,
				overflow_amount,
				drop_position
			)
	return dropped


static func _advance_blueprint_work(sim, cell_data: Array, actor_id: String = PLAYER_ACTOR_ID) -> Dictionary:
	var blueprint: Dictionary = sim._find_blueprint(cell_data)
	if blueprint.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:missing_blueprint",
		}
	if not sim._blueprint_has_all_materials(blueprint):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:required_materials_missing",
		}
	if not sim.actor_tool_supports(actor_id, "build"):
		return {"success":false,"changed":false,"reason_id":"core:construction_tool_not_selected"}
	if actor_id != PLAYER_ACTOR_ID and not sim.NpcHomeProjects.safe_to_build(sim,blueprint):
		return {"success":false,"changed":false,"reason_id":"core:npc_project_unsafe"}
	if sim._is_actor_in_blueprint(blueprint):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:occupied_by_actor",
		}

	var required_work: int = maxi(
		1,
		int(blueprint.get("required_work_minutes", 1))
	)
	var current_work: float = preload("res://src/items/tool_work_progress.gd").normalize(blueprint.get("work_progress_minutes", 0), required_work)
	var tool: Dictionary = sim.get_actor_tool(actor_id)
	var next_work: float = minf(current_work + sim.content.item_tool_work_rate(String(tool.get("item_id", ""))), float(required_work))
	blueprint["work_progress_minutes"] = preload("res://src/items/tool_work_progress.gd").stored(next_work)
	if next_work < required_work:
		return {
			"success": true,
			"changed": true,
			"reason_id": "core:construction_work_progressed",
			"cell": cell_data.duplicate(),
			"work_progress_minutes": next_work,
			"required_work_minutes": required_work,
			"blueprint": blueprint.duplicate(true),
		}

	var completion: Dictionary = sim._complete_blueprint_at_cell(cell_data)
	completion["work_progress_minutes"] = required_work
	completion["required_work_minutes"] = required_work
	return completion


static func _execute_complete_blueprint(sim, command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_complete_blueprint(command)
	)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var target_blueprint: Dictionary = sim._find_blueprint(cell_data)
	if not target_blueprint.is_empty() and sim._is_actor_in_blueprint(target_blueprint):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:occupied_by_actor",
		}

	var result: Dictionary = sim._complete_blueprint_at_cell(cell_data)
	if bool(result.get("changed", false)):
		sim.event_emitted.emit({"type": "state_changed"})
	return result


static func _complete_blueprint_at_cell(sim, cell_data: Array) -> Dictionary:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	var structures: Array = state["structures"] as Array
	var target_blueprint: Dictionary = sim._find_blueprint(cell_data)
	if target_blueprint.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:missing_blueprint",
		}
	var building_id := String(target_blueprint.get("building_id", ""))
	var anchor_cell: Array = target_blueprint.get("cell", []) as Array
	var layer_id := building_catalog.get_layer_id(building_id)

	for structure_value: Variant in structures:
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var existing_structure: Dictionary = structure_value as Dictionary
		if (
			building_catalog.get_layer_id(
				String(existing_structure.get("building_id", ""))
			) == layer_id
			and sim._building_footprints_overlap(building_id,
				anchor_cell,
				String(existing_structure.get("building_id", "")),
				existing_structure.get("cell", []) as Array
			)
		):
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}

	var blueprints: Array = state["blueprints"] as Array
	for index: int in range(blueprints.size()):
		var blueprint_value: Variant = blueprints[index]
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var current_blueprint: Dictionary = blueprint_value as Dictionary
		if current_blueprint != target_blueprint:
			continue
		if not sim._blueprint_has_all_materials(current_blueprint):
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:required_materials_missing",
			}

		var structure: Dictionary = {
			"building_id": String(current_blueprint.get("building_id", "")),
			"cell": anchor_cell.duplicate(),
			"stage_id": COMPLETE_STAGE_ID,
		}

		if building_id == "core:wood_door": structure["open"] = false
		blueprints.remove_at(index)
		sim.add_structure(structure)
		sim._sync_structure_navigation()

		return {
			"success": true,
			"changed": true,
			"reason_id": "core:structure_completed",
			"building_id": building_id,
			"structure": structure.duplicate(true),
		}

	return {
		"success": false,
		"changed": false,
		"reason_id": "core:missing_blueprint",
	}


static func _find_blueprint(sim, cell_data: Array) -> Dictionary:
	var state: Dictionary = sim.state
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue
		var blueprint: Dictionary = blueprint_value as Dictionary
		if sim._entity_occupies_cell(blueprint, cell_data):
			return blueprint
	return {}


static func get_blueprints(sim) -> Array:
	var state: Dictionary = sim.state
	return (state.get("blueprints", []) as Array).duplicate(true)


static func get_structures(sim) -> Array:
	var state: Dictionary = sim.state
	return (state.get("structures", []) as Array).duplicate(true)


static func is_navigation_cell_walkable(sim, cell: Vector2i) -> bool:
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	return npc_autonomy.is_cell_walkable(cell)


static func _find_structure(sim, cell_data: Array) -> Dictionary:
	var building_catalog: BuildingCatalog = sim.building_catalog
	var fallback: Dictionary = {}
	for structure_value: Variant in sim.structure_index.at(Vector2i(int(cell_data[0]),int(cell_data[1]))):
		if typeof(structure_value) == TYPE_DICTIONARY:
			var structure := structure_value as Dictionary
			if not sim._entity_occupies_cell(structure, cell_data):
				continue
			if fallback.is_empty():
				fallback = structure
			var definition := building_catalog.get_definition(
				String(structure.get("building_id", ""))
			)
			if not String(definition.get("station_type", "")).is_empty():
				return structure
			if not building_catalog.is_floor(String(structure.get("building_id", ""))):
				fallback = structure
	return fallback
