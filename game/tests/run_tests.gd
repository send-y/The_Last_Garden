extends SceneTree

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const AppearanceCatalog := preload("res://src/characters/character_appearance.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_complete_first_night()
	_test_serialization_round_trip()
	_test_duplicate_collection_is_rejected()
	_test_legacy_save_ids_are_migrated()
	_test_character_appearance_generation()

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

	simulation.execute_interaction("old_tools", "tools")
	for wood_id: String in ["wood_north", "wood_west", "wood_east"]:
		simulation.execute_interaction(wood_id, "wood")
	for stone_id: String in ["stone_south", "stone_east"]:
		simulation.execute_interaction(stone_id, "stone")
	simulation.execute_interaction("berry_bush", "food")
	simulation.execute_interaction("shore_water", "water")

	_expect(simulation.get_inventory_weight() <= simulation.MAX_CARRY_WEIGHT, "collected resources fit the weight limit")
	for _step: int in range(3):
		simulation.execute_interaction("repair_room", "repair")
	_expect(simulation.get_object_stage("repair") == 3, "room repair reaches stage 3")

	for _step: int in range(3):
		simulation.execute_interaction("campfire_site", "campfire")
	_expect(simulation.get_object_stage("campfire") == 2, "campfire is lit")
	_expect(bool(simulation.get_flags()["water_boiled"]), "water is boiled")

	simulation.execute_interaction("bed_site", "bed")
	_expect(bool(simulation.get_flags()["bed_ready"]), "temporary bed is ready")
	simulation.advance_minutes(simulation.EVENING_MINUTE - simulation.get_minute_of_day())
	var sleep_result: Dictionary = simulation.execute_interaction("bed_site", "bed")
	_expect(bool(sleep_result["success"]), "sleep command succeeds after 18:00")
	_expect(simulation.get_day() == 2, "sleep advances to day 2")
	_expect(simulation.get_time_text() == "07:00", "sleep advances to 07:00")
	_expect(bool(simulation.get_flags()["first_night_complete"]), "first night is marked complete")


func _test_serialization_round_trip() -> void:
	var original: FirstNightSimulation = Simulation.new()
	original.execute_interaction("old_tools", "tools")
	original.execute_interaction("wood_north", "wood")
	original.set_player_position(Vector2(321.5, 654.25))
	original.advance_minutes(37)

	var encoded: String = JSON.stringify(original.state)
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
	var first: Dictionary = simulation.execute_interaction("wood_north", "wood")
	var second: Dictionary = simulation.execute_interaction("wood_north", "wood")
	_expect(bool(first["success"]), "first resource collection succeeds")
	_expect(not bool(second["success"]), "duplicate resource collection is rejected")
	_expect(simulation.get_item_count(FirstNightContent.WOOD_ID) == 3, "duplicate collection does not create resources")


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


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % description)
