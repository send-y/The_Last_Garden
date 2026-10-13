extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func _normalize_blueprints(sim,
	value: Variant,
	allow_multiple_layers: bool = false,
	migrate_legacy_wall_material: bool = false
) -> Array[Dictionary]:
	var building_catalog: BuildingCatalog = sim.building_catalog
	var normalized: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return normalized

	var occupied_cells: Dictionary = {}
	for blueprint_value: Variant in (value as Array):
		if typeof(blueprint_value) != TYPE_DICTIONARY:
			continue

		var blueprint: Dictionary = blueprint_value as Dictionary
		var cell_value: Variant = blueprint.get("cell", [])
		if typeof(cell_value) != TYPE_ARRAY:
			continue

		var cell_data: Array = cell_value as Array
		if cell_data.size() != 2:
			continue
		if not _is_whole_number(cell_data[0]) or not _is_whole_number(cell_data[1]):
			continue

		var normalized_command: Dictionary = {
			"actor_id": ConstructionCommandScript.PLAYER_ACTOR_ID,
			"action_id": ConstructionCommandScript.ACTION_PLACE_BLUEPRINT,
			"building_id": String(blueprint.get("building_id", "")),
			"cell": [int(cell_data[0]), int(cell_data[1])],
		}
		var validation: Dictionary = (
			ConstructionValidatorScript.validate_place_blueprint(normalized_command)
		)
		if not bool(validation.get("success", false)):
			continue

		var normalized_cell: Array = validation.get("cell", []) as Array
		var building_id: String = String(
			validation.get("building_id", "")
		)
		var layer_suffix := ":%s" % building_catalog.get_layer_id(building_id)
		var footprint_keys: Array[String] = []
		var has_occupied_footprint := false
		for footprint_cell: Vector2i in building_catalog.get_footprint_cells(
			building_id,
			Vector2i(int(normalized_cell[0]), int(normalized_cell[1]))
		):
			var footprint_key := _construction_cell_key(
				[footprint_cell.x, footprint_cell.y]
			)
			if allow_multiple_layers:
				footprint_key += layer_suffix
			footprint_keys.append(footprint_key)
			if occupied_cells.has(footprint_key):
				has_occupied_footprint = true
		if has_occupied_footprint:
			continue
		for footprint_key: String in footprint_keys:
			occupied_cells[footprint_key] = true
		var required_materials: Dictionary = (
			building_catalog.get_material_cost(building_id)
		)
		var required_work_minutes: int = (
			building_catalog.get_work_minutes(building_id)
		)

		if required_materials.is_empty() or required_work_minutes <= 0:
			continue

		var raw_delivered: Dictionary = {}
		var delivered_value: Variant = blueprint.get(
			"delivered_materials",
			{}
		)
		if typeof(delivered_value) == TYPE_DICTIONARY:
			raw_delivered = delivered_value as Dictionary

		var delivered_materials: Dictionary = {}
		for item_variant: Variant in required_materials.keys():
			var item_id: String = String(item_variant)
			var required_amount: int = int(required_materials[item_variant])
			delivered_materials[item_id] = clampi(
				_safe_int(raw_delivered.get(item_id), 0),
				0,
				required_amount
			)
		if (
			migrate_legacy_wall_material
			and building_id == "core:wood_wall"
			and raw_delivered.has("core:wood")
		):
			# Preserve the historical v19 wall-delivery conversion for migrated saves.
			var converted_planks := int(delivered_materials.get("core:plank", 0))
			converted_planks += maxi(0, _safe_int(raw_delivered.get("core:wood"), 0)) * 2
			delivered_materials["core:plank"] = mini(
				converted_planks,
				int(required_materials.get("core:plank", 0))
			)

		var work_progress_minutes: float = preload("res://src/items/tool_work_progress.gd").normalize(blueprint.get("work_progress_minutes", 0), required_work_minutes)
		normalized.append({
			"building_id": building_id,
			"cell": normalized_cell.duplicate(),
			"stage_id": BLUEPRINT_STAGE_ID,
			"required_materials": required_materials,
			"delivered_materials": delivered_materials,
			"required_work_minutes": required_work_minutes,
			"work_progress_minutes": preload("res://src/items/tool_work_progress.gd").stored(work_progress_minutes),
		})
		var home_project_id: Variant = blueprint.get("home_project_id", "")
		if home_project_id is String and not home_project_id.is_empty() and home_project_id.length() <= 160:
			normalized.back()["home_project_id"] = home_project_id

	return normalized


static func _normalize_structures(sim, value: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = sim._normalize_blueprints(value, true)

	for structure: Dictionary in normalized:
		if String(structure.building_id) == "core:torch":
			structure.lit = true
			for raw: Variant in value:
				if not raw is Dictionary or not raw.get("cell",[]) is Array or raw.cell.size() != 2:
					continue
				if _is_whole_number(raw.cell[0]) and _is_whole_number(raw.cell[1]) and int(raw.cell[0]) == int(structure.cell[0]) and int(raw.cell[1]) == int(structure.cell[1]) and String(raw.get("building_id","")) == "core:torch" and raw.get("lit") is bool:
					structure.lit = raw.lit
					break
		if String(structure.building_id) == "core:wood_door":
			# Missing state is a legacy always-passable door.
			structure.open = true
			for raw: Variant in value:
				if raw is Dictionary and raw.get("cell",[]) == structure.cell and String(raw.get("building_id","")) == "core:wood_door" and raw.get("open") is bool:
					structure.open = raw.open
					break
		structure["stage_id"] = COMPLETE_STAGE_ID
		structure.erase("required_materials")
		structure.erase("delivered_materials")
		structure.erase("required_work_minutes")
		structure.erase("work_progress_minutes")
		structure.erase("home_project_id")

	return normalized


static func _without_structure_cells(sim,
	blueprints: Array[Dictionary],
	structures: Array[Dictionary]
) -> Array[Dictionary]:
	var building_catalog: BuildingCatalog = sim.building_catalog
	var structure_cells: Dictionary = {}
	for structure: Dictionary in structures:
		var cell_data: Array = structure.get("cell", []) as Array
		var building_id := String(structure.get("building_id", ""))
		for cell: Vector2i in building_catalog.get_footprint_cells(
			building_id, Vector2i(int(cell_data[0]), int(cell_data[1]))
		):
			var key := _construction_cell_key([cell.x, cell.y])
			key += ":%s" % building_catalog.get_layer_id(building_id)
			structure_cells[key] = true

	var filtered: Array[Dictionary] = []
	for blueprint: Dictionary in blueprints:
		var cell_data: Array = blueprint.get("cell", []) as Array
		var building_id := String(blueprint.get("building_id", ""))
		var overlaps_structure := false
		for cell: Vector2i in building_catalog.get_footprint_cells(
			building_id, Vector2i(int(cell_data[0]), int(cell_data[1]))
		):
			var key := _construction_cell_key([cell.x, cell.y])
			key += ":%s" % building_catalog.get_layer_id(building_id)
			if structure_cells.has(key):
				overlaps_structure = true
				break
		if overlaps_structure:
			continue
		filtered.append(blueprint.duplicate(true))
	return filtered
