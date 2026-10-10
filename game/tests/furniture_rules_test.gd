extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
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
	state.elapsed_game_minutes = 2160
	state.flags.repair_stage = 2
	state.npcs["core:first_neighbor"].known = true
	state.npcs["core:first_neighbor"].personal_inventory = {"core:food":0}
	state.npcs["core:first_neighbor"].needs.hunger = 100.0
	state.structures.append({"building_id":"core:table","cell":[22,20]})
	state.structures.append({"building_id":"core:chair","cell":[22,21]})
	state.structures.append({"building_id":"core:torch","cell":[24,20]})
	state.inventory["core:carrot"] = 2
	return World.new(state)

func _run() -> void:
	var sim = fixture()
	check(sim.has_method("execute_furniture_command"), "Functional furniture commands must exist")
	if not sim.has_method("execute_furniture_command"):
		quit(1)
		return
	_test_player_and_light()
	_test_npc_meal_and_reload()
	_test_fallback_and_rest()
	_test_seated_hunger_and_access()
	_test_removed_table_and_light_walls()
	_test_light_preference_and_safe_exit()
	_test_direct_work_command()
	if failures == 0:
		print("PASS: furniture meals, real food transport, chair recovery, light, ownership, fallback and persistence")
	quit(0 if failures == 0 else 1)

func _test_player_and_light() -> void:
	var sim = fixture()
	sim.set_player_position(Content.cell_center(22,22))
	sim.state.player_energy = 10.0
	sim.state.player_needs.restedness = 30.0
	check(sim.execute_furniture_command(Vector2i(22,21),"rest").success, "Nearby chair supports physical rest")
	check(sim.get_player_energy() > 16.0 and sim.get_player_needs().restedness <= 30, "Chair rest improves energy without restoring sleep debt")
	check(sim.execute_furniture_command(Vector2i(22,20),"eat","core:carrot").success, "Player can eat a real carried product at a chair beside the table")
	check(sim.get_item_count("core:carrot") == 1, "Table meal consumes exactly one product")
	sim.set_player_position(Content.cell_center(32,32))
	check(not sim.execute_furniture_command(Vector2i(22,20),"eat","core:carrot").success and sim.get_item_count("core:carrot") == 1, "Remote table cannot consume food or seat player")
	sim.state.minute_of_day = 20 * 60
	check(sim.is_cell_lit(Vector2i(22,21)), "Enabled torch lights nearby furniture")
	sim.set_player_position(Content.cell_center(24,21))
	check(sim.execute_furniture_command(Vector2i(24,20),"toggle_light").success and not sim.is_cell_lit(Vector2i(22,21)), "Turning off torch changes authoritative lighting")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(not restored.is_cell_lit(Vector2i(22,21)), "Disabled torch survives save reload: " + str(restored.state.structures))
	check(restored.get_player_needs() == sim.get_player_needs(), "Lighting reload preserves physical state")

func _test_npc_meal_and_reload() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.position = [Content.cell_center(22,23).x,Content.cell_center(22,23).y]
	npc.needs.hunger = 30.0
	sim.state.storage_items.append({"placement_id":"core:furniture_food", "item_id":"core:carrot", "amount":1,"cell":[22,24],"rotated":false})
	var carried := false
	for minute: int in range(30):
		sim.advance_minutes(1)
		if not npc.meal_trip.is_empty():
			carried = true
			check(int(npc.personal_inventory.get("core:carrot",0)) == 1 and sim.get_storage_contents(Vector2i(22,24)).get("core:carrot",0) == 0, "NPC takes one real portion before walking to table")
			var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
			check(restored.state.npcs[npc.id].meal_trip == npc.meal_trip, "Transported meal survives save/reload")
			sim = restored
			npc = sim.state.npcs[npc.id]
			break
	check(carried, "Actual simulation contains a food transport phase")
	sim.advance_minutes(15)
	check(int(npc.personal_inventory.get("core:carrot",0)) == 0 and float(npc.needs.hunger) > 50, "Carried food is eaten once after arrival")
	var reasons: Array = sim.get_npc_psychology(String(npc.id)).reasons
	check(reasons.any(func(reason: Dictionary) -> bool: return String(reason.key) == "needs.reason.table_meal"), "Table meal adds an explained NPC comfort effect")

func _test_fallback_and_rest() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.personal_inventory = {"core:carrot":1}
	npc.needs.hunger = 30.0
	sim.set_player_position(Content.cell_center(22,22))
	sim.execute_furniture_command(Vector2i(22,21),"rest")
	sim.advance_minutes(35)
	check(int(npc.personal_inventory.get("core:carrot",0)) == 0, "Occupied chair does not prevent an ordinary meal")
	sim.set_player_position(Content.cell_center(30,30))
	npc.needs.hunger = 100.0
	npc.needs.energy = 10.0
	sim.advance_minutes(25)
	check(String(npc.activity_id) == "core:chair_resting" and float(npc.needs.energy) > 10, "Resident physically rests at a free chair during the day: " + str(npc))

func _test_seated_hunger_and_access() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	sim.set_player_position(Content.cell_center(30,30))
	npc.needs.energy = 10.0
	sim.advance_minutes(25)
	check(not sim.furniture.comfort(sim,String(npc.id)).is_empty(), "Low energy resident reaches an actual chair")
	npc.personal_inventory = {"core:carrot":1}
	npc.needs.hunger = 30.0
	sim.advance_minutes(1)
	check(int(npc.personal_inventory.get("core:carrot",0)) == 0 and float(npc.needs.hunger) > 50, "Hungry seated resident eats at the same chair without an unreachable solid-cell target")
	sim = fixture()
	sim.set_player_position(Content.cell_center(22,23))
	check(not sim.execute_furniture_command(Vector2i(22,21),"eat","core:carrot").success and sim.get_item_count("core:carrot") == 2, "Player must reach a cell directly beside the chair before eating")

func _test_removed_table_and_light_walls() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	sim.set_player_position(Content.cell_center(30,30))
	npc.position = [Content.cell_center(22,22).x,Content.cell_center(22,22).y]
	npc.personal_inventory = {"core:carrot":1}
	npc.needs.hunger = 30.0
	sim.advance_minutes(1)
	check(String(npc.activity_id) == "core:table_eating", "NPC sits for the table meal")
	sim.state.structures = sim.state.structures.filter(func(s: Dictionary) -> bool: return String(s.building_id) != "core:table")
	sim._sync_structure_navigation()
	sim.advance_minutes(1)
	check(String(npc.activity_id) != "core:table_eating" and npc.furniture_use.is_empty(), "Removed table releases an ongoing table use")
	sim.state.minute_of_day = 20 * 60
	sim.state.structures.append({"building_id":"core:torch","cell":[20,20]})
	check(sim.is_cell_lit(Vector2i(21,20)) and not sim.is_cell_lit(Vector2i(18,20)), "Static house wall blocks torch illumination on its other side")

func _test_light_preference_and_safe_exit() -> void:
	var sim = fixture()
	sim.state.structures = [
		{"building_id":"core:table","cell":[20,21]},
		{"building_id":"core:chair","cell":[21,22]},
		{"building_id":"core:table","cell":[26,21]},
		{"building_id":"core:chair","cell":[27,22]},
		{"building_id":"core:torch","cell":[20,22]},
	]
	sim._sync_structure_navigation()
	sim.state.minute_of_day = 20 * 60
	sim.set_player_position(Content.cell_center(24,24))
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.position = [Content.cell_center(27,23).x,Content.cell_center(27,23).y]
	check(sim.furniture.find_seat(sim,String(npc.id),true).chair_cell == [21,22], "Resident prefers reachable illuminated dining over a nearer dark seat")
	npc.position = [Content.cell_center(21,22).x,Content.cell_center(21,22).y]
	npc.furniture_target = [21,22]
	npc.furniture_use = {"chair_cell":[21,22],"kind":"rest","until":0,"approach":[21,23]}
	check(sim.get_npc_psychology(String(npc.id)).reasons.any(func(r: Dictionary) -> bool: return r.key == "needs.reason.lit_seat"), "NPC details explain comfort from an illuminated seat")
	sim.set_player_position(Content.cell_center(20,23))
	sim.execute_furniture_command(Vector2i(20,22),"toggle_light")
	check(sim.get_npc_psychology(String(npc.id)).reasons.any(func(r: Dictionary) -> bool: return r.key == "needs.reason.dark_seat"), "Disabling the light changes the explained NPC comfort")
	sim = fixture()
	sim.set_player_position(Content.cell_center(22,22))
	sim.execute_furniture_command(Vector2i(22,21),"rest")
	npc = sim.state.npcs["core:first_neighbor"]
	npc.position = [Content.cell_center(22,22).x,Content.cell_center(22,22).y]
	check(sim.leave_player_seat() and sim.get_player_position() != Content.cell_center(22,22) and sim.is_navigation_cell_walkable(sim._world_position_to_cell(sim.get_player_position())), "Leaving a chair chooses another exit when its original approach is occupied")

func _test_direct_work_command() -> void:
	var sim = fixture()
	sim.state.structures.append({"building_id":"core:workbench","cell":[23,21]})
	sim._sync_structure_navigation()
	sim.set_player_position(Content.cell_center(22,22))
	sim.execute_furniture_command(Vector2i(22,21),"rest")
	sim.state.inventory["core:wood"] = 10
	var command := preload("res://src/crafting/crafting_command.gd")
	check(sim.execute_crafting_command(command.start_project(Vector2i(23,21),"core:split_firewood")).success, "Direct crafting fixture reserves actual wood")
	check(sim.execute_crafting_command(command.work_project(Vector2i(23,21))).success and sim.state.player_furniture_use.is_empty(), "Direct simulation work command also stops chair recovery")
