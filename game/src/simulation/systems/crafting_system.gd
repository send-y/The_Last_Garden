extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func execute_crafting_command(sim, command: Dictionary) -> Dictionary:
	var building_catalog: BuildingCatalog = sim.building_catalog
	if String(command.get("actor_id", "")) != PLAYER_ACTOR_ID:
		return _crafting_failure("core:unknown_actor")
	var cell_value: Variant = command.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
		return _crafting_failure("core:invalid_cell")
	var cell_data := cell_value as Array
	if typeof(cell_data[0]) != TYPE_INT or typeof(cell_data[1]) != TYPE_INT:
		return _crafting_failure("core:invalid_cell")
	var target_position := FirstNightContent.cell_center(
		int(cell_data[0]), int(cell_data[1])
	)
	if sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return _crafting_failure("core:too_far")
	var structure: Dictionary = sim._find_structure(cell_data)
	if structure.is_empty():
		return _crafting_failure("core:missing_station")
	var building: Dictionary = building_catalog.get_definition(
		String(structure.get("building_id", ""))
	)
	var station_type := String(building.get("station_type", ""))
	if station_type.is_empty():
		return _crafting_failure("core:invalid_station")
	cell_data = structure.get("cell", []) as Array
	target_position = FirstNightContent.cell_center(int(cell_data[0]), int(cell_data[1]))

	var action_id := String(command.get("action_id", ""))
	if action_id == CraftingCommandScript.ACTION_START_PROJECT:
		return sim._start_crafting_project(cell_data,
			station_type,
			String(command.get("recipe_id", ""))
		)
	if action_id == CraftingCommandScript.ACTION_WORK_PROJECT:
		return sim._advance_crafting_project(cell_data, target_position)
	return _crafting_failure("core:unsupported_action")


static func _start_crafting_project(sim,
	cell_data: Array,
	station_type: String,
	recipe_id: String
) -> Dictionary:
	var state: Dictionary = sim.state
	var crafting_catalog: CraftingCatalog = sim.crafting_catalog
	if not sim._find_crafting_project(cell_data).is_empty():
		return _crafting_failure("core:station_busy")
	var recipe: Dictionary = crafting_catalog.get_definition(recipe_id)
	if recipe.is_empty() or String(recipe.get("station_type", "")) != station_type:
		return _crafting_failure("core:invalid_recipe")
	var inputs: Dictionary = crafting_catalog.get_inputs(recipe_id)
	var outputs: Dictionary = crafting_catalog.get_outputs(recipe_id)
	var required_work: int = crafting_catalog.get_work_minutes(recipe_id)
	if inputs.is_empty() or outputs.is_empty() or required_work <= 0:
		return _crafting_failure("core:invalid_recipe")
	var inventory: Dictionary = sim._inventory_mutable()
	for item_variant: Variant in inputs.keys():
		var item_id := String(item_variant)
		if int(inventory.get(item_id, 0)) < int(inputs[item_variant]):
			return _crafting_failure("core:required_materials_missing")
	for item_variant: Variant in inputs.keys():
		var item_id := String(item_variant)
		inventory[item_id] = int(inventory.get(item_id, 0)) - int(inputs[item_variant])
	var project: Dictionary = {
		"cell": cell_data.duplicate(),
		"recipe_id": recipe_id,
		"reserved_inputs": inputs.duplicate(true),
		"required_work_minutes": required_work,
		"work_progress_minutes": 0,
	}
	(state["crafting_projects"] as Array).append(project)
	sim.event_emitted.emit({"type": "state_changed"})
	return {
		"success": true,
		"changed": true,
		"reason_id": "core:crafting_project_started",
		"project": project.duplicate(true),
	}


static func _advance_crafting_project(sim, cell_data: Array, target_position: Vector2) -> Dictionary:
	var state: Dictionary = sim.state
	var crafting_catalog: CraftingCatalog = sim.crafting_catalog
	var project: Dictionary = sim._find_crafting_project(cell_data)
	if project.is_empty():
		return _crafting_failure("core:missing_crafting_project")
	if not String(project.get("owner_id", "")).is_empty():
		return _crafting_failure("core:station_busy")
	if not sim.prepare_player_work() or sim.get_player_position().distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return _crafting_failure("core:too_far")
	sim._spend_player_work_energy()
	var required_work := maxi(1, int(project.get("required_work_minutes", 1)))
	var next_work := mini(
		int(project.get("work_progress_minutes", 0)) + 1,
		required_work
	)
	project["work_progress_minutes"] = next_work
	if next_work < required_work:
		sim.event_emitted.emit({"type": "state_changed"})
		return {
			"success": true,
			"changed": true,
			"reason_id": "core:crafting_work_progressed",
			"work_progress_minutes": next_work,
			"required_work_minutes": required_work,
		}
	var recipe_id := String(project.get("recipe_id", ""))
	var outputs: Dictionary = crafting_catalog.get_outputs(recipe_id)
	var drop_origin: Vector2 = sim._get_crafting_drop_origin(target_position)
	var created_drop_ids: Array[String] = []
	for item_variant: Variant in outputs.keys():
		created_drop_ids.append_array(sim._create_resource_drops(
			"crafting:%s" % recipe_id,
			String(item_variant),
			int(outputs[item_variant]),
			drop_origin
		))
	var projects: Array = state["crafting_projects"] as Array
	for index: int in range(projects.size()):
		if projects[index] == project:
			projects.remove_at(index)
			break
	sim.event_emitted.emit({"type": "state_changed"})
	return {
		"success": true,
		"changed": true,
		"reason_id": "core:crafting_completed",
		"recipe_id": recipe_id,
		"created_drop_ids": created_drop_ids,
		"work_progress_minutes": required_work,
		"required_work_minutes": required_work,
	}


static func _get_crafting_drop_origin(sim, station_position: Vector2) -> Vector2:
	var station_cell := _world_position_to_cell(station_position)
	var offsets: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 0),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	for offset: Vector2i in offsets:
		var cell := station_cell + offset
		if sim.is_navigation_cell_walkable(cell) and not sim._world_cell_blocks_storage(cell):
			return FirstNightContent.cell_center(cell.x, cell.y)
	return sim.get_player_position()


static func get_crafting_projects(sim) -> Array:
	var state: Dictionary = sim.state
	return (state.get("crafting_projects", []) as Array).duplicate(true)


static func get_crafting_recipes(sim, station_type: String) -> Array[Dictionary]:
	var crafting_catalog: CraftingCatalog = sim.crafting_catalog
	return crafting_catalog.recipes_for_station(station_type)


static func _normalize_crafting_projects(sim,
	value: Variant,
	structures: Array[Dictionary]
) -> Array[Dictionary]:
	var content: FirstNightContent = sim.content
	var building_catalog: BuildingCatalog = sim.building_catalog
	var crafting_catalog: CraftingCatalog = sim.crafting_catalog
	var normalized: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return normalized
	var stations: Dictionary = {}
	for structure: Dictionary in structures:
		var building := building_catalog.get_definition(
			String(structure.get("building_id", ""))
		)
		var station_type := String(building.get("station_type", ""))
		if station_type.is_empty():
			continue
		var building_id := String(structure.get("building_id", ""))
		var raw_origin := structure.get("cell", []) as Array
		if raw_origin.size() != 2:
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		for footprint_cell: Vector2i in building_catalog.get_footprint_cells(building_id, origin):
			stations[_construction_cell_key([footprint_cell.x, footprint_cell.y])] = {
				"station_type": station_type,
				"anchor": [origin.x, origin.y],
			}
	var occupied: Dictionary = {}
	for project_value: Variant in value as Array:
		if typeof(project_value) != TYPE_DICTIONARY:
			continue
		var project := project_value as Dictionary
		var cell_value: Variant = project.get("cell", [])
		if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
			continue
		var cell_data := cell_value as Array
		if not _is_whole_number(cell_data[0]) or not _is_whole_number(cell_data[1]):
			continue
		var normalized_cell: Array = [int(cell_data[0]), int(cell_data[1])]
		var clicked_cell_key := _construction_cell_key(normalized_cell)
		if not stations.has(clicked_cell_key):
			continue
		var station_data := stations[clicked_cell_key] as Dictionary
		var cell_key := _construction_cell_key(station_data.anchor as Array)
		if occupied.has(cell_key):
			var duplicate_recipe := String(project.get("recipe_id", ""))
			var duplicate_inputs: Dictionary = project.get(
				"reserved_inputs",
				crafting_catalog.get_inputs(duplicate_recipe)
			) as Dictionary
			for item_variant: Variant in duplicate_inputs.keys():
				var item_id := content.normalize_item_id(String(item_variant))
				var amount := maxi(0, _safe_int(duplicate_inputs[item_variant], 0))
				if amount > 0 and content.has_item(item_id):
					sim._create_resource_drops(
						"core:crafting_recovery",
						item_id,
						amount,
						FirstNightContent.cell_center(int((station_data.anchor as Array)[0]), int((station_data.anchor as Array)[1]))
					)
			continue
		var recipe_id := String(project.get("recipe_id", ""))
		var recipe := crafting_catalog.get_definition(recipe_id)
		if recipe.is_empty() or String(recipe.get("station_type", "")) != String(station_data.station_type):
			continue
		var required_work := crafting_catalog.get_work_minutes(recipe_id)
		var inputs := crafting_catalog.get_inputs(recipe_id)
		if required_work <= 0 or inputs.is_empty() or crafting_catalog.get_outputs(recipe_id).is_empty():
			continue
		occupied[cell_key] = true
		normalized.append({
			"cell": station_data.anchor.duplicate(),
			"recipe_id": recipe_id,
			"reserved_inputs": inputs,
			"required_work_minutes": required_work,
			"work_progress_minutes": clampi(
				_safe_int(project.get("work_progress_minutes"), 0),
				0,
				required_work
			),
		})
		var owner_value: Variant = project.get("owner_id", "")
		var home_value: Variant = project.get("home_cell", [])
		var owner: Dictionary = sim.state.npcs.get(owner_value, {}) if owner_value is String else {}
		if not owner.is_empty() and recipe_id == "core:saw_planks" and home_value is Array and home_value.size() == 2 and _is_whole_number(home_value[0]) and _is_whole_number(home_value[1]) and int(home_value[0]) >= 0 and int(home_value[0]) < 128 and int(home_value[1]) >= 0 and int(home_value[1]) < 128:
			normalized[-1].owner_id = owner_value
			normalized[-1].home_cell = [int(home_value[0]),int(home_value[1])]
	return normalized


# NPC work uses the same catalog and persistent station project as player work.
# It consumes physical carried input, and produces physical cargo at the station.
static func work_npc_project(sim, npc: Dictionary, cell: Array, recipe_id: String) -> Dictionary:
	var Production := preload("res://src/npc_work/npc_home_production.gd")
	var Supply := preload("res://src/npc_work/npc_work_supplies.gd")
	if recipe_id != Production.RECIPE or not Production.authorized(sim,npc) or not Production.station_free(sim,npc,cell):
		return _crafting_failure("core:station_busy")
	var structure: Dictionary = sim._find_structure(cell)
	var target := FirstNightContent.cell_center(int(cell[0]),int(cell[1]))
	if String(structure.get("building_id","")) != "core:workbench" or sim.get_npc_position(String(npc.id),Vector2.ZERO).distance_to(target) > FirstNightContent.INTERACTION_RANGE:
		return _crafting_failure("core:too_far")
	var project: Dictionary = sim._find_crafting_project(cell)
	var inputs: Dictionary = sim.crafting_catalog.get_inputs(recipe_id)
	var outputs: Dictionary = sim.crafting_catalog.get_outputs(recipe_id)
	if project.is_empty():
		var input_count := 0
		var output_count := 0
		for id: String in inputs:
			if int(npc.work_cargo.get(id,0)) < int(inputs[id]): return _crafting_failure("core:required_materials_missing")
			input_count += int(inputs[id])
		for amount: Variant in outputs.values(): output_count += int(amount)
		if Supply.cargo_size(npc) - input_count + output_count > Supply.CARRY_LIMIT:
			return _crafting_failure("core:required_materials_missing")
		for id: String in inputs:
			npc.work_cargo[id] = int(npc.work_cargo[id]) - int(inputs[id])
			if int(npc.work_cargo[id]) == 0: npc.work_cargo.erase(id)
		project = {"cell":cell.duplicate(),"recipe_id":recipe_id,"reserved_inputs":inputs.duplicate(true),"required_work_minutes":sim.crafting_catalog.get_work_minutes(recipe_id),"work_progress_minutes":0,"owner_id":String(npc.id),"home_cell":npc.home_goal.cell.duplicate()}
		sim.state.crafting_projects.append(project)
		return {"success":true,"reason_id":"core:crafting_project_started"}
	var next := mini(int(project.work_progress_minutes)+1,int(project.required_work_minutes))
	project.work_progress_minutes = next
	sim.needs.spend_work(npc.needs)
	if next < int(project.required_work_minutes): return {"success":true,"reason_id":"core:crafting_work_progressed"}
	for id: String in outputs:
		var amount := int(outputs[id])
		var fit := mini(amount,maxi(0,Supply.CARRY_LIMIT-Supply.cargo_size(npc)))
		npc.work_cargo[id] = int(npc.work_cargo.get(id,0)) + fit
		if amount > fit:
			var ids: Array[String] = sim._create_resource_drops(String(npc.id),id,amount-fit,target)
			for drop: Dictionary in sim.state.world_drops:
				if ids.has(String(drop.drop_id)): drop.npc_recovery = true
	sim.state.crafting_projects.erase(project)
	return {"success":true,"reason_id":"core:crafting_completed"}


static func _find_crafting_project(sim, cell_data: Array) -> Dictionary:
	var state: Dictionary = sim.state
	for project_value: Variant in state["crafting_projects"] as Array:
		if typeof(project_value) == TYPE_DICTIONARY:
			var project := project_value as Dictionary
			if project.get("cell", []) == cell_data:
				return project
	return {}
