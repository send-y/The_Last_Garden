extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Construction := preload("res://src/construction/construction_command.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func fixture():
	var state := World.create_new_game_state()
	state.day = 2
	state.minute_of_day = 20 * 60
	state.elapsed_game_minutes = 2640
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	state.npcs["core:first_neighbor"].known = true
	state.npcs["core:first_neighbor"].needs.hunger = 100.0
	return World.new(state)

func _run() -> void:
	var sim = fixture()
	check(sim.has_method("assign_sleep_place"), "Housing assignment API must exist")
	if not sim.has_method("assign_sleep_place"):
		quit(1)
		return
	_test_starter_and_shared_places()
	_test_npc_sleep_and_save()
	_test_quality_and_missing_place()
	_test_constructed_shared_room()
	_test_migration_and_preview()
	_test_fallback_and_starter_overlap()
	if failures == 0:
		print("PASS: personal sleep places, shared housing, starter bedroll, NPC sleep, physical quality and persistence")
	quit(0 if failures == 0 else 1)

func _test_starter_and_shared_places() -> void:
	var sim = fixture()
	var player: Dictionary = sim.get_character_home("core:player")
	check(String(player.get("place_id", "")) == "core:starter_bedroll", "Player has a starter bedroll without an expensive bed")
	check(not sim.assign_sleep_place("core:first_neighbor", "core:starter_bedroll").success, "NPC cannot take the player's occupied bedroll")
	sim.add_structure({"building_id": "core:bedroll", "cell": [20,23]})
	sim._sync_structure_navigation()
	check(sim.assign_sleep_place("core:first_neighbor", "core:bedroll@20,23").success, "A second cheap bedroll can be assigned in the shared base house")
	var npc: Dictionary = sim.get_character_home("core:first_neighbor")
	check(npc.room_id == player.room_id and npc.place_id != player.place_id, "Shared room supports separate personal sleep places")
	check(not sim.assign_sleep_place("core:player", "core:bedroll@20,23").success, "Two people cannot own the same sleep place")
	sim.assign_sleep_place("core:first_neighbor", "")
	check(sim.assign_sleep_place("core:player", "core:bedroll@20,23").success, "Released sleep place can be reassigned")

func _test_npc_sleep_and_save() -> void:
	var sim = fixture()
	sim.add_structure({"building_id": "core:bed", "cell": [20,23]})
	sim._sync_structure_navigation()
	check(sim.assign_sleep_place("core:first_neighbor", "core:bed@20,23").success, "Resident can be assigned a real constructed bed")
	var before: float = sim.state.npcs["core:first_neighbor"].needs.energy
	sim.advance_minutes(100)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	var home: Dictionary = sim.get_character_home("core:first_neighbor")
	var current: Vector2i = sim._world_position_to_cell(sim.get_npc_position(String(npc.id), Vector2.ZERO))
	check(String(npc.activity_id) == "core:sleeping" and home.target_cell == [current.x,current.y], "Resident actually walks to its own bed and sleeps beside it")
	check(float(npc.needs.energy) >= before, "NPC bed sleep recovers physical state")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(restored.get_character_home(String(npc.id)) == home, "Assignment and actual sleep place survive reload")

func _test_quality_and_missing_place() -> void:
	var sim = fixture()
	sim.state.player_energy = 0.0
	sim.state.player_needs.restedness = 0.0
	sim.set_player_position(Content.cell_center(26,23))
	check(sim.sleep_at_place("core:starter_bedroll").success, "Starter bedroll supports real night sleep")
	check(sim.get_player_energy() == 100, "Covered starter bedroll preserves full energy recovery")
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	sim.add_structure({"building_id": "core:bed", "cell": [20,23]})
	sim._sync_structure_navigation()
	sim.assign_sleep_place(String(npc.id), "core:bed@20,23")
	sim.remove_structure(sim.state.structures.back())
	sim._sync_structure_navigation()
	var missing: Dictionary = sim.get_character_home(String(npc.id))
	check(not bool(missing.get("valid", false)), "Removed bed does not remain a usable phantom place")
	check(not sim.sleep_at_place("core:bed@20,23").success, "Player cannot sleep in a removed bed")
	var bed := {"hunger":100.0,"energy":0.0,"restedness":0.0}
	var roll := bed.duplicate()
	for minute: int in range(30):
		sim.needs.advance(bed, "sleeping", true, {"speed":1.35})
		sim.needs.advance(roll, "sleeping", true, {"speed":1.0})
	check(float(bed.energy) > float(roll.energy) and float(bed.restedness) > float(roll.restedness), "Bed recovery is faster than bedroll recovery")

func room_fixture():
	var sim = fixture()
	sim.state.flags.repair_stage = 0
	sim.replace_structures([])
	sim.state.tree_nodes.clear()
	sim.state.resource_nodes.clear()
	for y: int in range(10,16):
		for x: int in range(10,17):
			if x == 10 or x == 16 or y == 10 or y == 15:
				sim.add_structure({"building_id":"core:wood_door" if x == 13 and y == 15 else "core:wood_wall", "cell":[x,y]})
	sim.add_structure({"building_id":"core:bed", "cell":[11,11]})
	sim.add_structure({"building_id":"core:bedroll", "cell":[14,13]})
	sim.add_structure({"building_id":"core:table", "cell":[12,12]})
	sim.add_structure({"building_id":"core:torch", "cell":[15,11]})
	sim._sync_structure_navigation()
	check(sim.assign_room_type("core:living_room", Vector2i(11,12)).success, "Real furnished enclosure can be designated a living room")
	return sim

func _test_constructed_shared_room() -> void:
	var sim = room_fixture()
	check(sim.set_home_mode(String(sim.state.room_assignments[0].id), "shared").success, "Constructed home explicitly allows shared occupancy")
	check(sim.assign_sleep_place("core:player", "core:bed@11,11").success, "Player can own constructed housing")
	check(sim.assign_sleep_place("core:first_neighbor", "core:bedroll@14,13").success, "Resident can share a constructed living room with the player")
	var player: Dictionary = sim.get_character_home("core:player")
	var npc: Dictionary = sim.get_character_home("core:first_neighbor")
	check(player.room_id == npc.room_id and bool(npc.covered) and not sim.is_roof_covered(), "Constructed room has independent shelter from the starting roof")
	sim.set_player_position(Content.cell_center(11,10))
	check(not sim.sleep_at_place("core:bed@11,11").success, "A nearby bed cannot be used through its room wall")
	sim.add_structure({"building_id":"core:bed", "cell":[32,32]})
	sim._sync_structure_navigation()
	check(not sim.assign_sleep_place("core:player", "core:bed@32,32").success, "Outdoor bed cannot be assigned as housing")
	var updated: Array = sim.get_structures()
	for structure: Dictionary in updated:
		if structure.cell == [13,15]:
			structure.building_id = "core:wood_wall"
	sim.replace_structures(updated)
	sim._sync_structure_navigation()
	check(not bool(sim.get_character_home("core:first_neighbor").valid), "A completely closed door invalidates access to assigned housing")
	check(not sim.assign_sleep_place("core:first_neighbor", "core:bedroll@14,13").success, "Unreachable housing cannot be assigned")
	for index: int in range(sim.state.structures.size()):
		if sim.state.structures[index].cell == [10,12]:
			sim.remove_structure(sim.state.structures[index])
			break
	sim._sync_structure_navigation()
	check(not bool(sim.get_character_home("core:player").valid), "Opening the enclosing wall invalidates actual housing geometry")
	check(String(sim.state.sleep_assignments["core:first_neighbor"]) == "core:bedroll@14,13", "Losing room validity preserves the personal assignment for repair")

func _test_migration_and_preview() -> void:
	var legacy := World.create_new_game_state()
	legacy.version = 29
	legacy.erase("sleep_assignments")
	legacy.player_energy = 34.0
	var position: Array = legacy.player_position.duplicate()
	var inventory: Dictionary = legacy.inventory.duplicate()
	var migrated = World.new(legacy)
	check(String(migrated.get_character_home("core:player").place_id) == "core:starter_bedroll", "Previous saves gain a starter bedroll assignment")
	check(migrated.state.player_position == position and migrated.get_inventory() == inventory and migrated.get_player_energy() == 34, "Migration preserves position, stock and physical state")
	legacy.sleep_assignments = {"core:player":"core:starter_bedroll", "core:first_neighbor":"core:starter_bedroll"}
	var duplicate = World.new(legacy)
	check(String(duplicate.state.sleep_assignments["core:first_neighbor"]).is_empty(), "Duplicate saved ownership is normalized")
	var sim = room_fixture()
	sim.state.minute_of_day = 6 * 60 + 30
	sim.state.player_energy = 0.0
	sim.set_player_position(Content.cell_center(11,12))
	var before := String(sim.state.sleep_assignments["core:player"])
	var preview: float = sim.get_sleep_energy_preview("core:bed@11,11")
	check(String(sim.state.sleep_assignments["core:player"]) == before, "Inspecting a bed preview never changes ownership")
	var sleep_result: Dictionary = sim.sleep_at_place("core:bed@11,11")
	check(bool(sleep_result.success) and is_equal_approx(sim.get_player_energy(),preview), "Late-night constructed bed preview agrees with actual sleep: expected %f, actual %f, result %s" % [preview,sim.get_player_energy(),str(sleep_result)])
	var day: int = sim.get_day()
	var minutes: int = sim.get_elapsed_game_minutes()
	check(sim.sleep_at_place("core:bed@11,11").success and sim.get_day() == day and sim.get_elapsed_game_minutes() == minutes + 15, "Daytime bed interaction gives short rest without skipping another day")
	var bed := {"hunger":100.0,"energy":0.0,"restedness":0.0}
	var roll := bed.duplicate()
	for minute: int in range(15):
		sim.needs.advance(bed, "resting_in_bed", true, {"speed":1.35})
		sim.needs.advance(roll, "resting_in_bed", true, {"speed":1.0})
	check(float(bed.energy) > float(roll.energy) and float(bed.restedness) > float(roll.restedness), "Daytime physical bed rest also uses bed quality")

func _test_fallback_and_starter_overlap() -> void:
	var sim = fixture()
	check(not sim.execute_construction_command(Construction.place_blueprint(Vector2i(26,23),"core:bedroll")).success, "Furniture cannot duplicate the starter's physical place")
	check(not sim.execute_construction_command(Construction.place_blueprint(Vector2i(25,23),"core:bed")).success, "Full furniture footprint reserves starter place")
	sim.add_structure({"building_id":"core:wood_wall", "cell":[25,23]})
	sim._sync_structure_navigation()
	sim.state.npcs["core:first_neighbor"].needs.energy = 5.0
	sim.advance_minutes(110)
	check(String(sim.state.npcs["core:first_neighbor"].activity_id) == "core:resting" and float(sim.state.npcs["core:first_neighbor"].needs.energy) > 5, "Resident without housing finds reachable temporary rest when old rest cell is blocked")
	var overlapping = fixture()
	overlapping.add_structure({"building_id":"core:bed", "cell":[26,23]})
	overlapping._sync_structure_navigation()
	check(not bool(overlapping.get_character_home("core:player").valid), "Older overlapping furniture cannot produce two usable personal places")
	check(overlapping.assign_sleep_place("core:first_neighbor", "core:bed@26,23").success, "Older constructed bed remains assignable without deleting it")
