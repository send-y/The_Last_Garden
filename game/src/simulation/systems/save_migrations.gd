extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func _normalize_state(sim) -> void:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var npc_catalog: NpcCatalog = sim.npc_catalog
	var seed_value: int = _safe_int(state.get("seed"), DEFAULT_SEED)
	var generation_version := clampi(
		_safe_int(state.get("resource_generation_version"), ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION),
		ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION,
		ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION
	)
	var defaults: Dictionary = create_new_state(seed_value, generation_version)
	for key_variant: Variant in defaults.keys():
		var key: String = String(key_variant)
		if not state.has(key):
			state[key] = defaults[key]

	var loaded_version: int = _safe_int(state.get("version"), SAVE_VERSION)
	state["version"] = SAVE_VERSION
	state["seed"] = seed_value
	state["resource_generation_version"] = generation_version
	var raw_energy: Variant = state.get("player_energy", PLAYER_ENERGY_MAX)
	state["player_energy"] = PLAYER_ENERGY_MAX
	if typeof(raw_energy) == TYPE_INT or typeof(raw_energy) == TYPE_FLOAT:
		var energy := float(raw_energy)
		if is_finite(energy):
			state["player_energy"] = clampf(energy, 0.0, PLAYER_ENERGY_MAX)
	var normalized_needs: Dictionary = sim.needs.normalize(state.get("player_needs", {}))
	state["player_needs"] = {"hunger": normalized_needs.hunger, "restedness": normalized_needs.restedness}
	state["day"] = maxi(1, _safe_int(state.get("day"), 1))
	state["minute_of_day"] = clampi(
		_safe_int(state.get("minute_of_day"), START_MINUTE),
		0,
		LAST_MINUTE_OF_DAY
	)
	state["elapsed_game_minutes"] = maxi(
		0,
		_safe_int(
			state.get("elapsed_game_minutes"),
			(sim.get_day() - 1) * 24 * 60 + sim.get_minute_of_day()
		)
	)

	state["inventory"] = content.normalize_inventory(_as_dictionary(state.get("inventory")))
	state["item_instances"] = sim._normalize_item_instances(
		state.get("item_instances", []), state["inventory"] as Dictionary
	)
	state["inventory"] = sim._inventory_counts_without_instances(
		state["inventory"] as Dictionary
	)
	state["next_item_instance_serial"] = sim._normalize_next_item_instance_serial(
		state.get("next_item_instance_serial", 1),
		state["item_instances"] as Array
	)
	var layout_value: Variant = state.get("inventory_layout", [])
	var raw_layout: Array = []
	if typeof(layout_value) == TYPE_ARRAY:
		raw_layout = layout_value as Array
	var normalized_layout: Array[Dictionary] = []
	for entry_variant: Variant in raw_layout:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			normalized_layout.append((entry_variant as Dictionary).duplicate(true))
	var inventory_layout_result: Dictionary = InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content, normalized_layout, 4, 4
	)
	state["inventory_layout"] = inventory_layout_result.get("layout", [])
	state["markers"] = sim._normalize_markers(state.get("markers", []))
	state["next_marker_serial"] = sim._normalize_next_marker_serial(
		state.get("next_marker_serial", 1), state["markers"] as Array
	)
	state["resource_nodes"] = sim._normalize_resource_nodes(
		state.get("resource_nodes", defaults["resource_nodes"]),
		seed_value
	)
	state["tree_nodes"] = sim._normalize_tree_nodes(
		state.get("tree_nodes", defaults["tree_nodes"]),
		seed_value,
		state["resource_nodes"] as Array
	)
	sim._berry_bush_nodes = ResourceNodeCatalogScript.generate_berry_bushes(
		seed_value,
		state["resource_nodes"] as Array,
		state["tree_nodes"] as Array,
		generation_version
	)
	sim._food_object_ids.clear()
	for definition: Dictionary in content.interactables():
		if String(definition.get("kind", "")) == "food":
			sim._food_object_ids[String(definition["id"])] = true
	for bush: Dictionary in sim._berry_bush_nodes:
		sim._food_object_ids[String(bush["id"])] = true
	var removed: Dictionary = {}
	var raw_removed: Variant = state.get("removed_bushes",{})
	if raw_removed is Dictionary:
		for id: String in sim._food_object_ids:
			if raw_removed.get(id,false) is bool and raw_removed.get(id,false): removed[id] = true
	state["removed_bushes"] = removed
	state["collected"] = content.normalize_collected(_as_dictionary(state.get("collected")))
	state["resource_work"] = sim._normalize_resource_work(state.get("resource_work", {}))
	state["resource_work_tool_instances"] = sim._normalize_resource_work_tool_instances(
		state.get("resource_work_tool_instances", {}),
		state["resource_work"] as Dictionary
	)
	state["world_drops"] = sim._normalize_world_drops(
		state.get("world_drops", [])
	)
	state["next_drop_serial"] = _normalize_next_drop_serial(
		state.get("next_drop_serial", 1),
		state["world_drops"] as Array
	)
	var raw_storage_items: Variant = state.get("storage_items", [])
	state["storage_zones"] = sim._normalize_storage_zones(
		state.get("storage_zones", [])
	)
	state["storage_items"] = sim._normalize_storage_items(
		raw_storage_items,
		state["storage_zones"] as Array
	)
	sim._recover_orphaned_storage_items(
		raw_storage_items,
		state["storage_items"] as Array
	)
	state["npcs"] = npc_catalog.normalize_states(_as_dictionary(state.get("npcs")), seed_value)
	state["next_npc_serial"] = maxi(1, preload("res://src/npc_work/npc_work_state.gd").number(state.get("next_npc_serial", 1)))
	sim._reconcile_item_instance_locations()
	sim._normalize_hotbar_state()
	var selected_value: Variant = state.get("selected_inventory_item", {})
	state["selected_inventory_item"] = _as_dictionary(selected_value)
	if sim.get_held_item().is_empty():
		state["selected_inventory_item"] = {}
	state["next_storage_zone_serial"] = sim._normalize_next_storage_zone_serial(
		state.get("next_storage_zone_serial", 1),
		state["storage_zones"] as Array
	)
	state["room_assignments"] = sim._normalize_room_assignments(
		state.get("room_assignments", [])
	)
	state["next_room_serial"] = sim._normalize_next_room_serial(
		state.get("next_room_serial", 1),
		state["room_assignments"] as Array
	)

	var normalized_structures: Array[Dictionary] = (
		sim._normalize_structures(state.get("structures", []))
	)
	var normalized_blueprints: Array[Dictionary] = (
		sim._normalize_blueprints(
			state.get("blueprints", []),
			true,
			loaded_version < LEGACY_WALL_MATERIAL_MIGRATION_CUTOFF
		)
	)
	state["structures"] = normalized_structures
	state["blueprints"] = sim._without_structure_cells(
		normalized_blueprints,
		normalized_structures
	)
	state["crafting_projects"] = sim._normalize_crafting_projects(
		state.get("crafting_projects", []),
		normalized_structures
	)

	var flags: Dictionary = _as_dictionary(state.get("flags"))
	var default_flags: Dictionary = defaults["flags"] as Dictionary
	for flag_variant: Variant in default_flags.keys():
		var flag_id: String = String(flag_variant)
		var default_value: Variant = default_flags[flag_id]
		if typeof(default_value) == TYPE_BOOL:
			flags[flag_id] = _safe_bool(flags.get(flag_id), bool(default_value))
		else:
			flags[flag_id] = _safe_int(flags.get(flag_id), int(default_value))
	flags["repair_stage"] = clampi(_safe_int(flags.get("repair_stage"), 0), 0, 3)
	flags["campfire_stage"] = clampi(_safe_int(flags.get("campfire_stage"), 0), 0, 2)
	if loaded_version < PLAYER_ENERGY_SAVE_VERSION:
		flags["comfortable_sleep_completed"] = (
			bool(flags["first_night_complete"]) and int(flags["repair_stage"]) >= 3
		)
	state["flags"] = flags
	if sim.get_day() > 2 or (sim.get_day() == 2 and sim.get_minute_of_day() >= MORNING_MINUTE):
		flags["first_night_complete"] = true
	if bool(flags["first_night_complete"]):
		npc_catalog.activate_after_first_night(sim._npcs_mutable())

	var stored_position_value: Variant = state.get("player_position", defaults["player_position"])
	if not _is_valid_position(stored_position_value):
		state["player_position"] = (defaults["player_position"] as Array).duplicate(true)
	else:
		var stored_position: Array = stored_position_value as Array
		state["player_position"] = [float(stored_position[0]), float(stored_position[1])]
	state["outcomes"] = _normalize_outcomes(state.get("outcomes"), loaded_version)

	if loaded_version != SAVE_VERSION:
		push_warning("Save version %s migrated into prototype version %s." % [loaded_version, SAVE_VERSION])
