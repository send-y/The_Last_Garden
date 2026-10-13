extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func execute_construction_command(sim, command: Dictionary) -> Dictionary:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	var farming: FarmingSystem = sim.farming
	var action_id: String = String(command.get("action_id", ""))
	if action_id == ConstructionCommandScript.ACTION_CANCEL_BLUEPRINT:
		return sim._execute_cancel_blueprint(command)

	if action_id == ConstructionCommandScript.ACTION_DELIVER_MATERIALS:
		return sim._execute_deliver_blueprint_materials(command)

	if action_id == ConstructionCommandScript.ACTION_WORK_BLUEPRINT:
		return sim._execute_work_blueprint(command)

	if action_id == ConstructionCommandScript.ACTION_COMPLETE_BLUEPRINT:
		return sim._execute_complete_blueprint(command)

	var actor_id := String(command.get("actor_id",""))
	if actor_id != PLAYER_ACTOR_ID and not sim.NpcHomeProjects.can_place_command(sim,command):
		return {"success":false,"changed":false,"reason_id":"core:unknown_actor"}
	var validation: Dictionary = ConstructionValidatorScript.validate_place_blueprint(command,[],actor_id)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var building_id: String = String(validation.get("building_id", ""))
	for farm_cell: Vector2i in building_catalog.get_footprint_cells(building_id, Vector2i(int(cell_data[0]), int(cell_data[1]))):
		if not farming.bed_at(sim, farm_cell).is_empty():
			return {"success": false, "changed": false, "reason_id": "core:occupied_cell"}
	if not building_catalog.is_floor(building_id):
		var blueprint_origin := Vector2i(int(cell_data[0]), int(cell_data[1]))
		for occupied_cell: Vector2i in building_catalog.get_footprint_cells(
			building_id, blueprint_origin
		):
			if sim.housing.is_starter_cell(occupied_cell):
				return {"success": false, "changed": false, "reason_id": "core:occupied_cell"}
			if sim._storage_zone_index_at_cell(occupied_cell) >= 0:
				return {
					"success": false,
					"changed": false,
					"reason_id": "core:room_storage_furniture_forbidden",
				}
	if not sim._building_allowed_in_assigned_rooms(building_id, cell_data):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:room_storage_furniture_forbidden",
		}
	var layer_id: String = building_catalog.get_layer_id(building_id)
	for blueprint_value: Variant in (state["blueprints"] as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var existing: Dictionary = blueprint_value as Dictionary
		if (
			building_catalog.get_layer_id(
				String(existing.get("building_id", ""))
			) == layer_id
			and sim._building_footprints_overlap(
			building_id,
			cell_data,
			String(existing.get("building_id", "")),
			existing.get("cell", []) as Array
			)
		):
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}

	var footprint: Array[Vector2i] = building_catalog.get_footprint_cells(building_id,Vector2i(int(cell_data[0]),int(cell_data[1])))
	for structure_value: Variant in sim.structure_index.in_cells(footprint):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue

		var existing_structure: Dictionary = structure_value as Dictionary
		if (
			building_catalog.get_layer_id(
				String(existing_structure.get("building_id", ""))
			) == layer_id
			and sim._building_footprints_overlap(
				building_id,
				cell_data,
				String(existing_structure.get("building_id", "")),
				existing_structure.get("cell", []) as Array
			)
		):
			return {
				"success": false,
				"changed": false,
				"reason_id": "core:occupied_cell",
			}
	var material_cost: Dictionary = building_catalog.get_material_cost(building_id)
	var required_work_minutes: int = building_catalog.get_work_minutes(building_id)

	if material_cost.is_empty() or required_work_minutes <= 0:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:invalid_building",
		}

	var delivered_materials: Dictionary = {}
	for item_variant: Variant in material_cost.keys():
		delivered_materials[String(item_variant)] = 0

	var blueprint: Dictionary = {
		"building_id": building_id,
		"cell": cell_data.duplicate(),
		"stage_id": BLUEPRINT_STAGE_ID,
		"required_materials": material_cost.duplicate(true),
		"delivered_materials": delivered_materials,
		"required_work_minutes": required_work_minutes,
		"work_progress_minutes": 0,
	}
	(state["blueprints"] as Array).append(blueprint)
	sim.event_emitted.emit({"type": "state_changed"})

	return {
		"success": true,
		"changed": true,
		"reason_id": "core:blueprint_placed",
		"blueprint": blueprint.duplicate(true),
	}


static func _execute_cancel_blueprint(sim, command: Dictionary) -> Dictionary:
	var state: Dictionary = sim.state
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_cancel_blueprint(command)
	)

	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var blueprints: Array = state["blueprints"] as Array

	for index: int in range(blueprints.size()):
		var blueprint_value: Variant = blueprints[index]
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var blueprint: Dictionary = blueprint_value as Dictionary
		if not sim._entity_occupies_cell(blueprint, cell_data):
			continue
		var blueprint_anchor: Array = blueprint.get("cell", []) as Array

		var returned_materials: Dictionary = (
			blueprint.get("delivered_materials", {}) as Dictionary
		).duplicate(true)
		var dropped_materials: Dictionary = sim._return_cancelled_materials(
			returned_materials,
			Vector2i(int(blueprint_anchor[0]), int(blueprint_anchor[1]))
		)
		blueprints.remove_at(index)
		sim.event_emitted.emit({"type": "state_changed"})

		return {
			"success": true,
			"changed": true,
			"reason_id": "core:blueprint_cancelled",
			"cell": blueprint_anchor.duplicate(),
			"returned_materials": returned_materials,
			"dropped_materials": dropped_materials,
		}

	return {
		"success": false,
		"changed": false,
		"reason_id": "core:missing_blueprint",
	}


static func _execute_deliver_blueprint_materials(sim, command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_deliver_materials(command)
	)
	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var blueprint: Dictionary = sim._find_blueprint(cell_data)
	if blueprint.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:missing_blueprint",
		}

	var target_position := FirstNightContent.cell_center(
		int(cell_data[0]),
		int(cell_data[1])
	)
	if sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:too_far",
		}

	if sim._blueprint_has_all_materials(blueprint):
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:materials_already_delivered",
		}

	var inventory: Dictionary = sim._inventory_mutable()
	var transfer: Dictionary = sim._calculate_material_transfer(blueprint, inventory)
	if transfer.is_empty():
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:required_materials_missing",
		}

	sim._apply_material_transfer(blueprint, inventory, transfer)
	var transferred_total: int = 0
	for amount_value: Variant in transfer.values():
		transferred_total += int(amount_value)
	sim.event_emitted.emit({"type": "state_changed"})
	return {
		"success": true,
		"changed": true,
		"reason_id": "core:materials_delivered",
		"cell": cell_data.duplicate(),
		"transferred_materials": transfer.duplicate(true),
		"transferred_total": transferred_total,
		"materials_ready": sim._blueprint_has_all_materials(blueprint),
		"blueprint": blueprint.duplicate(true),
	}


static func _execute_work_blueprint(sim, command: Dictionary) -> Dictionary:
	var validation: Dictionary = (
		ConstructionValidatorScript.validate_work_blueprint(command)
	)
	if not bool(validation.get("success", false)):
		var rejected: Dictionary = validation.duplicate(true)
		rejected["changed"] = false
		return rejected

	var cell_data: Array = validation.get("cell", []) as Array
	var target_position := FirstNightContent.cell_center(
		int(cell_data[0]),
		int(cell_data[1])
	)
	if sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return {
			"success": false,
			"changed": false,
			"reason_id": "core:too_far",
		}

	# Work cannot be combined with an ongoing chair rest.
	if not sim.actor_tool_supports(PLAYER_ACTOR_ID, "build"):
		return {"success":false,"changed":false,"reason_id":"core:construction_tool_not_selected"}
	if not sim.prepare_player_work() or sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return {"success":false,"changed":false,"reason_id":"core:too_far"}
	var result: Dictionary = sim._advance_blueprint_work(cell_data)
	if bool(result.get("success", false)):
		sim._spend_player_work_energy()
	if bool(result.get("changed", false)):
		sim.event_emitted.emit({"type": "state_changed"})
	return result
