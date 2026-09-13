extends SceneTree

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const AppearanceCatalog := preload("res://src/characters/character_appearance.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const SessionNodeScript := preload("res://src/autoload/session.gd")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const LocalGridPathfinderScript := preload("res://src/simulation/local_grid_pathfinder.gd")
const FirstNightNavigationScript := preload("res://src/simulation/first_night_navigation.gd")
const NpcAutonomyScript := preload("res://src/simulation/npc_autonomy.gd")
const ConstructionCommandScript := preload("res://src/construction/construction_command.gd")
const ConstructionValidatorScript := preload("res://src/construction/construction_validator.gd")
const ConstructionCursorScript := preload("res://src/construction/construction_cursor.gd")
const BuildingCatalogScript := preload("res://src/construction/building_catalog.gd")
const NpcWorkRequestScript := preload("res://src/simulation/npc_work_request.gd")
const NpcWorkRequestValidatorScript := preload(
	"res://src/simulation/npc_work_request_validator.gd"
)
const NpcMemoryScript := preload("res://src/simulation/npc_memory.gd")
const TEST_SAVE_PATH: String = "user://first_night_save_store_test.json"
const TEST_LAB_SAVE_PATH: String = "user://mechanics_lab_session_test.json"
const LOCALIZATION_PATH: String = "res://localization/core.csv"
const LOCALIZATION_SOURCE_PATHS: Array[String] = [
	"res://content/core/character_parts.json",
	"res://content/core/buildings.json",
	"res://content/core/first_night_objects.json",
	"res://content/core/first_night_progression.json",
	"res://content/core/items.json",
	"res://content/core/npcs.json",
	"res://src/autoload/session.gd",
	"res://src/characters/npc_catalog.gd",
	"res://src/content/first_night_content.gd",
	"res://src/save/first_night_save_store.gd",
	"res://src/simulation/first_night_simulation.gd",
	"res://src/simulation/npc_autonomy.gd",
	"res://src/ui/first_night_hud.gd",
	"res://src/world/first_night_world.gd",
]

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	TranslationServer.set_locale("ru")
	_test_localization_catalog_and_resolver()
	_test_complete_first_night()
	_test_serialization_round_trip()
	_test_duplicate_collection_is_rejected()
	_test_command_boundary_rejects_forged_commands()
	_test_command_boundary_enforces_range_and_resolves_kind()
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
	_test_character_appearance_generation()
	_test_first_neighbor_arrives_and_talks()
	_test_grid_pathfinder_avoids_static_obstacles()
	_test_mira_needs_schedule_and_personal_food()
	_test_mira_autonomy_is_deterministic_and_serialized()
	_test_npc_work_request_contract_and_refusals()
	_test_mira_completes_construction_commitment()
	_test_missing_blueprint_releases_commitment()
	_test_shared_wall_creates_memory_and_relationship()
	_test_shared_wall_context_line_is_consumed_once()
	_test_construction_command_payload()
	_test_building_catalog()
	_test_construction_command_validation()
	_test_blueprint_command_execution()
	_test_construction_cursor_requires_build_mode()
	_test_lab_rejects_unknown_scenario()
	_test_lab_fresh_start()
	_test_lab_prepared_evening()
	_test_lab_morning_with_mira()
	_test_lab_mira_resting()
	_test_lab_mira_after_shared_wall()
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
		"\"((?:item|object|character_part|npc|dialogue|ui|first_night|interaction|system|save)\\.[a-z0-9_.]+)\""
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
	var simulation: FirstNightSimulation = Simulation.new()
	_expect(simulation.get_day() == 1, "new game starts on day 1")
	_expect(simulation.get_time_text() == "11:00", "new game starts at 11:00")

	_interact_near(simulation, "old_tools")
	for wood_id: String in ["wood_north", "wood_west", "wood_east"]:
		_interact_near(simulation, wood_id)
	for stone_id: String in ["stone_south", "stone_east"]:
		_interact_near(simulation, stone_id)
	_interact_near(simulation, "berry_bush")
	_interact_near(simulation, "shore_water")

	_expect(simulation.get_inventory_weight() <= simulation.MAX_CARRY_WEIGHT, "collected resources fit the weight limit")
	for _step: int in range(3):
		_interact_near(simulation, "repair_room")
	_expect(simulation.get_object_stage("repair") == 3, "room repair reaches stage 3")

	for _step: int in range(3):
		_interact_near(simulation, "campfire_site")
	_expect(simulation.get_object_stage("campfire") == 2, "campfire is lit")
	_expect(bool(simulation.get_flags()["water_boiled"]), "water is boiled")

	_interact_near(simulation, "bed_site")
	_expect(bool(simulation.get_flags()["bed_ready"]), "temporary bed is ready")
	simulation.advance_minutes(simulation.EVENING_MINUTE - simulation.get_minute_of_day())
	var sleep_result: Dictionary = _interact_near(simulation, "bed_site")
	_expect(bool(sleep_result["success"]), "sleep command succeeds after 18:00")
	_expect(not sleep_result.has("message"), "sleep result contains no localized copy")
	var localized_morning: String = Localized.resolve(
		String(sleep_result.get("message_key", "")),
		sleep_result.get("message_args", {}) as Dictionary
	)
	_expect(localized_morning.contains("сухая комната"), "morning summary localizes outcome ids")
	_expect(not localized_morning.contains("core:"), "morning summary exposes no technical ids")
	_expect(simulation.get_day() == 2, "sleep advances to day 2")
	_expect(simulation.get_time_text() == "07:00", "sleep advances to 07:00")
	_expect(bool(simulation.get_flags()["first_night_complete"]), "first night is marked complete")
	_expect(simulation.is_npc_visible("core:first_neighbor"), "first neighbor appears after the first night")
	_expect(
		not simulation.get_npc_position(
			"core:first_neighbor",
			Vector2.ZERO
		).is_equal_approx(simulation.get_player_position()),
		"first neighbor does not appear inside the player"
	)


func _test_serialization_round_trip() -> void:
	var original: FirstNightSimulation = Simulation.new()
	_interact_near(original, "old_tools")
	_interact_near(original, "wood_north")
	original.set_player_position(Vector2(321.5, 654.25))
	original.advance_minutes(37)

	var encoded: String = JSON.stringify(original.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "serialized state parses as a dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
	_expect(restored.get_time_text() == original.get_time_text(), "time survives serialization")
	_expect(restored.get_player_position().is_equal_approx(original.get_player_position()), "position survives serialization")
	_expect(restored.get_item_count(FirstNightContent.WOOD_ID) == 3, "inventory survives serialization")
	_expect(bool(restored.get_flags()["tools_found"]), "flags survive serialization")


func _test_duplicate_collection_is_rejected() -> void:
	var simulation: FirstNightSimulation = Simulation.new()
	var first: Dictionary = _interact_near(simulation, "wood_north")
	var second: Dictionary = _interact_near(simulation, "wood_north")
	_expect(bool(first["success"]), "first resource collection succeeds")
	_expect(not bool(second["success"]), "duplicate resource collection is rejected")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 3, "duplicate collection does not create resources")


func _test_command_boundary_rejects_forged_commands() -> void:
	var simulation: FirstNightSimulation = Simulation.new()
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
	var simulation: FirstNightSimulation = Simulation.new()
	var distant_result: Dictionary = simulation.execute_interaction("wood_north")
	_expect(not bool(distant_result["success"]), "simulation rejects an out-of-range target")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "out-of-range command changes no inventory")

	simulation.set_player_position(simulation.get_interaction_target_position("stone_south"))
	var stone_result: Dictionary = simulation.execute_command(
		simulation.PLAYER_ACTOR_ID,
		"stone_south",
		simulation.ACTION_INTERACT
	)
	_expect(bool(stone_result["success"]), "universal interaction succeeds near a real target")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 3, "target catalog resolves resource kind")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 0, "caller cannot spoof resource kind")


func _test_query_snapshots_are_isolated() -> void:
	var simulation: FirstNightSimulation = Simulation.new()
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

	var restored: FirstNightSimulation = Simulation.new(corrupt)
	_expect(restored.get_day() == 1, "invalid negative day is clamped")
	_expect(restored.get_minute_of_day() == restored.LATEST_MINUTE, "late time is clamped")
	_expect(restored.get_inventory_weight() == 0.0, "invalid inventory falls back to empty")
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
	var normalized_numbers: FirstNightSimulation = Simulation.new(invalid_numbers)
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
	var normalized_npc: FirstNightSimulation = Simulation.new(invalid_npc_state)
	var normalized_needs: Dictionary = normalized_npc.get_npc_needs("core:first_neighbor")
	_expect(float(normalized_needs["hunger"]) == 0.0, "NPC hunger is clamped")
	_expect(float(normalized_needs["energy"]) == 82.0, "invalid NPC energy uses default")
	_expect(
		normalized_npc.get_npc_activity_id("core:first_neighbor") == &"core:arriving",
		"invalid NPC activity uses default"
	)
	_expect(
		normalized_npc.get_npc_target_cell("core:first_neighbor") == Vector2i(47, 0),
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

	var simulation: FirstNightSimulation = Simulation.new(raw_state)
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

	var simulation: FirstNightSimulation = Simulation.new(legacy_state)
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

	var simulation: FirstNightSimulation = Simulation.new(legacy_state)
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
	_expect(int(migrated_state.get("version", 0)) == 10, "v3 save migrates to save version 10")
	_expect(migrated_state.get("outcomes", []) == expected, "v3 outcome copy migrates to stable ids")

	var encoded: String = JSON.stringify(migrated_state)
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "migrated outcomes survive JSON encoding")
	if typeof(decoded) == TYPE_DICTIONARY:
		var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
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

	var simulation: FirstNightSimulation = Simulation.new(legacy_state)
	var migrated: Dictionary = simulation.export_state()
	var mira: Dictionary = (migrated["npcs"] as Dictionary)["core:first_neighbor"] as Dictionary
	_expect(int(migrated.get("version", 0)) == 10, "v4 save migrates to save version 10")
	_expect(typeof(mira.get("needs")) == TYPE_DICTIONARY, "v4 NPC gains normalized needs")
	_expect(String(mira.get("activity_id", "")).contains(":"), "v4 NPC gains stable activity id")
	_expect(int((mira.get("personal_inventory", {}) as Dictionary).get("core:food", -1)) == 2, "v4 NPC gains initial personal food")
	_expect(typeof(mira.get("target_cell")) == TYPE_ARRAY, "v4 NPC gains a target cell")


func _test_v5_blueprints_are_migrated() -> void:
	var legacy_state: Dictionary = Simulation.create_new_state()
	legacy_state["version"] = 5
	legacy_state.erase("blueprints")
	legacy_state.erase("structures")
	var migrated_simulation: FirstNightSimulation = Simulation.new(legacy_state)
	_expect(
		int(migrated_simulation.export_state().get("version", 0)) == 10,
		"v5 save migrates to save version 10"
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
	var simulation: FirstNightSimulation = Simulation.new(state_with_blueprint)
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
	var migrated_simulation: FirstNightSimulation = Simulation.new(legacy_state)
	_expect(
		int(migrated_simulation.export_state().get("version", 0)) == 10,
		"v6 save migrates to save version 10"
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
	var simulation: FirstNightSimulation = Simulation.new(state_with_structures)
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
	var simulation: FirstNightSimulation = Simulation.new()
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
		simulation.get_current_objective_key() == "first_night.objective.complete",
		"objective returns to completed slice after greeting"
	)

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "NPC state serializes as a dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
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
	var simulation: FirstNightSimulation = Simulation.new()
	_complete_first_night_for_test(simulation)
	var start_position: Vector2 = simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	var start_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(simulation.get_npc_personal_food("core:first_neighbor") == 2, "Mira arrives with two personal food portions")

	simulation.advance_minutes(5 * 60)
	var midday_position: Vector2 = simulation.get_npc_position("core:first_neighbor", Vector2.ZERO)
	var midday_needs: Dictionary = simulation.get_npc_needs("core:first_neighbor")
	_expect(not midday_position.is_equal_approx(start_position), "Mira changes position during her morning")
	_expect(float(midday_needs.get("energy", 100.0)) < float(start_needs.get("energy", 0.0)), "Mira spends energy while awake")
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

	var first: FirstNightSimulation = first_result["simulation"] as FirstNightSimulation
	var second: FirstNightSimulation = second_result["simulation"] as FirstNightSimulation
	first.advance_minutes(7 * 60)
	second.advance_minutes(7 * 60)
	_expect(first.get_npcs() == second.get_npcs(), "equal state and elapsed minutes produce identical NPC autonomy")

	var encoded: String = JSON.stringify(first.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "autonomy state survives JSON encoding")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
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

	var unacquainted: FirstNightSimulation = _build_mira_work_simulation(
		target_cell,
		false,
		true
	)
	var unacquainted_result: Dictionary = unacquainted.execute_npc_work_request(command)
	_expect(
		String(unacquainted_result.get("reason_id", "")) == "core:not_acquainted",
		"Mira refuses a request before meeting the player"
	)

	var missing_blueprint: FirstNightSimulation = _build_mira_work_simulation(
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
		FirstNightContent.WOOD_ID
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
	var simulation: FirstNightSimulation = _build_mira_work_simulation(
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
			FirstNightContent.WOOD_ID,
			0
		)) == 2,
		"Mira transfers required carried wood into the blueprint"
	)
	_expect(
		(simulation.get_blueprints()[0] as Dictionary).get(
			"delivered_materials",
			{}
		) == {FirstNightContent.WOOD_ID: 1},
		"Mira's delivered wood becomes part of the blueprint"
	)
	_expect(
		int(commitment.get("required_minutes", 0))
		== NpcAutonomyScript.CONSTRUCTION_WORK_MINUTES,
		"construction commitment records its required work time"
	)

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored := Simulation.new(decoded as Dictionary)
	_expect(
		restored.get_npc_work_commitment("core:first_neighbor") == commitment,
		"construction commitment survives a save round trip"
	)

	simulation.advance_minutes(14)
	_expect(
		simulation.get_blueprints().size() == 1
		and simulation.get_structures().is_empty(),
		"construction does not finish before travel and work time elapse"
	)
	_expect(
		simulation.get_npc_memories("core:first_neighbor").is_empty(),
		"unfinished construction creates no memory"
	)
	simulation.advance_minutes(1)
	_expect(simulation.get_blueprints().is_empty(), "Mira consumes the completed blueprint")
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


func _test_missing_blueprint_releases_commitment() -> void:
	var target_cell := Vector2i(22, 29)
	var simulation: FirstNightSimulation = _build_mira_work_simulation(
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
	var simulation: FirstNightSimulation = _build_mira_work_simulation(
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
	simulation.advance_minutes(15)

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

	var debug_completion: FirstNightSimulation = _build_mira_work_simulation(
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
	var simulation: FirstNightSimulation = _build_mira_work_simulation(
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
	simulation.advance_minutes(15)
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
) -> FirstNightSimulation:
	var scenario: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	var simulation: FirstNightSimulation = scenario["simulation"] as FirstNightSimulation
	var state_with_materials: Dictionary = simulation.export_state()
	var mira: Dictionary = (
		state_with_materials["npcs"] as Dictionary
	)["core:first_neighbor"] as Dictionary
	var mira_inventory: Dictionary = mira.get("personal_inventory", {}) as Dictionary
	mira_inventory[FirstNightContent.WOOD_ID] = 3
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
		ConstructionCommandScript.complete_blueprint(Vector2i(48, 29))
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
	var empty_inventory_simulation: FirstNightSimulation = Simulation.new()
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
	(initial_state["inventory"] as Dictionary)[FirstNightContent.WOOD_ID] = 3
	var simulation: FirstNightSimulation = Simulation.new(initial_state)
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
			first_blueprint.get("required_materials", {}) == {"core:wood": 1},
			"placed wall blueprint snapshots its material requirement"
		)
		_expect(
			first_blueprint.get("delivered_materials", {}) == {"core:wood": 0},
			"placed wall blueprint starts without delivered materials"
		)
		_expect(
			int(first_blueprint.get("required_work_minutes", 0)) == 12,
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
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 2,
		"delivered wood leaves the player inventory"
	)
	_expect(
		(simulation.get_blueprints()[0] as Dictionary).get(
			"delivered_materials",
			{}
		) == {FirstNightContent.WOOD_ID: 1},
		"delivered wood becomes part of the blueprint"
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
	var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
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
		simulation.get_item_count(FirstNightContent.WOOD_ID) == 3,
		"cancelling a blueprint returns its delivered materials"
	)
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
	var complete_result: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.complete_blueprint(Vector2i(23, 29))
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
	var actor_blocked_completion: Dictionary = simulation.execute_construction_command(
		ConstructionCommandScript.complete_blueprint(Vector2i(24, 29))
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
	var completed_restored: FirstNightSimulation = Simulation.new(completed_decoded as Dictionary)
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
		int(migrated.export_state().get("version", 0)) == 10,
		"v7 save migrates to save version 10"
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
		int(migrated.export_state().get("version", 0)) == 10,
		"v8 save migrates to save version 10"
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
		int(migrated.export_state().get("version", 0)) == 10,
		"v9 save migrates to save version 10"
	)
	var migrated_blueprints: Array = migrated.get_blueprints()
	_expect(migrated_blueprints.size() == 1, "v9 blueprint survives migration")
	if migrated_blueprints.size() == 1:
		var migrated_blueprint: Dictionary = migrated_blueprints[0] as Dictionary
		_expect(
			migrated_blueprint.get("required_materials", {}) == {"core:wood": 1},
			"v9 blueprint gains its catalog material requirement"
		)
		_expect(
			migrated_blueprint.get("delivered_materials", {}) == {"core:wood": 0},
			"v9 blueprint starts with no delivered materials"
		)
		_expect(
			int(migrated_blueprint.get("required_work_minutes", 0)) == 12,
			"v9 blueprint gains its catalog work requirement"
		)

	var corrupt_state: Dictionary = Simulation.create_new_state()
	corrupt_state["blueprints"] = [{
		"building_id": "core:wood_wall",
		"cell": [22, 29],
		"stage_id": "core:blueprint",
		"delivered_materials": {"core:wood": 99, "core:stone": 5},
		"work_progress_minutes": 99,
	}]
	var normalized_progress := Simulation.new(corrupt_state)
	var normalized_blueprint: Dictionary = (
		normalized_progress.get_blueprints()[0] as Dictionary
	)
	_expect(
		normalized_blueprint.get("delivered_materials", {}) == {"core:wood": 1},
		"blueprint delivery is clamped to its catalog requirement"
	)
	_expect(
		int(normalized_blueprint.get("work_progress_minutes", 0)) == 12,
		"blueprint work progress is clamped to its requirement"
	)


func _test_building_catalog() -> void:
	var catalog := BuildingCatalogScript.new()
	var wall: Dictionary = catalog.get_definition("core:wood_wall")
	_expect(not wall.is_empty(), "building catalog loads the wooden wall")
	_expect(
		catalog.get_material_cost("core:wood_wall") == {"core:wood": 1},
		"wooden wall reads its material cost from content"
	)
	_expect(
		catalog.get_work_minutes("core:wood_wall") == 12,
		"wooden wall reads its work duration from content"
	)
	wall["work_minutes"] = 999
	_expect(
		catalog.get_work_minutes("core:wood_wall") == 12,
		"building definition snapshots do not mutate the catalog"
	)
	_expect(
		catalog.get_definition("core:missing").is_empty(),
		"unknown building has no definition"
	)


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
	var simulation: FirstNightSimulation = result["simulation"] as FirstNightSimulation
	_expect(simulation.export_state() == Simulation.new().export_state(), "fresh lab scenario matches a new game")
	_expect(simulation.get_day() == 1, "fresh lab scenario starts on day 1")
	_expect(simulation.get_time_text() == "11:00", "fresh lab scenario starts at 11:00")
	_expect(simulation.get_inventory_weight() == 0.0, "fresh lab scenario has an empty inventory")
	_expect(simulation.get_object_stage("repair") == 0, "fresh lab scenario has no repair progress")
	_expect(simulation.get_object_stage("campfire") == 0, "fresh lab scenario has no campfire progress")
	_expect(not simulation.is_npc_visible("core:first_neighbor"), "fresh lab scenario keeps Mira hidden")


func _test_lab_prepared_evening() -> void:
	var result: Dictionary = LabScenarios.build(LabScenarios.PREPARED_EVENING)
	_expect(bool(result.get("success", false)), "prepared evening lab scenario builds")
	if not bool(result.get("success", false)):
		return
	var simulation: FirstNightSimulation = result["simulation"] as FirstNightSimulation
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
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 1, "prepared evening has one wood left")
	_expect(simulation.get_item_count(FirstNightContent.STONE_ID) == 2, "prepared evening has two stone left")
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
	var simulation: FirstNightSimulation = result["simulation"] as FirstNightSimulation
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
	var simulation: FirstNightSimulation = result["simulation"] as FirstNightSimulation
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
	var simulation: FirstNightSimulation = result["simulation"] as FirstNightSimulation
	_expect(simulation.get_day() == 2, "shared-wall scenario remains on day 2")
	_expect(simulation.get_time_text() == "07:20", "shared-wall scenario starts at 07:20")
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
	var first_simulation: FirstNightSimulation = first["simulation"] as FirstNightSimulation
	var talk_result: Dictionary = _interact_near(first_simulation, "core:first_neighbor")
	_expect(bool(talk_result.get("success", false)), "reset test can change the first scenario instance")

	var rebuilt: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	_expect(bool(rebuilt.get("success", false)), "morning scenario rebuild succeeds")
	if not bool(rebuilt.get("success", false)):
		return
	var rebuilt_simulation: FirstNightSimulation = rebuilt["simulation"] as FirstNightSimulation
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


func _complete_first_night_for_test(simulation: FirstNightSimulation) -> void:
	_interact_near(simulation, "old_tools")
	for wood_id: String in ["wood_north", "wood_west", "wood_east"]:
		_interact_near(simulation, wood_id)
	for stone_id: String in ["stone_south", "stone_east"]:
		_interact_near(simulation, stone_id)
	_interact_near(simulation, "berry_bush")
	_interact_near(simulation, "shore_water")
	for _step: int in range(3):
		_interact_near(simulation, "repair_room")
	for _step: int in range(3):
		_interact_near(simulation, "campfire_site")
	_interact_near(simulation, "bed_site")
	simulation.advance_minutes(simulation.EVENING_MINUTE - simulation.get_minute_of_day())
	_interact_near(simulation, "bed_site")


func _interact_near(simulation: FirstNightSimulation, target_id: String) -> Dictionary:
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
	return simulation.execute_interaction(target_id)


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
