extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Topology := preload("res://src/construction/room_topology.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func fixture():
	var sim = World.new(World.create_new_game_state())
	sim.state.flags.first_night_complete = true
	sim.state.npcs["core:first_neighbor"].known = true
	sim.state.npcs["core:first_neighbor"].active = true
	sim.state.structures.clear()
	sim.state.resource_nodes.clear()
	sim.state.tree_nodes.clear()
	for y: int in range(10, 16):
		for x: int in range(10, 17):
			if x == 10 or x == 16 or y == 10 or y == 15:
				sim.state.structures.append({"building_id": "core:wood_door" if x == 13 and y == 15 else "core:wood_wall", "cell": [x,y]})
	sim.state.structures.append({"building_id":"core:bedroll", "cell":[11,11]})
	sim.state.structures.append({"building_id":"core:bedroll", "cell":[14,13]})
	sim._sync_structure_navigation()
	return sim

func _run() -> void:
	var sim = fixture()
	for method: String in ["get_housing_rooms", "get_home_policy", "set_home_mode", "get_stock_reserve_report", "set_stock_reserve"]:
		check(sim.has_method(method), "Resident home API is required: " + method)
	if failures > 0:
		quit(1)
		return
	_test_base()
	_test_assignment()
	_test_migration()
	_test_reserves()
	if failures == 0:
		print("PASS: resident home modes, foundation admission, legacy assignments, damaged policies and stock reserves")
	quit(0 if failures == 0 else 1)

func _test_base() -> void:
	var sim = fixture()
	var policy: Dictionary = sim.get_home_policy("core:player")
	check(policy.mode == "settlement" and policy.room_id == "core:base_house", "Starter house always belongs to settlement")
	check(not sim.set_home_mode("core:base_house", "personal").success, "Starter mode cannot be changed")
	check(not sim.get_home_policy("core:first_neighbor").may_furnish, "Unhoused NPC cannot furnish")
	check(not sim.set_home_mode("missing", "shared").success, "Unknown room is rejected")

func _test_assignment() -> void:
	var sim = fixture()
	check(sim.assign_room_type(Topology.LIVING_ROOM_ID, Vector2i(11,12)).success, "Enclosed sleeping foundation admits living designation without table or light")
	var room_id := String(sim.state.room_assignments[0].id)
	check(sim.assign_sleep_place("core:first_neighbor", "core:bedroll@11,11").success, "First occupant enters personal home")
	check(sim.get_home_policy("core:first_neighbor").mode == "personal" and sim.get_home_policy("core:first_neighbor").may_furnish, "Known resident may furnish personal home")
	check(not sim.assign_sleep_place("core:player", "core:bedroll@14,13").success, "Player also counts toward personal home's single occupant")
	check(sim.set_home_mode(room_id, "shared").success, "Player can allow shared living")
	check(sim.assign_sleep_place("core:player", "core:bedroll@14,13").success, "Shared room admits separate second sleeping place")
	check(sim.get_home_policy("core:first_neighbor").members.size() == 2, "Shared members include player and resident")
	check(not sim.set_home_mode(room_id, "personal").success, "Occupied shared room cannot become personal without relocation")
	check(not sim.set_home_mode(room_id, "invalid").success, "Invalid mode rejected")
	sim.state.npcs["core:first_neighbor"].residency = "visitor"
	check(not sim.get_home_policy("core:first_neighbor").may_furnish, "Visitors cannot furnish even with assigned bed")
	sim.state.npcs["core:first_neighbor"].residency = "resident"
	sim.state.npcs["core:first_neighbor"].known = false
	check(not sim.get_home_policy("core:first_neighbor").may_furnish, "Unknown residents cannot furnish")
	sim.state.npcs["core:first_neighbor"].known = true
	sim.state.npcs["core:first_neighbor"].active = false
	check(not sim.get_home_policy("core:first_neighbor").may_furnish, "Inactive residents cannot furnish")

func _test_migration() -> void:
	var sim = fixture()
	sim.assign_room_type(Topology.LIVING_ROOM_ID, Vector2i(11,12))
	var room_id := String(sim.state.room_assignments[0].id)
	sim.state.sleep_assignments["core:player"] = "core:bedroll@14,13"
	sim.state.sleep_assignments["core:first_neighbor"] = "core:bedroll@11,11"
	var legacy: Dictionary = sim.state.duplicate(true)
	legacy.version = 33
	legacy.erase("home_policies")
	legacy.erase("stock_reserves")
	var loaded = World.new(legacy)
	check(loaded.state.version == World.SAVE_VERSION, "Saves migrate to the current schema version")
	check(loaded.get_home_policy("core:first_neighbor").mode == "shared", "Legacy multiple occupants migrate to shared")
	check(loaded.state.sleep_assignments == sim.state.sleep_assignments, "Migration preserves existing assignments")
	legacy.home_policies = {room_id:"broken", "core:base_house":"personal", "missing":"shared"}
	legacy.stock_reserves = {"core:wood":7, "core:stone":-1, "core:food":NAN, "missing":4, "core:axe":3}
	loaded = World.new(legacy)
	check(loaded.get_home_policy("core:first_neighbor").mode == "shared", "Corrupt room mode recovers by assigned membership")
	check(loaded.get_home_policy("core:player").mode == "shared", "Base override corruption does not change external assignments")
	check(loaded.state.home_policies.get("core:base_house", "") == "settlement" and not loaded.state.home_policies.has("missing"), "Base forced communal and unknown policies removed")
	check(loaded.state.stock_reserves == {"core:wood":7}, "Invalid reserve values and nonstackable items are discarded")
	legacy.home_policies = []
	legacy.stock_reserves = "damaged"
	loaded = World.new(legacy)
	check(loaded.state.home_policies is Dictionary and loaded.state.stock_reserves.is_empty(), "Malformed policy containers normalize")

func _test_reserves() -> void:
	var sim = fixture()
	sim.state.storage_items.append({"item_id":"core:wood", "amount":8, "zone_id":"a"})
	sim.state.storage_items.append({"item_id":"core:wood", "amount":5, "zone_id":"b"})
	check(sim.set_stock_reserve("core:wood", 9).success, "Reserve command succeeds")
	var found := false
	for row: Dictionary in sim.get_stock_reserve_report():
		if row.item_id == "core:wood":
			found = true
			check(row.stock == 13 and row.reserved == 9 and row.available == 4 and not String(row.label_key).is_empty(), "Reserve aggregates whole warehouse")
	check(found, "Reserve report includes protected material")
	check(sim.set_stock_reserve("core:wood", 20).success, "Reserve can exceed current stock")
	for row: Dictionary in sim.get_stock_reserve_report():
		if row.item_id == "core:wood": check(row.available == 0, "Availability never becomes negative")
	check(not sim.set_stock_reserve("core:wood", -1).success, "Negative reserve rejected")
	check(not sim.set_stock_reserve("core:wood", NAN).success, "Nonfinite reserve rejected")
	check(not sim.set_stock_reserve("core:wood", "3").success, "String reserve rejected")
	check(not sim.set_stock_reserve("missing", 3).success, "Unknown reserve item rejected")
	check(not sim.set_stock_reserve("core:axe", 3).success, "Instance items cannot get stack reserves")
	var loaded = World.new(sim.state)
	check(loaded.state.stock_reserves.get("core:wood", 0) == 20, "Reserve survives reload")
