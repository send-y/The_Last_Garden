extends SceneTree

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
# Explicit script type also works before the editor refreshes its class registry.
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const InventoryPacker := preload("res://src/inventory/inventory_auto_packer.gd")
const InventoryGridScript := preload("res://src/ui/inventory_grid.gd")
const ResourceNodeCatalogScript := preload(
	"res://src/content/resource_node_catalog.gd"
)
const AppearanceCatalog := preload("res://src/characters/character_appearance.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const SessionNodeScript := preload("res://src/autoload/session.gd")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const LocalGridPathfinderScript := preload("res://src/simulation/local_grid_pathfinder.gd")
const FirstNightNavigationScript := preload("res://src/simulation/first_night_navigation.gd")
const WaterMapScript := preload("res://src/world/water_map.gd")
const CollectionLookupProbe := preload("res://tests/fixtures/collection_lookup_probe.gd")
const NpcAutonomyScript := preload("res://src/simulation/npc_autonomy.gd")
const ConstructionCommandScript := preload("res://src/construction/construction_command.gd")
const ConstructionValidatorScript := preload("res://src/construction/construction_validator.gd")
const ConstructionCursorScript := preload("res://src/construction/construction_cursor.gd")
const BuildingCatalogScript := preload("res://src/construction/building_catalog.gd")
const RoomTopologyScript := preload("res://src/construction/room_topology.gd")
const CraftingCatalogScript := preload("res://src/crafting/crafting_catalog.gd")
const CraftingCommandScript := preload("res://src/crafting/crafting_command.gd")
const PlaceholderIconScript := preload("res://src/items/item_placeholder_icon.gd")
const NpcWorkRequestScript := preload("res://src/simulation/npc_work_request.gd")
const NpcWorkRequestValidatorScript := preload(
	"res://src/simulation/npc_work_request_validator.gd"
)
const NpcMemoryScript := preload("res://src/simulation/npc_memory.gd")
const TEST_SAVE_PATH: String = "user://first_night_save_store_test.json"
const TEST_LAB_SAVE_PATH: String = "user://mechanics_lab_session_test.json"
const TEST_SURFACE_ROUTE_SAVE_PATH: String = "user://surface_first_night_route_test.json"
const LOCALIZATION_PATH: String = "res://localization/core.csv"
const LOCALIZATION_SOURCE_PATHS: Array[String] = [
	"res://content/core/character_parts.json",
	"res://content/core/buildings.json",
	"res://content/core/first_night_objects.json",
	"res://content/core/water_map.json",
	"res://content/core/first_night_progression.json",
	"res://content/core/items.json",
	"res://content/core/npcs.json",
	"res://content/core/recipes.json",
	"res://src/autoload/session.gd",
	"res://src/characters/npc_catalog.gd",
	"res://src/content/first_night_content.gd",
	"res://src/content/resource_node_catalog.gd",
	"res://src/save/first_night_save_store.gd",
	"res://src/simulation/first_night_simulation.gd",
	"res://src/simulation/world_simulation.gd",
	"res://src/simulation/world_rules.gd",
	"res://src/simulation/systems/opening_scenario.gd",
	"res://src/simulation/systems/world_calendar.gd",
	"res://src/simulation/systems/resource_system.gd",
	"res://src/simulation/systems/world_drops.gd",
	"res://src/simulation/systems/inventory_system.gd",
	"res://src/simulation/systems/equipment_system.gd",
	"res://src/simulation/systems/map_markers.gd",
	"res://src/simulation/systems/storage_system.gd",
	"res://src/simulation/systems/storage_transfers.gd",
	"res://src/simulation/systems/room_system.gd",
	"res://src/simulation/systems/settlement_npcs.gd",
	"res://src/simulation/systems/construction_commands.gd",
	"res://src/simulation/systems/construction_projects.gd",
	"res://src/simulation/systems/crafting_system.gd",
	"res://src/simulation/npc_autonomy.gd",
	"res://src/ui/first_night_hud.gd",
	"res://src/ui/construction_palette.gd",
	"res://src/ui/crafting_panel.gd",
	"res://src/ui/storage_panel.gd",
	"res://src/ui/inventory_panel.gd",
	"res://src/world/first_night_world.gd",
]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	TranslationServer.set_locale("ru")
	_test_localization_catalog_and_resolver()
	_test_complete_first_night()
	_test_player_energy_and_roof_sleep()
	_test_player_energy_save_migration()
	_test_serialization_round_trip()
	_test_duplicate_collection_is_rejected()
	_test_command_boundary_rejects_forged_commands()
	_test_command_boundary_enforces_range_and_resolves_kind()
	_test_resource_work_progress_completion_and_serialization()
	_test_resource_work_requires_selected_physical_tools()
	_test_surface_boulders_are_seeded_and_workable()
	_test_surface_trees_are_seeded_and_workable()
	_test_surface_berry_bushes_are_seeded_and_collectible()
	_test_collection_lookup_avoids_surface_scan()
	_test_starter_resources_are_accessible_across_seeds()
	_test_resource_layout_versions_preserve_existing_saves()
	_test_resource_search_hints_follow_available_work()
	_test_water_cells_share_navigation_and_construction_rules()
	_test_bucket_instances_hotbar_and_transfers()
	_test_pickup_respects_inventory_limits()
	_test_manual_inventory_layout_and_rotation()
	_test_pickup_keeps_manual_inventory_layout()
	_test_click_to_pickup_inventory_controls()
	_test_player_food_consumption()
	_test_named_markers_and_save_round_trip()
	_test_world_drops_persist_and_pickup_by_id()
	_test_inventory_stack_drop_and_expiry()
	_test_placeholder_icons_cover_missing_art()
	_test_storage_zones_and_physical_transfers()
	_test_storage_transfers_preserve_backpack_layout()
	_test_room_detection_and_designation()
	_test_query_snapshots_are_isolated()
	_test_corrupt_nested_state_uses_defaults()
	_test_save_header_validation()
	_test_unknown_npc_state_survives_normalization()
	_test_save_store_rotates_and_recovers_backup()
	_test_session_uses_backup_for_invalid_header_only()
	_test_legacy_save_ids_are_migrated()
	_test_v3_outcomes_are_migrated()
	_test_v4_npc_state_is_migrated()
	_test_v5_blueprints_are_migrated()
	_test_v6_structures_are_migrated()
	_test_v7_work_commitments_are_migrated()
	_test_v8_memories_are_migrated()
	_test_v9_blueprint_progress_is_migrated()
	_test_v19_wall_materials_migrate_to_planks()
	_test_character_appearance_generation()
	_test_first_neighbor_arrives_and_talks()
	_test_grid_pathfinder_avoids_static_obstacles()
	_test_mira_needs_schedule_and_personal_food()
	_test_mira_autonomy_is_deterministic_and_serialized()
	_test_npc_work_request_contract_and_refusals()
	_test_mira_completes_construction_commitment()
	_test_simulation_time_step_invariance()
	_test_missing_blueprint_releases_commitment()
	_test_shared_wall_creates_memory_and_relationship()
	_test_shared_wall_context_line_is_consumed_once()
	_test_construction_command_payload()
	_test_building_catalog()
	_test_multi_cell_construction_footprints()
	_test_floor_layer_coexists_with_structures()
	_test_crafting_catalog_and_project_lifecycle()
	_test_crafting_station_footprint_is_canonical()
	_test_construction_command_validation()
	_test_blueprint_command_execution()
	_test_construction_cursor_requires_build_mode()
	_test_lab_rejects_unknown_scenario()
	_test_lab_fresh_start()
	_test_lab_prepared_evening()
	_test_lab_morning_with_mira()
	_test_lab_mira_resting()
	_test_lab_mira_after_shared_wall()
	_test_lab_workbench_crafting()
	_test_lab_surface_boulders()
	_test_lab_scenarios_are_deterministic()
	_test_lab_rebuild_discards_previous_changes()
	_test_session_installs_lab_state_without_aliasing_or_save()

	if _failures == 0:
		print("PASS: prototype simulation and mechanics lab tests")
		quit(0)
	else:
		push_error("FAIL: %d first-night simulation assertion(s)" % _failures)
		quit(1)


func _test_localization_catalog_and_resolver() -> void:
	var catalog: Dictionary = {}
	var duplicate_keys: Array[String] = []
	var file: FileAccess = FileAccess.open(LOCALIZATION_PATH, FileAccess.READ)
	_expect(file != null, "Russian localization CSV is readable")
	if file == null:
		return

	var header: PackedStringArray = file.get_csv_line()
	_expect(header.size() >= 2 and header[0] == "keys" and header[1] == "ru", "localization CSV has keys and ru columns")
	while file.get_position() < file.get_length():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty() or String(row[0]).is_empty():
			continue
		var key: String = String(row[0])
		if catalog.has(key):
			duplicate_keys.append(key)
			continue
		catalog[key] = String(row[1]) if row.size() > 1 else ""
	file.close()
	_expect(duplicate_keys.is_empty(), "localization keys are unique")

	var key_pattern := RegEx.new()
	var compile_error: Error = key_pattern.compile(
		"\"((?:item|object|character_part|npc|dialogue|ui|world|first_night|interaction|system|save)\\.[a-z0-9_.]+)\""
	)
	_expect(compile_error == OK, "localization key audit pattern compiles")
	var missing_keys: Array[String] = []
	if compile_error == OK:
		for source_path: String in LOCALIZATION_SOURCE_PATHS:
			var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
			_expect(source_file != null, "localization source is readable: %s" % source_path)
			if source_file == null:
				continue
			var source_text: String = source_file.get_as_text()
			source_file.close()
			for match_result: RegExMatch in key_pattern.search_all(source_text):
				var referenced_key: String = match_result.get_string(1)
				if not catalog.has(referenced_key) and not missing_keys.has(referenced_key):
					missing_keys.append(referenced_key)
	_expect(missing_keys.is_empty(), "all runtime localization keys exist: %s" % [missing_keys])

	var greeting: String = Localized.resolve("ui.dialogue.speaker_line", {
		"speaker": Localized.text_reference("npc.core.first_neighbor.name"),
		"line": Localized.text_reference("dialogue.core.first_neighbor.greeting"),
	})
	_expect(greeting.begins_with("Мира:"), "nested localized speaker and line resolve in Russian")
	_expect(
		Localized.resolve("ui.hud.day_time", {"day": 2, "time": "07:00"}) == "День 2  07:00",
		"named localization arguments resolve in Russian"
	)
	_expect(Localized.resolve("npc.activity.resting") == "Отдыхает", "NPC activity resolves in Russian")
	_expect(
		Localized.resolve("ui.hud.selection.in_range_with_status", {
			"label": "Мира",
			"status": "Отдыхает",
		}).contains("Мира — Отдыхает"),
		"NPC selection renders a whole localized status variant"
	)
	_expect(Localized.resolve("ui.hud.controls").contains("\n"), "escaped CSV newline is imported")
	TranslationServer.set_locale("en")
	_expect(
		Localized.resolve("system.save.success") == "Состояние сохранено.",
		"unsupported locale falls back to Russian"
	)
	TranslationServer.set_locale("ru")
	_expect(
		Localized.resolve("missing.localization.key") == "missing.localization.key",
		"missing localization key remains visibly detectable"
	)


func _test_complete_first_night() -> void:
	var simulation: World = Simulation.new(
		Simulation.create_new_game_state()
	)
	_expect(simulation.get_day() == 1, "new game starts on day 1")
	_expect(simulation.get_time_text() == "11:00", "new game starts at 11:00")
	var original_instances: Array = simulation.export_state().get("item_instances", [])
	var starting_elapsed := simulation.get_elapsed_game_minutes()
	var axe_id := _surface_route_take_tool(simulation, "core:axe")
	if axe_id.is_empty():
		return
	if not _surface_route_interact(simulation, "core:repair_room"):
		return
	_expect(String(simulation.get_resource_search_hint().get("kind", "")) == "wood", "ordinary start points toward generated wood after finding a pantry tool")
	if not _surface_route_harvest(simulation, simulation.get_surface_trees()):
		return
	if not _surface_route_store_item(simulation, "core:axe", axe_id):
		return
	var pickaxe_id := _surface_route_take_tool(simulation, "core:pickaxe")
	if pickaxe_id.is_empty():
		return
	if not _surface_route_harvest(simulation, simulation.get_surface_boulders()):
		return
	if not _surface_route_store_item(simulation, "core:pickaxe", pickaxe_id):
		return
	_expect(simulation.get_current_objective_key() == "first_night.objective.build_workbench", "ordinary roof route explains the missing board-making station")
	var workbench_cell := _surface_route_build_workbench(simulation)
	if workbench_cell.x < 0:
		return
	if not _surface_route_saw_planks(simulation, workbench_cell):
		return
	_expect(simulation.get_item_count("core:plank") == 10, "ordinary route physically collects its first crafted roof boards")
	_expect(simulation.get_current_objective_key() == "first_night.objective.cover_roof", "picked-up boards advance the ordinary objective to covering the roof")
	var energy_before_roof := simulation.get_player_energy()
	if not _surface_route_interact(simulation, "core:repair_room"):
		return
	_expect(simulation.is_roof_covered(), "earned boards close the roof")
	_expect(simulation.get_item_count("core:plank") == 0, "covering the roof consumes the crafted boards")
	_expect(is_equal_approx(simulation.get_player_energy(), energy_before_roof), "covering the roof does not instantly restore player energy")
	_expect(
		simulation.get_elapsed_game_minutes() > starting_elapsed + 16 + 18 + 8,
		"ordinary gathering, construction, crafting, and walking advance the first-night clock"
	)
	_expect(
		simulation.get_item_count(FirstNightContent.WOOD_ID) >= 5
		and simulation.get_item_count(FirstNightContent.STONE_ID) >= 4,
		"generated resources leave enough material for optional room finishing, campfire, and bedding"
	)
	if not _surface_route_interact(simulation, "core:berry_bush"):
		return
	if not _surface_route_interact(simulation, "core:shore_water"):
		return
	_expect(
		simulation.get_item_count(FirstNightContent.RAW_WATER_ID) == 1,
		"legacy shore interaction still provides drinking water for the first-night loop"
	)
	_expect(
		bool(simulation.get_flags().get("tools_found", false)),
		"taking a tool from the ordinary starter pantry advances the tutorial"
	)
	if not _surface_route_interact(simulation, "core:repair_room"):
		return
	_expect(simulation.get_object_stage("repair") == 3, "room repair reaches stage 3")
	for _step: int in range(3):
		if not _surface_route_interact(simulation, "core:campfire_site"):
			return
	_expect(simulation.get_object_stage("campfire") == 2, "campfire is lit")
	_expect(bool(simulation.get_flags()["water_boiled"]), "water is boiled")
	if not _surface_route_interact(simulation, "core:bed_site"):
		return
	_expect(bool(simulation.get_flags()["bed_ready"]), "temporary bed is ready")
	simulation.advance_minutes(simulation.EVENING_MINUTE - simulation.get_minute_of_day())
	var sleep_result := simulation.execute_interaction("core:bed_site")
	_expect(bool(sleep_result["success"]), "sleep command succeeds after 18:00")
	_expect(not sleep_result.has("message"), "sleep result contains no localized copy")
	var localized_morning: String = Localized.resolve(
		String(sleep_result.get("message_key", "")),
		sleep_result.get("message_args", {}) as Dictionary
	)
	_expect(localized_morning.contains(Localized.resolve("first_night.outcome.dry_room")), "morning summary localizes outcome ids")
	_expect(not localized_morning.contains("core:"), "morning summary exposes no technical ids")
	_expect(simulation.get_day() == 2, "sleep advances to day 2")
	_expect(simulation.get_time_text() == "07:00", "sleep advances to 07:00")
	_expect(bool(simulation.get_flags()["first_night_complete"]), "first night is marked complete")
	_expect(bool(simulation.get_flags().get("comfortable_sleep_completed", false)), "ordinary covered-roof sleep completes the comfortable-start result")
	_expect(is_equal_approx(simulation.get_player_energy(), simulation.get_player_energy_max()), "comfortable sleep restores full player energy after actual work")
	_expect(simulation.is_npc_visible("core:first_neighbor"), "first neighbor appears after the first night")
	_expect(
		not simulation.get_npc_position(
			"core:first_neighbor",
			Vector2.ZERO
		).is_equal_approx(simulation.get_player_position()),
		"first neighbor does not appear inside the player"
	)
	_cleanup_save_files(TEST_SURFACE_ROUTE_SAVE_PATH)
	var store := SaveStore.new(TEST_SURFACE_ROUTE_SAVE_PATH)
	var written := store.write_state(simulation.export_state())
	_expect(bool(written.get("success", false)), "ordinary first-night route can be saved to disk")
	var read_result := store.read_state()
	_expect(bool(read_result.get("success", false)), "ordinary first-night route can be loaded from disk")
	if bool(read_result.get("success", false)):
		var restored := Simulation.new(read_result.get("state", {}) as Dictionary)
		_expect(restored.get_day() == 2 and bool(restored.get_flags()["first_night_complete"]), "saved ordinary route preserves its morning and completion")
		_expect(restored.get_inventory() == simulation.get_inventory(), "saved ordinary route preserves its earned and consumed resources")
		_expect(restored.is_roof_covered() and bool(restored.get_flags().get("comfortable_sleep_completed", false)), "saved ordinary route preserves roof and comfortable sleep completion")
		_expect(is_equal_approx(restored.get_player_energy(), simulation.get_player_energy()), "saved ordinary route preserves restored player energy")
		_expect(restored.get_structures() == simulation.get_structures(), "saved ordinary route preserves the actually built starter workbench")
		_expect(restored.export_state().get("resource_nodes") == simulation.export_state().get("resource_nodes"), "saved ordinary route preserves mined generated boulders")
		_expect(restored.export_state().get("tree_nodes") == simulation.export_state().get("tree_nodes"), "saved ordinary route preserves harvested generated trees")
		_expect(restored.export_state().get("collected") == simulation.export_state().get("collected"), "saved ordinary route preserves resource depletion")
		_expect((restored.export_state().get("item_instances", []) as Array).size() == original_instances.size(), "ordinary route and reload do not create replacement tools")
		for instance: Dictionary in original_instances:
			var preserved := restored.get_item_instance(String(instance.get("instance_id", "")))
			_expect(String(preserved.get("item_id", "")) == String(instance.get("item_id", "")), "ordinary route preserves every original physical tool ID")
	_cleanup_save_files(TEST_SURFACE_ROUTE_SAVE_PATH)
	_continue_ordinary_farming_route(simulation, workbench_cell)


func _continue_ordinary_farming_route(simulation: World, workbench_cell: Vector2i) -> void:
	# Continue the real tool/tree/workbench/plank/roof/sleep route. No seeds,
	# crops, table materials, water charges, or completed buildings are granted.
	while not simulation.get_inventory_placements().is_empty():
		var placement: Dictionary = simulation.get_inventory_placements()[0]
		var stored := false
		for zone: Dictionary in simulation.get_storage_zones():
			for raw_cell: Array in zone.cells:
				var storage_cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
				if not _surface_route_move(simulation, _cell_center(storage_cell)):
					return
				var result := simulation.transfer_inventory_stack_to_storage(storage_cell, String(placement.item_id), int(placement.stack_index))
				if bool(result.success):
					stored = true
					break
			if stored:
				break
		if not stored:
			_expect(false, "ordinary farm route must be able to store its first-night surplus")
			return
	var axe := _surface_route_take_tool(simulation, "core:axe")
	var fresh_trees: Array[Dictionary] = simulation.get_surface_trees().filter(func(tree: Dictionary) -> bool:
		return String(tree.get("stage_id", "tree")) == "tree" and not simulation.is_collected(String(tree.id))
	)
	if axe.is_empty() or not _surface_route_harvest(simulation, fresh_trees):
		return
	if not _surface_route_store_item(simulation, "core:axe", axe):
		return
	if not _surface_route_move(simulation, _cell_center(workbench_cell)):
		return
	var started := simulation.execute_crafting_command(CraftingCommandScript.start_project(workbench_cell, "core:saw_planks"))
	if not bool(started.success):
		_expect(false, "ordinary farm route starts a second saw batch with earned wood")
		return
	var result: Dictionary = {}
	for _minute: int in range(CraftingCatalogScript.new().get_work_minutes("core:saw_planks")):
		simulation.advance_minutes(1)
		result = simulation.execute_crafting_command(CraftingCommandScript.work_project(workbench_cell))
		if not bool(result.success):
			_expect(false, "ordinary farm route must complete its table boards")
			return
	if not _surface_route_pick_drops(simulation, result.get("created_drop_ids", [])):
		return
	var table := Vector2i(-1, -1)
	for y: int in range(19, 22):
		for x: int in range(21, 26):
			var candidate := Vector2i(x, y)
			if bool(simulation.execute_construction_command(ConstructionCommandScript.place_blueprint(candidate, "core:study_table")).success):
				table = candidate
				break
		if table.x >= 0:
			break
	if table.x < 0 or not _surface_route_move(simulation, _cell_center(table)):
		_expect(false, "ordinary farm route must place a reachable study table")
		return
	if not bool(simulation.execute_construction_command(ConstructionCommandScript.deliver_blueprint_materials(table)).success):
		_expect(false, "earned boards must be delivered into the study table")
		return
	for _minute: int in range(BuildingCatalogScript.new().get_work_minutes("core:study_table")):
		simulation.advance_minutes(1)
		result = simulation.execute_construction_command(ConstructionCommandScript.work_blueprint(table))
		if not bool(result.success):
			_expect(false, "ordinary farm route must construct its study table through work")
			return
	_expect(simulation.farming.extraction_unlocked(simulation), "actually built table unlocks ordinary seed extraction")
	var fresh_bushes := simulation.get_surface_berry_bushes()
	var gathered := false
	for bush: Dictionary in fresh_bushes:
		if not simulation.farming.berry_ready(simulation, String(bush.id)):
			continue
		if not _surface_route_path(simulation, bush.position, Content.INTERACTION_RANGE).is_empty() and _surface_route_move(simulation, bush.position):
			var berry_result := simulation.execute_interaction(String(bush.id))
			_expect(bool(berry_result.success), "reachable generated bush must provide actual starter berries")
			if not bool(berry_result.success):
				return
			gathered = true
			break
	if not gathered:
		_expect(false, "ordinary farm route must collect a real ready berry bush")
		return
	result = _farm_route_command(simulation, "extract", Vector2i(-1, -1), "core:food")
	if not bool(result.success):
		_expect(false, "carried special berry must produce the starting seeds")
		return
	var crop: Dictionary = {}
	for definition: Dictionary in simulation.farming.catalog.crops:
		if simulation.get_item_count(String(definition.seed_id)) > 0:
			crop = definition
			break
	var hoe := _surface_route_take_tool(simulation, "core:hoe")
	if hoe.is_empty() or crop.is_empty():
		return
	var bed := Vector2i(-1, -1)
	for y: int in range(27, 34):
		for x: int in range(21, 31):
			var candidate := Vector2i(x, y)
			if simulation.farming._soil_allowed(simulation, candidate) and not _surface_route_path(simulation, _cell_center(candidate), Content.INTERACTION_RANGE).is_empty():
				bed = candidate
				break
		if bed.x >= 0:
			break
	if bed.x < 0 or not _surface_route_move(simulation, _cell_center(bed)):
		_expect(false, "ordinary farm route needs reachable soil; position=%s table=%s" % [simulation.get_player_position(), table])
		return
	if not bool(_farm_route_command(simulation, "till", bed).success):
		_expect(false, "original pantry hoe prepares the bed")
		return
	if not _surface_route_store_item(simulation, "core:hoe", hoe):
		return
	var bucket := _surface_route_take_tool(simulation, "core:bucket")
	if bucket.is_empty() or not _surface_route_move(simulation, _cell_center(bed)):
		return
	if not bool(_farm_route_command(simulation, "plant", bed, String(crop.seed_id)).success):
		_expect(false, "special berry seeds must plant without an artificial seed grant")
		return
	# Put unused starter seeds away. The second sowing must rely entirely on
	# seeds actually extracted from the first crop, not the berry surplus.
	for placement: Dictionary in simulation.get_inventory_placements():
		if String(placement.item_id) != String(crop.seed_id):
			continue
		var stored := false
		for zone: Dictionary in simulation.get_storage_zones():
			for raw_cell: Array in zone.cells:
				var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
				if not _surface_route_move(simulation, _cell_center(cell)):
					return
				if bool(simulation.transfer_inventory_stack_to_storage(cell, String(crop.seed_id), int(placement.stack_index)).success):
					stored = true
					break
			if stored:
				break
		if not stored:
			_expect(false, "ordinary farm route must store unused starter seeds")
			return
	_expect(simulation.get_item_count(String(crop.seed_id)) == 0, "second sowing begins without carried starter seeds")
	for cycle: int in range(2):
		if not _farm_route_grow(simulation, bed):
			return
		var previous_drops := simulation.get_world_drops().duplicate(true)
		if not bool(_farm_route_command(simulation, "harvest", bed).success):
			_expect(false, "ordinary farm route harvests the grown crop")
			return
		var new_ids: Array[String] = []
		for drop: Dictionary in simulation.get_world_drops():
			if not previous_drops.has(drop):
				new_ids.append(String(drop.drop_id))
		if not _surface_route_pick_drops(simulation, new_ids):
			return
		if cycle == 0:
			result = _farm_route_command(simulation, "extract", Vector2i(-1, -1), String(crop.product_id))
			if not bool(result.success):
				_expect(false, "ordinary harvest replaces seed stock through the constructed table")
				return
			if String(crop.harvest_mode) == "perennial":
				# Replant using the returned seeds even for a perennial, so this
				# route proves seed supply independently of repeat fruiting.
				_farm_route_command(simulation, "remove", bed)
				if not _surface_route_store_item(simulation, "core:bucket", bucket):
					return
				hoe = _surface_route_take_tool(simulation, "core:hoe")
				_surface_route_move(simulation, _cell_center(bed))
				_farm_route_command(simulation, "till", bed)
				_surface_route_store_item(simulation, "core:hoe", hoe)
				bucket = _surface_route_take_tool(simulation, "core:bucket")
			_surface_route_move(simulation, _cell_center(bed))
			if not bool(_farm_route_command(simulation, "plant", bed, String(crop.seed_id)).success):
				_expect(false, "own crop seeds provide the second planting")
				return
	_expect(simulation.get_item_count(String(crop.product_id)) > 0, "second crop has usable products after reserving seed material")
	var store := SaveStore.new(TEST_SURFACE_ROUTE_SAVE_PATH)
	_expect(bool(store.write_state(simulation.export_state()).success), "ordinary repeated crop saves to disk")
	var restored := _farm_route_restore(store)
	_expect(restored.get_farm_beds() == simulation.get_farm_beds() and restored.get_inventory() == simulation.get_inventory(), "ordinary repeated harvest and seed stock survive disk reload")
	_cleanup_save_files(TEST_SURFACE_ROUTE_SAVE_PATH)
	print("PASS: ordinary pantry -> actual wood/planks/study table -> wild berry seeds -> watered crop -> own seeds -> replanted second harvest")


func _farm_route_restore(store: FirstNightSaveStore) -> World:
	return Simulation.new(store.read_state().get("state", {}))


func _farm_route_command(simulation: World, action: String, cell: Vector2i, item_id: String = "") -> Dictionary:
	return simulation.execute_farming_command({"actor_id": "core:player", "action_id": action, "cell": [cell.x, cell.y], "item_id": item_id})


func _farm_route_grow(simulation: World, cell: Vector2i) -> bool:
	for _step: int in range(32):
		if not _surface_route_move(simulation, _cell_center(cell)):
			return false
		var bed := simulation.get_farm_bed(cell)
		var crop := simulation.farming.catalog.find(String(bed.crop_id))
		var required := simulation.farming._required_growth(bed, crop)
		if int(bed.growth) >= required:
			return true
		if int(bed.wet_until) <= simulation.get_elapsed_game_minutes():
			if not _surface_route_move(simulation, _cell_center(Vector2i(6, 27))):
				return false
			if not bool(simulation.fill_active_bucket(Vector2i(6, 27)).success):
				_expect(false, "ordinary watering must fill the original bucket from actual river water")
				return false
			if not _surface_route_move(simulation, _cell_center(cell)) or not bool(_farm_route_command(simulation, "water", cell).success):
				_expect(false, "ordinary watering reaches and waters its crop")
				return false
			bed = simulation.get_farm_bed(cell)
		if simulation.get_minute_of_day() >= 18 * 60:
			if not _surface_route_interact(simulation, "core:bed_site"):
				return false
		else:
			var until_evening := 18 * 60 - simulation.get_minute_of_day()
			var minutes := maxi(1, mini(until_evening, mini(required - int(bed.growth), int(bed.wet_until) - simulation.get_elapsed_game_minutes())))
			simulation.advance_minutes(minutes)
	_expect(false, "ordinary crop must mature within the bounded care scenario")
	return false


func _test_player_energy_and_roof_sleep() -> void:
	var working_state := Simulation.create_new_state()
	working_state["player_energy"] = 3.0
	var working := Simulation.new(working_state)
	working.tick(2.0)
	_expect(is_equal_approx(working.get_player_energy(), 3.0), "elapsed time alone does not charge the player's work energy")
	_interact_near(working, "common_house")
	_expect(is_equal_approx(working.get_player_energy(), 3.0), "non-work interaction does not consume player energy")
	_add_test_tool(working, "core:axe", true)
	working.set_player_position(working.get_interaction_target_position("wood_north"))
	for minute: int in range(4):
		var work := working.execute_resource_work(Simulation.PLAYER_ACTOR_ID, "wood_north")
		_expect(bool(work.get("success", false)), "resource work remains available when player energy reaches zero")
		_expect(is_equal_approx(working.get_player_energy(), maxf(0.0, 3.0 - float(minute + 1))), "successful player resource minutes spend energy once and clamp at zero")
	var rejected_energy := working.get_player_energy()
	working.set_player_position(Vector2.ZERO)
	var distant_work := working.execute_resource_work(Simulation.PLAYER_ACTOR_ID, "wood_north")
	_expect(not bool(distant_work.get("success", false)) and is_equal_approx(working.get_player_energy(), rejected_energy), "rejected distant resource work does not spend energy")
	var rejected_state := Simulation.create_new_state()
	rejected_state["player_energy"] = 31.5
	(rejected_state["structures"] as Array).append({"building_id": "core:workbench", "cell": [22, 29], "stage_id": "core:complete"})
	var rejected := Simulation.new(rejected_state)
	rejected.set_player_position(_cell_center(Vector2i(22, 29)))
	var no_inputs := rejected.execute_crafting_command(CraftingCommandScript.start_project(Vector2i(22, 29), "core:saw_planks"))
	var no_project := rejected.execute_crafting_command(CraftingCommandScript.work_project(Vector2i(22, 29)))
	var no_blueprint := rejected.execute_construction_command(ConstructionCommandScript.work_blueprint(Vector2i(22, 29)))
	_expect(not bool(no_inputs.get("success", false)) and not bool(no_project.get("success", false)) and not bool(no_blueprint.get("success", false)) and is_equal_approx(rejected.get_player_energy(), 31.5), "missing crafting inputs, crafting projects, and construction blueprints spend no player energy")
	var roof_state := Simulation.create_new_state()
	roof_state["player_energy"] = 31.5
	(roof_state["flags"] as Dictionary)["tools_found"] = true
	(roof_state["flags"] as Dictionary)["repair_stage"] = 1
	(roof_state["inventory"] as Dictionary)["core:plank"] = 9
	(roof_state["inventory"] as Dictionary)["core:wood"] = 20
	var insufficient_roof := Simulation.new(roof_state)
	insufficient_roof.set_player_position(insufficient_roof.get_interaction_target_position("core:repair_room"))
	var before_roof_rejection := insufficient_roof.export_state()
	var roof_rejected := insufficient_roof.execute_interaction("core:repair_room")
	_expect(not bool(roof_rejected.get("success", false)) and insufficient_roof.export_state() == before_roof_rejection, "nine boards and spare logs cannot cover the roof or partially consume its stock")

	var early_state := Simulation.create_new_state()
	early_state["player_energy"] = 20.0
	(early_state["inventory"] as Dictionary)["core:wood"] = 1
	var early := Simulation.new(early_state)
	var prepared := _interact_near(early, "bed_site")
	_expect(bool(prepared.get("success", false)) and bool(early.get_flags().get("bed_ready", false)), "daytime bedding preparation is available under an open roof")
	_expect(not early.is_roof_covered() and early.get_player_energy() > 20.0 and early.get_item_count("core:wood") == 1, "free starter bedroll supports daytime rest without repairing the roof or consuming wood")
	var repeated_early := early.execute_interaction("core:bed_site")
	_expect(bool(repeated_early.get("success", false)) and early.get_day() == 1, "daytime rest does not skip a night")

	var poor_state := Simulation.create_new_game_state()
	poor_state["player_energy"] = 0.0
	var poor := Simulation.new(poor_state)
	poor.advance_minutes(Simulation.EVENING_MINUTE - poor.get_minute_of_day())
	poor.set_player_position(poor.get_interaction_target_position("core:bed_site"))
	var poor_inventory := poor.get_inventory()
	var poor_sleep := poor.execute_interaction("core:bed_site")
	_expect(bool(poor_sleep.get("success", false)) and poor.get_day() == 2 and poor.get_time_text() == "07:00", "an unprepared first night reaches morning without roof, tools, food, water, or bedding")
	_expect(poor.get_player_energy() > 0.0 and poor.get_player_energy() < poor.get_player_energy_max(), "an open roof restores a partial positive amount of player energy")
	_expect(poor.get_inventory() == poor_inventory and not poor.is_roof_covered(), "poor sleep does not demand missing resources or silently repair the roof")
	_expect(bool(poor.get_flags().get("first_night_complete", false)) and not bool(poor.get_flags().get("comfortable_sleep_completed", true)), "surviving a poor first night does not finish the comfortable-start result")
	_expect(poor.get_current_objective_key() != "first_night.objective.meet_neighbor", "poor sleep keeps the roof route as the current objective")
	var poor_reload := Simulation.new(JSON.parse_string(JSON.stringify(poor.export_state())) as Dictionary)
	_expect(is_equal_approx(poor_reload.get_player_energy(), poor.get_player_energy()) and not poor_reload.is_roof_covered() and not bool(poor_reload.get_flags().get("comfortable_sleep_completed", true)), "poor-night energy and unfinished roof survive serialization")

	var covered_state := Simulation.create_new_state()
	covered_state["player_energy"] = 17.5
	(covered_state["flags"] as Dictionary)["repair_stage"] = 2
	var covered := Simulation.new(covered_state)
	_expect(covered.is_roof_covered(), "roof coverage is complete before the optional final room-finishing stage")
	covered.advance_minutes(Simulation.EVENING_MINUTE - covered.get_minute_of_day())
	covered.set_player_position(covered.get_interaction_target_position("core:bed_site"))
	var covered_sleep := covered.execute_interaction("core:bed_site")
	_expect(bool(covered_sleep.get("success", false)) and is_equal_approx(covered.get_player_energy(), covered.get_player_energy_max()), "covered-roof sleep restores full energy without optional campfire, food, water, bedding, or stage-three finishing")
	_expect(bool(covered.get_flags().get("comfortable_sleep_completed", false)), "covered-roof sleep completes the comfortable-start result")
	var morning_energy := covered.get_player_energy()
	var repeated_sleep := covered.execute_interaction("core:bed_site")
	_expect(bool(repeated_sleep.get("success", false)) and covered.get_day() == 2 and is_equal_approx(covered.get_player_energy(), morning_energy), "morning bed interaction offers short rest without skipping another night")


func _test_player_energy_save_migration() -> void:
	var legacy := Simulation.create_new_state()
	legacy["version"] = 23
	legacy.erase("player_energy")
	(legacy["flags"] as Dictionary).erase("comfortable_sleep_completed")
	(legacy["flags"] as Dictionary)["repair_stage"] = 2
	var original_legacy := legacy.duplicate(true)
	var migrated := Simulation.new(legacy)
	_expect(is_equal_approx(migrated.get_player_energy(), migrated.get_player_energy_max()), "v23 saves without player energy receive the safe full-energy default")
	_expect(migrated.is_roof_covered() and migrated.get_object_stage("repair") == 2, "v23 energy migration preserves historical roof repair")
	_expect(legacy == original_legacy, "energy migration does not mutate the caller's source state")
	var current := migrated.export_state()
	current["player_energy"] = 27.5
	current["day"] = 2
	current["minute_of_day"] = 7 * 60
	(current["flags"] as Dictionary)["first_night_complete"] = true
	(current["flags"] as Dictionary)["comfortable_sleep_completed"] = true
	var restored := Simulation.new(JSON.parse_string(JSON.stringify(current)) as Dictionary)
	_expect(is_equal_approx(restored.get_player_energy(), 27.5), "fractional player energy survives JSON save/load")
	_expect(restored.is_roof_covered() and bool(restored.get_flags().get("comfortable_sleep_completed", false)), "roof and comfortable-sleep state survive JSON save/load")
	var second_reload := Simulation.new(JSON.parse_string(JSON.stringify(restored.export_state())) as Dictionary)
	_expect(second_reload.export_state() == restored.export_state(), "repeated energy save normalization is idempotent")
	var invalid := Simulation.create_new_state()
	invalid["player_energy"] = "invalid"
	_expect(is_equal_approx(Simulation.new(invalid).get_player_energy(), migrated.get_player_energy_max()), "invalid player energy receives the safe default")
	invalid["player_energy"] = -10.0
	_expect(is_equal_approx(Simulation.new(invalid).get_player_energy(), 0.0), "negative player energy clamps to zero")
	invalid["player_energy"] = migrated.get_player_energy_max() + 10.0
	_expect(is_equal_approx(Simulation.new(invalid).get_player_energy(), migrated.get_player_energy_max()), "player energy above the domain maximum clamps to that maximum")


func _test_starter_resources_are_accessible_across_seeds() -> void:
	var seeds: Array[int] = [Simulation.DEFAULT_SEED, 4127, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109]
	for seed_value: int in seeds:
		var simulation := Simulation.new(Simulation.create_new_game_state(seed_value))
		var spawn := simulation.get_player_position()
		var resource_sets: Array = [simulation.get_surface_boulders(), simulation.get_surface_trees()]
		var minimum_nearby: Array[int] = [8, 16]
		for kind_index: int in range(resource_sets.size()):
			var resources: Array = resource_sets[kind_index]
			var nearby_reachable := 0
			for resource: Dictionary in resources:
				var position := resource.get("position", Vector2.ZERO) as Vector2
				_expect(not WaterMapScript.contains_cell(_surface_route_cell(position)), "seed %d keeps generated resources off water" % seed_value)
				if spawn.distance_to(position) >= 28.0 * Content.CELL_SIZE:
					continue
				if not _surface_route_path(simulation, position, Content.INTERACTION_RANGE).is_empty():
					nearby_reachable += 1
			_expect(nearby_reachable >= minimum_nearby[kind_index], "seed %d supplies plentiful reachable starter %s within twenty-eight cells" % [seed_value, "stone" if kind_index == 0 else "trees"])
		_expect(simulation.get_surface_boulders().size() >= 90 and simulation.get_surface_boulders().size() <= 110, "new map supplies the expanded stone reserve")
		_expect(simulation.get_surface_trees().size() >= 180 and simulation.get_surface_trees().size() <= 220, "new map supplies the expanded wood reserve")
		_expect(simulation.get_surface_boulders().size() >= ResourceNodeCatalogScript.BOULDER_COUNT_MIN and simulation.get_surface_boulders().size() <= ResourceNodeCatalogScript.BOULDER_COUNT_MAX, "starter placement preserves total boulder bounds")
		_expect(simulation.get_surface_trees().size() >= ResourceNodeCatalogScript.TREE_COUNT_MIN and simulation.get_surface_trees().size() <= ResourceNodeCatalogScript.TREE_COUNT_MAX, "starter placement preserves total tree bounds")


func _test_resource_layout_versions_preserve_existing_saves() -> void:
	var seed_value := 247061
	var previous_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/resources_layout_2_seed_247061.json"))
	_expect(typeof(previous_data) == TYPE_DICTIONARY, "pre-density layout fixture is readable")
	if typeof(previous_data) != TYPE_DICTIONARY:
		return
	var previous := previous_data as Dictionary
	var previous_boulders := ResourceNodeCatalogScript.generate_surface_boulders(seed_value, 2)
	var previous_trees := ResourceNodeCatalogScript.generate_surface_trees(seed_value, previous_boulders, 2)
	var previous_berries := ResourceNodeCatalogScript.generate_berry_bushes(seed_value, previous_boulders, previous_trees, 2)
	_expect(JSON.parse_string(JSON.stringify(previous_boulders)) == previous.get("resource_nodes"), "layout 2 boulders match the independent pre-density fixture")
	_expect(JSON.parse_string(JSON.stringify(previous_trees)) == previous.get("tree_nodes"), "layout 2 trees match the independent pre-density fixture")
	_expect(JSON.parse_string(JSON.stringify(previous_berries)) == previous.get("berry_bushes"), "layout 2 berries match the independent pre-density fixture")
	var previous_state := Simulation.create_new_state(seed_value, 2)
	(previous_state["tree_nodes"] as Array)[0]["stage_id"] = "stump"
	previous_state["collected"] = {String(previous_boulders[0]["id"]): true}
	var reloaded_previous := Simulation.new(JSON.parse_string(JSON.stringify(previous_state)) as Dictionary)
	_expect(int(reloaded_previous.export_state().get("resource_generation_version", -1)) == 2, "existing layout 2 keeps its profile after the density increase")
	_expect(reloaded_previous.export_state().get("tree_nodes") == previous_state.get("tree_nodes") and reloaded_previous.export_state().get("resource_nodes") == previous_state.get("resource_nodes"), "existing layout 2 keeps positions, yields, and stumps without respawning resources")
	_expect(reloaded_previous.is_collected(String(previous_boulders[0]["id"])), "existing layout 2 keeps exhausted stone")
	for berry: Dictionary in previous_berries:
		_expect(reloaded_previous.get_interaction_target_position(String(berry["id"])).is_equal_approx(ResourceNodeCatalogScript.to_interactable(berry)["position"] as Vector2), "existing layout 2 keeps berry positions")
	var invalid_previous := previous_state.duplicate(true)
	invalid_previous["tree_nodes"] = []
	invalid_previous["resource_nodes"] = []
	var regenerated_previous := Simulation.new(invalid_previous)
	_expect(regenerated_previous.export_state().get("tree_nodes") == previous_trees and regenerated_previous.export_state().get("resource_nodes") == previous_boulders, "layout 2 invalid arrays regenerate the previous sparse layout")
	var historical_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_resources_seed_247061.json"))
	_expect(typeof(historical_data) == TYPE_DICTIONARY, "independent historical resource fixture is readable")
	if typeof(historical_data) != TYPE_DICTIONARY:
		return
	var historical := historical_data as Dictionary
	_expect(int(historical.get("seed", -1)) == seed_value, "historical fixture identifies its original world seed")
	var legacy_boulders: Array[Dictionary] = ResourceNodeCatalogScript.generate_surface_boulders(seed_value, ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION)
	var legacy_trees: Array[Dictionary] = ResourceNodeCatalogScript.generate_surface_trees(seed_value, legacy_boulders, ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION)
	var expected_legacy_berries := ResourceNodeCatalogScript.generate_berry_bushes(seed_value, legacy_boulders, legacy_trees, ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION)
	_expect(JSON.parse_string(JSON.stringify(legacy_boulders)) == historical.get("resource_nodes"), "legacy boulder generation matches the independent pre-package fixture")
	_expect(JSON.parse_string(JSON.stringify(legacy_trees)) == historical.get("tree_nodes"), "legacy tree generation matches the independent pre-package fixture")
	_expect(JSON.parse_string(JSON.stringify(expected_legacy_berries)) == historical.get("berry_bushes"), "legacy berry generation matches the independent pre-package fixture")
	var oldest_state := Simulation.create_new_state(seed_value)
	oldest_state["version"] = 13
	oldest_state.erase("resource_generation_version")
	oldest_state.erase("resource_nodes")
	oldest_state.erase("tree_nodes")
	var oldest := Simulation.new(oldest_state)
	_expect(JSON.parse_string(JSON.stringify(oldest.export_state().get("resource_nodes"))) == historical.get("resource_nodes") and JSON.parse_string(JSON.stringify(oldest.export_state().get("tree_nodes"))) == historical.get("tree_nodes"), "older saves without persisted resource arrays regenerate their original legacy layout")
	for berry: Dictionary in historical.get("berry_bushes", []) as Array:
		var historical_cell := berry.get("cell", []) as Array
		_expect(oldest.get_interaction_target_position(String(berry.get("id", ""))).is_equal_approx(Content.cell_center(int(historical_cell[0]), int(historical_cell[1]))), "older saves without resource arrays retain their legacy berry coordinates")
	var legacy_state := Simulation.create_new_state(seed_value)
	legacy_state["version"] = 22
	legacy_state.erase("resource_generation_version")
	legacy_state["resource_nodes"] = legacy_boulders.duplicate(true)
	legacy_state["tree_nodes"] = legacy_trees.duplicate(true)
	var depleted_id := String(legacy_boulders[0].get("id", ""))
	var worked_id := String(legacy_trees[0].get("id", ""))
	var tool_instance_id := "core:item_instance_000100"
	legacy_state["collected"] = {depleted_id: true}
	legacy_state["resource_work"] = {worked_id: 3}
	legacy_state["resource_work_tool_instances"] = {worked_id: tool_instance_id}
	legacy_state["item_instances"] = [{
		"instance_id": tool_instance_id, "item_id": "core:axe", "state": {},
		"location": {"kind": "inventory", "id": ""},
	}]
	legacy_state["hotbar_slots"] = [tool_instance_id, "", "", "", ""]
	legacy_state["active_hotbar_slot"] = 0
	var migrated := Simulation.new(legacy_state)
	var migrated_state := migrated.export_state()
	_expect(int(migrated_state.get("resource_generation_version", -1)) == ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION, "v22 saves without a layout field retain the legacy generator")
	_expect(migrated_state.get("resource_nodes") == legacy_boulders, "migration preserves legacy boulder IDs, coordinates, and yields")
	_expect(migrated_state.get("tree_nodes") == legacy_trees, "migration preserves legacy tree IDs, coordinates, and yields")
	_expect(migrated.is_collected(depleted_id), "migration preserves already mined legacy resources")
	_expect(migrated.get_resource_work_progress(worked_id) == 3, "migration preserves interrupted legacy resource work")
	_expect(String((migrated_state.get("resource_work_tool_instances", {}) as Dictionary).get(worked_id, "")) == tool_instance_id, "migration preserves the physical tool responsible for interrupted work")
	var legacy_encoded: Variant = JSON.parse_string(JSON.stringify(migrated_state))
	var reloaded_legacy := Simulation.new(legacy_encoded as Dictionary)
	_expect(reloaded_legacy.export_state().get("resource_nodes") == legacy_boulders and reloaded_legacy.export_state().get("tree_nodes") == legacy_trees, "legacy resource layout survives a subsequent current-version reload")
	_expect(reloaded_legacy.is_collected(depleted_id) and reloaded_legacy.get_resource_work_progress(worked_id) == 3, "legacy depletion and partial work survive the next reload")
	var current_state := Simulation.create_new_game_state(seed_value)
	var invalid_current := current_state.duplicate(true)
	invalid_current["resource_nodes"] = []
	invalid_current["tree_nodes"] = []
	var repaired_current := Simulation.new(invalid_current)
	_expect(repaired_current.export_state().get("resource_nodes") == current_state.get("resource_nodes") and repaired_current.export_state().get("tree_nodes") == current_state.get("tree_nodes"), "invalid arrays in a current save regenerate the current layout rather than the legacy layout")
	var current_encoded: Variant = JSON.parse_string(JSON.stringify(current_state))
	var reloaded_current := Simulation.new(current_encoded as Dictionary)
	_expect(int(reloaded_current.export_state().get("resource_generation_version", -1)) == ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION, "new games explicitly retain the current resource generator")
	_expect(reloaded_current.export_state().get("resource_nodes") == current_state.get("resource_nodes") and reloaded_current.export_state().get("tree_nodes") == current_state.get("tree_nodes"), "new starter resource positions remain stable on reload")
	var expected_current_berries := ResourceNodeCatalogScript.generate_berry_bushes(seed_value, current_state.get("resource_nodes", []) as Array, current_state.get("tree_nodes", []) as Array, ResourceNodeCatalogScript.CURRENT_LAYOUT_VERSION)
	_expect(migrated.get_surface_berry_bushes().size() == expected_legacy_berries.size(), "legacy berry regeneration retains the legacy layout count")
	for berry: Dictionary in expected_legacy_berries:
		_expect(migrated.get_interaction_target_position(String(berry.get("id", ""))).is_equal_approx(ResourceNodeCatalogScript.to_interactable(berry).get("position", Vector2.ZERO) as Vector2), "legacy berry IDs retain their old positions")
	for berry: Dictionary in expected_current_berries:
		_expect(reloaded_current.get_interaction_target_position(String(berry.get("id", ""))).is_equal_approx(ResourceNodeCatalogScript.to_interactable(berry).get("position", Vector2.ZERO) as Vector2), "new berry IDs retain the current layout on reload")


func _test_resource_search_hints_follow_available_work() -> void:
	var simulation := Simulation.new(Simulation.create_new_game_state())
	_expect(simulation.get_resource_search_hint().is_empty(), "resource hints wait until the starter tools have been found")
	var fixture := simulation.export_state()
	(fixture["flags"] as Dictionary)["tools_found"] = true
	(fixture["flags"] as Dictionary)["repair_stage"] = 1
	simulation = Simulation.new(fixture)
	var first_hint := simulation.get_resource_search_hint()
	_expect(String(first_hint.get("kind", "")) == "wood", "the first missing construction resource is wood")
	var first_id := String(first_hint.get("target_id", ""))
	_expect(not first_id.is_empty(), "resource hints identify a generated world target")
	_expect(Localized.resolve(String(first_hint.get("direction_key", ""))) != String(first_hint.get("direction_key", "")), "resource hint directions resolve through localization")
	fixture = simulation.export_state()
	(fixture["collected"] as Dictionary)[first_id] = true
	var depleted := Simulation.new(fixture)
	_expect(String(depleted.get_resource_search_hint().get("target_id", "")) != first_id, "resource hints skip a depleted closest tree")
	fixture = simulation.export_state()
	for node: Dictionary in fixture["tree_nodes"] as Array:
		if String(node.get("id", "")) == first_id:
			node["stage_id"] = "stump"
	var stump := Simulation.new(fixture)
	var stump_hint := stump.get_resource_search_hint()
	_expect(not stump_hint.is_empty() and String(stump_hint.get("target_id", "")) != first_id, "wood hints skip a nearby stump that yields no wood")
	fixture = simulation.export_state()
	for node: Dictionary in fixture["tree_nodes"] as Array:
		if String(node.get("id", "")) != first_id:
			(fixture["collected"] as Dictionary)[String(node.get("id", ""))] = true
	var only_target := Simulation.new(fixture)
	var target := only_target.get_interaction_target_position(first_id)
	only_target.set_player_position(target + Vector2(32.0, 0.0))
	var nearby_hint := only_target.get_resource_search_hint()
	_expect(String(nearby_hint.get("direction_key", "")) == "resource.direction.nearby" and int(nearby_hint.get("distance_cells", -1)) == 1, "resource hints describe an adjacent live target as nearby")
	only_target.set_player_position(target + Vector2(200.0, 0.0))
	var west_hint := only_target.get_resource_search_hint()
	_expect(String(west_hint.get("direction_key", "")) == "resource.direction.west" and int(west_hint.get("distance_cells", -1)) == 7, "resource hints use the target direction and rounded-up cell distance")
	fixture = only_target.export_state()
	(fixture["collected"] as Dictionary)[first_id] = true
	_expect(Simulation.new(fixture).get_resource_search_hint().is_empty(), "exhausted wood resources produce no misleading target")
	fixture = simulation.export_state()
	(fixture["flags"] as Dictionary)["first_night_complete"] = true
	_expect(not Simulation.new(fixture).get_resource_search_hint().is_empty(), "a poor first night retains gathering guidance for the unfinished roof route")
	(fixture["flags"] as Dictionary)["comfortable_sleep_completed"] = true
	(fixture["flags"] as Dictionary)["repair_stage"] = 2
	_expect(Simulation.new(fixture).get_resource_search_hint().is_empty(), "comfortable sleep completion stops showing the starter resource hint")
	fixture = simulation.export_state()
	(fixture["flags"] as Dictionary)["repair_stage"] = 2
	_expect(Simulation.new(fixture).get_resource_search_hint().is_empty(), "a covered roof does not require optional campfire stone in the starter hint")
	fixture = simulation.export_state()
	(fixture["inventory"] as Dictionary)["core:wood"] = int(BuildingCatalogScript.new().get_material_cost("core:workbench").get("core:wood", 0)) + int(CraftingCatalogScript.new().get_inputs("core:saw_planks").get("core:wood", 0))
	_expect(Simulation.new(fixture).get_resource_search_hint().is_empty(), "wood sufficient for the workbench and first boards does not request extra gathering")


func _surface_route_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / Content.CELL_SIZE), floori(position.y / Content.CELL_SIZE))


func _surface_route_path(simulation: World, target: Vector2, max_distance: float) -> Array[Vector2i]:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Content.MAP_SIZE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for cell: Vector2i in FirstNightNavigationScript.blocked_cells():
		grid.set_point_solid(cell)
	var buildings := BuildingCatalogScript.new()
	for structure: Dictionary in simulation.get_structures():
		var building_id := String(structure.get("building_id", ""))
		if not bool(buildings.get_definition(building_id).get("blocks_movement", false)):
			continue
		var origin_data: Array = structure.get("cell", []) as Array
		for cell: Vector2i in buildings.get_footprint_cells(building_id, Vector2i(int(origin_data[0]), int(origin_data[1]))):
			grid.set_point_solid(cell)
	for resource: Dictionary in simulation.get_surface_boulders():
		grid.set_point_solid(_surface_route_cell(resource.get("position", Vector2.ZERO) as Vector2))
	for resource: Dictionary in simulation.get_surface_trees():
		if String(resource.get("presentation_id", "")) == "surface_tree":
			grid.set_point_solid(_surface_route_cell(resource.get("position", Vector2.ZERO) as Vector2))
	var from_cell := _surface_route_cell(simulation.get_player_position())
	var target_cell := _surface_route_cell(target)
	var best_path: Array[Vector2i] = []
	if not grid.is_in_boundsv(from_cell) or grid.is_point_solid(from_cell):
		return best_path
	var radius := ceili(max_distance / float(Content.CELL_SIZE))
	for y: int in range(target_cell.y - radius, target_cell.y + radius + 1):
		for x: int in range(target_cell.x - radius, target_cell.x + radius + 1):
			var candidate := Vector2i(x, y)
			if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate):
				continue
			if max_distance > 0.0 and _cell_center(candidate).distance_to(target) > max_distance:
				continue
			var candidate_path: Array[Vector2i] = grid.get_id_path(from_cell, candidate)
			if not candidate_path.is_empty() and (best_path.is_empty() or candidate_path.size() < best_path.size()):
				best_path = candidate_path
	return best_path


func _surface_route_move(simulation: World, target: Vector2, max_distance: float = Content.INTERACTION_RANGE) -> bool:
	var path := _surface_route_path(simulation, target, max_distance)
	if path.is_empty():
		_expect(false, "ordinary route cannot reach %s from %s" % [target, simulation.get_player_position()])
		return false
	var player_script := load("res://src/player/player_controller.gd") as Script
	var move_speed := float(player_script.get_script_constant_map().get("MOVE_SPEED", 0.0))
	if move_speed <= 0.0:
		_expect(false, "ordinary route requires the actual positive player movement speed")
		return false
	for cell: Vector2i in path:
		var next_position := _cell_center(cell)
		var distance := simulation.get_player_position().distance_to(next_position)
		simulation.set_player_position(next_position)
		simulation.tick(distance / move_speed)
	if max_distance == 0.0:
		var distance := simulation.get_player_position().distance_to(target)
		simulation.set_player_position(target)
		simulation.tick(distance / move_speed)
	return true


func _surface_route_take_tool(simulation: World, item_id: String) -> String:
	for stored: Dictionary in simulation.get_storage_items():
		if String(stored.get("item_id", "")) != item_id:
			continue
		var raw_cell: Array = stored.get("cell", []) as Array
		if not _surface_route_move(simulation, _cell_center(Vector2i(int(raw_cell[0]), int(raw_cell[1])))):
			return ""
		var instance_id := String(stored.get("instance_id", ""))
		var taken := simulation.transfer_storage_stack_to_inventory(Vector2i(int(raw_cell[0]), int(raw_cell[1])), String(stored.get("placement_id", "")))
		if not bool(taken.get("success", false)):
			_expect(false, "ordinary route cannot retrieve %s: %s" % [item_id, taken])
			return ""
		var assigned := simulation.assign_hotbar_slot(0, instance_id)
		var selected := simulation.select_hotbar_slot(0)
		if not bool(assigned.get("success", false)) or not bool(selected.get("success", false)):
			_expect(false, "ordinary route cannot select retrieved physical tool %s" % item_id)
			return ""
		_expect(String(simulation.get_active_item_instance().get("instance_id", "")) == instance_id, "ordinary route equips the exact pantry tool, without a replacement instance")
		return instance_id
	_expect(false, "ordinary starter pantry is missing %s" % item_id)
	return ""


func _surface_route_build_workbench(simulation: World) -> Vector2i:
	var catalog := BuildingCatalogScript.new()
	var building_id := "core:workbench"
	var chosen := Vector2i(-1, -1)
	var before_placement_energy := simulation.get_player_energy()
	for y: int in range(27, 33):
		for x: int in range(21, 30):
			var candidate := Vector2i(x, y)
			var path := _surface_route_path(simulation, _cell_center(candidate), Content.INTERACTION_RANGE)
			if path.is_empty() or catalog.get_footprint_cells(building_id, candidate).has(path[-1]):
				continue
			var placed := simulation.execute_construction_command(ConstructionCommandScript.place_blueprint(candidate, building_id))
			if bool(placed.get("success", false)):
				chosen = candidate
				break
		if chosen.x >= 0:
			break
	if chosen.x < 0:
		_expect(false, "ordinary route cannot place a reachable workbench outside its actor's standing cell")
		return chosen
	_expect(is_equal_approx(simulation.get_player_energy(), before_placement_energy), "placing a workbench blueprint does not charge a work minute")
	_expect(simulation.get_current_objective_key() == "first_night.objective.finish_workbench", "an unfinished workbench receives its own ordinary objective")
	if not _surface_route_move(simulation, _cell_center(chosen)):
		return Vector2i(-1, -1)
	var delivered := simulation.execute_construction_command(ConstructionCommandScript.deliver_blueprint_materials(chosen))
	if not bool(delivered.get("success", false)):
		_expect(false, "ordinary route cannot deliver earned workbench logs: %s" % delivered)
		return Vector2i(-1, -1)
	var required := catalog.get_work_minutes(building_id)
	if required <= 0 or required > 24 * 60:
		_expect(false, "ordinary workbench construction has an invalid bounded work duration")
		return Vector2i(-1, -1)
	var starting_energy := simulation.get_player_energy()
	var started_at := simulation.get_elapsed_game_minutes()
	var result: Dictionary = {}
	for minute: int in range(required):
		simulation.advance_minutes(1)
		result = simulation.execute_construction_command(ConstructionCommandScript.work_blueprint(chosen))
		if not bool(result.get("success", false)):
			_expect(false, "ordinary workbench construction stopped at minute %d: %s" % [minute, result])
			return Vector2i(-1, -1)
	_expect(String(result.get("reason_id", "")) == "core:structure_completed", "ordinary route finishes its own workbench")
	_expect(simulation.get_current_objective_key() == "first_night.objective.saw_planks", "completed workbench points to the existing board recipe")
	_expect(simulation.get_elapsed_game_minutes() - started_at == required, "ordinary workbench construction consumes its elapsed work minutes")
	_expect(is_equal_approx(simulation.get_player_energy(), maxf(0.0, starting_energy - float(required))), "successful player construction minutes spend energy exactly once")
	return chosen


func _surface_route_saw_planks(simulation: World, workbench_cell: Vector2i) -> bool:
	if not _surface_route_move(simulation, _cell_center(workbench_cell)):
		return false
	var before_start_energy := simulation.get_player_energy()
	var started := simulation.execute_crafting_command(CraftingCommandScript.start_project(workbench_cell, "core:saw_planks"))
	if not bool(started.get("success", false)):
		_expect(false, "ordinary route cannot start its earned plank project: %s" % started)
		return false
	_expect(is_equal_approx(simulation.get_player_energy(), before_start_energy), "reserving recipe input does not charge a crafting work minute")
	_expect(simulation.get_current_objective_key() == "first_night.objective.finish_saw_planks" and simulation.get_resource_search_hint().is_empty(), "reserved saw inputs point to finishing the project without extra gathering")
	var required := CraftingCatalogScript.new().get_work_minutes("core:saw_planks")
	if required <= 0 or required > 24 * 60:
		_expect(false, "ordinary plank recipe has an invalid bounded work duration")
		return false
	var starting_energy := simulation.get_player_energy()
	var started_at := simulation.get_elapsed_game_minutes()
	var result: Dictionary = {}
	for minute: int in range(required):
		simulation.advance_minutes(1)
		result = simulation.execute_crafting_command(CraftingCommandScript.work_project(workbench_cell))
		if not bool(result.get("success", false)):
			_expect(false, "ordinary plank crafting stopped at minute %d: %s" % [minute, result])
			return false
	_expect(String(result.get("reason_id", "")) == "core:crafting_completed", "ordinary route completes its first board recipe")
	_expect(simulation.get_current_objective_key() == "first_night.objective.pick_up_planks" and simulation.get_resource_search_hint().is_empty(), "physical board outputs point to pickup without requesting more logs")
	_expect(simulation.get_elapsed_game_minutes() - started_at == required, "ordinary plank crafting consumes its elapsed work minutes")
	_expect(is_equal_approx(simulation.get_player_energy(), maxf(0.0, starting_energy - float(required))), "successful player crafting minutes spend energy exactly once")
	return _surface_route_pick_drops(simulation, result.get("created_drop_ids", []) as Array)


func _surface_route_store_item(simulation: World, item_id: String, instance_id: String) -> bool:
	var stack_index := -1
	for placement: Dictionary in simulation.get_inventory_placements():
		if String(placement.get("instance_id", "")) == instance_id:
			stack_index = int(placement.get("stack_index", -1))
			break
	if stack_index < 0:
		_expect(false, "ordinary route cannot find carried physical tool %s" % instance_id)
		return false
	for zone: Dictionary in simulation.get_storage_zones():
		for raw_cell: Array in zone.get("cells", []) as Array:
			var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			if not _surface_route_move(simulation, _cell_center(cell)):
				return false
			var before := simulation.export_state()
			var stored := simulation.transfer_inventory_stack_to_storage(cell, item_id, stack_index)
			if bool(stored.get("success", false)):
				var instance := simulation.get_item_instance(instance_id)
				_expect(String((instance.get("location", {}) as Dictionary).get("kind", "")) == "storage", "ordinary return preserves the exact physical tool in storage")
				return true
			_expect(simulation.export_state() == before, "a refused pantry transfer preserves the carried item and selected instance")
	_expect(false, "ordinary route cannot return %s to any pantry cell" % item_id)
	return false


func _surface_route_harvest(simulation: World, resources: Array[Dictionary]) -> bool:
	var closest: Dictionary = {}
	var closest_distance := INF
	for resource: Dictionary in resources:
		var position := resource.get("position", Vector2.ZERO) as Vector2
		var distance := simulation.get_player_position().distance_squared_to(position)
		if distance < closest_distance and not _surface_route_path(simulation, position, Content.INTERACTION_RANGE).is_empty():
			closest = resource
			closest_distance = distance
	if closest.is_empty():
		_expect(false, "ordinary route has no reachable generated resource")
		return false
	var target_id := String(closest.get("id", ""))
	if not _surface_route_move(simulation, closest.get("position", Vector2.ZERO) as Vector2):
		return false
	var required := simulation.get_resource_work_required(target_id)
	if required <= 0 or required > 24 * 60:
		_expect(false, "ordinary resource %s has invalid bounded work duration %d" % [target_id, required])
		return false
	var started_at := simulation.get_elapsed_game_minutes()
	var starting_energy := simulation.get_player_energy()
	var all_drop_ids: Array[String] = []
	var result: Dictionary = {}
	for step: int in range(required):
		simulation.advance_minutes(1)
		result = simulation.execute_resource_work(simulation.PLAYER_ACTOR_ID, target_id)
		if not bool(result.get("success", false)):
			_expect(false, "ordinary resource work stopped at %s step %d: %s" % [target_id, step, result])
			return false
		for drop_id: Variant in result.get("created_drop_ids", []) as Array:
			all_drop_ids.append(String(drop_id))
	_expect(simulation.get_elapsed_game_minutes() - started_at == required, "ordinary resource work consumes its actual elapsed game minutes")
	_expect(is_equal_approx(simulation.get_player_energy(), maxf(0.0, starting_energy - float(required))), "successful player gathering minutes spend energy exactly once")
	_expect(String(result.get("reason_id", "")) == "core:resource_depleted", "ordinary resource work completes before pickup")
	_expect(not all_drop_ids.is_empty(), "ordinary resource work creates physical world drops")
	return _surface_route_pick_drops(simulation, all_drop_ids)


func _surface_route_pick_drops(simulation: World, drop_ids: Array) -> bool:
	if drop_ids.is_empty():
		_expect(false, "ordinary work must expose actual physical drops before pickup")
		return false
	for drop_id_value: Variant in drop_ids:
		var drop_id := String(drop_id_value)
		var found: Dictionary = {}
		for drop: Dictionary in simulation.get_world_drops():
			if String(drop.get("drop_id", "")) == drop_id:
				found = drop
				break
		if found.is_empty():
			_expect(false, "ordinary route cannot find its physical drop %s" % drop_id)
			return false
		var raw_position: Array = found.get("position", []) as Array
		if not _surface_route_move(simulation, Vector2(float(raw_position[0]), float(raw_position[1])), 0.0):
			return false
		var picked := simulation.try_pickup_world_drop(drop_id)
		if not bool(picked.get("success", false)):
			_expect(false, "ordinary route cannot pick up %s: %s" % [drop_id, picked])
			return false
	return true


func _surface_route_interact(simulation: World, target_id: String) -> bool:
	var definition := simulation.content.get_interactable(target_id)
	if definition.is_empty() or not bool(definition.get("spawn_in_world", true)):
		_expect(false, "ordinary route refuses missing or hidden target %s" % target_id)
		return false
	if not _surface_route_move(simulation, definition.get("position", Vector2.ZERO) as Vector2):
		return false
	var result := simulation.execute_interaction(target_id)
	if not bool(result.get("success", false)):
		_expect(false, "ordinary interaction with %s failed: %s" % [target_id, result])
		return false
	return true


func _test_serialization_round_trip() -> void:
	var original: World = Simulation.new()
	_interact_near(original, "old_tools")
	original.try_pickup_item(FirstNightContent.WOOD_ID, 3)
	original.set_player_position(Vector2(321.5, 654.25))
	original.advance_minutes(37)

	var encoded: String = JSON.stringify(original.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "serialized state parses as a dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: World = Simulation.new(decoded as Dictionary)
	_expect(restored.get_time_text() == original.get_time_text(), "time survives serialization")
	_expect(restored.get_player_position().is_equal_approx(original.get_player_position()), "position survives serialization")
	_expect(restored.get_item_count(FirstNightContent.WOOD_ID) == 3, "inventory survives serialization")
	_expect(bool(restored.get_flags()["tools_found"]), "flags survive serialization")


func _test_duplicate_collection_is_rejected() -> void:
	var simulation: World = Simulation.new()
	var first: Dictionary = _work_resource_to_completion(
		simulation,
		"wood_north"
	)
	var second: Dictionary = simulation.execute_resource_work(
		simulation.PLAYER_ACTOR_ID,
		"wood_north"
	)
	_expect(bool(first["success"]), "first resource work completes")
	_expect(not bool(second["success"]), "depleted resource rejects duplicate work")
	_expect(
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 0,
		"resource work creates drops instead of inventory items"
	)


func _test_command_boundary_rejects_forged_commands() -> void:
	var simulation: World = Simulation.new()
	simulation.set_player_position(simulation.get_interaction_target_position("wood_north"))

	var wrong_actor: Dictionary = simulation.execute_command(
		"core:forged_player",
		"wood_north",
		simulation.ACTION_INTERACT
	)
	var wrong_action: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"wood_north",
		"core:collect_wood"
	)
	var wrong_target: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"core:forged_wood",
		simulation.ACTION_INTERACT
	)
	_expect(not bool(wrong_actor["success"]), "unknown actor is rejected")
	_expect(not bool(wrong_action["success"]), "unknown action is rejected")
	_expect(not bool(wrong_target["success"]), "unknown target is rejected")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "forged commands cannot create resources")

	simulation.set_player_position(simulation.get_interaction_target_position("core:first_neighbor"))
	var inactive_npc: Dictionary = simulation.execute_interaction("core:first_neighbor")
	_expect(not bool(inactive_npc["success"]), "inactive NPC cannot be talked to")


func _test_command_boundary_enforces_range_and_resolves_kind() -> void:
	var simulation: World = Simulation.new()
	var distant_result: Dictionary = simulation.execute_resource_work(
		simulation.PLAYER_ACTOR_ID,
		"wood_north"
	)
	_expect(not bool(distant_result["success"]), "simulation rejects an out-of-range target")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "out-of-range command changes no inventory")

	simulation.set_player_position(simulation.get_interaction_target_position("stone_south"))
	var direct_result: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"stone_south",
		simulation.ACTION_INTERACT
	)
	_expect(
		not bool(direct_result["success"]),
		"direct interaction cannot bypass resource work"
	)
	var stone_result: Dictionary = _work_resource_to_completion(
		simulation,
		"stone_south"
	)
	_expect(bool(stone_result["success"]), "resource work succeeds near a real target")
	_expect(
		String(stone_result.get("drop_item_id", "")) == FirstNightContent.STONE_ID,
		"target catalog resolves the dropped resource kind"
	)
	_expect(int(stone_result.get("drop_amount", 0)) == 3, "resource work returns the configured yield")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 0, "completed work does not bypass ground pickup")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "caller cannot spoof resource kind")


func _test_resource_work_progress_completion_and_serialization() -> void:
	var simulation: World = Simulation.new()
	var target_id := "wood_north"
	_equip_test_resource_tool(simulation, target_id)
	simulation.set_player_position(
		simulation.get_interaction_target_position(target_id)
	)

	var first: Dictionary = simulation.execute_resource_work(
		simulation.PLAYER_ACTOR_ID,
		target_id
	)
	_expect(bool(first.get("success", false)), "resource work minute succeeds")
	_expect(
		simulation.get_resource_work_progress(target_id) == 1,
		"resource work progress increments by one minute"
	)

	var restored := World.new(simulation.export_state())
	_expect(
		restored.get_resource_work_progress(target_id) == 1,
		"resource work progress survives serialization"
	)

	var completed: Dictionary = _work_resource_to_completion(
		restored,
		target_id
	)
	_expect(bool(completed.get("success", false)), "restored resource work completes")
	_expect(
		String(completed.get("reason_id", "")) == "core:resource_depleted",
		"completed work reports resource depletion"
	)
	_expect(restored.is_collected(target_id), "completed resource becomes unavailable")
	_expect(
		restored.get_resource_work_progress(target_id) == 0,
		"completed resource clears saved work progress"
	)
	_expect(
		completed.get("drop_origin", null) is Vector2,
		"completed resource returns an exact world drop origin"
	)
	_expect(
		restored.get_world_drops().size() == 3,
		"completed resource creates one persistent record per drop"
	)


func _test_resource_work_requires_selected_physical_tools() -> void:
	_expect(
		Localized.resolve("resource.feedback.axe_required").contains("топор")
			and Localized.resolve("resource.feedback.pickaxe_required").contains("кирку")
			and Localized.resolve("resource.feedback.tool_changed").contains("прервана"),
		"tool rejection and interruption messages are localized clearly"
	)
	var tree_id := "wood_north"
	var simulation: World = Simulation.new()
	simulation.set_player_position(
		simulation.get_interaction_target_position(tree_id)
	)
	var initial_time := simulation.get_time_text()
	var initial_energy := simulation.get_player_energy()
	var no_tool := simulation.execute_resource_work("core:player", tree_id)
	_expect(
		String(no_tool.get("reason_id", "")) == "core:resource_tool_not_selected"
			and not bool(no_tool.get("changed", true)),
		"empty hands reject tree work without a state change"
	)
	_expect(
		simulation.get_resource_work_progress(tree_id) == 0
			and simulation.get_time_text() == initial_time
			and is_equal_approx(simulation.get_player_energy(), initial_energy)
			and simulation.get_world_drops().is_empty(),
		"missing tool consumes no work, time, energy, or resource"
	)

	var axe_instance_id := _add_test_tool(simulation, "core:axe", false)
	var pickaxe_instance_id := _add_test_tool(simulation, "core:pickaxe", true, 0)
	var backpack_only := simulation.execute_resource_work("core:player", tree_id)
	_expect(
		String(backpack_only.get("reason_id", "")) == "core:resource_tool_not_selected"
			and simulation.get_resource_work_progress(tree_id) == 0
			and is_equal_approx(simulation.get_player_energy(), initial_energy),
		"having the required axe only in the backpack is insufficient"
	)
	_expect(
		String(simulation.get_active_item_instance().get("instance_id", ""))
			== pickaxe_instance_id,
		"the wrong selected tool is confirmed active for the rejection case"
	)

	var axe_slot := simulation.assign_hotbar_slot(1, axe_instance_id)
	_expect(bool(axe_slot.get("success", false)), "inventory axe can be assigned to hotbar")
	simulation.select_hotbar_slot(1)
	var started := simulation.execute_resource_work("core:player", tree_id)
	_expect(
		bool(started.get("success", false))
			and simulation.get_resource_work_progress(tree_id) == 1
			and is_equal_approx(simulation.get_player_energy(), initial_energy - 1.0),
		"selected axe allows work on a tree"
	)

	var energy_before_switch := simulation.get_player_energy()
	simulation.select_hotbar_slot(0)
	var interrupted := simulation.execute_resource_work("core:player", tree_id)
	_expect(
		String(interrupted.get("reason_id", "")) == "core:resource_work_tool_changed"
			and simulation.get_resource_work_progress(tree_id) == 0
			and not simulation.is_collected(tree_id)
			and is_equal_approx(simulation.get_player_energy(), energy_before_switch),
		"switching tools during work stops it before changing the tree"
	)
	var removed_tool_simulation: World = Simulation.new()
	removed_tool_simulation.set_player_position(
		removed_tool_simulation.get_interaction_target_position(tree_id)
	)
	var removed_axe_id := _add_test_tool(
		removed_tool_simulation,
		"core:axe",
		true,
		0
	)
	removed_tool_simulation.execute_resource_work("core:player", tree_id)
	removed_tool_simulation._clear_hotbar_instance(removed_axe_id)
	removed_tool_simulation._remove_item_instance(removed_axe_id)
	var removed_result := removed_tool_simulation.execute_resource_work(
		"core:player",
		tree_id
	)
	_expect(
		String(removed_result.get("reason_id", ""))
			== "core:resource_work_tool_changed"
			and removed_tool_simulation.get_resource_work_progress(tree_id) == 0
			and not removed_tool_simulation.is_collected(tree_id),
		"removing the selected axe during work interrupts without felling the tree"
	)

	simulation.select_hotbar_slot(1)
	var completed := _work_resource_to_completion(simulation, tree_id)
	_expect(
		bool(completed.get("success", false))
			and int(completed.get("drop_amount", 0)) == 3,
		"correct tool preserves the existing tree work duration and yield"
	)

	var boulder_simulation: World = Simulation.new()
	var boulders := boulder_simulation.get_surface_boulders()
	if boulders.is_empty():
		_failures += 1
		push_error("FAIL: tool requirement test has no generated surface boulder")
		return
	var boulder_id := String(boulders[0].get("id", ""))
	boulder_simulation.set_player_position(
		boulder_simulation.get_interaction_target_position(boulder_id)
	)
	_add_test_tool(boulder_simulation, "core:axe", true, 0)
	var wrong_pick := boulder_simulation.execute_resource_work("core:player", boulder_id)
	_expect(
		String(wrong_pick.get("reason_id", "")) == "core:resource_tool_not_selected"
			and boulder_simulation.get_resource_work_progress(boulder_id) == 0,
		"an axe cannot mine a boulder"
	)
	_add_test_tool(boulder_simulation, "core:pickaxe", true, 1)
	boulder_simulation.select_hotbar_slot(1)
	var right_pick := _work_resource_to_completion(boulder_simulation, boulder_id)
	_expect(
		bool(right_pick.get("success", false))
			and int(right_pick.get("drop_amount", 0)) >= 9
			and int(right_pick.get("drop_amount", 0)) <= 12,
		"selected pickaxe preserves the existing boulder yield"
	)

	var dropped := Simulation.new()
	dropped._create_resource_drops("test", "core:wood", 1, dropped.get_player_position())
	var drop_id := String((dropped.get_world_drops()[0] as Dictionary).get("drop_id", ""))
	var pickup := dropped.try_pickup_world_drop(drop_id)
	_expect(bool(pickup.get("success", false)), "dropped resources remain collectible without tools")


func _test_surface_boulders_are_seeded_and_workable() -> void:
	var state_a: Dictionary = Simulation.create_new_state(4127)
	var simulation := World.new(state_a)
	var same_seed := World.new(
		Simulation.create_new_state(4127)
	)
	var other_seed := World.new(
		Simulation.create_new_state(4128)
	)
	var boulders: Array[Dictionary] = simulation.get_surface_boulders()
	_expect(
		boulders.size() >= ResourceNodeCatalogScript.BOULDER_COUNT_MIN and boulders.size() <= ResourceNodeCatalogScript.BOULDER_COUNT_MAX,
		"world generation creates the expanded surface boulder reserve"
	)
	_expect(
		boulders == same_seed.get_surface_boulders(),
		"same world seed generates the same boulder locations"
	)
	var boulder_grouping_found := false
	for first_index: int in range(boulders.size()):
		for second_index: int in range(first_index + 1, boulders.size()):
			var first_pos: Vector2 = boulders[first_index]["position"] as Vector2
			var second_pos: Vector2 = boulders[second_index]["position"] as Vector2
			if first_pos.distance_to(second_pos) <= 32.0 * 3.0:
				boulder_grouping_found = true
	_expect(boulder_grouping_found, "boulders include nearby clusters")
	_expect(
		boulders != other_seed.get_surface_boulders(),
		"different world seed varies generated boulder locations"
	)
	for seed_value: int in range(100, 110):
		var seed_boulders := ResourceNodeCatalogScript.generate_surface_boulders(seed_value)
		var seed_trees := ResourceNodeCatalogScript.generate_surface_trees(
			seed_value,
			seed_boulders
		)
		_expect(
			seed_boulders.size() >= ResourceNodeCatalogScript.BOULDER_COUNT_MIN and seed_boulders.size() <= ResourceNodeCatalogScript.BOULDER_COUNT_MAX
				and seed_trees.size() >= ResourceNodeCatalogScript.TREE_COUNT_MIN and seed_trees.size() <= ResourceNodeCatalogScript.TREE_COUNT_MAX,
			"generated resource counts stay within target ranges across seeds"
		)
	for index: int in range(boulders.size()):
		var boulder: Dictionary = boulders[index]
		_expect(
			String(boulder.get("id", ""))
				== "core:surface_boulder_%02d" % (index + 1),
			"generated boulder IDs are stable and unique"
		)
	var legacy_state: Dictionary = Simulation.create_new_state(4129, ResourceNodeCatalogScript.LEGACY_LAYOUT_VERSION)
	legacy_state["version"] = 13
	legacy_state.erase("resource_generation_version")
	legacy_state.erase("resource_nodes")
	var migrated := World.new(legacy_state)
	_expect(
		migrated.get_surface_boulders().size() >= 30
			and migrated.get_surface_boulders().size() <= 35,
		"version 13 saves receive deterministic surface boulders"
	)
	if boulders.is_empty():
		return

	var first_boulder: Dictionary = boulders[0]
	var target_id: String = String(first_boulder.get("id", ""))
	var target_position: Vector2 = first_boulder.get(
		"position",
		Vector2.ZERO
	) as Vector2
	simulation.set_player_position(target_position)
	_expect(
		simulation.get_resource_work_required(target_id) == 8,
		"surface boulder uses the configured stone work duration"
	)
	var completed := _work_resource_to_completion(simulation, target_id)
	_expect(bool(completed.get("success", false)), "surface boulder can be mined")
	_expect(
		int(completed.get("drop_amount", 0)) >= 9
			and int(completed.get("drop_amount", 0)) <= 12,
		"surface boulder yields nine to twelve stones"
	)
	_expect(
		simulation.is_collected(target_id),
		"mined surface boulder remains depleted"
	)
	var restored := World.new(simulation.export_state())
	_expect(
		restored.get_surface_boulders() == boulders,
		"generated boulder layout survives a save-state round trip"
	)
	_expect(
		restored.is_collected(target_id)
			and restored.get_world_drops().size() == int(completed.get("drop_amount", 0)),
		"depletion and physical stone drops survive a save-state round trip"
	)


func _test_surface_trees_are_seeded_and_workable() -> void:
	var simulation := World.new(
		Simulation.create_new_state(7712)
	)
	var trees := simulation.get_surface_trees()
	var same_seed := World.new(
		Simulation.create_new_state(7712)
	)
	_expect(
		trees.size() >= ResourceNodeCatalogScript.TREE_COUNT_MIN and trees.size() <= ResourceNodeCatalogScript.TREE_COUNT_MAX,
		"world generation creates the expanded surface tree reserve"
	)
	_expect(
		trees == same_seed.get_surface_trees(),
		"same world seed generates the same tree groves"
	)
	var grove_found := false
	for first_index: int in range(trees.size()):
		for second_index: int in range(first_index + 1, trees.size()):
			var first_pos: Vector2 = trees[first_index]["position"] as Vector2
			var second_pos: Vector2 = trees[second_index]["position"] as Vector2
			if first_pos.distance_to(second_pos) <= 32.0 * 3.0:
				grove_found = true
	_expect(grove_found, "world generation places trees in groves")
	if trees.is_empty():
		return
	var tree: Dictionary = trees[0]
	var tree_id := String(tree.get("id", ""))
	_equip_test_resource_tool(simulation, tree_id)
	simulation.set_player_position(tree.get("position", Vector2.ZERO) as Vector2)
	_expect(
		simulation.get_resource_work_required(tree_id) == 8,
		"tree requires eight work steps"
	)
	var felled: Dictionary = {}
	for _step: int in range(8):
		felled = simulation.execute_resource_work("core:player", tree_id)
	_expect(
		bool(felled.get("success", false))
			and int(felled.get("drop_amount", 0)) >= 12
			and int(felled.get("drop_amount", 0)) <= 13,
		"felled tree drops twelve to thirteen logs"
	)
	var pinecones_before_stump: int = 0
	for drop: Dictionary in simulation.get_world_drops():
		if String(drop.get("item_id", "")) == "core:pinecone":
			pinecones_before_stump += int(drop.get("amount", 0))
	_expect(
		pinecones_before_stump >= 0 and pinecones_before_stump <= 8,
		"each of the eight tree work steps can drop at most one pinecone"
	)
	var stump: Dictionary = {}
	for tree_view: Dictionary in simulation.get_surface_trees():
		if String(tree_view.get("id", "")) == tree_id:
			stump = tree_view
			break
	_expect(
		String(stump.get("presentation_id", "")) == "surface_stump"
			and simulation.get_resource_work_required(tree_id) == 4,
		"felled tree becomes a stump requiring four more steps"
	)
	var restored := World.new(simulation.export_state())
	var saved_stump: Dictionary = {}
	for tree_view: Dictionary in restored.get_surface_trees():
		if String(tree_view.get("id", "")) == tree_id:
			saved_stump = tree_view
			break
	_expect(
		String(saved_stump.get("presentation_id", "")) == "surface_stump"
			and restored.get_world_drops().size() == simulation.get_world_drops().size(),
		"stump stage and dropped resources survive save/load"
	)
	for _step: int in range(4):
		restored.execute_resource_work("core:player", tree_id)
	_expect(restored.is_collected(tree_id), "cleared stump is depleted")
	var pinecones_after_stump: int = 0
	for drop: Dictionary in restored.get_world_drops():
		if String(drop.get("item_id", "")) == "core:pinecone":
			pinecones_after_stump += int(drop.get("amount", 0))
	_expect(
		pinecones_after_stump == pinecones_before_stump,
		"stump work does not produce pinecones"
	)

func _test_surface_berry_bushes_are_seeded_and_collectible() -> void:
	var simulation := World.new(
		Simulation.create_new_state(55821)
	)
	var bushes := simulation.get_surface_berry_bushes()
	var same_seed := World.new(
		Simulation.create_new_state(55821)
	)
	var different_seed := World.new(
		Simulation.create_new_state(55822)
	)
	_expect(
		bushes.size() >= ResourceNodeCatalogScript.BERRY_BUSH_COUNT_MIN
			and bushes.size() <= ResourceNodeCatalogScript.BERRY_BUSH_COUNT_MAX,
		"world generation creates the configured number of berry bushes"
	)
	_expect(
		bushes == same_seed.get_surface_berry_bushes(),
		"berry bush locations are stable for a world seed"
	)
	_expect(
		bushes != different_seed.get_surface_berry_bushes(),
		"berry bush locations vary with the world seed"
	)
	for starter_resource_id: String in [
		"core:wood_north",
		"core:wood_west",
		"core:wood_east",
		"core:stone_south",
		"core:stone_east",
	]:
		var starter_definition := simulation.content.get_interactable(starter_resource_id)
		_expect(
			not bool(starter_definition.get("spawn_in_world", true)),
			"legacy starter resource is retained for compatibility but disabled in world: %s" % starter_resource_id
		)
	if bushes.is_empty():
		return
	var bush: Dictionary = bushes[0]
	var bush_id := String(bush.get("id", ""))
	simulation.set_player_position(bush.get("position", Vector2.ZERO) as Vector2)
	var harvested := simulation.execute_interaction(bush_id)
	_expect(
		bool(harvested.get("success", false))
			and simulation.get_item_count("core:food") == 2,
		"harvesting a berry bush gives two servings of the first food"
	)
	_expect(
		simulation.is_collected(bush_id),
		"harvested berry bush does not produce food repeatedly"
	)
	_expect(
		not simulation.should_hide_interactable(bush_id, "food"),
		"picked bush stays in the world to show its berryless sprite"
	)
	var restored := World.new(simulation.export_state())
	_expect(
		restored.is_collected(bush_id)
			and restored.get_surface_berry_bushes() == bushes,
		"berry harvest and generated layout persist through save/load"
	)


func _test_collection_lookup_avoids_surface_scan() -> void:
	var simulation := CollectionLookupProbe.new(Simulation.create_new_game_state())
	simulation.target_resolution_count = 0
	simulation.get_interaction_target_position("core:common_house")
	_expect(simulation.target_resolution_count == 1, "facade keeps subclass resolution dispatch so the lookup probe is effective")
	simulation.target_resolution_count = 0
	for nodes: Array in [simulation.get_surface_trees(), simulation.get_surface_boulders()]:
		for node: Dictionary in nodes:
			_expect(not simulation.is_collected(String(node["id"])), "fresh resource is not depleted")
	var tree_id := String(simulation.get_surface_trees()[0]["id"])
	(simulation.state["collected"] as Dictionary)[tree_id] = true
	_expect(simulation.is_collected(tree_id), "collection lookup reads resource depletion immediately")
	_expect(simulation.target_resolution_count == 0, "collection queries never scan all surface targets")
	var bush := simulation.get_surface_berry_bushes()[0]
	var bush_id := String(bush["id"])
	simulation.set_player_position(bush["position"])
	_expect(bool(simulation.execute_interaction(bush_id).get("success", false)), "lookup probe harvests a generated bush")
	simulation.target_resolution_count = 0
	_expect(simulation.is_collected(bush_id), "berry collection lookup observes the regrowth timer")
	simulation.state["elapsed_game_minutes"] = int(simulation.state["farming"]["berry_ready_at"][bush_id])
	_expect(not simulation.is_collected(bush_id), "berry lookup sees regrowth without rebuilding its index")
	_expect(not simulation.is_collected("berry_bush"), "legacy static berry alias keeps its readiness behavior")
	_expect(simulation.target_resolution_count == 0, "berry and static-alias checks avoid target scans")
	var restored := CollectionLookupProbe.new(JSON.parse_string(JSON.stringify(simulation.export_state())) as Dictionary)
	restored.target_resolution_count = 0
	_expect(restored.is_collected(tree_id) and not restored.is_collected(bush_id), "collection index is rebuilt on load without losing depletion or berry readiness")
	_expect(restored.target_resolution_count == 0, "loaded collection queries remain independent of map size")


func _test_bucket_instances_hotbar_and_transfers() -> void:
	var legacy_state := Simulation.create_new_state(4400)
	legacy_state["version"] = 21
	(legacy_state["inventory"] as Dictionary)["core:bucket"] = 2
	var migrated: World = Simulation.new(legacy_state)
	var migrated_first := migrated.get_inventory_instance_id("core:bucket", 0)
	var migrated_second := migrated.get_inventory_instance_id("core:bucket", 1)
	_expect(not migrated_first.is_empty() and migrated_first != migrated_second, "legacy aggregate buckets migrate to distinct item instances")
	_expect(int((migrated.get_item_instance(migrated_first).get("state", {}) as Dictionary).get("charges", 0)) == 0, "migrated buckets receive safe empty state")
	var initial_state := Simulation.create_new_state(4401)
	initial_state["player_position"] = [
		Content.cell_center(7, 27).x,
		Content.cell_center(7, 27).y,
	]
	initial_state["item_instances"] = [
		{
			"instance_id": "core:item_instance_000101",
			"item_id": "core:bucket",
			"state": {"charges": 0},
			"location": {"kind": "inventory", "id": ""},
		},
		{
			"instance_id": "core:item_instance_000102",
			"item_id": "core:bucket",
			"state": {"charges": 1},
			"location": {"kind": "inventory", "id": ""},
		},
	]
	initial_state["next_item_instance_serial"] = 103
	var simulation: World = Simulation.new(initial_state)
	var first_id := simulation.get_inventory_instance_id("core:bucket", 0)
	var second_id := simulation.get_inventory_instance_id("core:bucket", 1)
	_expect(first_id != second_id and not first_id.is_empty(), "bucket stacks are distinct item instances")
	_expect(not bool(simulation.fill_active_bucket(Vector2i(6, 27)).get("success", false)), "a bucket only in the backpack cannot fill")
	_expect(bool(simulation.assign_hotbar_slot(0, first_id).get("success", false)), "an inventory bucket can be assigned to hotbar")
	_expect(bool(simulation.assign_hotbar_slot(1, second_id).get("success", false)), "a second individual bucket can occupy another hotbar slot")
	_expect(bool(simulation.select_hotbar_slot(0).get("success", false)), "hotbar selection succeeds")
	_expect(not bool(simulation.fill_active_bucket(Vector2i(7, 27)).get("success", false)), "a dry shore cell is not accepted as a water target")
	simulation.set_player_position(Content.cell_center(20, 20))
	_expect(not bool(simulation.fill_active_bucket(Vector2i(6, 27)).get("success", false)), "water outside interaction distance cannot fill the bucket")
	simulation.set_player_position(Content.cell_center(7, 27))
	var fill := simulation.fill_active_bucket(Vector2i(6, 27))
	_expect(bool(fill.get("success", false)), "equipped bucket fills from an adjacent water cell")
	_expect(int((simulation.get_item_instance(first_id).get("state", {}) as Dictionary).get("charges", 0)) == 2, "filling changes only the selected bucket to two charges")
	_expect(int((simulation.get_item_instance(second_id).get("state", {}) as Dictionary).get("charges", 0)) == 1, "filling leaves the other bucket's partial charge unchanged")
	var repeated_fill := simulation.fill_active_bucket(Vector2i(6, 27))
	_expect(bool(repeated_fill.get("success", false)) and not bool(repeated_fill.get("changed", true)), "repeating fill with a full bucket is a no-op")
	_expect(bool(simulation.select_hotbar_slot(1).get("success", false)), "the second bucket can be selected independently")
	var structures: Array = simulation.state.get("structures", []) as Array
	structures.append({"building_id": "core:wood_wall", "cell": [7, 27], "stage_id": "core:complete"})
	simulation.state["structures"] = structures
	simulation.set_player_position(Content.cell_center(8, 27))
	var blocked_fill := simulation.fill_active_bucket(Vector2i(6, 27))
	_expect(not bool(blocked_fill.get("success", false)), "a constructed wall blocks filling through it")
	_expect(int((simulation.get_item_instance(second_id).get("state", {}) as Dictionary).get("charges", 0)) == 1, "a blocked attempt preserves the partially filled bucket")
	simulation.state["structures"] = []
	simulation.set_player_position(Content.cell_center(7, 27))
	var inventory_layout: Array[Dictionary] = simulation.get_inventory_layout()
	for placement: Dictionary in inventory_layout:
		if String(placement.get("item_id", "")) == "core:bucket" and int(placement.get("stack_index", -1)) == 0:
			placement["origin"] = [2, 0]
			placement["rotation"] = 1
	var move_result := simulation.set_inventory_layout(inventory_layout)
	_expect(bool(move_result.get("success", false)), "an individual bucket can move and rotate within the backpack")
	_expect(int((simulation.get_item_instance(first_id).get("state", {}) as Dictionary).get("charges", 0)) == 2, "moving and rotating preserves bucket state")
	var loaded := Simulation.new(simulation.export_state())
	_expect(int((loaded.get_item_instance(first_id).get("state", {}) as Dictionary).get("charges", 0)) == 2, "bucket charges survive save normalization")
	_expect(loaded.get_hotbar_slots()[0] == first_id, "hotbar bucket assignment survives save normalization")
	var storage_cell := Vector2i(-1, -1)
	for y: int in range(32, 49):
		for x: int in range(32, 49):
			var candidate := Vector2i(x, y)
			if bool(loaded.create_storage_zone(candidate, candidate + Vector2i.ONE).get("success", false)):
				storage_cell = candidate
				break
		if storage_cell.x >= 0:
			break
	_expect(storage_cell.x >= 0, "storage test area can be created on a clear generated-world 2x2 area")
	if storage_cell.x < 0:
		return
	loaded.set_player_position(_cell_center(storage_cell))
	var store_result := loaded.transfer_inventory_stack_to_storage(storage_cell, "core:bucket", 0)
	_expect(bool(store_result.get("success", false)), "individual bucket can move into physical storage")
	_expect(loaded.get_hotbar_slots()[0].is_empty(), "a bucket moved into storage is removed from hotbar")
	var stored_layout := loaded.get_storage_layout(storage_cell)
	_expect(stored_layout.size() == 1 and String(stored_layout[0].get("instance_id", "")) == first_id, "storage contains the same bucket instance")
	if stored_layout.is_empty():
		return
	var stored_state := Simulation.new(loaded.export_state())
	var stored_id := String(stored_state.get_storage_layout(storage_cell)[0].get("placement_id", ""))
	var take_result := stored_state.transfer_storage_stack_to_inventory(storage_cell, stored_id)
	_expect(bool(take_result.get("success", false)), "individual bucket can return from storage")
	_expect(String(stored_state.get_item_instance(first_id).get("location", {}).get("kind", "")) == "inventory", "returning the bucket restores its original identity to inventory")
	_expect(int((stored_state.get_item_instance(first_id).get("state", {}) as Dictionary).get("charges", 0)) == 2, "charges survive storage and reload")
	var bucket_stack := -1
	for index: int in range(2):
		if stored_state.get_inventory_instance_id("core:bucket", index) == first_id:
			bucket_stack = index
	_expect(bucket_stack >= 0, "returned bucket is still represented in inventory")
	var dropped := stored_state.drop_inventory_stack("core:bucket", bucket_stack)
	_expect(bool(dropped.get("success", false)), "individual bucket can be dropped into the world")
	var drops := stored_state.get_world_drops()
	var bucket_drop_id := ""
	for drop_value: Variant in drops:
		if typeof(drop_value) == TYPE_DICTIONARY and String((drop_value as Dictionary).get("instance_id", "")) == first_id:
			bucket_drop_id = String((drop_value as Dictionary).get("drop_id", ""))
	_expect(not bucket_drop_id.is_empty(), "world drop retains the bucket instance ID")
	var dropped_state := Simulation.new(stored_state.export_state())
	_expect(bool(dropped_state.try_pickup_world_drop(bucket_drop_id).get("success", false)), "dropped bucket can be picked up again")
	_expect(int((dropped_state.get_item_instance(first_id).get("state", {}) as Dictionary).get("charges", 0)) == 2, "bucket charges survive drop, pickup, and save normalization")
	_expect(bool(dropped_state.try_pickup_item("core:bucket", 1).get("success", false)), "a new individual bucket can be added after loading")
	var new_bucket_id := dropped_state.get_inventory_instance_id("core:bucket", 2)
	_expect(not new_bucket_id.is_empty() and new_bucket_id != first_id and new_bucket_id != second_id, "the instance ID generator does not reuse IDs after loading")


func _test_water_cells_share_navigation_and_construction_rules() -> void:
	var surface_water := WaterMapScript.surface_cells()
	_expect(surface_water.size() == 105, "configured river provides 105 water cells")
	_expect(
		WaterMapScript.contains_cell(Vector2i(0, 20))
			and WaterMapScript.contains_cell(Vector2i(6, 34))
			and not WaterMapScript.contains_cell(Vector2i(7, 27)),
		"surface river bounds match the configured 7-by-15 cell region"
	)
	for water_cell: Vector2i in surface_water:
		_expect(
			WaterMapScript.cell_rect(water_cell).size == Vector2(32.0, 32.0)
				and FirstNightNavigationScript.blocked_cells().has(water_cell),
			"each rendered water tile uses the same full tile for collision and navigation"
		)

	var shaped_water := WaterMapScript.cells_from_regions([
		{"from": [10, 10], "to": [11, 10]},
		{"from": [10, 11], "to": [10, 12]},
		{"from": [30, 30], "to": [31, 31]},
	])
	_expect(shaped_water.size() == 8, "water map data supports an L-shaped river and a separate pond")
	_expect(
		shaped_water.has(Vector2i(10, 12))
			and not shaped_water.has(Vector2i(11, 12))
			and shaped_water.has(Vector2i(31, 31)),
		"region composition preserves irregular water outlines without filling gaps"
	)
	var shaped_blocked := FirstNightNavigationScript.blocked_cells(shaped_water)
	_expect(
		shaped_blocked.has(Vector2i(10, 12))
			and not shaped_blocked.has(Vector2i(11, 12)),
		"navigation blocks supplied irregular water cells only"
	)
	var overlap_command := ConstructionCommandScript.place_blueprint(
		Vector2i(9, 10),
		ConstructionCommandScript.WORKBENCH_ID
	)
	var overlapping_footprint := ConstructionValidatorScript.validate_place_blueprint(
		overlap_command,
		shaped_water
	)
	_expect(
		not bool(overlapping_footprint.get("success", false))
			and String(overlapping_footprint.get("reason_id", "")) == "core:blocked_cell",
		"two-cell structure is rejected when its second tile overlaps irregular water"
	)
	var beside_command := ConstructionCommandScript.place_blueprint(
		Vector2i(8, 10),
		ConstructionCommandScript.WORKBENCH_ID
	)
	_expect(
		bool(ConstructionValidatorScript.validate_place_blueprint(
			beside_command,
			shaped_water
		).get("success", false)),
		"two-cell structure may be placed flush beside the water edge"
	)
	var floor_on_water := ConstructionCommandScript.place_blueprint(
		Vector2i(6, 27),
		"core:wood_floor"
	)
	_expect(
		not bool(ConstructionValidatorScript.validate_place_blueprint(floor_on_water).get("success", false)),
		"floor placement is rejected on a configured water cell"
	)
	var simulation := World.new()
	var storage_on_water := simulation.create_storage_zone(Vector2i(6, 27), Vector2i(6, 27))
	_expect(
		not bool(storage_on_water.get("success", false)),
		"storage zones cannot be placed on water cells"
	)
	var shore_workbench := ConstructionCommandScript.place_blueprint(
		Vector2i(7, 27),
		ConstructionCommandScript.WORKBENCH_ID
	)
	_expect(
		bool(ConstructionValidatorScript.validate_place_blueprint(shore_workbench).get("success", false)),
		"multi-cell building remains placeable on dry cells directly at the shoreline"
	)


func _test_pickup_respects_inventory_limits() -> void:
	var simulation: World = Simulation.new()
	var valid: Dictionary = simulation.try_pickup_item(
		FirstNightContent.WOOD_ID,
		1
	)
	_expect(bool(valid.get("success", false)), "valid ground item pickup succeeds")
	_expect(
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 1,
		"successful pickup adds the item to inventory"
	)

	var fill: Dictionary = simulation.try_pickup_item(
		FirstNightContent.WOOD_ID,
		79
	)
	_expect(bool(fill.get("success", false)), "pickup fills all inventory slots without a weight cap")
	var overflow: Dictionary = simulation.try_pickup_item(
		FirstNightContent.WOOD_ID,
		1
	)
	_expect(not bool(overflow.get("success", false)), "pickup rejects items beyond grid capacity")
	_expect(
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 80,
		"rejected pickup leaves inventory unchanged"
	)
	var invalid: Dictionary = simulation.try_pickup_item("core:not_an_item", 1)
	_expect(not bool(invalid.get("success", false)), "pickup rejects unknown item ids")


func _test_manual_inventory_layout_and_rotation() -> void:
	var inventory := Content.new().create_empty_inventory()
	inventory[FirstNightContent.WOOD_ID] = 1
	inventory[FirstNightContent.RAW_WATER_ID] = 1
	var layout: Array[Dictionary] = [
		{"item_id": FirstNightContent.WOOD_ID, "stack_index": 0, "origin": [3, 3], "rotation": 0},
		{"item_id": FirstNightContent.RAW_WATER_ID, "stack_index": 0, "origin": [1, 1], "rotation": 1},
	]
	var packed: Dictionary = InventoryPacker.pack_with_layout(
		inventory, Content.new(), layout
	)
	var placements: Array = packed.get("placements", []) as Array
	var rotated_water: Dictionary = {}
	for placement_variant: Variant in placements:
		var placement: Dictionary = placement_variant as Dictionary
		if String(placement.get("item_id", "")) == FirstNightContent.RAW_WATER_ID:
			rotated_water = placement
	_expect(bool(packed.get("requested_layout_valid", false)), "manual inventory positions are accepted")
	_expect(
		int(rotated_water.get("rotation", 0)) == 1
			and (rotated_water.get("footprint", []) as Array).size() == 2,
		"two-cell item remembers its quarter-turn rotation"
	)
	var collision_layout := layout.duplicate(true)
	(collision_layout[0] as Dictionary)["origin"] = [1, 1]
	var collision := InventoryPacker.pack_with_layout(
		inventory, Content.new(), collision_layout
	)
	_expect(not bool(collision.get("requested_layout_valid", false)), "inventory rejects overlapping manual placements")
	var state := Simulation.create_new_state()
	(state["inventory"] as Dictionary)[FirstNightContent.WOOD_ID] = 1
	(state["inventory"] as Dictionary)[FirstNightContent.RAW_WATER_ID] = 1
	var simulation: World = Simulation.new(state)
	var moved: Dictionary = simulation.set_inventory_layout(layout)
	var restored := World.new(simulation.export_state())
	_expect(bool(moved.get("success", false)), "manual inventory placement applies")
	_expect(restored.export_state().get("inventory_layout", []) == simulation.export_state().get("inventory_layout", []), "manual inventory layout survives save/load")
	var item_content := Content.new()
	_expect(item_content.item_max_stack("core:plank") == 10, "a plank stack contains ten pieces")
	_expect(item_content.item_footprint("core:plank").size() == 2, "a plank occupies two cells")
	_expect(item_content.item_footprint("core:pickaxe").size() == 5, "a pickaxe occupies its five-cell T footprint")
	_expect(item_content.item_footprint("core:hoe").size() == 4, "a hoe occupies its four-cell L footprint")
	_expect(item_content.item_footprint("core:axe").size() == 5, "an axe occupies its five-cell P footprint")


func _test_pickup_keeps_manual_inventory_layout() -> void:
	var state := Simulation.create_new_state()
	(state["inventory"] as Dictionary)["core:wood"] = 40
	(state["inventory"] as Dictionary)["core:pinecone"] = 3
	state["item_instances"] = [{
		"instance_id": "core:item_instance_000001", "item_id": "core:axe", "state": {},
		"location": {"kind": "inventory", "id": ""},
	}]
	state["next_item_instance_serial"] = 2
	state["hotbar_slots"] = ["core:item_instance_000001", "", "", "", ""]
	state["active_hotbar_slot"] = 0
	var layout: Array[Dictionary] = []
	for index: int in range(8):
		layout.append({"item_id": "core:wood", "stack_index": index, "origin": [index % 4, index / 4], "rotation": 0})
	layout.append({"item_id": "core:pinecone", "stack_index": 0, "origin": [0, 2], "rotation": 0})
	layout.append({"item_id": "core:axe", "stack_index": 0, "origin": [1, 2], "rotation": 1})
	state["inventory_layout"] = layout
	var simulation := Simulation.new(state)
	var original_axe: Dictionary = {}
	for placement: Dictionary in simulation.get_inventory_placements():
		if String(placement["item_id"]) == "core:axe":
			original_axe = placement.duplicate(true)
	_expect(simulation._can_add_item("core:wood", 1), "screenshot layout accepts wood in its two free cells")
	var added := 0
	for index: int in range(10):
		var drop_ids := simulation._create_resource_drops("test:wood", "core:wood", 1, simulation.get_player_position())
		var pickup := simulation.try_pickup_world_drop(drop_ids[0])
		if bool(pickup.get("success", false)):
			added += 1
		for placement: Dictionary in simulation.get_inventory_placements():
			if String(placement["item_id"]) == "core:axe":
				_expect(placement["origin"] == original_axe["origin"] and placement["rotation"] == 1 and placement["instance_id"] == original_axe["instance_id"], "wood pickup keeps the rotated physical axe in its manually chosen cells")
	_expect(added == 10 and simulation.get_item_count("core:wood") == 50, "both free cells accept full five-piece wood stacks")
	_expect(simulation.get_world_drops().is_empty(), "accepted wood drops disappear without duplication")
	_expect(String(simulation.get_active_item_instance().get("instance_id", "")) == "core:item_instance_000001", "pickup keeps the selected physical tool")
	var before_rejection := simulation.get_inventory_layout()
	var rejected := simulation.try_pickup_item("core:wood", 1)
	_expect(not bool(rejected.get("success", false)) and simulation.get_inventory_layout() == before_rejection, "a truly full backpack rejects pickup without moving existing stacks")
	var restored := Simulation.new(JSON.parse_string(JSON.stringify(simulation.export_state())) as Dictionary)
	_expect(restored.get_inventory_layout() == simulation.get_inventory_layout(), "pickup layout survives JSON save/load")

	var sparse_state := Simulation.create_new_state()
	sparse_state["item_instances"] = state["item_instances"].duplicate(true)
	sparse_state["next_item_instance_serial"] = 2
	sparse_state["inventory_layout"] = [{"item_id": "core:axe", "stack_index": 0, "origin": [2, 0], "rotation": 0}]
	var sparse := Simulation.new(sparse_state)
	_expect(bool(sparse.try_pickup_item("core:wood", 1).get("success", false)), "sparse bag accepts its first resource")
	var wood_origin := Vector2i(-1, -1)
	for placement: Dictionary in sparse.get_inventory_placements():
		if String(placement["item_id"]) == "core:wood":
			wood_origin = placement["origin"]
	_expect(bool(sparse.try_pickup_item("core:carrot_seed", 1).get("success", false)), "sparse bag accepts an earlier-catalogue seed")
	for placement: Dictionary in sparse.get_inventory_placements():
		if String(placement["item_id"]) == "core:wood":
			_expect(placement["origin"] == wood_origin, "later pickups cannot move a newly created resource stack")


func _test_click_to_pickup_inventory_controls() -> void:
	var grid: InventoryGrid = InventoryGridScript.new()
	root.add_child(grid)
	grid.size = Vector2(168, 168)
	_expect(grid._cell_at_position(Vector2(41.99, 10)) == Vector2i.ZERO, "point just before a touching cell edge belongs to the first slot")
	_expect(grid._cell_at_position(Vector2(42, 10)) == Vector2i(1, 0), "the shared edge between touching slots maps directly to the next slot")
	grid.present([{
		"item_id": "core:raw_water",
		"stack_index": 0,
		"amount": 1,
		"origin": Vector2i.ZERO,
		"rotation": 0,
		"footprint": [Vector2i.ZERO, Vector2i.DOWN],
	}])
	var changed_layouts: Array[Array] = []
	grid.layout_changed.connect(func(layout: Array[Dictionary]) -> void:
		changed_layouts.append(layout.duplicate(true))
	)
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_LEFT
	pick.pressed = true
	pick.position = Vector2(10, 10)
	var equipped: Array[Dictionary] = []
	grid.equip_requested.connect(func(placement: Dictionary) -> void: equipped.append(placement))
	grid._gui_input(pick)
	_expect(grid.is_holding_item(), "one LMB click attaches the selected item to the cursor")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = pick.position
	release.global_position = pick.position
	grid._input(release)
	_expect(equipped.size() == 1 and grid.is_holding_item() and changed_layouts.is_empty(), "releasing LMB keeps the cursor item and does not rearrange inventory")
	var motion := InputEventMouseMotion.new()
	motion.global_position = Vector2(10, 142)
	grid._input(motion)
	_expect(grid.is_holding_item(), "cursor transfer persists while moving without held LMB")
	release.global_position = motion.global_position
	release.pressed = true
	grid._input(release)
	_expect(grid.is_holding_item() and changed_layouts.is_empty(), "invalid placement leaves the item on the cursor without changing its original layout")
	motion.global_position = Vector2(98, 98)
	grid._input(motion)
	release.global_position = motion.global_position
	grid._input(release)
	_expect(changed_layouts.size() == 1, "a second valid click places the item")
	grid.return_held_item()
	_expect(not grid.is_holding_item(), "returning the held item cancels the temporary cursor state")
	root.remove_child(grid)
	grid.free()


func _test_player_food_consumption() -> void:
	var state := Simulation.create_new_state()
	(state["inventory"] as Dictionary)[FirstNightContent.FOOD_ID] = 2
	var simulation: World = Simulation.new(state)
	var eaten: Dictionary = simulation.eat_food()
	_expect(bool(eaten.get("success", false)), "player can eat carried berries")
	_expect(simulation.get_item_count(FirstNightContent.FOOD_ID) == 1, "eating consumes exactly one berry portion")
	simulation.eat_food()
	var empty_result: Dictionary = simulation.eat_food()
	_expect(not bool(empty_result.get("success", false)), "player cannot eat food that is not in inventory")


func _test_named_markers_and_save_round_trip() -> void:
	var simulation: World = Simulation.new()
	simulation.set_player_position(Vector2(224.0, 416.0))
	var empty_name := simulation.create_marker("  ", Color("e5b94f"))
	_expect(not bool(empty_name.get("success", false)), "marker requires a non-empty name")
	var created := simulation.create_marker("Old well", Color("e5b94f"))
	var markers := simulation.get_markers()
	_expect(bool(created.get("success", false)) and markers.size() == 1, "named marker can be created")
	if markers.is_empty():
		return
	var marker := markers[0]
	var position := marker.get("position", []) as Array
	_expect(position == [224.0, 416.0], "marker records the player's current position")
	_expect(String(marker.get("color", "")) == "e5b94f", "marker keeps its chosen random color")
	var marker_id := String(marker.get("id", ""))
	var renamed := simulation.rename_marker(marker_id, "North spring")
	var disabled := simulation.set_marker_enabled(marker_id, false)
	var restored := World.new(simulation.export_state())
	_expect(bool(renamed.get("success", false)) and String(restored.get_markers()[0].get("name", "")) == "North spring", "marker name and location survive save/load")
	_expect(bool(disabled.get("success", false)) and not bool(restored.get_markers()[0].get("enabled", true)), "a temporarily hidden marker remains disabled after save/load")
	var enabled := restored.set_marker_enabled(marker_id, true)
	_expect(bool(enabled.get("success", false)) and bool(restored.get_markers()[0].get("enabled", false)), "a hidden marker can be shown again")
	var removed := restored.remove_marker(marker_id)
	_expect(bool(removed.get("success", false)) and restored.get_markers().is_empty(), "marker can be deleted from the list")


func _test_world_drops_persist_and_pickup_by_id() -> void:
	var simulation: World = Simulation.new()
	var completed: Dictionary = _work_resource_to_completion(
		simulation,
		"wood_north"
	)
	var created_ids: Array = completed.get("created_drop_ids", []) as Array
	_expect(created_ids.size() == 3, "wood work creates three stable drop ids")
	var before_save: Array = simulation.get_world_drops()
	var restored := World.new(simulation.export_state())
	_expect(
		restored.get_world_drops() == before_save,
		"world drops survive a save-state round trip"
	)
	if created_ids.is_empty():
		return

	var drop_id: String = String(created_ids[0])
	var picked: Dictionary = restored.try_pickup_world_drop(drop_id)
	_expect(bool(picked.get("success", false)), "pickup by persistent drop id succeeds")
	_expect(
		restored.get_item_count(FirstNightContent.WOOD_ID) == 1,
		"persistent drop pickup adds exactly its stored amount"
	)
	_expect(
		restored.get_world_drops().size() == 2,
		"successful pickup removes only the selected world drop"
	)
	var duplicate: Dictionary = restored.try_pickup_world_drop(drop_id)
	_expect(not bool(duplicate.get("success", false)), "removed drop id cannot be picked twice")
	_expect(
		restored.get_item_count(FirstNightContent.WOOD_ID) == 1,
		"duplicate drop pickup cannot duplicate inventory items"
	)


func _test_inventory_stack_drop_and_expiry() -> void:
	var simulation: World = Simulation.new()
	var pickup := simulation.try_pickup_item("core:wood", 7)
	_expect(bool(pickup.get("success", false)), "inventory can receive items before dropping a stack")
	var dropped := simulation.drop_inventory_stack("core:wood", 0)
	_expect(bool(dropped.get("success", false)), "player can drop a whole inventory stack")
	_expect(int(simulation.get_inventory().get("core:wood", 0)) == 2, "dropping removes only the selected stack amount")
	var drops := simulation.get_world_drops()
	_expect(drops.size() == 1, "a dropped inventory stack becomes one world-loot object")
	if drops.is_empty():
		return
	var drop := drops[0] as Dictionary
	_expect(int(drop.get("amount", 0)) == 5, "the dropped world-loot object keeps the whole stack count")
	var expiry := int(drop.get("expires_at_game_minute", -1))
	_expect(expiry == simulation.get_elapsed_game_minutes() + 30 * 60, "world loot expires after 30 game hours")
	simulation.state["elapsed_game_minutes"] = expiry - 1
	simulation.advance_minutes(1)
	_expect(simulation.get_world_drops().is_empty(), "world loot disappears at the 30-hour expiry boundary")


func _test_placeholder_icons_cover_missing_art() -> void:
	var grid := InventoryGridScript.new()
	for item_id: String in ["core:plank", "core:firewood"]:
		var texture := PlaceholderIconScript.texture_for(item_id)
		_expect(texture != null, "%s gets a generated placeholder icon" % item_id)
		if texture != null:
			_expect(texture.get_width() == 16 and texture.get_height() == 16, "%s placeholder has a stable pixel-art size" % item_id)
		_expect(
			grid._placement_icon({"item_id": item_id, "icon_path": ""}) != null,
			"inventory grid can draw %s without an authored icon" % item_id
		)
	grid.free()


func _test_storage_zones_and_physical_transfers() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state(941)
	legacy_state["version"] = 16
	legacy_state.erase("storage_zones")
	legacy_state.erase("storage_items")
	legacy_state.erase("next_storage_zone_serial")
	var migrated := World.new(legacy_state)
	_expect(migrated.get_storage_zones().is_empty() and migrated.get_storage_items().is_empty(), "v16 saves migrate with empty storage state")
	var legacy_storage_state := Simulation.create_new_state(942)
	legacy_storage_state["version"] = 18
	legacy_storage_state["storage_zones"] = [{"id": "core:storage_zone_0001", "cells": [[10, 10]]}]
	legacy_storage_state["storage_items"] = [{"cell": [10, 10], "item_id": FirstNightContent.WOOD_ID, "amount": 4}]
	var migrated_storage := World.new(legacy_storage_state)
	var migrated_layout := migrated_storage.get_storage_layout(Vector2i(10, 10))
	_expect(migrated_layout.size() == 1 and migrated_layout[0].origin == Vector2i.ZERO, "legacy stack storage migrates into the new cell grid")

	var simulation: World = Simulation.new()
	simulation.set_player_position(Content.cell_center(10, 10))
	simulation.try_pickup_item(FirstNightContent.WOOD_ID, 8)
	var first_zone := simulation.create_storage_zone(Vector2i(10, 10), Vector2i(10, 10))
	var second_zone := simulation.create_storage_zone(Vector2i(12, 10), Vector2i(12, 10))
	_expect(bool(first_zone.get("success", false)), "storage zone can be designated on an open map cell")
	_expect(bool(second_zone.get("success", false)), "separate storage zones can coexist")
	var reserved_zone := simulation.create_storage_zone(Vector2i(20, 20), Vector2i(20, 20))
	_expect(not bool(reserved_zone.get("success", false)), "storage zones respect the current house and map reservations")
	var object_zone := simulation.create_storage_zone(Vector2i(12, 31), Vector2i(12, 31))
	_expect(not bool(object_zone.get("success", false)), "storage zones cannot cover a world object")
	var overlap := simulation.create_storage_zone(Vector2i(10, 10), Vector2i(11, 10))
	_expect(not bool(overlap.get("success", false)), "storage zones cannot overlap")
	var first_store := simulation.transfer_inventory_stack_to_storage(Vector2i(10, 10), FirstNightContent.WOOD_ID, 0)
	var first_store_args := first_store.get("message_args", {}) as Dictionary
	_expect(bool(first_store.get("success", false)) and int(first_store_args.get("amount", 0)) == 5, "storage transfers one selected backpack stack")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 3, "unselected items remain in the backpack")
	var second_store := simulation.transfer_inventory_stack_to_storage(Vector2i(10, 10), FirstNightContent.WOOD_ID, 0)
	_expect(bool(second_store.get("success", false)) and simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "a second stack can be placed independently")
	var first_layout := simulation.get_storage_layout(Vector2i(10, 10))
	_expect(first_layout.size() == 2, "stacks occupy distinct placements in the 3x2 cell grid")
	_expect(first_layout.size() != 2 or first_layout[0].origin != first_layout[1].origin, "separate stored stacks cannot overlap")
	if first_layout.size() == 2:
		var arranged := first_layout.duplicate(true)
		arranged[1]["origin"] = Vector2i(2, 1)
		var layout_result := simulation.set_storage_layout(Vector2i(10, 10), arranged)
		_expect(bool(layout_result.get("success", false)), "items can be rearranged inside the storage grid")
		first_layout = simulation.get_storage_layout(Vector2i(10, 10))
		_expect(first_layout[1].origin == Vector2i(2, 1), "storage placement and orientation are saved per tile")
		var overlapping := first_layout.duplicate(true)
		overlapping[1]["origin"] = overlapping[0]["origin"]
		_expect(not bool(simulation.set_storage_layout(Vector2i(10, 10), overlapping).get("success", false)), "storage grid rejects overlapping placements")
	var restored := World.new(simulation.export_state())
	_expect(restored.get_storage_zones().size() == 2 and restored.get_storage_layout(Vector2i(10, 10)).size() == 2, "cell inventory layout persists through save/load")
	var cannot_remove := restored.remove_storage_zone_at(Vector2i(10, 10))
	_expect(not bool(cannot_remove.get("success", false)), "a non-empty storage zone cannot be removed")
	var take_layout := restored.get_storage_layout(Vector2i(10, 10))
	var total_taken := 0
	for placement: Dictionary in take_layout:
		var take_result := restored.transfer_storage_stack_to_inventory(Vector2i(10, 10), String(placement.get("placement_id", "")))
		if bool(take_result.get("success", false)):
			total_taken += int((take_result.get("message_args", {}) as Dictionary).get("amount", 0))
	_expect(total_taken == 8, "each stored stack can be quickly transferred back to the backpack")
	_expect(restored.get_storage_contents(Vector2i(10, 10)).is_empty(), "taking from one cell leaves it empty without affecting another")
	_expect(bool(restored.remove_storage_zone_at(Vector2i(10, 10)).get("success", false)), "an emptied storage cell can be removed")

	var floor_storage_state: Dictionary = Simulation.create_new_state(2441)
	floor_storage_state["storage_zones"] = [{
		"id": "core:storage_zone_0001",
		"cells": [[10, 10]],
	}]
	floor_storage_state["storage_items"] = [{
		"cell": [10, 10],
		"item_id": FirstNightContent.WOOD_ID,
		"amount": 5,
		"origin": [0, 0],
		"rotation": 0,
		"stack_index": 0,
		"placement_id": "core:wood:0",
	}]
	floor_storage_state["structures"] = [{
		"building_id": "core:wood_floor",
		"cell": [10, 10],
		"stage_id": "core:complete",
	}]
	var floor_storage_json := JSON.stringify(floor_storage_state)
	var floor_storage_decoded: Variant = JSON.parse_string(floor_storage_json)
	var floor_storage := World.new(floor_storage_decoded as Dictionary)
	_expect(
		floor_storage.get_storage_contents(Vector2i(10, 10)).get(FirstNightContent.WOOD_ID, 0) == 5,
		"stored logs survive save normalization when a compatible floor covers the cell"
	)
	_expect(
		floor_storage.get_storage_zones().size() == 1,
		"a compatible floor does not invalidate its storage cell during load"
	)
	var blocked_storage_blueprint := ConstructionCommandScript.place_blueprint(
		Vector2i(10, 10), "core:wood_wall"
	)
	_expect(
		not bool(floor_storage.execute_construction_command(blocked_storage_blueprint).get("success", false)),
		"blocking construction cannot overwrite an allocated storage cell"
	)
	var obstructed_storage_state := floor_storage_state.duplicate(true)
	var obstructed_structures := obstructed_storage_state["structures"] as Array
	(obstructed_structures[0] as Dictionary)["building_id"] = "core:wood_wall"
	var recovered_storage := World.new(obstructed_storage_state)
	var recovered_drop_amount := 0
	for drop_value: Variant in recovered_storage.get_world_drops():
		var drop := drop_value as Dictionary
		if String(drop.get("item_id", "")) == FirstNightContent.WOOD_ID:
			recovered_drop_amount += int(drop.get("amount", 0))
	_expect(
		recovered_drop_amount == 5,
		"items from an invalid legacy storage cell are recovered as world drops instead of deleted"
	)


func _test_storage_transfers_preserve_backpack_layout() -> void:
	var state: Dictionary = Simulation.create_new_state(2450)
	state["inventory"] = {"core:wood": 10, "core:food": 5}
	state["inventory_layout"] = [
		{"item_id": "core:wood", "stack_index": 0, "origin": [0, 0], "rotation": 0},
		{"item_id": "core:wood", "stack_index": 1, "origin": [1, 0], "rotation": 0},
		{"item_id": "core:food", "stack_index": 0, "origin": [3, 3], "rotation": 0},
	]
	var simulation := World.new(state)
	simulation.set_player_position(Content.cell_center(10, 10))
	var created := simulation.create_storage_zone(Vector2i(10, 10), Vector2i(10, 10))
	_expect(bool(created.get("success", false)), "layout preservation test creates a storage cell")
	var stored := simulation.transfer_inventory_stack_to_storage(
		Vector2i(10, 10), "core:wood", 0
	)
	_expect(bool(stored.get("success", false)), "a selected backpack stack can be stored")
	var after_store: Dictionary = simulation.export_state()
	var stored_layout: Array = after_store.get("inventory_layout", []) as Array
	var preserved_other_stack := false
	var preserved_berry_position := false
	for entry_value: Variant in stored_layout:
		var entry := entry_value as Dictionary
		if String(entry.get("item_id", "")) == "core:wood" and int(entry.get("stack_index", -1)) == 0:
			preserved_other_stack = entry.get("origin", []) == [1, 0]
		if String(entry.get("item_id", "")) == "core:food":
			preserved_berry_position = entry.get("origin", []) == [3, 3]
	_expect(preserved_other_stack, "storing one of identical stacks preserves the remaining stack location")
	_expect(preserved_berry_position, "storing an item preserves unrelated manual backpack positions")
	var storage_layout := simulation.get_storage_layout(Vector2i(10, 10))
	var taken := simulation.transfer_storage_stack_to_inventory(
		Vector2i(10, 10),
		String(storage_layout[0].get("placement_id", "")),
		Vector2i(2, 0)
	)
	_expect(bool(taken.get("success", false)), "a stored stack can return to a selected backpack slot")
	var after_take: Array = simulation.export_state().get("inventory_layout", []) as Array
	var preserved_after_return := false
	var returned_at_destination := false
	for entry_value: Variant in after_take:
		var entry := entry_value as Dictionary
		if String(entry.get("item_id", "")) == "core:food":
			preserved_after_return = entry.get("origin", []) == [3, 3]
		if String(entry.get("item_id", "")) == "core:wood" and int(entry.get("stack_index", -1)) == 1:
			returned_at_destination = entry.get("origin", []) == [2, 0]
	_expect(preserved_after_return, "taking a stack preserves unrelated backpack positions")
	_expect(returned_at_destination, "returned stack lands at its requested backpack slot")

	var stone_state := Simulation.create_new_state(2451)
	stone_state["inventory"] = {"core:stone": 3, "core:wood": 5}
	stone_state["inventory_layout"] = [
		{"item_id": "core:stone", "stack_index": 0, "origin": [0, 0], "rotation": 0},
		{"item_id": "core:wood", "stack_index": 0, "origin": [1, 0], "rotation": 0},
	]
	var stone_simulation := World.new(stone_state)
	stone_simulation.set_player_position(Content.cell_center(10, 10))
	stone_simulation.create_storage_zone(Vector2i(10, 10), Vector2i(10, 10))
	var moved_wood := stone_simulation.transfer_inventory_stack_to_storage(
		Vector2i(10, 10), "core:wood", 0
	)
	_expect(bool(moved_wood.get("success", false)), "regression setup stores logs beside the backpack stone")
	var returned_wood: Dictionary = stone_simulation.get_storage_layout(Vector2i(10, 10))[0]
	var returned_result := stone_simulation.transfer_storage_stack_to_inventory(
		Vector2i(10, 10),
		String(returned_wood.get("placement_id", "")),
		Vector2i(3, 3)
	)
	_expect(bool(returned_result.get("success", false)), "stored logs can be manually returned to the bottom-right backpack slot")
	var stone_return_layout: Array = stone_simulation.export_state().get("inventory_layout", []) as Array
	var stone_stayed_put := false
	var logs_at_bottom_right := false
	for entry: Dictionary in stone_return_layout:
		if String(entry.get("item_id", "")) == "core:stone":
			stone_stayed_put = entry.get("origin", []) == [0, 0]
		if String(entry.get("item_id", "")) == "core:wood":
			logs_at_bottom_right = entry.get("origin", []) == [3, 3]
	_expect(stone_stayed_put, "returning logs to a free slot preserves the stone at 0,0")
	_expect(logs_at_bottom_right, "returned logs occupy the requested 3,3 slot")

	var blocked_return_state := Simulation.create_new_state(2452)
	blocked_return_state["inventory"] = {"core:wood": 3, "core:stone": 1}
	blocked_return_state["inventory_layout"] = [
		{"item_id": "core:wood", "stack_index": 0, "origin": [0, 0], "rotation": 0},
		{"item_id": "core:stone", "stack_index": 0, "origin": [3, 3], "rotation": 0},
	]
	blocked_return_state["storage_zones"] = [{
		"id": "core:storage_zone_0001",
		"cells": [[10, 10]],
	}]
	blocked_return_state["storage_items"] = [{
		"cell": [10, 10],
		"item_id": "core:wood",
		"amount": 2,
		"origin": [0, 0],
		"rotation": 0,
		"stack_index": 0,
		"placement_id": "core:wood:0",
	}]
	var blocked_return := World.new(blocked_return_state)
	blocked_return.set_player_position(Content.cell_center(10, 10))
	var blocked_placement: Dictionary = blocked_return.get_storage_layout(Vector2i(10, 10))[0]
	var rejected_return := blocked_return.transfer_storage_stack_to_inventory(
		Vector2i(10, 10),
		String(blocked_placement.get("placement_id", "")),
		Vector2i(3, 3)
	)
	_expect(not bool(rejected_return.get("success", false)), "returning a partial stack into another item's occupied slot is rejected")
	var unchanged_state := blocked_return.export_state()
	_expect(
		int((unchanged_state["inventory"] as Dictionary).get("core:wood", 0)) == 3
		and int((unchanged_state["inventory"] as Dictionary).get("core:stone", 0)) == 1,
		"rejected stack placement leaves backpack counts unchanged"
	)
	_expect(
		(unchanged_state["inventory_layout"] as Array) == blocked_return_state["inventory_layout"]
		and (unchanged_state["storage_items"] as Array).size() == 1,
		"rejected stack placement preserves all positions and keeps the stored logs"
	)


func _test_room_detection_and_designation() -> void:
	var stress_structures: Array[Dictionary] = []
	for x: int in range(20, 70):
		stress_structures.append({"building_id": "core:wood_wall", "cell": [x, 64]})
	var room_catalog := BuildingCatalogScript.new()
	var room_started := Time.get_ticks_usec()
	var open_map_result := RoomTopologyScript.find_room_at(
		Vector2i(60, 60), stress_structures, room_catalog, Vector2i(128, 128)
	)
	var room_elapsed_msec := float(Time.get_ticks_usec() - room_started) / 1000.0
	_expect(open_map_result.is_empty(), "open map with a wall row is not a closed room")
	_expect(room_elapsed_msec < 2000.0, "room search with 50 structures completes within two seconds")
	print("PASS: 50-structure open-map room search (%0.2f ms)" % room_elapsed_msec)
	var storage_state := _enclosed_room_state(2, 2)
	var storage_simulation := World.new(storage_state)
	var storage_result := storage_simulation.assign_room_type(
		"core:storage_room", Vector2i(11, 11)
	)
	_expect(bool(storage_result.get("success", false)), "a closed 2x2 interior can be designated as a warehouse")
	_expect(storage_simulation.get_storage_zones().size() == 1, "warehouse assignment creates the existing per-cell storage zone")
	_expect(storage_simulation.get_storage_zones()[0].get("cells", []).size() == 4, "every interior tile in the warehouse becomes a storage tile")
	var floor_blueprint := ConstructionCommandScript.place_blueprint(
		Vector2i(11, 11), "core:wood_floor"
	)
	_expect(
		bool(storage_simulation.execute_construction_command(floor_blueprint).get("success", false)),
		"floor upgrades remain allowed inside storage rooms"
	)
	var forbidden_blueprint := ConstructionCommandScript.place_blueprint(
		Vector2i(11, 11), "core:chair"
	)
	_expect(
		String(storage_simulation.execute_construction_command(forbidden_blueprint).get("reason_id", "")) == "core:room_storage_furniture_forbidden",
		"non-shelf furniture cannot be placed inside a warehouse"
	)
	var restored := World.new(storage_simulation.export_state())
	_expect(restored.get_room_assignments().size() == 1, "room type and interior cells persist in saves")
	_expect(restored.get_storage_zones().size() == 1, "room-linked storage survives save normalization")

	var too_small := World.new(_enclosed_room_state(1, 1))
	_expect(
		String(too_small.assign_room_type("core:storage_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.too_small",
		"warehouse designation enforces the four-interior-cell minimum"
	)
	var too_large := World.new(_enclosed_room_state(13, 2))
	_expect(
		String(too_large.assign_room_type("core:storage_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.too_large",
		"warehouse designation enforces the 25-interior-cell maximum"
	)
	var no_door_state := _enclosed_room_state(2, 2)
	for structure: Dictionary in no_door_state["structures"] as Array:
		if String(structure.get("building_id", "")) == "core:wood_door":
			structure["building_id"] = "core:wood_wall"
	var no_door := World.new(no_door_state)
	_expect(
		String(no_door.assign_room_type("core:storage_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.door_required",
		"warehouse designation requires a door in the boundary"
	)
	var open_state := _enclosed_room_state(2, 2)
	var open_structures: Array = open_state["structures"] as Array
	for structure_index: int in range(open_structures.size()):
		if (open_structures[structure_index] as Dictionary).get("cell", []) == [10, 12]:
			open_structures.remove_at(structure_index)
			break
	var open_room := World.new(open_state)
	_expect(
		String(open_room.assign_room_type("core:storage_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.not_enclosed",
		"a gap in the wall prevents room assignment even when it looks almost enclosed"
	)

	var living_state := _enclosed_room_state(3, 2)
	var living_simulation := World.new(living_state)
	_expect(
		String(living_simulation.assign_room_type("core:living_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.missing_requirements",
		"living rooms require a physical sleeping place before designation"
	)
	var foundation_state := living_state.duplicate(true)
	(foundation_state["structures"] as Array).append({"building_id": "core:bedroll", "cell": [11, 11]})
	var foundation_living := World.new(foundation_state)
	_expect(bool(foundation_living.assign_room_type("core:living_room", Vector2i(11, 11)).success), "a sleeping foundation admits housing before table and light improvements")
	(living_state["structures"] as Array).append_array([
		{"building_id": "core:bed", "cell": [11, 11]},
		{"building_id": "core:table", "cell": [12, 12]},
		{"building_id": "core:torch", "cell": [11, 12]},
	])
	var furnished_living := World.new(living_state)
	var living_result := furnished_living.assign_room_type(
		"core:living_room", Vector2i(11, 11)
	)
	_expect(bool(living_result.get("success", false)), "a 3x2 living room passes with bed, table, and light")
	_expect(furnished_living.get_room_assignments().size() == 1, "living-room designation is stored separately from storage areas")
	var living_remove := furnished_living.remove_room_at(Vector2i(11, 11))
	_expect(bool(living_remove.get("success", false)), "right-click removal clears a living-room designation")

	var forbidden_storage_state := _enclosed_room_state(2, 2)
	(forbidden_storage_state["structures"] as Array).append({
		"building_id": "core:torch",
		"cell": [11, 11],
	})
	var forbidden_storage := World.new(forbidden_storage_state)
	_expect(
		String(forbidden_storage.assign_room_type("core:storage_room", Vector2i(11, 11)).get("message_key", "")) == "ui.room.failure.storage_furniture",
		"non-storage furniture is rejected from warehouse rooms"
	)
	print("PASS: room enclosure, size limits, requirements, designation, and persistence")


func _enclosed_room_state(interior_width: int, interior_height: int) -> Dictionary:
	var state := Simulation.create_new_state(7781)
	var structures: Array = []
	var left := 10
	var top := 10
	var right := left + interior_width + 1
	var bottom := top + interior_height + 1
	for y: int in range(top, bottom + 1):
		for x: int in range(left, right + 1):
			if x != left and x != right and y != top and y != bottom:
				continue
			var is_door := y == top and x == left + 1
			structures.append({
				"building_id": "core:wood_door" if is_door else "core:wood_wall",
				"cell": [x, y],
			})
	state["structures"] = structures
	return state


func _test_query_snapshots_are_isolated() -> void:
	var simulation: World = Simulation.new()
	var inventory: Dictionary = simulation.get_inventory()
	inventory[FirstNightContent.WOOD_ID] = 99
	var flags: Dictionary = simulation.get_flags()
	flags["tools_found"] = true
	var npcs: Dictionary = simulation.get_npcs()
	(npcs["core:first_neighbor"] as Dictionary)["active"] = true
	var exported: Dictionary = simulation.export_state()
	(exported["inventory"] as Dictionary)[FirstNightContent.STONE_ID] = 99

	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "inventory query is isolated")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 0, "exported state is isolated")
	_expect(not bool(simulation.get_flags()["tools_found"]), "flags query cannot mutate simulation")
	_expect(not simulation.is_npc_visible("core:first_neighbor"), "NPC query cannot mutate simulation")
	var queried_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	queried_needs["hunger"] = 0.0
	_expect(
		float(simulation.get_npc_needs("core:first_neighbor").get("hunger", 0.0)) == 72.0,
		"NPC needs query is isolated"
	)


func _test_corrupt_nested_state_uses_defaults() -> void:
	var corrupt: Dictionary = Simulation.create_new_state()
	corrupt["day"] = -4
	corrupt["minute_of_day"] = 99999
	corrupt["inventory"] = ["bad"]
	corrupt["collected"] = "bad"
	corrupt["flags"] = "bad"
	corrupt["npcs"] = {"core:first_neighbor": "bad"}
	corrupt["blueprints"] = "bad"
	corrupt["structures"] = "bad"
	corrupt["player_position"] = {"x": 1}
	corrupt["outcomes"] = "bad"

	var restored: World = Simulation.new(corrupt)
	_expect(restored.get_day() == 1, "invalid negative day is clamped")
	_expect(restored.get_minute_of_day() == restored.LAST_MINUTE_OF_DAY, "invalid time is clamped to the last minute of the full day")
	_expect(
		restored.get_item_count(FirstNightContent.WOOD_ID) == 0
			and restored.get_item_count(FirstNightContent.STONE_ID) == 0,
		"invalid inventory falls back to zero counts"
	)
	_expect(not bool(restored.get_flags()["tools_found"]), "invalid flags fall back to defaults")
	_expect(
		restored.get_player_position().is_equal_approx(Vector2(784.0, 944.0)),
		"invalid player position falls back to default"
	)
	_expect(not restored.is_npc_visible("core:first_neighbor"), "invalid NPC falls back to default")
	_expect(restored.get_blueprints().is_empty(), "invalid blueprints fall back to empty")
	_expect(restored.get_structures().is_empty(), "invalid structures fall back to empty")
	_expect(
		(restored.export_state().get("outcomes", []) as Array).is_empty(),
		"invalid outcomes fall back to empty"
	)

	var invalid_numbers: Dictionary = Simulation.create_new_state()
	invalid_numbers["inventory"] = {
		FirstNightContent.WOOD_ID: -2,
		FirstNightContent.STONE_ID: 1.5,
		FirstNightContent.FOOD_ID: 2,
	}
	invalid_numbers["flags"] = {
		"tools_found": "false",
		"repair_stage": 2.5,
	}
	var normalized_numbers: World = Simulation.new(invalid_numbers)
	_expect(normalized_numbers.get_item_count(FirstNightContent.WOOD_ID) == 0, "negative amount is clamped")
	_expect(normalized_numbers.get_item_count(FirstNightContent.STONE_ID) == 0, "fractional amount is rejected")
	_expect(normalized_numbers.get_item_count(FirstNightContent.FOOD_ID) == 2, "valid amount survives")
	_expect(not bool(normalized_numbers.get_flags()["tools_found"]), "string boolean stays false")
	_expect(normalized_numbers.get_object_stage("repair") == 0, "fractional stage falls back")

	var invalid_npc_state: Dictionary = Simulation.create_new_state()
	var invalid_mira: Dictionary = (
		invalid_npc_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	invalid_mira["needs"] = {
		"hunger": -20.0,
		"energy": "bad",
	}
	invalid_mira["activity_id"] = "not_namespaced"
	invalid_mira["target_cell"] = [999, -5]
	invalid_mira["personal_inventory"] = {
		"core:food": -2,
		"bad": 3,
	}
	invalid_mira["facing"] = [0.0, 0.0]
	invalid_mira["moving"] = "yes"
	var normalized_npc: World = Simulation.new(invalid_npc_state)
	var normalized_needs: Dictionary = normalized_npc.get_npc_needs("core:first_neighbor")
	_expect(float(normalized_needs["hunger"]) == 0.0, "NPC hunger is clamped")
	_expect(float(normalized_needs["energy"]) == 82.0, "invalid NPC energy uses default")
	_expect(
		normalized_npc.get_npc_activity_id("core:first_neighbor") == &"core:arriving",
		"invalid NPC activity uses default"
	)
	_expect(
		normalized_npc.get_npc_target_cell("core:first_neighbor") == Vector2i(127, 0),
		"NPC target cell is clamped to the map"
	)
	_expect(
		normalized_npc.get_npc_personal_food("core:first_neighbor") == 2,
		"invalid personal food uses default"
	)
	_expect(
		normalized_npc.get_npc_facing("core:first_neighbor") == Vector2.UP,
		"invalid NPC facing uses default"
	)
	_expect(not normalized_npc.is_npc_moving("core:first_neighbor"), "invalid moving flag uses default")


func _test_save_header_validation() -> void:
	for version: int in range(1, Simulation.SAVE_VERSION + 1):
		var compatible: Dictionary = Simulation.create_new_state()
		compatible["version"] = version
		var result: Dictionary = Simulation.validate_save_header(compatible)
		_expect(bool(result["success"]), "save version %d is accepted" % version)

	var future: Dictionary = Simulation.create_new_state()
	future["version"] = Simulation.SAVE_VERSION + 1
	var future_result: Dictionary = Simulation.validate_save_header(future)
	_expect(not bool(future_result["success"]), "future save version is rejected")
	_expect(String(future_result["code"]) == "future_version", "future version has a distinct reason")

	var missing_version: Dictionary = Simulation.create_new_state()
	missing_version.erase("version")
	var missing_result: Dictionary = Simulation.validate_save_header(missing_version)
	_expect(not bool(missing_result["success"]), "save without version is rejected")


func _test_unknown_npc_state_survives_normalization() -> void:
	var raw_state: Dictionary = Simulation.create_new_state()
	var raw_npcs: Dictionary = raw_state["npcs"] as Dictionary
	raw_npcs["mod:traveler"] = {
		"active": true,
		"memory": {"event": "arrived"},
	}
	raw_npcs["mod:invalid"] = "bad"

	var simulation: World = Simulation.new(raw_state)
	var normalized_npcs: Dictionary = simulation.get_npcs()
	_expect(normalized_npcs.has("mod:traveler"), "unknown dictionary NPC is preserved")
	_expect(not normalized_npcs.has("mod:invalid"), "invalid unknown NPC is discarded")
	var traveler: Dictionary = normalized_npcs["mod:traveler"] as Dictionary
	(traveler["memory"] as Dictionary)["event"] = "changed"
	var fresh_npcs: Dictionary = simulation.get_npcs()
	var fresh_traveler: Dictionary = fresh_npcs["mod:traveler"] as Dictionary
	var fresh_memory: Dictionary = fresh_traveler["memory"] as Dictionary
	_expect(String(fresh_memory["event"]) == "arrived", "unknown NPC state is deeply isolated")


func _test_save_store_rotates_and_recovers_backup() -> void:
	_cleanup_test_save_files()
	var store := SaveStore.new(TEST_SAVE_PATH)
	var first_state: Dictionary = Simulation.create_new_state()
	first_state["day"] = 7
	var second_state: Dictionary = Simulation.create_new_state()
	second_state["day"] = 8

	var first_write: Dictionary = store.write_state(first_state)
	var second_write: Dictionary = store.write_state(second_state)
	_expect(bool(first_write["success"]), "first atomic save succeeds")
	_expect(bool(second_write["success"]), "second atomic save succeeds")

	var current_read: Dictionary = store.read_state()
	_expect(bool(current_read["success"]), "current save reads after rotation")
	if bool(current_read["success"]):
		var current_state: Dictionary = current_read["state"] as Dictionary
		_expect(int(current_state["day"]) == 8, "main save contains newest state")

	var backup_store := SaveStore.new(TEST_SAVE_PATH + ".bak")
	var backup_read: Dictionary = backup_store.read_state()
	_expect(bool(backup_read["success"]), "backup exists after rotation")
	if bool(backup_read["success"]):
		var backup_state: Dictionary = backup_read["state"] as Dictionary
		_expect(int(backup_state["day"]) == 7, "backup contains previous state")

	var corrupt_file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	_expect(corrupt_file != null, "test can corrupt primary save")
	if corrupt_file != null:
		corrupt_file.store_string("{broken")
		corrupt_file.close()
	var recovered: Dictionary = store.read_state()
	_expect(bool(recovered["success"]), "store recovers from corrupt primary")
	_expect(bool(recovered.get("recovered_from_backup", false)), "backup recovery is reported")
	if bool(recovered["success"]):
		var recovered_state: Dictionary = recovered["state"] as Dictionary
		_expect(int(recovered_state["day"]) == 7, "recovery returns intact backup")
	_cleanup_test_save_files()


func _test_session_uses_backup_for_invalid_header_only() -> void:
	_cleanup_test_save_files()
	var store := SaveStore.new(TEST_SAVE_PATH)
	var backup_state: Dictionary = Simulation.create_new_state()
	backup_state["day"] = 7
	var newer_state: Dictionary = Simulation.create_new_state()
	newer_state["day"] = 8
	_expect(bool(store.write_state(backup_state)["success"]), "backup setup save succeeds")
	_expect(bool(store.write_state(newer_state)["success"]), "primary setup save succeeds")

	var invalid_header_file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	_expect(invalid_header_file != null, "test can write invalid save header")
	if invalid_header_file != null:
		invalid_header_file.store_string(JSON.stringify({"version": "broken"}))
		invalid_header_file.close()

	var recovery_session = SessionNodeScript.new()
	recovery_session._save_store = store
	recovery_session._start_new_simulation()
	_expect(recovery_session.load_game(), "session uses backup for invalid primary header")
	_expect(recovery_session.get_day() == 7, "invalid header recovery loads backup state")
	recovery_session.free()

	var future_state: Dictionary = Simulation.create_new_state()
	future_state["version"] = Simulation.SAVE_VERSION + 1
	future_state["day"] = 9
	var future_file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	_expect(future_file != null, "test can write future save")
	if future_file != null:
		future_file.store_string(JSON.stringify(future_state))
		future_file.close()

	var future_session = SessionNodeScript.new()
	future_session._save_store = store
	future_session._start_new_simulation()
	_expect(not future_session.load_game(), "session rejects future primary save")
	_expect(future_session.get_day() == 1, "future save does not silently load older backup")
	future_session.free()
	_cleanup_test_save_files()


func _test_legacy_save_ids_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 1
	legacy_state["inventory"] = {
		"wood": 2,
		"stone": 1,
		"raw_water": 1,
	}
	legacy_state["collected"] = {
		"wood_north": true,
	}

	var simulation: World = Simulation.new(legacy_state)
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 2, "legacy wood id migrates to core namespaced id")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 1, "legacy stone id migrates to core namespaced id")
	_expect(simulation.get_item_count(FirstNightContent.RAW_WATER_ID) == 1, "legacy water id migrates to core namespaced id")
	_expect(simulation.is_collected("core:wood_north"), "legacy collected object id migrates to core namespaced id")


func _test_v3_outcomes_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 3
	legacy_state["outcomes"] = [
		"сухая комната",
		"холодный сквозняк",
		"остаточное тепло",
		"безопасная вода",
		"лёгкий ужин",
		"голодный сон",
		"mod:custom_outcome",
		"неизвестный старый результат",
		42,
	]

	var simulation: World = Simulation.new(legacy_state)
	var expected: Array[String] = [
		Simulation.OUTCOME_DRY_ROOM_ID,
		Simulation.OUTCOME_COLD_DRAFT_ID,
		Simulation.OUTCOME_RESIDUAL_WARMTH_ID,
		Simulation.OUTCOME_SAFE_WATER_ID,
		Simulation.OUTCOME_LIGHT_SUPPER_ID,
		Simulation.OUTCOME_HUNGRY_SLEEP_ID,
		"mod:custom_outcome",
	]
	var migrated_state: Dictionary = simulation.export_state()
	_expect(
		int(migrated_state.get("version", 0)) == Simulation.SAVE_VERSION,
		"v3 save migrates to current save version"
	)
	_expect(migrated_state.get("outcomes", []) == expected, "v3 outcome copy migrates to stable ids")

	var encoded: String = JSON.stringify(migrated_state)
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "migrated outcomes survive JSON encoding")
	if typeof(decoded) == TYPE_DICTIONARY:
		var restored: World = Simulation.new(decoded as Dictionary)
		_expect(
			restored.export_state().get("outcomes", []) == expected,
			"stable outcome ids survive a save round trip"
		)


func _test_v4_npc_state_is_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 4
	var legacy_npcs: Dictionary = legacy_state["npcs"] as Dictionary
	var legacy_mira: Dictionary = legacy_npcs["core:first_neighbor"] as Dictionary
	for key: String in [
		"needs",
		"activity_id",
		"activity_started_minute",
		"target_cell",
		"personal_inventory",
		"facing",
		"moving",
	]:
		legacy_mira.erase(key)

	var simulation: World = Simulation.new(legacy_state)
	var migrated: Dictionary = simulation.export_state()
	var mira: Dictionary = (migrated["npcs"] as Dictionary)["core:first_neighbor"] as Dictionary
	_expect(
		int(migrated.get("version", 0)) == Simulation.SAVE_VERSION,
		"v4 save migrates to current save version"
	)
	_expect(typeof(mira.get("needs")) == TYPE_DICTIONARY, "v4 NPC gains normalized needs")
	_expect(String(mira.get("activity_id", "")).contains(":"), "v4 NPC gains stable activity id")
	_expect(int((mira.get("personal_inventory", {}) as Dictionary).get("core:food", -1)) == 2, "v4 NPC gains initial personal food")
	_expect(typeof(mira.get("target_cell")) == TYPE_ARRAY, "v4 NPC gains a target cell")


func _test_v5_blueprints_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 5
	legacy_state.erase("blueprints")
	legacy_state.erase("structures")
	var migrated_simulation: World = Simulation.new(legacy_state)
	_expect(
		int(migrated_simulation.export_state().get("version", 0)) == Simulation.SAVE_VERSION,
		"v5 save migrates to current save version"
	)
	_expect(migrated_simulation.get_blueprints().is_empty(), "v5 save gains empty blueprints")
	_expect(migrated_simulation.get_structures().is_empty(), "v5 save gains empty structures")

	var state_with_blueprint: Dictionary = Simulation.create_new_state()
	state_with_blueprint["blueprints"] = [
		{
			"building_id": "core:wood_wall",
			"cell": [22, 29],
		},
		{
			"building_id": "core:wood_wall",
			"cell": [22, 29],
			"stage_id": "corrupt:stage",
		},
		{
			"building_id": "core:wood_wall",
			"cell": [19, 22],
		},
		{
			"building_id": "core:wood_wall",
			"cell": [22.5, 30],
		},
	]
	var simulation: World = Simulation.new(state_with_blueprint)
	var snapshot: Array = simulation.get_blueprints()
	_expect(snapshot.size() == 1, "blueprint normalization rejects duplicates and invalid cells")
	_expect(
		String((snapshot[0] as Dictionary).get("stage_id", "")) == "core:blueprint",
		"blueprint normalization restores the canonical stage"
	)
	(snapshot[0] as Dictionary)["cell"] = [99, 99]
	_expect(
		(simulation.get_blueprints()[0] as Dictionary).get("cell", []) == [22, 29],
		"blueprint query is isolated from simulation state"
	)


func _test_v6_structures_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 6
	legacy_state.erase("structures")
	var migrated_simulation: World = Simulation.new(legacy_state)
	_expect(
		int(migrated_simulation.export_state().get("version", 0)) == Simulation.SAVE_VERSION,
		"v6 save migrates to current save version"
	)
	_expect(migrated_simulation.get_structures().is_empty(), "v6 save gains empty structures")

	var state_with_structures: Dictionary = Simulation.create_new_state()
	state_with_structures["blueprints"] = [
		{"building_id": "core:wood_wall", "cell": [22, 29]},
		{"building_id": "core:wood_wall", "cell": [23, 29]},
	]
	state_with_structures["structures"] = [
		{"building_id": "core:wood_wall", "cell": [22, 29]},
		{"building_id": "core:wood_wall", "cell": [22, 29]},
		{"building_id": "core:wood_wall", "cell": [19, 22]},
	]
	var simulation: World = Simulation.new(state_with_structures)
	var structures: Array = simulation.get_structures()
	_expect(structures.size() == 1, "structure normalization rejects duplicates and blocked cells")
	_expect(
		String((structures[0] as Dictionary).get("stage_id", "")) == "core:complete",
		"structure normalization restores the canonical stage"
	)
	_expect(
		simulation.get_blueprints().size() == 1
		and (simulation.get_blueprints()[0] as Dictionary).get("cell", []) == [23, 29],
		"completed structure wins over a conflicting blueprint"
	)
	(structures[0] as Dictionary)["cell"] = [99, 99]
	_expect(
		(simulation.get_structures()[0] as Dictionary).get("cell", []) == [22, 29],
		"structure query is isolated from simulation state"
	)


func _test_character_appearance_generation() -> void:
	var catalog := AppearanceCatalog.new()
	_expect(catalog.get_frame_size() == Vector2i(32, 32), "character appearance uses 32x32 frames")
	_expect(catalog.get_frames_per_direction() == 4, "character appearance uses four walk frames")

	var player_appearance: Dictionary = catalog.get_default_player_appearance()
	_expect(catalog.validate_appearance(player_appearance).is_empty(), "default player appearance is valid")
	_expect(String(player_appearance.get("cloak", "")) == "core:cloak_charcoal", "default player appearance uses the placeholder cloak")

	var npc_a: Dictionary = catalog.generate_npc_appearance(247061)
	var npc_b: Dictionary = catalog.generate_npc_appearance(247061)
	var npc_c: Dictionary = catalog.generate_npc_appearance(247062)
	_expect(npc_a == npc_b, "NPC appearance generation is deterministic for the same seed")
	_expect(npc_a != npc_c, "NPC appearance generation changes with a different seed")
	_expect(catalog.validate_appearance(npc_a).is_empty(), "generated NPC appearance is valid")
	_expect(catalog.get_layered_parts(npc_a).size() >= 4, "generated NPC appearance has drawable parts")


func _test_first_neighbor_arrives_and_talks() -> void:
	var simulation: World = Simulation.new()
	_expect(not simulation.is_npc_visible("core:first_neighbor"), "first neighbor is hidden before the first night is complete")
	_complete_first_night_for_test(simulation)

	_expect(simulation.is_npc_visible("core:first_neighbor"), "first neighbor is visible after sleeping")
	_expect(
		simulation.get_object_label_key(
			"npc",
			"npc.generic.traveler.name",
			"core:first_neighbor"
		) == "npc.core.first_neighbor.unknown",
		"first neighbor starts with an unknown label key"
	)
	_expect(
		simulation.get_current_objective_key() == "first_night.objective.meet_neighbor",
		"objective points to the first neighbor"
	)

	var talk_result: Dictionary = _interact_near(simulation, "core:first_neighbor")
	_expect(bool(talk_result["success"]), "talking to first neighbor succeeds")
	_expect(
		String(talk_result.get("message_key", "")) == "ui.dialogue.speaker_line",
		"NPC result exposes a localization key"
	)
	_expect(not talk_result.has("message"), "simulation does not return localized NPC copy")
	var localized_talk: String = Localized.resolve(
		String(talk_result.get("message_key", "")),
		talk_result.get("message_args", {}) as Dictionary
	)
	_expect(localized_talk.begins_with("Мира:"), "first neighbor introduces herself by name")
	_expect(
		simulation.get_object_label_key(
			"npc",
			"npc.generic.traveler.name",
			"core:first_neighbor"
		) == "npc.core.first_neighbor.name",
		"first neighbor label becomes known after talking"
	)
	_expect(
		simulation.get_current_objective_key() == "farming.objective.study",
		"objective opens the farming route after greeting"
	)

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "NPC state serializes as a dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: World = Simulation.new(decoded as Dictionary)
	_expect(restored.is_npc_visible("core:first_neighbor"), "first neighbor visibility survives serialization")
	_expect(
		restored.get_object_label_key(
			"npc",
			"npc.generic.traveler.name",
			"core:first_neighbor"
		) == "npc.core.first_neighbor.name",
		"known NPC label key survives serialization"
	)
	_expect(not restored.get_npc_appearance("core:first_neighbor").is_empty(), "NPC appearance survives serialization")


func _test_grid_pathfinder_avoids_static_obstacles() -> void:
	var pathfinder := LocalGridPathfinderScript.new(
		FirstNightNavigationScript.MAP_SIZE,
		FirstNightNavigationScript.CELL_SIZE,
		FirstNightNavigationScript.blocked_cells()
	)
	_expect(not pathfinder.is_walkable(Vector2i(2, 25)), "water cell is blocked")
	_expect(not pathfinder.is_walkable(Vector2i(19, 22)), "house wall cell is blocked")
	_expect(pathfinder.is_walkable(Vector2i(24, 25)), "house doorway is walkable")

	var current := Vector2i(26, 29)
	var target := Vector2i(25, 23)
	var visited: Array[Vector2i] = [current]
	for _step: int in range(32):
		if current == target:
			break
		current = pathfinder.next_cell(current, target)
		visited.append(current)
	_expect(current == target, "grid path reaches the shelter rest cell")
	_expect(visited.has(Vector2i(24, 25)), "grid path enters the house through its doorway")
	for cell: Vector2i in visited:
		_expect(pathfinder.is_walkable(cell), "grid path never enters a blocked cell: %s" % cell)


func _test_mira_needs_schedule_and_personal_food() -> void:
	var simulation: World = Simulation.new()
	_complete_first_night_for_test(simulation)
	var start_position: Vector2 = simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	var start_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(simulation.get_npc_personal_food("core:first_neighbor") == 2, "Mira arrives with two personal food portions")

	simulation.advance_minutes(5 * 60)
	var midday_position: Vector2 = simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	var midday_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(not midday_position.is_equal_approx(start_position), "Mira changes position during her morning")
	_expect(float(midday_needs.restedness) < float(start_needs.restedness), "Mira spends restedness while awake, under shared physical rules")
	_expect(simulation.get_npc_personal_food("core:first_neighbor") == 1, "Mira eats one personal portion before noon")
	_expect(float(midday_needs.get("hunger", 0.0)) > 45.0, "Mira restores hunger after eating")

	simulation.advance_minutes(simulation.LATEST_MINUTE - simulation.get_minute_of_day())
	var night_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(
		simulation.get_npc_activity_id("core:first_neighbor") == NpcAutonomyScript.ACTIVITY_RESTING,
		"Mira rests at the end of the day"
	)
	_expect(simulation.get_npc_personal_food("core:first_neighbor") == 0, "Mira uses both travel portions across the day")
	_expect(float(night_needs.get("energy", 0.0)) > 20.0, "rest begins restoring Mira's energy")


func _test_mira_autonomy_is_deterministic_and_serialized() -> void:
	var first_result: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	var second_result: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	_expect(bool(first_result.get("success", false)), "first autonomy scenario builds")
	_expect(bool(second_result.get("success", false)), "second autonomy scenario builds")
	if not bool(first_result.get("success", false)) or not bool(second_result.get("success", false)):
		return

	var first: World = first_result["simulation"] as World
	var second: World = second_result["simulation"] as World
	first.advance_minutes(7 * 60)
	second.advance_minutes(7 * 60)
	_expect(first.get_npcs() == second.get_npcs(), "equal state and elapsed minutes produce identical NPC autonomy")

	var encoded: String = JSON.stringify(first.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "autonomy state survives JSON encoding")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: World = Simulation.new(decoded as Dictionary)
	var expected_npcs: Dictionary = first.get_npcs()
	var restored_npcs: Dictionary = restored.get_npcs()
	_expect(
		JSON.stringify(restored_npcs) == JSON.stringify(expected_npcs),
		"NPC needs, activity and position survive save round trip"
	)


func _test_npc_work_request_contract_and_refusals() -> void:
	var target_cell := Vector2i(22, 29)
	var command: Dictionary = NpcWorkRequestScript.request_construction_help(
		"core:first_neighbor",
		target_cell
	)
	_expect(
		String(command.get("actor_id", "")) == "core:player",
		"work request uses the player actor id"
	)
	_expect(
		String(command.get("action_id", "")) == "core:request_construction_help",
		"work request uses a stable action id"
	)
	_expect(
		command.get("target_cell", []) == [22, 29],
		"work request serializes its target cell"
	)
	_expect(
		bool(
			NpcWorkRequestValidatorScript.validate_construction_help(command).get(
				"success",
				false
			)
		),
		"work request validator accepts a canonical request"
	)

	var forged: Dictionary = command.duplicate(true)
	forged["actor_id"] = "core:forged"
	var forged_result: Dictionary = (
		NpcWorkRequestValidatorScript.validate_construction_help(forged)
	)
	_expect(
		String(forged_result.get("reason_id", "")) == "core:unknown_actor",
		"work request validator rejects a forged actor"
	)

	var unacquainted: World = _build_mira_work_simulation(
		target_cell,
		false,
		true
	)
	var unacquainted_result: Dictionary = unacquainted.execute_npc_work_request(command)
	_expect(
		String(unacquainted_result.get("reason_id", "")) == "core:not_acquainted",
		"Mira refuses a request before meeting the player"
	)

	var missing_blueprint: World = _build_mira_work_simulation(
		target_cell,
		true,
		false
	)
	var missing_result: Dictionary = missing_blueprint.execute_npc_work_request(command)
	_expect(
		String(missing_result.get("reason_id", "")) == "core:missing_blueprint",
		"work request requires a real blueprint"
	)

	var no_material_state: Dictionary = _build_mira_work_simulation(
		target_cell,
		true,
		true
	).export_state()
	var no_material_mira: Dictionary = (
		no_material_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	(no_material_mira["personal_inventory"] as Dictionary)[
		"core:plank"
	] = 0
	var no_materials := Simulation.new(no_material_state)
	_expect(
		String(
			no_materials.execute_npc_work_request(command).get("reason_id", "")
		) == "core:required_materials_missing",
		"Mira cannot start construction without delivered or carried materials"
	)

	var hungry_state: Dictionary = _build_mira_work_simulation(
		target_cell,
		true,
		true
	).export_state()
	var hungry_npc: Dictionary = (
		hungry_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	(hungry_npc["needs"] as Dictionary)["hunger"] = 20.0
	var hungry := Simulation.new(hungry_state)
	_expect(
		String(
			hungry.execute_npc_work_request(command).get("reason_id", "")
		) == "core:npc_hungry",
		"Mira refuses construction while too hungry"
	)

	var tired_state: Dictionary = _build_mira_work_simulation(
		target_cell,
		true,
		true
	).export_state()
	var tired_npc: Dictionary = (
		tired_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	(tired_npc["needs"] as Dictionary)["energy"] = 20.0
	var tired := Simulation.new(tired_state)
	_expect(
		String(
			tired.execute_npc_work_request(command).get("reason_id", "")
		) == "core:npc_tired",
		"Mira refuses construction while too tired"
	)

	var blocked_target := Vector2i(10, 10)
	var blocked_state: Dictionary = _build_mira_work_simulation(
		blocked_target,
		true,
		true
	).export_state()
	for blocked_cell: Vector2i in [
		blocked_target + Vector2i.DOWN,
		blocked_target + Vector2i.RIGHT,
		blocked_target + Vector2i.UP,
		blocked_target + Vector2i.LEFT,
	]:
		(blocked_state["structures"] as Array).append({
			"building_id": "core:wood_wall",
			"cell": [blocked_cell.x, blocked_cell.y],
			"stage_id": "core:complete",
		})
	var blocked := Simulation.new(blocked_state)
	var blocked_command: Dictionary = NpcWorkRequestScript.request_construction_help(
		"core:first_neighbor",
		blocked_target
	)
	_expect(
		String(
			blocked.execute_npc_work_request(blocked_command).get("reason_id", "")
		) == "core:unreachable_work",
		"Mira refuses a blueprint without an adjacent work cell"
	)


func _test_mira_completes_construction_commitment() -> void:
	var target_cell := Vector2i(22, 29)
	var simulation: World = _build_mira_work_simulation(
		target_cell,
		true,
		true
	)
	var command: Dictionary = NpcWorkRequestScript.request_construction_help(
		"core:first_neighbor",
		target_cell
	)
	var accepted: Dictionary = simulation.execute_npc_work_request(command)
	_expect(bool(accepted.get("success", false)), "Mira accepts an available construction request")
	_expect(
		String(accepted.get("reason_id", "")) == "core:request_accepted",
		"accepted construction request has a stable reason"
	)
	var commitment: Dictionary = simulation.get_npc_work_commitment("core:first_neighbor")
	_expect(not commitment.is_empty(), "accepted request creates a work commitment")
	var mira_after_acceptance: Dictionary = (
		simulation.get_npcs().get("core:first_neighbor", {}) as Dictionary
	)
	_expect(
		int((mira_after_acceptance.get("personal_inventory", {}) as Dictionary).get(
			"core:plank",
			0
		)) == 0,
		"Mira transfers required carried planks into the blueprint"
	)
	_expect(
		(simulation.get_blueprints()[0] as Dictionary).get(
			"delivered_materials",
			{}
		) == {"core:plank": 30},
		"Mira's delivered planks become part of the blueprint"
	)
	_expect(
		int(commitment.get("required_minutes", 0))
		== 25,
		"construction commitment records its required work time"
	)

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored := Simulation.new(decoded as Dictionary)
	_expect(
		restored.get_npc_work_commitment("core:first_neighbor") == commitment,
		"construction commitment survives a save round trip"
	)

	var player_energy_before_npc_work := simulation.get_player_energy()
	simulation.advance_minutes(14)
	_expect(
		simulation.get_blueprints().size() == 1
		and simulation.get_structures().is_empty(),
		"construction does not finish before travel and work time elapse"
	)
	_expect(
		int((simulation.get_blueprints()[0] as Dictionary).get(
			"work_progress_minutes",
			0
		)) == 11,
		"Mira advances the same work progress stored on the blueprint"
	)
	_expect(
		simulation.get_npc_memories("core:first_neighbor").is_empty(),
		"unfinished construction creates no memory"
	)
	simulation.advance_minutes(14)
	_expect(simulation.get_blueprints().is_empty(), "Mira consumes the completed blueprint")
	_expect(is_equal_approx(simulation.get_player_energy(), player_energy_before_npc_work), "Mira's successful construction work does not spend the player's energy")
	_expect(simulation.get_structures().size() == 1, "Mira creates one completed wall")
	_expect(
		simulation.get_npc_work_commitment("core:first_neighbor").is_empty(),
		"completed construction closes the work commitment"
	)
	_expect(
		not simulation.is_navigation_cell_walkable(target_cell),
		"Mira's completed wall updates navigation"
	)
	_expect(
		simulation.get_npc_activity_id("core:first_neighbor")
		!= NpcAutonomyScript.ACTIVITY_BUILDING,
		"Mira returns to her prior routine after completing the wall"
	)

	var deterministic_a := Simulation.new(decoded as Dictionary)
	var deterministic_b := Simulation.new(decoded as Dictionary)
	deterministic_a.advance_minutes(15)
	deterministic_b.advance_minutes(15)
	_expect(
		deterministic_a.export_state() == deterministic_b.export_state(),
		"equal commitments and elapsed time produce the same construction result"
	)


func _test_simulation_time_step_invariance() -> void:
	var target_cell := Vector2i(22, 29)
	var accepted_simulation: World = _build_mira_work_simulation(
		target_cell,
		true,
		true
	)
	var accepted := accepted_simulation.execute_npc_work_request(
		NpcWorkRequestScript.request_construction_help("core:first_neighbor", target_cell)
	)
	_expect(bool(accepted.get("success", false)), "time-step comparison accepts Mira's work request")
	if not bool(accepted.get("success", false)):
		return
	var one_step := Simulation.new(accepted_simulation.export_state())
	var minute_steps := Simulation.new(accepted_simulation.export_state())
	one_step.advance_minutes(60)
	for _minute: int in range(60):
		minute_steps.advance_minutes(1)
	_expect(
		one_step.export_state() == minute_steps.export_state(),
		"one 60-minute advance must match sixty one-minute advances"
	)


func _test_missing_blueprint_releases_commitment() -> void:
	var target_cell := Vector2i(22, 29)
	var simulation: World = _build_mira_work_simulation(
		target_cell,
		true,
		true
	)
	var request: Dictionary = NpcWorkRequestScript.request_construction_help(
		"core:first_neighbor",
		target_cell
	)
	_expect(
		bool(simulation.execute_npc_work_request(request).get("success", false)),
		"commitment cancellation scenario starts with an accepted request"
	)
	simulation.execute_construction_command(
		ConstructionCommandScript.cancel_blueprint(target_cell)
	)
	simulation.advance_minutes(1)
	_expect(
		simulation.get_npc_work_commitment("core:first_neighbor").is_empty(),
		"missing blueprint releases Mira from the commitment"
	)
	_expect(
		simulation.get_npc_memories("core:first_neighbor").is_empty(),
		"cancelled construction creates no memory"
	)


func _test_shared_wall_creates_memory_and_relationship() -> void:
	var target_cell := Vector2i(22, 29)
	var simulation: World = _build_mira_work_simulation(
		target_cell,
		true,
		true
	)
	var request: Dictionary = NpcWorkRequestScript.request_construction_help(
		"core:first_neighbor",
		target_cell
	)
	_expect(
		bool(simulation.execute_npc_work_request(request).get("success", false)),
		"memory scenario starts with an accepted work request"
	)
	simulation.advance_minutes(28)

	var memories: Array = simulation.get_npc_memories("core:first_neighbor")
	_expect(memories.size() == 1, "completed shared wall creates one memory")
	if memories.size() == 1:
		var memory: Dictionary = memories[0] as Dictionary
		_expect(
			String(memory.get("memory_id", "")) == "core:first_shared_wall",
			"shared wall memory has a stable id"
		)
		_expect(
			String(memory.get("event_id", "")) == "core:shared_wall_completed",
			"shared wall memory records the confirmed event"
		)
		_expect(memory.get("target_cell", []) == [22, 29], "memory records the wall cell")
		_expect(not bool(memory.get("acknowledged", true)), "new memory awaits a context line")

	var relationship: Dictionary = simulation.get_npc_relationship_to_player(
		"core:first_neighbor"
	)
	_expect(float(relationship.get("trust", 0.0)) == 1.0, "memory derives one trust point")
	_expect(float(relationship.get("warmth", 0.0)) == 2.0, "memory derives two warmth points")
	_expect(float(relationship.get("respect", 0.0)) == 1.0, "memory derives one respect point")

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored := Simulation.new(decoded as Dictionary)
	_expect(
		restored.get_npc_memories("core:first_neighbor") == memories,
		"shared wall memory survives a save round trip"
	)
	_expect(
		restored.get_npc_relationship_to_player("core:first_neighbor") == relationship,
		"derived relationship survives through its memory source"
	)

	(memories[0] as Dictionary)["acknowledged"] = true
	_expect(
		not bool(
			(simulation.get_npc_memories("core:first_neighbor")[0] as Dictionary).get(
				"acknowledged",
				true
			)
		),
		"memory query is isolated from simulation state"
	)

	var debug_completion: World = _build_mira_work_simulation(
		Vector2i(23, 29),
		true,
		true
	)
	debug_completion.execute_construction_command(
		ConstructionCommandScript.complete_blueprint(Vector2i(23, 29))
	)
	_expect(
		debug_completion.get_npc_memories("core:first_neighbor").is_empty(),
		"debug blueprint completion creates no shared memory"
	)

	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)
	var second_cell := Vector2i(22, 30)
	simulation.execute_construction_command(
		ConstructionCommandScript.place_wall_blueprint(second_cell)
	)
	simulation.execute_npc_work_request(
		NpcWorkRequestScript.request_construction_help(
			"core:first_neighbor",
			second_cell
		)
	)
	simulation.advance_minutes(20)
	_expect(
		simulation.get_npc_memories("core:first_neighbor").size() == 1,
		"later shared walls do not duplicate the first-wall memory"
	)


func _test_shared_wall_context_line_is_consumed_once() -> void:
	var target_cell := Vector2i(22, 29)
	var simulation: World = _build_mira_work_simulation(
		target_cell,
		true,
		true
	)
	simulation.execute_npc_work_request(
		NpcWorkRequestScript.request_construction_help(
			"core:first_neighbor",
			target_cell
		)
	)
	simulation.advance_minutes(28)
	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)

	var follow_up: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"core:first_neighbor",
		simulation.ACTION_INTERACT
	)
	var follow_up_args: Dictionary = follow_up.get("message_args", {}) as Dictionary
	var follow_up_line: Dictionary = follow_up_args.get("line", {}) as Dictionary
	_expect(
		String(follow_up_line.get("text_key", ""))
		== "dialogue.core.first_neighbor.shared_wall",
		"first conversation after construction uses the shared-wall line"
	)
	_expect(
		bool(
			(simulation.get_npc_memories("core:first_neighbor")[0] as Dictionary).get(
				"acknowledged",
				false
			)
		),
		"contextual conversation acknowledges the memory"
	)

	var repeated: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"core:first_neighbor",
		simulation.ACTION_INTERACT
	)
	var repeated_args: Dictionary = repeated.get("message_args", {}) as Dictionary
	var repeated_line: Dictionary = repeated_args.get("line", {}) as Dictionary
	_expect(
		String(repeated_line.get("text_key", ""))
		== "dialogue.core.first_neighbor.repeat",
		"later conversation returns to Mira's ordinary repeat line"
	)


func _build_mira_work_simulation(
	target_cell: Vector2i,
	acquainted: bool,
	with_blueprint: bool
) -> World:
	var scenario: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	var simulation: World = scenario["simulation"] as World
	var state_with_materials: Dictionary = simulation.export_state()
	var mira: Dictionary = (
		state_with_materials["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	var mira_inventory: Dictionary = mira.get("personal_inventory", {}) as Dictionary
	mira_inventory[FirstNightContent.WOOD_ID] = 3
	mira_inventory["core:plank"] = 30
	mira["personal_inventory"] = mira_inventory
	simulation = Simulation.new(state_with_materials)
	simulation.set_player_position(
		simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	)
	if acquainted:
		simulation.execute_command(
			simulation.PLAYER_ACTOR_ID,
			"core:first_neighbor",
			simulation.ACTION_INTERACT
		)
	if with_blueprint:
		simulation.execute_construction_command(
			ConstructionCommandScript.place_wall_blueprint(target_cell)
		)
	return simulation


func _test_construction_command_payload() -> void:
	var command: Dictionary = ConstructionCommandScript.place_wall_blueprint(Vector2i(22, 29))
	_expect(
		String(command.get("actor_id", "")) == "core:player",
		"construction command uses the player actor id"
	)
	_expect(
		String(command.get("action_id", "")) == "core:place_blueprint",
		"construction command uses a stable action id"
	)
	_expect(
		String(command.get("building_id", "")) == "core:wood_wall",
		"construction command uses a stable building id"
	)
	_expect(
		command.get("cell", []) == [22, 29],
		"construction command serializes the selected cell as integers"
	)

	var cancel_command: Dictionary = (
		ConstructionCommandScript.cancel_blueprint(Vector2i(22, 29))
	)
	_expect(
		String(cancel_command.get("actor_id", "")) == "core:player",
		"blueprint cancellation uses the player actor id"
	)
	_expect(
		String(cancel_command.get("action_id", "")) == "core:cancel_blueprint",
		"blueprint cancellation uses a stable action id"
	)
	_expect(
		cancel_command.get("cell", []) == [22, 29],
		"blueprint cancellation serializes the selected cell as integers"
	)
	_expect(
		not cancel_command.has("building_id"),
		"blueprint cancellation identifies the target by cell"
	)

	var delivery_command: Dictionary = (
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	_expect(
		String(delivery_command.get("action_id", ""))
		== "core:deliver_blueprint_materials",
		"blueprint delivery uses a stable action id"
	)
	_expect(
		delivery_command.get("cell", []) == [22, 29],
		"blueprint delivery identifies the target by cell"
	)
	var work_command: Dictionary = (
		ConstructionCommandScript.work_blueprint(Vector2i(22, 29))
	)
	_expect(
		String(work_command.get("action_id", "")) == "core:work_blueprint",
		"blueprint work uses a stable action id"
	)
	_expect(
		work_command.get("cell", []) == [22, 29],
		"blueprint work identifies the target by cell"
	)

	var complete_command: Dictionary = (
		ConstructionCommandScript.complete_blueprint(Vector2i(22, 29))
	)
	_expect(
		String(complete_command.get("actor_id", "")) == "core:player",
		"blueprint completion uses the player actor id"
	)
	_expect(
		String(complete_command.get("action_id", "")) == "core:complete_blueprint",
		"blueprint completion uses a stable action id"
	)
	_expect(
		complete_command.get("cell", []) == [22, 29],
		"blueprint completion serializes the selected cell as integers"
	)
	_expect(
		not complete_command.has("building_id"),
		"blueprint completion resolves the building from state"
	)


func _test_construction_command_validation() -> void:
	var valid_command: Dictionary = ConstructionCommandScript.place_wall_blueprint(Vector2i(22, 29))
	var valid_result: Dictionary = ConstructionValidatorScript.validate_place_blueprint(valid_command)
	_expect(bool(valid_result.get("success", false)), "construction validator accepts free ground")
	_expect(valid_result.get("cell", []) == [22, 29], "construction validator preserves a valid cell")

	var blocked_command: Dictionary = ConstructionCommandScript.place_wall_blueprint(Vector2i(19, 22))
	var blocked_result: Dictionary = ConstructionValidatorScript.validate_place_blueprint(blocked_command)
	_expect(not bool(blocked_result.get("success", true)), "construction validator rejects a wall cell")
	_expect(
		String(blocked_result.get("reason_id", "")) == "core:blocked_cell",
		"blocked construction has a stable reason id"
	)

	var outside_command: Dictionary = ConstructionCommandScript.place_wall_blueprint(Vector2i(-1, 20))
	var outside_result: Dictionary = ConstructionValidatorScript.validate_place_blueprint(outside_command)
	_expect(not bool(outside_result.get("success", true)), "construction validator rejects outside map")
	_expect(
		String(outside_result.get("reason_id", "")) == "core:outside_map",
		"outside construction has a stable reason id"
	)

	var forged_command: Dictionary = valid_command.duplicate(true)
	forged_command["actor_id"] = "core:forged_actor"
	var forged_result: Dictionary = ConstructionValidatorScript.validate_place_blueprint(forged_command)
	_expect(not bool(forged_result.get("success", true)), "construction validator rejects forged actor")
	_expect(
		String(forged_result.get("reason_id", "")) == "core:unknown_actor",
		"forged construction actor has a stable reason id"
	)

	var cancel_command: Dictionary = ConstructionCommandScript.cancel_blueprint(Vector2i(22, 29))
	var cancel_result: Dictionary = (
		ConstructionValidatorScript.validate_cancel_blueprint(cancel_command)
	)
	_expect(bool(cancel_result.get("success", false)), "cancellation validator accepts a valid cell")
	_expect(
		cancel_result.get("cell", []) == [22, 29],
		"cancellation validator preserves a valid cell"
	)

	var outside_cancel: Dictionary = (
		ConstructionCommandScript.cancel_blueprint(Vector2i(-1, 29))
	)
	var outside_cancel_result: Dictionary = (
		ConstructionValidatorScript.validate_cancel_blueprint(outside_cancel)
	)
	_expect(
		String(outside_cancel_result.get("reason_id", "")) == "core:outside_map",
		"cancellation validator rejects a cell outside the map"
	)

	var forged_cancel: Dictionary = cancel_command.duplicate(true)
	forged_cancel["actor_id"] = "core:forged_actor"
	var forged_cancel_result: Dictionary = (
		ConstructionValidatorScript.validate_cancel_blueprint(forged_cancel)
	)
	_expect(
		String(forged_cancel_result.get("reason_id", "")) == "core:unknown_actor",
		"cancellation validator rejects a forged actor"
	)

	var delivery_command: Dictionary = (
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	var delivery_validation: Dictionary = (
		ConstructionValidatorScript.validate_deliver_materials(delivery_command)
	)
	_expect(
		bool(delivery_validation.get("success", false)),
		"delivery validator accepts a valid cell"
	)
	var forged_delivery: Dictionary = delivery_command.duplicate(true)
	forged_delivery["actor_id"] = "core:forged_actor"
	_expect(
		String(
			ConstructionValidatorScript.validate_deliver_materials(
				forged_delivery
			).get("reason_id", "")
		) == "core:unknown_actor",
		"delivery validator rejects a forged actor"
	)
	var work_command: Dictionary = ConstructionCommandScript.work_blueprint(
		Vector2i(22, 29)
	)
	_expect(
		bool(
			ConstructionValidatorScript.validate_work_blueprint(
				work_command
			).get("success", false)
		),
		"work validator accepts a canonical command"
	)

	var complete_command: Dictionary = (
		ConstructionCommandScript.complete_blueprint(Vector2i(22, 29))
	)
	var complete_result: Dictionary = (
		ConstructionValidatorScript.validate_complete_blueprint(complete_command)
	)
	_expect(bool(complete_result.get("success", false)), "completion validator accepts a valid cell")
	_expect(
		complete_result.get("cell", []) == [22, 29],
		"completion validator preserves a valid cell"
	)

	var outside_complete: Dictionary = (
		ConstructionCommandScript.complete_blueprint(Vector2i(128, 29))
	)
	var outside_complete_result: Dictionary = (
		ConstructionValidatorScript.validate_complete_blueprint(outside_complete)
	)
	_expect(
		String(outside_complete_result.get("reason_id", "")) == "core:outside_map",
		"completion validator rejects a cell outside the map"
	)

	var forged_complete: Dictionary = complete_command.duplicate(true)
	forged_complete["actor_id"] = "core:forged_actor"
	var forged_complete_result: Dictionary = (
		ConstructionValidatorScript.validate_complete_blueprint(forged_complete)
	)
	_expect(
		String(forged_complete_result.get("reason_id", "")) == "core:unknown_actor",
		"completion validator rejects a forged actor"
	)


func _test_blueprint_command_execution() -> void:
	var empty_inventory_simulation: World = Simulation.new()
	empty_inventory_simulation.execute_construction_command(
		ConstructionCommandScript.place_wall_blueprint(Vector2i(22, 29))
	)
	var empty_delivery: Dictionary = empty_inventory_simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	_expect(
		String(empty_delivery.get("reason_id", ""))
		== "core:required_materials_missing",
		"delivery reports when the player carries no required materials"
	)
	empty_inventory_simulation.set_player_position(Vector2.ZERO)
	var distant_delivery: Dictionary = empty_inventory_simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	_expect(
		String(distant_delivery.get("reason_id", "")) == "core:too_far",
		"delivery requires the player to stand near the blueprint"
	)

	var initial_state: Dictionary = Simulation.create_new_state()
	(initial_state["inventory"] as Dictionary)["core:plank"] = 99
	var simulation: World = Simulation.new(initial_state)
	var first_command: Dictionary = (
		ConstructionCommandScript.place_wall_blueprint(Vector2i(22, 29))
	)
	var first_result: Dictionary = simulation.execute_construction_command(first_command)
	_expect(bool(first_result.get("success", false)), "valid construction command places a blueprint")
	_expect(bool(first_result.get("changed", false)), "blueprint placement reports a state change")

	var blueprints: Array = simulation.get_blueprints()
	_expect(blueprints.size() == 1, "blueprint placement adds one state entry")
	if blueprints.size() == 1:
		var first_blueprint: Dictionary = blueprints[0] as Dictionary
		_expect(
			String(first_blueprint.get("building_id", "")) == "core:wood_wall",
			"placed blueprint preserves the building id"
		)
		_expect(first_blueprint.get("cell", []) == [22, 29], "placed blueprint preserves the cell")
		_expect(
			String(first_blueprint.get("stage_id", "")) == "core:blueprint",
			"placed blueprint uses the blueprint stage"
		)
		_expect(
			first_blueprint.get("required_materials", {}) == {"core:plank": 30},
			"placed wall blueprint snapshots its material requirement"
		)
		_expect(
			first_blueprint.get("delivered_materials", {}) == {"core:plank": 0},
			"placed wall blueprint starts without delivered materials"
		)
		_expect(
			int(first_blueprint.get("required_work_minutes", 0)) == 25,
			"placed wall blueprint snapshots required work"
		)
		_expect(
			int(first_blueprint.get("work_progress_minutes", -1)) == 0,
			"placed wall blueprint starts without work progress"
		)

	var delivery_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	_expect(bool(delivery_result.get("success", false)), "player delivers carried wood")
	_expect(
		simulation.get_item_count("core:plank") == 69,
		"delivered planks leave the player inventory"
	)
	_expect(
		(simulation.get_blueprints()[0] as Dictionary).get(
			"delivered_materials",
			{}
		) == {"core:plank": 30},
		"delivered planks become part of the blueprint"
	)
	var duplicate_delivery: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	_expect(
		String(duplicate_delivery.get("reason_id", ""))
		== "core:materials_already_delivered",
		"a complete material requirement rejects duplicate delivery"
	)

	var duplicate_result: Dictionary = simulation.execute_construction_command(first_command)
	_expect(
		not bool(duplicate_result.get("success", true)),
		"duplicate blueprint placement is rejected"
	)
	_expect(
		String(duplicate_result.get("reason_id", "")) == "core:occupied_cell",
		"duplicate blueprint placement has a stable reason id"
	)
	_expect(simulation.get_blueprints().size() == 1, "duplicate placement does not mutate state")

	var blocked_command: Dictionary = (
		ConstructionCommandScript.place_wall_blueprint(Vector2i(19, 22))
	)
	var blocked_result: Dictionary = simulation.execute_construction_command(blocked_command)
	_expect(
		String(blocked_result.get("reason_id", "")) == "core:blocked_cell",
		"blocked blueprint execution preserves validation failure"
	)
	_expect(simulation.get_blueprints().size() == 1, "blocked placement does not mutate state")

	var forged_command: Dictionary = first_command.duplicate(true)
	forged_command["actor_id"] = "core:forged_actor"
	var forged_result: Dictionary = simulation.execute_construction_command(forged_command)
	_expect(
		String(forged_result.get("reason_id", "")) == "core:unknown_actor",
		"blueprint execution rejects a forged actor"
	)
	_expect(simulation.get_blueprints().size() == 1, "forged placement does not mutate state")

	var second_command: Dictionary = (
		ConstructionCommandScript.place_wall_blueprint(Vector2i(23, 29))
	)
	var second_result: Dictionary = simulation.execute_construction_command(second_command)
	_expect(bool(second_result.get("success", false)), "a second free cell accepts a blueprint")
	_expect(simulation.get_blueprints().size() == 2, "two free cells store two blueprints")

	var expected_blueprints: Array = simulation.get_blueprints()
	var decoded: Variant = JSON.parse_string(JSON.stringify(simulation.export_state()))
	_expect(typeof(decoded) == TYPE_DICTIONARY, "blueprint state survives JSON encoding")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: World = Simulation.new(decoded as Dictionary)
	_expect(
		restored.get_blueprints() == expected_blueprints,
		"placed blueprints survive save round trip"
	)

	var cancel_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.cancel_blueprint(Vector2i(22, 29))
	)
	_expect(bool(cancel_result.get("success", false)), "valid cancellation removes a blueprint")
	_expect(bool(cancel_result.get("changed", false)), "valid cancellation reports a state change")
	_expect(
		String(cancel_result.get("reason_id", "")) == "core:blueprint_cancelled",
		"valid cancellation has a stable reason id"
	)
	_expect(
		simulation.get_item_count("core:plank") == 80,
		"cancelling a blueprint returns only the materials that fit in the backpack"
	)
	var full_cancel_state: Dictionary = Simulation.create_new_state()
	(full_cancel_state["inventory"] as Dictionary)["core:plank"] = 30
	var full_cancel := World.new(full_cancel_state)
	full_cancel.execute_construction_command(
		ConstructionCommandScript.place_wall_blueprint(Vector2i(22, 29))
	)
	full_cancel.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(22, 29))
	)
	full_cancel_state = full_cancel.export_state()
	(full_cancel_state["inventory"] as Dictionary)[FirstNightContent.WOOD_ID] = 80
	full_cancel = World.new(full_cancel_state)
	full_cancel.set_player_position(Content.cell_center(100, 100))
	var full_cancel_result := full_cancel.execute_construction_command(
		ConstructionCommandScript.cancel_blueprint(Vector2i(22, 29))
	)
	_expect(bool(full_cancel_result.get("success", false)), "a distant blueprint can still be cancelled")
	_expect(
		full_cancel.get_item_count(FirstNightContent.WOOD_ID) == 80
		and full_cancel.get_item_count("core:plank") == 0,
		"cancellation does not overflow a full backpack"
	)
	var cancellation_drop_amount := 0
	var cancellation_drop_near_blueprint := true
	for drop_value: Variant in full_cancel.get_world_drops():
		var drop := drop_value as Dictionary
		if String(drop.get("item_id", "")) != "core:plank":
			continue
		cancellation_drop_amount += int(drop.get("amount", 0))
		var drop_position_data := drop.get("position", []) as Array
		var drop_position := Vector2(float(drop_position_data[0]), float(drop_position_data[1]))
		if drop_position.distance_to(Content.cell_center(22, 29)) > 64.0:
			cancellation_drop_near_blueprint = false
	_expect(cancellation_drop_amount == 30, "overflow from cancellation remains as world loot")
	_expect(cancellation_drop_near_blueprint, "cancellation loot is dropped near the blueprint even when cancelled remotely")
	var remaining_blueprints: Array = simulation.get_blueprints()
	_expect(remaining_blueprints.size() == 1, "cancellation removes exactly one blueprint")
	if remaining_blueprints.size() == 1:
		_expect(
			(remaining_blueprints[0] as Dictionary).get("cell", []) == [23, 29],
			"cancellation preserves blueprints in other cells"
		)

	var missing_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.cancel_blueprint(Vector2i(22, 29))
	)
	_expect(
		String(missing_result.get("reason_id", "")) == "core:missing_blueprint",
		"cancelling an empty cell has a stable reason id"
	)
	_expect(
		not bool(missing_result.get("changed", true)),
		"cancelling an empty cell does not mutate state"
	)
	_expect(simulation.get_blueprints().size() == 1, "empty cancellation preserves state")

	var forged_cancel: Dictionary = (
		ConstructionCommandScript.cancel_blueprint(Vector2i(23, 29))
	)
	forged_cancel["actor_id"] = "core:forged_actor"
	var forged_cancel_result: Dictionary = simulation.execute_construction_command(forged_cancel)
	_expect(
		String(forged_cancel_result.get("reason_id", "")) == "core:unknown_actor",
		"blueprint execution rejects forged cancellation"
	)
	_expect(simulation.get_blueprints().size() == 1, "forged cancellation preserves state")

	_expect(
		simulation.is_navigation_cell_walkable(Vector2i(23, 29)),
		"a blueprint does not block NPC navigation"
	)
	var premature_completion: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.complete_blueprint(Vector2i(23, 29))
	)
	_expect(
		String(premature_completion.get("reason_id", ""))
		== "core:required_materials_missing",
		"construction cannot finish before materials are delivered"
	)
	_expect(bool(simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(23, 29))
	).get("success", false)), "second blueprint accepts its material")
	for work_step: int in range(24):
		var progress_result: Dictionary = simulation.execute_construction_command(
			ConstructionCommandScript.work_blueprint(Vector2i(23, 29))
		)
		_expect(
			String(progress_result.get("reason_id", ""))
			== "core:construction_work_progressed",
			"player work step %d advances the shared blueprint" % (work_step + 1)
		)
	_expect(
		int((simulation.get_blueprints()[0] as Dictionary).get(
			"work_progress_minutes",
			0
		)) == 24,
		"player work progress is stored on the blueprint"
	)
	var complete_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.work_blueprint(Vector2i(23, 29))
	)
	_expect(bool(complete_result.get("success", false)), "valid completion builds a structure")
	_expect(bool(complete_result.get("changed", false)), "valid completion reports a state change")
	_expect(
		String(complete_result.get("reason_id", "")) == "core:structure_completed",
		"valid completion has a stable reason id"
	)
	_expect(simulation.get_blueprints().is_empty(), "completion consumes its blueprint")
	var structures: Array = simulation.get_structures()
	_expect(structures.size() == 1, "completion creates exactly one structure")
	if structures.size() == 1:
		var structure: Dictionary = structures[0] as Dictionary
		_expect(structure.get("cell", []) == [23, 29], "completed structure preserves the cell")
		_expect(
			String(structure.get("building_id", "")) == "core:wood_wall",
			"completed structure preserves the building id"
		)
		_expect(
			String(structure.get("stage_id", "")) == "core:complete",
			"completed structure uses the complete stage"
		)
	_expect(
		not simulation.is_navigation_cell_walkable(Vector2i(23, 29)),
		"a completed wall blocks NPC navigation"
	)

	var occupied_placement: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.place_wall_blueprint(Vector2i(23, 29))
	)
	_expect(
		String(occupied_placement.get("reason_id", "")) == "core:occupied_cell",
		"a completed wall rejects a new blueprint in its cell"
	)

	var missing_completion: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.complete_blueprint(Vector2i(22, 29))
	)
	_expect(
		String(missing_completion.get("reason_id", "")) == "core:missing_blueprint",
		"completing an empty cell has a stable reason id"
	)

	var player_cell_command: Dictionary = (
		ConstructionCommandScript.place_wall_blueprint(Vector2i(24, 29))
	)
	_expect(
		bool(simulation.execute_construction_command(player_cell_command).get("success", false)),
		"a blueprint may be designated under an actor"
	)
	_expect(bool(simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(24, 29))
	).get("success", false)), "an actor-cell blueprint accepts its material")
	var actor_blocked_completion: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.work_blueprint(Vector2i(24, 29))
	)
	_expect(
		String(actor_blocked_completion.get("reason_id", "")) == "core:occupied_by_actor",
		"a wall cannot complete inside the player"
	)
	_expect(
		simulation.get_blueprints().size() == 1 and simulation.get_structures().size() == 1,
		"actor-blocked completion preserves construction state"
	)

	var completed_decoded: Variant = JSON.parse_string(JSON.stringify(simulation.export_state()))
	_expect(typeof(completed_decoded) == TYPE_DICTIONARY, "structure state survives JSON encoding")
	if typeof(completed_decoded) != TYPE_DICTIONARY:
		return
	var completed_restored: World = Simulation.new(completed_decoded as Dictionary)
	_expect(
		completed_restored.get_structures() == simulation.get_structures(),
		"completed structures survive save round trip"
	)
	_expect(
		not completed_restored.is_navigation_cell_walkable(Vector2i(23, 29)),
		"loaded structures rebuild NPC navigation blockers"
	)


func _test_v7_work_commitments_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 7
	var legacy_mira: Dictionary = (
		legacy_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	legacy_mira.erase("work_commitment")
	var migrated := Simulation.new(legacy_state)
	_expect(
		int(migrated.export_state().get("version", 0)) == Simulation.SAVE_VERSION,
		"v7 save migrates to current save version"
	)
	_expect(
		migrated.get_npc_work_commitment("core:first_neighbor").is_empty(),
		"v7 Mira gains an empty work commitment"
	)

	var corrupt_state: Dictionary = Simulation.create_new_state()
	var corrupt_mira: Dictionary = (
		corrupt_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	corrupt_mira["work_commitment"] = {
		"commitment_id": "core:help_build",
		"requester_id": "core:player",
		"target_cell": [22, 29],
		"work_cell": [40, 40],
		"building_id": "core:wood_wall",
		"required_minutes": 12,
		"resume_activity_id": "core:morning",
	}
	var normalized := Simulation.new(corrupt_state)
	_expect(
		normalized.get_npc_work_commitment("core:first_neighbor").is_empty(),
		"invalid non-adjacent work commitment is discarded"
	)


func _test_v8_memories_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 8
	var legacy_mira: Dictionary = (
		legacy_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	legacy_mira.erase("memories")
	var migrated := Simulation.new(legacy_state)
	_expect(
		int(migrated.export_state().get("version", 0)) == Simulation.SAVE_VERSION,
		"v8 save migrates to current save version"
	)
	_expect(
		migrated.get_npc_memories("core:first_neighbor").is_empty(),
		"v8 Mira gains an empty memory list"
	)

	var memory: Dictionary = NpcMemoryScript.create_first_shared_wall(
		2,
		7 * 60 + 15,
		Vector2i(22, 29)
	)
	var corrupt_state: Dictionary = Simulation.create_new_state()
	var corrupt_mira: Dictionary = (
		corrupt_state["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	var duplicate: Dictionary = memory.duplicate(true)
	var invalid: Dictionary = memory.duplicate(true)
	invalid["memory_id"] = "core:invalid_memory"
	invalid["target_cell"] = [999, 999]
	corrupt_mira["memories"] = [memory, duplicate, invalid, "broken"]
	var normalized := Simulation.new(corrupt_state)
	_expect(
		normalized.get_npc_memories("core:first_neighbor").size() == 1,
		"memory normalization rejects duplicates and corrupt entries"
	)


func _test_v9_blueprint_progress_is_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 9
	legacy_state["blueprints"] = [{
		"building_id": "core:wood_wall",
		"cell": [22, 29],
		"stage_id": "core:blueprint",
	}]
	var migrated := Simulation.new(legacy_state)
	_expect(
		int(migrated.export_state().get("version", 0)) == Simulation.SAVE_VERSION,
		"v9 save migrates to current save version"
	)
	var migrated_blueprints: Array = migrated.get_blueprints()
	_expect(migrated_blueprints.size() == 1, "v9 blueprint survives migration")
	if migrated_blueprints.size() == 1:
		var migrated_blueprint: Dictionary = migrated_blueprints[0] as Dictionary
		_expect(
			migrated_blueprint.get("required_materials", {}) == {"core:plank": 30},
			"v9 blueprint gains its catalog material requirement"
		)
		_expect(
			migrated_blueprint.get("delivered_materials", {}) == {"core:plank": 0},
			"v9 blueprint starts with no delivered materials"
		)
		_expect(
			int(migrated_blueprint.get("required_work_minutes", 0)) == 25,
			"v9 blueprint gains its catalog work requirement"
		)

	var corrupt_state: Dictionary = Simulation.create_new_state()
	corrupt_state["blueprints"] = [{
		"building_id": "core:wood_wall",
		"cell": [22, 29],
		"stage_id": "core:blueprint",
		"delivered_materials": {"core:plank": 99, "core:stone": 5},
		"work_progress_minutes": 99,
	}]
	var normalized_progress := Simulation.new(corrupt_state)
	var normalized_blueprint: Dictionary = (
		normalized_progress.get_blueprints()[0] as Dictionary
	)
	_expect(
		normalized_blueprint.get("delivered_materials", {}) == {"core:plank": 30},
		"blueprint delivery is clamped to its catalog requirement"
	)
	_expect(
		int(normalized_blueprint.get("work_progress_minutes", 0)) == 25,
		"blueprint work progress is clamped to its requirement"
	)


func _test_building_catalog() -> void:
	var catalog := BuildingCatalogScript.new()
	var wall: Dictionary = catalog.get_definition("core:wood_wall")
	_expect(not wall.is_empty(), "building catalog loads the wooden wall")
	_expect(
		catalog.get_material_cost("core:wood_wall") == {"core:plank": 30},
		"wooden wall reads its material cost from content"
	)
	_expect(
		catalog.get_work_minutes("core:wood_wall") == 25,
		"wooden wall reads its work duration from content"
	)
	wall["work_minutes"] = 999
	_expect(
		catalog.get_work_minutes("core:wood_wall") == 25,
		"building definition snapshots do not mutate the catalog"
	)
	_expect(
		catalog.get_definition("core:missing").is_empty(),
		"unknown building has no definition"
	)
	_expect(
		catalog.get_material_cost("core:wood_floor") == {"core:plank": 10}
		and catalog.get_work_minutes("core:wood_floor") == 4
		and catalog.is_floor("core:wood_floor"),
		"wood floor has its own layer, materials and work requirement"
	)
	_expect(
		catalog.get_material_cost("core:bed") == {"core:plank": 50}
		and catalog.get_work_minutes("core:bed") == 20,
		"bed has the authored materials and work requirement"
	)
	_expect(
		catalog.get_footprint_size("core:bed") == Vector2i(2, 1)
		and catalog.get_footprint_size("core:table") == Vector2i(2, 1)
		and catalog.get_footprint_size("core:workbench") == Vector2i(2, 1),
		"bed, table and workbench occupy their authored 2x1 footprints"
	)
	_expect(
		ResourceLoader.exists(catalog.get_texture_path("core:wood_wall"))
		and ResourceLoader.exists(catalog.get_texture_path("core:brick_wall"))
		and ResourceLoader.exists(catalog.get_texture_path("core:bed"))
		and ResourceLoader.exists(catalog.get_texture_path("core:wood_floor")),
		"authored building sprites are available to the building catalog"
	)


func _test_multi_cell_construction_footprints() -> void:
	var state := Simulation.create_new_state()
	state["player_position"] = [944.0, 976.0]
	(state["inventory"] as Dictionary)["core:plank"] = 100
	var simulation := Simulation.new(state)
	var table_cell := Vector2i(30, 30)
	var table_result := simulation.execute_construction_command(
		ConstructionCommandScript.place_blueprint(table_cell, "core:table")
	)
	_expect(bool(table_result.get("success", false)), "table blueprint fits on the map")
	var overlap_result := simulation.execute_construction_command(
		ConstructionCommandScript.place_blueprint(Vector2i(31, 30), "core:bed")
	)
	_expect(
		not bool(overlap_result.get("success", false))
		and String(overlap_result.get("reason_id", "")) == "core:occupied_cell",
		"2x1 blueprints cannot overlap through their secondary cell"
	)
	var delivery_result := simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(Vector2i(31, 30))
	)
	_expect(
		bool(delivery_result.get("success", false))
		and String(delivery_result.get("blueprint", {}).get("building_id", "")) == "core:table",
		"secondary-cell interaction resolves the 2x1 blueprint anchor"
	)
	var edge_result := ConstructionValidatorScript.validate_place_blueprint(
		ConstructionCommandScript.place_blueprint(Vector2i(127, 30), "core:bed")
	)
	_expect(
		not bool(edge_result.get("success", false))
		and String(edge_result.get("reason_id", "")) == "core:outside_map",
		"2x1 blueprint footprint cannot extend past the map edge"
	)
	for _minute: int in range(15):
		simulation.execute_construction_command(
			ConstructionCommandScript.work_blueprint(Vector2i(31, 30))
		)
	var completed_table := simulation.get_structures().filter(
		func(value: Variant) -> bool:
			return String((value as Dictionary).get("building_id", "")) == "core:table"
	)
	_expect(completed_table.size() == 1, "table can be completed from either footprint cell")
	var floor_result := simulation.execute_construction_command(
		ConstructionCommandScript.place_blueprint(Vector2i(31, 30), "core:wood_floor")
	)
	_expect(
		bool(floor_result.get("success", false)),
		"floor layer can coexist under the secondary cell of a 2x1 object"
	)
	var restored_with_floor_blueprint := Simulation.new(simulation.export_state())
	_expect(
		restored_with_floor_blueprint.get_blueprints().size() == 1,
		"different-layer blueprint survives save normalization under a structure"
	)
	_expect(
		not restored_with_floor_blueprint.is_navigation_cell_walkable(Vector2i(31, 30)),
		"the secondary cell of a 2x1 table blocks navigation"
	)


func _test_v19_wall_materials_migrate_to_planks() -> void:
	var legacy_state := Simulation.create_new_state()
	legacy_state["version"] = 19
	legacy_state["blueprints"] = [{
		"building_id": "core:wood_wall",
		"cell": [22, 29],
		"stage_id": "core:blueprint",
		"delivered_materials": {"core:wood": 1},
		"work_progress_minutes": 8,
	}]
	var migrated := Simulation.new(legacy_state)
	var blueprints: Array = migrated.get_blueprints()
	_expect(blueprints.size() == 1, "v19 wall blueprint survives the material update")
	if blueprints.is_empty():
		return
	var delivered: Dictionary = (blueprints[0] as Dictionary).get(
		"delivered_materials",
		{}
	)
	_expect(
		delivered == {"core:plank": 2},
		"legacy v19 wall deliveries keep their historical two-plank conversion"
	)
	_expect(
		int((blueprints[0] as Dictionary).get("work_progress_minutes", 0)) == 8,
		"legacy construction work is preserved during material migration"
	)
	legacy_state["version"] = 22
	var previous_version := Simulation.new(legacy_state)
	var previous_blueprints := previous_version.get_blueprints()
	_expect(previous_blueprints.size() == 1, "v22 wall blueprint survives the resource-layout version bump")
	if not previous_blueprints.is_empty():
		var previous_delivered := (previous_blueprints[0] as Dictionary).get("delivered_materials", {}) as Dictionary
		_expect(int(previous_delivered.get("core:plank", -1)) == 0, "v22 saves do not acquire historical wood-to-plank conversion during later save-version updates")


func _test_floor_layer_coexists_with_structures() -> void:
	var state := Simulation.create_new_state()
	(state["inventory"] as Dictionary)["core:plank"] = 100
	var simulation := Simulation.new(state)
	var cell := Vector2i(22, 29)
	var wall_result := simulation.execute_construction_command(
		ConstructionCommandScript.place_blueprint(cell, "core:wood_wall")
	)
	_expect(bool(wall_result.get("success", false)), "wall blueprint can be placed")
	_expect(bool(simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(cell)
	).get("success", false)), "wall materials can be delivered")
	for _minute: int in range(25):
		simulation.execute_construction_command(
			ConstructionCommandScript.work_blueprint(cell)
		)
	var floor_result := simulation.execute_construction_command(
		ConstructionCommandScript.place_blueprint(cell, "core:wood_floor")
	)
	_expect(bool(floor_result.get("success", false)), "floor can share a cell with a wall")
	_expect(bool(simulation.execute_construction_command(
		ConstructionCommandScript.deliver_blueprint_materials(cell)
	).get("success", false)), "floor materials can be delivered over a wall")
	for _minute: int in range(4):
		simulation.execute_construction_command(
			ConstructionCommandScript.work_blueprint(cell)
		)
	_expect(simulation.get_structures().size() == 2, "floor and wall persist as separate structures")
	var restored := Simulation.new(simulation.export_state())
	_expect(restored.get_structures().size() == 2, "floor and wall survive save normalization")
	_expect(
		not restored.is_navigation_cell_walkable(cell),
		"floor layer does not remove the wall navigation blocker"
	)


func _test_crafting_catalog_and_project_lifecycle() -> void:
	var catalog := CraftingCatalogScript.new()
	var recipes: Array[Dictionary] = catalog.recipes_for_station("core:workbench")
	_expect(recipes.size() == 2, "workbench catalog exposes two starter recipes")
	_expect(
		catalog.get_inputs("core:saw_planks") == {"core:wood": 5},
		"plank recipe reads its input from content"
	)
	_expect(
		catalog.get_outputs("core:saw_planks") == {"core:plank": 10},
		"plank recipe reads its output from content"
	)
	_expect(
		catalog.get_work_minutes("core:saw_planks") == 8,
		"plank recipe keeps its existing eight-minute work cost"
	)

	var initial_state: Dictionary = Simulation.create_new_state()
	(initial_state["inventory"] as Dictionary)["core:wood"] = 8
	(initial_state["structures"] as Array).append({
		"building_id": "core:workbench",
		"cell": [22, 29],
		"stage_id": "core:complete",
	})
	var simulation := World.new(initial_state)
	var start_result: Dictionary = simulation.execute_crafting_command(
		CraftingCommandScript.start_project(Vector2i(22, 29), "core:saw_planks")
	)
	_expect(bool(start_result.get("success", false)), "player starts a workbench project")
	_expect(
		int(simulation.get_inventory().get("core:wood", 0)) == 3,
		"starting a project reserves five logs"
	)
	for _minute: int in range(3):
		simulation.execute_crafting_command(
			CraftingCommandScript.work_project(Vector2i(22, 29))
		)
	var restored := World.new(simulation.export_state())
	var restored_projects: Array = restored.get_crafting_projects()
	_expect(restored_projects.size() == 1, "unfinished crafting survives save round trip")
	if restored_projects.size() == 1:
		_expect(
			int((restored_projects[0] as Dictionary).get("work_progress_minutes", 0)) == 3,
			"crafting progress survives save round trip"
		)
	var completion: Dictionary = {}
	for _minute: int in range(5):
		completion = restored.execute_crafting_command(
			CraftingCommandScript.work_project(Vector2i(22, 29))
		)
	_expect(
		String(completion.get("reason_id", "")) == "core:crafting_completed",
		"final work minute completes the project"
	)
	_expect(restored.get_crafting_projects().is_empty(), "completion clears the station project")
	var plank_amount: int = 0
	for drop_value: Variant in restored.get_world_drops():
		var drop := drop_value as Dictionary
		if String(drop.get("item_id", "")) == "core:plank":
			plank_amount += int(drop.get("amount", 0))
	_expect(plank_amount == 10, "completed recipe drops ten planks beside the workbench")


func _test_crafting_station_footprint_is_canonical() -> void:
	var initial_state := Simulation.create_new_state()
	(initial_state["inventory"] as Dictionary)["core:wood"] = 10
	(initial_state["structures"] as Array).append({
		"building_id": "core:workbench",
		"cell": [22, 29],
		"stage_id": "core:complete",
	})
	var simulation := World.new(initial_state)
	var started := simulation.execute_crafting_command(
		CraftingCommandScript.start_project(Vector2i(23, 29), "core:saw_planks")
	)
	_expect(bool(started.get("success", false)), "workbench project starts from its secondary footprint cell")
	_expect(
		(simulation.get_crafting_projects()[0] as Dictionary).get("cell", []) == [22, 29],
		"crafting project is stored at the workbench anchor"
	)
	var duplicate := simulation.execute_crafting_command(
		CraftingCommandScript.start_project(Vector2i(22, 29), "core:saw_planks")
	)
	_expect(
		not bool(duplicate.get("success", false))
		and String(duplicate.get("reason_id", "")) == "core:station_busy",
		"clicking another footprint cell cannot start a parallel workbench project"
	)
	_expect(
		int(simulation.get_inventory().get("core:wood", 0)) == 5,
		"duplicate station command cannot consume a second recipe input"
	)
	var legacy_state := simulation.export_state()
	(legacy_state["crafting_projects"] as Array).append({
		"cell": [23, 29],
		"recipe_id": "core:saw_planks",
		"reserved_inputs": {"core:wood": 5},
		"required_work_minutes": 8,
		"work_progress_minutes": 0,
	})
	var recovered := Simulation.new(legacy_state)
	_expect(recovered.get_crafting_projects().size() == 1, "save normalization merges duplicate footprint station keys")
	var returned_duplicate_inputs := 0
	for drop_value: Variant in recovered.get_world_drops():
		var drop := drop_value as Dictionary
		if String(drop.get("source_id", "")) == "core:crafting_recovery":
			returned_duplicate_inputs += int(drop.get("amount", 0))
	_expect(returned_duplicate_inputs == 5, "normalizing a duplicate legacy project returns its reserved materials")


func _test_construction_cursor_requires_build_mode() -> void:
	var cursor: ConstructionCursor = ConstructionCursorScript.new()
	root.add_child(cursor)
	var selected_cells: Array[Vector2i] = []
	cursor.cell_selected.connect(func(cell: Vector2i) -> void:
		selected_cells.append(cell)
	)

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true

	_expect(not cursor.visible, "construction cursor starts hidden")
	_expect(not cursor.is_processing(), "construction cursor starts without processing")
	cursor._unhandled_input(left_click)
	_expect(selected_cells.is_empty(), "disabled construction mode ignores left clicks")

	cursor.set_build_mode_active(true)
	_expect(cursor.visible, "enabled construction mode shows the cursor")
	_expect(cursor.is_processing(), "enabled construction mode updates the cursor")
	cursor._unhandled_input(left_click)
	_expect(selected_cells.size() == 1, "enabled construction mode accepts one left click")

	cursor.set_build_mode_active(false)
	cursor._unhandled_input(left_click)
	_expect(selected_cells.size() == 1, "disabled construction mode stops accepting clicks")

	root.remove_child(cursor)
	cursor.free()


func _test_lab_rejects_unknown_scenario() -> void:
	var result: Dictionary = LabScenarios.build(&"missing_scenario")
	_expect(not bool(result.get("success", true)), "lab rejects an unknown scenario")
	_expect(not result.has("simulation"), "unknown lab scenario creates no simulation")


func _test_lab_fresh_start() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.FRESH_START)
	_expect(bool(result.get("success", false)), "fresh lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	_expect(simulation.export_state() == Simulation.new().export_state(), "fresh lab scenario matches a new game")
	_expect(simulation.get_day() == 1, "fresh lab scenario starts on day 1")
	_expect(simulation.get_time_text() == "11:00", "fresh lab scenario starts at 11:00")
	_expect(
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 0
			and simulation.get_item_count(FirstNightContent.STONE_ID) == 0,
		"fresh lab scenario has no collected starter resources"
	)
	_expect(simulation.get_object_stage("repair") == 0, "fresh lab scenario has no repair progress")
	_expect(simulation.get_object_stage("campfire") == 0, "fresh lab scenario has no campfire progress")
	_expect(not simulation.is_npc_visible("core:first_neighbor"), "fresh lab scenario keeps Mira hidden")


func _test_lab_workbench_crafting() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.WORKBENCH_CRAFTING)
	_expect(bool(result.get("success", false)), "workbench lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	_expect(
		int(simulation.get_inventory().get("core:wood", 0)) == 5,
		"workbench lab scenario supplies five logs"
	)
	var structures: Array = simulation.get_structures()
	_expect(
		structures.size() == 1
		and String((structures[0] as Dictionary).get("building_id", "")) == "core:workbench",
		"workbench lab scenario contains one completed workbench"
	)


func _test_lab_surface_boulders() -> void:
	var result: Dictionary = LabScenarios.build(
		LabScenarios.SURFACE_BOULDERS
	)
	_expect(bool(result.get("success", false)), "boulder lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result[
		"simulation"
	] as World
	var boulders: Array[Dictionary] = simulation.get_surface_boulders()
	_expect(
		boulders.size() >= ResourceNodeCatalogScript.BOULDER_COUNT_MIN and boulders.size() <= ResourceNodeCatalogScript.BOULDER_COUNT_MAX,
		"boulder lab scenario retains generated world resources"
	)
	if boulders.is_empty():
		return
	var target: Vector2 = boulders[0].get(
		"position",
		Vector2.ZERO
	) as Vector2
	_expect(
		simulation.get_player_position().distance_to(target) <= 68.0,
		"boulder lab scenario places the player within work range"
	)


func _test_lab_prepared_evening() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.PREPARED_EVENING)
	_expect(bool(result.get("success", false)), "prepared evening lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	var flags: Dictionary = simulation.get_flags()
	_expect(simulation.get_day() == 1, "prepared evening stays on day 1")
	_expect(simulation.get_time_text() == "17:50", "prepared evening starts ten minutes before sleep")
	_expect(bool(flags.get("house_inspected", false)), "prepared evening inspected the house")
	_expect(bool(flags.get("tools_found", false)), "prepared evening found the tools")
	_expect(simulation.get_object_stage("repair") == 3, "prepared evening completed the room")
	_expect(simulation.get_object_stage("campfire") == 2, "prepared evening lit the campfire")
	_expect(bool(flags.get("bed_ready", false)), "prepared evening prepared the bed")
	_expect(bool(flags.get("water_boiled", false)), "prepared evening boiled water")
	_expect(bool(flags.get("dusk_warned", false)), "debug time uses the real dusk transition")
	_expect(not bool(flags.get("first_night_complete", false)), "prepared evening has not slept")
	_expect(not simulation.is_npc_visible("core:first_neighbor"), "prepared evening keeps Mira hidden")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 5, "prepared evening retains five logs because starter bedroll uses no wood")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 4, "prepared evening retains four stone after the board-only roof cost")
	_expect(simulation.get_item_count(FirstNightContent.RAW_WATER_ID) == 0, "prepared evening used raw water")
	_expect(simulation.get_item_count(FirstNightContent.BOILED_WATER_ID) == 1, "prepared evening has safe water")
	_expect(simulation.get_item_count(FirstNightContent.FOOD_ID) == 2, "prepared evening has two food")
	var bed_position: Vector2 = simulation.get_interaction_target_position("core:bed_site")
	_expect(
		simulation.get_player_position().distance_to(bed_position) <= FirstNightContent.INTERACTION_RANGE,
		"prepared evening places the player by the bed"
	)
	_expect(_all_lab_steps_succeeded(result), "prepared evening completes every canonical step")
	_expect(
		_lab_interaction_steps_have_message_keys(result),
		"prepared evening keeps localization descriptors for diagnostics"
	)


func _test_lab_morning_with_mira() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	_expect(bool(result.get("success", false)), "morning lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	var flags: Dictionary = simulation.get_flags()
	var npcs: Dictionary = simulation.get_npcs()
	var mira: Dictionary = npcs.get("core:first_neighbor", {}) as Dictionary
	_expect(simulation.get_day() == 2, "morning lab scenario starts on day 2")
	_expect(simulation.get_time_text() == "07:00", "morning lab scenario starts at 07:00")
	_expect(bool(flags.get("first_night_complete", false)), "morning lab scenario completed the first night")
	_expect(simulation.is_npc_visible("core:first_neighbor"), "morning lab scenario activates Mira")
	_expect(not bool(mira.get("known", true)), "Mira is still unknown in the morning scenario")
	_expect(int(mira.get("talk_count", -1)) == 0, "Mira has not been greeted in the morning scenario")
	_expect(
		simulation.get_current_objective_key() == "first_night.objective.meet_neighbor",
		"morning lab objective points to the traveler"
	)
	_expect(
		not simulation.get_npc_position(
			"core:first_neighbor",
			Vector2.ZERO
		).is_equal_approx(simulation.get_player_position()),
		"morning lab scenario keeps Mira outside the player"
	)
	_expect(
		simulation.export_state().get("outcomes", []) == [
			Simulation.OUTCOME_DRY_ROOM_ID,
			Simulation.OUTCOME_RESIDUAL_WARMTH_ID,
			Simulation.OUTCOME_SAFE_WATER_ID,
			Simulation.OUTCOME_LIGHT_SUPPER_ID,
		],
		"morning lab scenario preserves the real sleep outcomes"
	)
	_expect(simulation.get_item_count(FirstNightContent.FOOD_ID) == 1, "morning lab scenario consumed one food")
	_expect(_all_lab_steps_succeeded(result), "morning lab completes every canonical step")
	_expect(
		_lab_interaction_steps_have_message_keys(result),
		"morning lab keeps localization descriptors for diagnostics"
	)


func _test_lab_mira_resting() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.MIRA_RESTING)
	_expect(bool(result.get("success", false)), "resting Mira lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	var needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(simulation.get_day() == 2, "resting Mira scenario remains on day 2")
	_expect(simulation.get_time_text() == "22:00", "resting Mira scenario starts at 22:00")
	_expect(
		simulation.get_npc_activity_id("core:first_neighbor") == NpcAutonomyScript.ACTIVITY_RESTING,
		"resting Mira scenario reaches the real resting activity"
	)
	_expect(simulation.get_npc_personal_food("core:first_neighbor") == 0, "resting Mira scenario consumed two travel portions")
	_expect(float(needs.get("hunger", 100.0)) >= 0.0, "resting Mira scenario exposes normalized hunger")


func _test_lab_mira_after_shared_wall() -> void:
	var result: Dictionary = LabScenarios.build(
		LabScenarios.MIRA_AFTER_SHARED_WALL
	)
	_expect(bool(result.get("success", false)), "shared-wall memory lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: World = result["simulation"] as World
	_expect(simulation.get_day() == 2, "shared-wall scenario remains on day 2")
	_expect(simulation.get_time_text() == "07:35", "shared-wall scenario starts after the longer wall build")
	_expect(simulation.get_structures().size() == 1, "shared-wall scenario contains the completed wall")
	_expect(
		simulation.get_npc_memories("core:first_neighbor").size() == 1,
		"shared-wall scenario contains the confirmed memory"
	)
	_expect(
		not bool(
			(simulation.get_npc_memories("core:first_neighbor")[0] as Dictionary).get(
				"acknowledged",
				true
			)
		),
		"shared-wall scenario keeps the context line ready"
	)
	_expect(
		simulation.get_player_position().distance_to(
			simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
		) <= FirstNightContent.INTERACTION_RANGE,
		"shared-wall scenario places the player close enough to talk"
	)
	_expect(_all_lab_steps_succeeded(result), "shared-wall scenario completes every canonical step")


func _test_lab_scenarios_are_deterministic() -> void:
	var seen_ids: Dictionary = {}
	for definition: Dictionary in LabScenarios.definitions():
		var scenario_id := StringName(definition.get("id", &""))
		_expect(not seen_ids.has(scenario_id), "lab scenario ids are unique: %s" % scenario_id)
		seen_ids[scenario_id] = true
		var first: Dictionary = LabScenarios.build(scenario_id)
		var second: Dictionary = LabScenarios.build(scenario_id)
		_expect(bool(first.get("success", false)), "first deterministic lab build succeeds: %s" % scenario_id)
		_expect(bool(second.get("success", false)), "second deterministic lab build succeeds: %s" % scenario_id)
		if bool(first.get("success", false)) and bool(second.get("success", false)):
			_expect(first.get("state", {}) == second.get("state", {}), "lab scenario is deterministic: %s" % scenario_id)


func _test_lab_rebuild_discards_previous_changes() -> void:
	var first: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	if not bool(first.get("success", false)):
		_expect(false, "first morning build succeeds before reset test")
		return
	var first_simulation: World = first["simulation"] as World
	var talk_result: Dictionary = _interact_near(first_simulation, "core:first_neighbor")
	_expect(bool(talk_result.get("success", false)), "reset test can change the first scenario instance")

	var rebuilt: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	_expect(bool(rebuilt.get("success", false)), "morning scenario rebuild succeeds")
	if not bool(rebuilt.get("success", false)):
		return
	var rebuilt_simulation: World = rebuilt["simulation"] as World
	var rebuilt_mira: Dictionary = rebuilt_simulation.get_npcs().get(
		"core:first_neighbor",
		{}
	) as Dictionary
	_expect(not bool(rebuilt_mira.get("known", true)), "scenario rebuild discards Mira acquaintance")
	_expect(int(rebuilt_mira.get("talk_count", -1)) == 0, "scenario rebuild restores Mira talk count")


func _test_session_installs_lab_state_without_aliasing_or_save() -> void:
	_cleanup_save_files(TEST_LAB_SAVE_PATH)
	var build_result: Dictionary = LabScenarios.build(LabScenarios.PREPARED_EVENING)
	if not bool(build_result.get("success", false)):
		_expect(false, "lab session test scenario builds")
		return
	var source_state: Dictionary = (build_result.get("state", {}) as Dictionary).duplicate(true)
	var lab_session = SessionNodeScript.new()
	lab_session._save_store = SaveStore.new(TEST_LAB_SAVE_PATH)
	lab_session._start_new_simulation()
	var published_times: Array[int] = []
	lab_session.time_changed.connect(
		func() -> void:
			published_times.append(lab_session.get_minute_of_day())
	)
	_expect(lab_session.set_mechanics_lab_active(true), "test session enters mechanics lab mode")
	_expect(
		lab_session.apply_debug_state(source_state, "test evening", true),
		"test session installs a lab state"
	)
	_expect(lab_session.is_paused(), "installed lab scenario starts paused")
	_expect(lab_session.get_day() == 1, "installed lab scenario reaches the test session")

	(source_state["flags"] as Dictionary)["bed_ready"] = false
	_expect(
		bool(lab_session.get_flags().get("bed_ready", false)),
		"installed lab state does not alias the source dictionary"
	)
	_expect(not lab_session.save_game(false), "lab mode rejects ordinary saves")
	_expect(not FileAccess.file_exists(TEST_LAB_SAVE_PATH), "lab mode creates no ordinary save file")
	_expect(lab_session.advance_debug_minutes(10), "lab session advances real simulation time")
	_expect(lab_session.get_time_text() == "18:00", "lab time control reaches the evening")
	var time_events_before_sleep: int = published_times.size()
	var sleep_result: Dictionary = lab_session.execute_interaction("core:bed_site")
	_expect(bool(sleep_result.get("success", false)), "lab session can complete the real sleep command")
	_expect(lab_session.get_day() == 2, "lab sleep reaches day 2")
	_expect(
		published_times.size() == time_events_before_sleep + 1
		and published_times[-1] == 7 * 60,
		"sleep publishes the morning time for visual systems"
	)
	_expect(
		not FileAccess.file_exists(TEST_LAB_SAVE_PATH),
		"lab auto-save event creates no ordinary save file"
	)
	_expect(lab_session.advance_debug_minutes(10), "lab time can advance after the current slice")
	_expect(lab_session.get_time_text() == "07:10", "lab time control advances morning by ten minutes")

	lab_session.set_mechanics_lab_active(false)
	lab_session.free()
	_cleanup_save_files(TEST_LAB_SAVE_PATH)


func _all_lab_steps_succeeded(build_result: Dictionary) -> bool:
	var steps: Array = build_result.get("steps", []) as Array
	if steps.is_empty():
		return false
	for step_variant: Variant in steps:
		var step: Dictionary = step_variant as Dictionary
		if not bool(step.get("success", false)):
			return false
	return true


func _lab_interaction_steps_have_message_keys(build_result: Dictionary) -> bool:
	var steps: Array = build_result.get("steps", []) as Array
	for step_variant: Variant in steps:
		var step: Dictionary = step_variant as Dictionary
		if String(step.get("kind", "")) != "interaction":
			continue
		if String(step.get("message_key", "")).is_empty():
			return false
		if typeof(step.get("message_args", {})) != TYPE_DICTIONARY:
			return false
	return true


func _complete_first_night_for_test(simulation: World) -> void:
	_interact_near(simulation, "old_tools")
	for wood_id: String in ["wood_north", "wood_west", "wood_east"]:
		_interact_near(simulation, wood_id)
	for stone_id: String in ["stone_south", "stone_east"]:
		_interact_near(simulation, stone_id)
	_interact_near(simulation, "berry_bush")
	_interact_near(simulation, "shore_water")
	# These narrow NPC fixtures receive roof stock directly; the ordinary route
	# above constructs a real workbench, crafts the boards, and physically picks them up.
	if simulation.get_storage_zones().is_empty():
		for placement: Dictionary in simulation.get_inventory_placements():
			if String(placement.get("item_id", "")) in ["core:axe", "core:pickaxe"]:
				var instance_id := String(placement.get("instance_id", ""))
				simulation._clear_hotbar_instance(instance_id)
				simulation._remove_item_instance(instance_id)
	var roof_fixture := simulation.try_pickup_item("core:plank", int(simulation.content.get_cost("repair_stage_1").get("core:plank", 0)))
	_expect(bool(roof_fixture.get("success", false)), "narrow NPC first-night fixture supplies its explicit roof-board stock")
	for _step: int in range(3):
		_interact_near(simulation, "repair_room")
	for _step: int in range(3):
		_interact_near(simulation, "campfire_site")
	_interact_near(simulation, "bed_site")
	simulation.advance_minutes(simulation.EVENING_MINUTE - simulation.get_minute_of_day())
	_interact_near(simulation, "bed_site")


func _interact_near(simulation: World, target_id: String) -> Dictionary:
	var missing_position := Vector2(-999999.0, -999999.0)
	var target_position: Vector2 = simulation.get_interaction_target_position(
		target_id,
		missing_position
	)
	_expect(
		not target_position.is_equal_approx(missing_position),
		"test target exists: %s" % target_id
	)
	simulation.set_player_position(target_position)
	if simulation.get_resource_work_required(target_id) > 0:
		var work_result: Dictionary = _work_resource_to_completion(
			simulation,
			target_id
		)
		if not bool(work_result.get("success", false)):
			return work_result
		for drop_id_variant: Variant in (
			work_result.get("created_drop_ids", []) as Array
		):
			var pickup_result: Dictionary = (
				simulation.try_pickup_world_drop(
					String(drop_id_variant)
				)
			)
			if not bool(pickup_result.get("success", false)):
				return pickup_result
		return work_result
	return simulation.execute_interaction(target_id)


func _work_resource_to_completion(
	simulation: World,
	target_id: String
) -> Dictionary:
	_equip_test_resource_tool(simulation, target_id)
	var target_position: Vector2 = (
		simulation.get_interaction_target_position(target_id)
	)
	simulation.set_player_position(target_position)
	var required: int = simulation.get_resource_work_required(target_id)
	var progress: int = simulation.get_resource_work_progress(target_id)
	var result: Dictionary = {}

	for _minute: int in range(maxi(0, required - progress)):
		result = simulation.execute_resource_work(
			simulation.PLAYER_ACTOR_ID,
			target_id
		)

	return result


func _equip_test_resource_tool(
	simulation: World,
	target_id: String
) -> void:
	var required_item_id := simulation.get_resource_required_tool_item_id(
		target_id
	)
	if required_item_id.is_empty():
		return
	var storage_zones := simulation.get_storage_zones()
	if not storage_zones.is_empty():
		var equipment_ids: Array[String] = [
			"core:axe", "core:pickaxe", "core:hoe", "core:bucket",
		]
		for placement: Dictionary in simulation.get_inventory_placements():
			var item_id := String(placement.get("item_id", ""))
			if not equipment_ids.has(item_id) or item_id == required_item_id:
				continue
			var stored_back := false
			for zone: Dictionary in storage_zones:
				for cell_value: Variant in zone.get("cells", []):
					var cell_data := cell_value as Array
					if cell_data.size() != 2:
						continue
					var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
					simulation.set_player_position(_cell_center(cell))
					var stored := simulation.transfer_inventory_stack_to_storage(
						cell,
						item_id,
						int(placement.get("stack_index", 0))
					)
					if bool(stored.get("success", false)):
						stored_back = true
						break
				if stored_back:
					break
		for stored_item: Dictionary in simulation.get_storage_items():
			if String(stored_item.get("item_id", "")) != required_item_id:
				continue
			var cell_data := stored_item.get("cell", []) as Array
			if cell_data.size() != 2:
				continue
			var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
			simulation.set_player_position(_cell_center(cell))
			var taken := simulation.transfer_storage_stack_to_inventory(
				cell,
				String(stored_item.get("placement_id", ""))
			)
			if bool(taken.get("success", false)):
				break
	var instance_id := ""
	for placement: Dictionary in simulation.get_inventory_placements():
		if String(placement.get("item_id", "")) == required_item_id:
			instance_id = String(placement.get("instance_id", ""))
			break
	if instance_id.is_empty():
		instance_id = _add_test_tool(simulation, required_item_id, false)
	var active := simulation.get_active_item_instance()
	if (
		String(active.get("item_id", "")) == required_item_id
		and String(active.get("instance_id", "")) == instance_id
	):
		return
	var assigned := simulation.assign_hotbar_slot(0, instance_id)
	_expect(bool(assigned.get("success", false)), "test fixture equips the required tool")
	simulation.select_hotbar_slot(0)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * Content.CELL_SIZE,
		(float(cell.y) + 0.5) * Content.CELL_SIZE
	)


func _add_test_tool(
	simulation: World,
	item_id: String,
	assign_hotbar: bool,
	slot_index: int = 0
) -> String:
	var created: Array[String] = simulation._create_item_instances(
		item_id,
		1,
		"inventory"
	)
	if created.is_empty():
		return ""
	var packed := InventoryPacker.pack_with_layout(
		simulation.get_inventory(),
		simulation.content,
		simulation.get_inventory_layout(),
		4,
		4
	)
	simulation.state["inventory_layout"] = packed.get("layout", [])
	if assign_hotbar:
		simulation.assign_hotbar_slot(slot_index, created[0])
		simulation.select_hotbar_slot(slot_index)
	return created[0]


func _cleanup_test_save_files() -> void:
	_cleanup_save_files(TEST_SAVE_PATH)


func _cleanup_save_files(base_path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = base_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % description)
