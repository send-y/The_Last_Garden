extends SceneTree

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const AppearanceCatalog := preload("res://src/characters/character_appearance.gd")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const SessionNodeScript := preload("res://src/autoload/session.gd")
const TEST_SAVE_PATH: String = "user://first_night_save_store_test.json"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	_test_character_appearance_generation()
	_test_first_neighbor_arrives_and_talks()

	if _failures == 0:
		print("PASS: first-night simulation tests")
		quit(0)
	else:
		push_error("FAIL: %d first-night simulation assertion(s)" % _failures)
		quit(1)


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


func _test_corrupt_nested_state_uses_defaults() -> void:
	var corrupt: Dictionary = Simulation.create_new_state()
	corrupt["day"] = -4
	corrupt["minute_of_day"] = 99999
	corrupt["inventory"] = ["bad"]
	corrupt["collected"] = "bad"
	corrupt["flags"] = "bad"
	corrupt["npcs"] = {"core:first_neighbor": "bad"}
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


func _test_save_header_validation() -> void:
	for version: int in [1, 2, 3]:
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
	_expect(simulation.get_object_label("npc", "?", "core:first_neighbor") == "Путник у Общего дома", "first neighbor starts unknown")
	_expect(simulation.get_current_objective() == "Утром у Общего дома появился путник. Поговорите с ним.", "objective points to the first neighbor")

	var talk_result: Dictionary = _interact_near(simulation, "core:first_neighbor")
	_expect(bool(talk_result["success"]), "talking to first neighbor succeeds")
	_expect(String(talk_result["message"]).begins_with("Мира:"), "first neighbor introduces herself by name")
	_expect(simulation.get_object_label("npc", "?", "core:first_neighbor") == "Мира", "first neighbor label becomes known after talking")
	_expect(simulation.get_current_objective() == "Первое утро наступило. Срез пройден.", "objective returns to completed slice after greeting")

	var encoded: String = JSON.stringify(simulation.export_state())
	var decoded: Variant = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "NPC state serializes as a dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var restored: FirstNightSimulation = Simulation.new(decoded as Dictionary)
	_expect(restored.is_npc_visible("core:first_neighbor"), "first neighbor visibility survives serialization")
	_expect(restored.get_object_label("npc", "?", "core:first_neighbor") == "Мира", "known NPC label survives serialization")
	_expect(not restored.get_npc_appearance("core:first_neighbor").is_empty(), "NPC appearance survives serialization")


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
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % description)
