extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"
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
	state.minute_of_day = 12 * 60
	state.npcs[NPC].known = true
	state.npcs[NPC].personal_inventory = {"core:food":0}
	state.npcs[NPC].position = [Content.cell_center(22,23).x,Content.cell_center(22,23).y]
	state.structures.append({"building_id":"core:bedroll","cell":[20,23]})
	state.structures.append({"building_id":"core:table","cell":[22,20]})
	state.structures.append({"building_id":"core:chair","cell":[22,21]})
	state.structures.append({"building_id":"core:torch","cell":[24,20]})
	return World.new(state)

func row(report: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in report.rows:
		if value.id == id:
			return value
	return {}

func _run() -> void:
	var sim = fixture()
	check(sim.has_method("get_npc_household_status"), "NPC household feedback must have an authoritative query")
	if not sim.has_method("get_npc_household_status"):
		quit(1)
		return
	var before := JSON.stringify(sim.export_state())
	var report: Dictionary = sim.get_npc_household_status(NPC)
	check(row(report,"sleep").status == "unassigned" and row(report,"food").status == "missing", "Missing personal sleep and actual food are explained")
	check(JSON.stringify(sim.export_state()) == before, "Reading feedback must not reserve furniture, start food transport, spend resources or advance time")
	sim.assign_sleep_place(NPC,"core:bedroll@20,23")
	report = sim.get_npc_household_status(NPC)
	check(row(report,"sleep").status == "poor_roof" and report.home.cell == [20,23], "Assigned bedroll location and unfinished roof are visible")
	sim.state.flags.repair_stage = 2
	sim.state.npcs[NPC].personal_inventory = {"core:carrot":1}
	report = sim.get_npc_household_status(NPC)
	check(row(report,"sleep").status == "ready" and row(report,"food").status == "personal" and row(report,"dining").status == "ready" and row(report,"light").status == "ready", "Good ordinary household shows four fulfilled provisions")
	before = JSON.stringify(sim.export_state())
	sim.state.npcs[NPC].needs.hunger = 30.0
	before = JSON.stringify(sim.export_state())
	sim.get_npc_household_status(NPC)
	check(JSON.stringify(sim.export_state()) == before, "Reading a hungry resident with real personal food must not reserve a seat or start a meal")
	check(not report.rows.any(func(r: Dictionary) -> bool: return r.get("hint_key","") == "household.hint.upgrade_bed"), "Good covered bedroll is not falsely reported as needing a bed upgrade")
	sim.state.npcs[NPC].personal_inventory = {}
	sim.state.storage_items.append({"placement_id":"core:feedback_food","item_id":"core:carrot","amount":1,"cell":[22,24],"rotated":false})
	check(row(sim.get_npc_household_status(NPC),"food").status == "storage", "Reachable shared food counts as available")
	sim.add_structure({"building_id":"core:wood_wall","cell":[21,24]})
	sim.add_structure({"building_id":"core:wood_wall","cell":[23,24]})
	sim.add_structure({"building_id":"core:wood_wall","cell":[22,23]})
	sim._sync_structure_navigation()
	sim.state.npcs[NPC].position = [Content.cell_center(25,23).x,Content.cell_center(25,23).y]
	check(row(sim.get_npc_household_status(NPC),"food").status == "blocked", "Food behind walls is reported as inaccessible, not usable stock")
	sim = fixture()
	sim.state.flags.repair_stage = 2
	sim.assign_sleep_place(NPC,"core:bedroll@20,23")
	sim.replace_structures(sim.state.structures.filter(func(s: Dictionary) -> bool: return String(s.building_id) != "core:bedroll"))
	sim._sync_structure_navigation()
	check(row(sim.get_npc_household_status(NPC),"sleep").status == "missing", "Destroyed assigned sleeping place is distinct from an unassigned one")
	sim = fixture()
	sim.set_player_position(Content.cell_center(22,22))
	sim.execute_furniture_command(Vector2i(22,21),"rest")
	check(row(sim.get_npc_household_status(NPC),"dining").status == "busy", "A real occupied table chair is reported as busy")
	sim.set_player_position(Content.cell_center(24,21))
	sim.state.minute_of_day = 12 * 60
	sim.execute_furniture_command(Vector2i(24,20),"toggle_light")
	check(row(sim.get_npc_household_status(NPC),"light").status == "dark", "Daytime feedback anticipates lack of evening light")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(row(restored.get_npc_household_status(NPC),"light").status == "dark", "Feedback derives from actual restored light state")
	check(sim.get_npc_household_status("mod:unknown").is_empty(), "Unknown resident query is safe")
	_test_room_diagnostics()
	_test_evening_choice()
	if failures == 0:
		print("PASS: household location, availability, actual food, occupied furniture, evening lighting and read-only feedback")
	quit(0 if failures == 0 else 1)

func _test_room_diagnostics() -> void:
	var sim = fixture()
	for x: int in range(40,46):
		for y: int in [40,45]:
			sim.add_structure({"building_id":"core:wood_door" if Vector2i(x,y) == Vector2i(42,45) else "core:wood_wall","cell":[x,y]})
	for y: int in range(41,45):
		for x: int in [40,45]:
			sim.add_structure({"building_id":"core:wood_wall","cell":[x,y]})
	var cells: Array = []
	for x: int in range(41,45):
		for y: int in range(41,45):
			cells.append([x,y])
	sim.state.room_assignments.append({"id":"core:feedback_room","room_type_id":"core:living_room","cells":cells})
	sim.notify_housing_changed(true)
	sim.add_structure({"building_id":"core:bedroll","cell":[41,43]})
	sim.add_structure({"building_id":"core:table","cell":[41,41]})
	sim.add_structure({"building_id":"core:torch","cell":[44,41]})
	sim.state.npcs[NPC].position = [Content.cell_center(42,44).x,Content.cell_center(42,44).y]
	sim._sync_structure_navigation()
	check(sim.assign_sleep_place(NPC,"core:bedroll@41,43").success, "Constructed room has a real assigned sleep place")
	sim.replace_structures(sim.state.structures.filter(func(s: Dictionary) -> bool: return s.cell != [44,41]))
	sim._sync_structure_navigation()
	var sleep: Dictionary = row(sim.get_npc_household_status(NPC),"sleep")
	check(sleep.status == "ready", "Missing room light is a comfort improvement and preserves usable sleeping foundation")
	sim.replace_structures(sim.state.structures.filter(func(s: Dictionary) -> bool: return s.cell != [40,43]))
	sim._sync_structure_navigation()
	check(row(sim.get_npc_household_status(NPC),"sleep").status == "room_open", "Broken room wall is explained separately from missing furniture")

func _test_evening_choice() -> void:
	var sim = fixture()
	sim.replace_structures([
		{"building_id":"core:table","cell":[20,21]},
		{"building_id":"core:chair","cell":[21,22]},
		{"building_id":"core:table","cell":[26,21]},
		{"building_id":"core:chair","cell":[27,22]},
		{"building_id":"core:torch","cell":[20,22]},
	])
	sim._sync_structure_navigation()
	sim.state.npcs[NPC].position = [Content.cell_center(27,23).x,Content.cell_center(27,23).y]
	check(sim.furniture.find_seat(sim,NPC,true).chair_cell == [27,22], "Daylight selection can use the nearest unlit seat")
	var before := JSON.stringify(sim.export_state())
	check(row(sim.get_npc_household_status(NPC),"light").status == "ready", "Evening feedback considers the lit seat NPC will prefer at night, without demanding an extra torch")
	check(JSON.stringify(sim.export_state()) == before, "Checking evening choice must not change the actual time")
