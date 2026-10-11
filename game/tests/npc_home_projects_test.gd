extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const NPC := Fixture.NPC
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func fixture() -> World:
	return Fixture.create()

func _run() -> void:
	var sim = fixture()
	check(sim.has_method("get_npc_personal_goal"), "NPC must have a persistent self-chosen home project query")
	if not sim.has_method("get_npc_personal_goal"):
		quit(1)
		return
	_test_lab_scenario()
	_test_choice_and_materials()
	_test_completion_and_reload()
	_test_authority_and_defer()
	_test_safety()
	_test_interrupt_and_cancel()
	_test_existing_home_and_light()
	_test_shared_room()
	_test_adopted_cancellation_and_other_worker()
	_test_player_does_not_block_home()
	if failures == 0:
		print("PASS: NPC home projects, real materials, safe layout, needs, refusal and deterministic persistence")
	quit(0 if failures == 0 else 1)

func stock(sim, amount: int) -> void:
	Fixture.stock(sim, amount)

func _test_lab_scenario() -> void:
	var result: Dictionary = Scenarios.build(&"resident_homes")
	check(String(Scenarios.get_definition(&"resident_homes").label) == "Дома жителей и защищённый запас", "Resident-homes scenario has a readable Russian label in the selector")
	check(bool(result.get("success", false)), "Playable resident-homes scenario is available through the scenario registry")
	if not bool(result.get("success", false)): return
	var sim = result.simulation
	var residents: Array[String] = []
	for id: String in sim.state.npcs:
		if id.begins_with("core:resident_"): residents.append(id)
	check(residents.size() == 2, "Resident-homes scenario creates two actual procedural residents")
	for id: String in residents:
		check(sim.get_character_home(id).valid and sim.get_home_policy(id).mode == "personal", "Scenario residents have separate valid bare personal homes")
	var before: Array = sim.get_stock_reserve_report()
	check(not before.is_empty(), "Scenario exposes physical common warehouse stock")
	var initial_planks: Dictionary = {}
	for entry: Dictionary in before:
		if entry.item_id == "core:plank": initial_planks = entry
	check(not initial_planks.is_empty() and int(initial_planks.stock) == 70 and int(initial_planks.reserved) == 35 and int(initial_planks.available) == 35,
		"Scenario starts with 70 real planks, 35 protected and 35 available for personal projects")
	sim.advance_minutes(1)
	var has_goal := false
	var has_expansion := false
	for id: String in residents:
		var report: Dictionary = sim.get_npc_personal_goal(id)
		has_goal = has_goal or not report.goal.is_empty()
		has_expansion = has_expansion or not report.expansion.is_empty()
	check(has_goal and has_expansion, "Playable scenario immediately demonstrates furnishing and a cramped-home expansion request")
	var plank_report: Dictionary = {}
	for entry: Dictionary in sim.get_stock_reserve_report():
		if entry.item_id == "core:plank": plank_report = entry
	check(not plank_report.is_empty() and int(plank_report.reserved) == 35, "Scenario keeps a configured protected plank reserve")
	sim.advance_minutes(100)
	var completed := false
	for id: String in residents: completed = completed or not sim.get_npc_personal_goal(id).completed.is_empty()
	check(completed, "Scenario resident physically completes furniture from the reachable warehouse")
	for entry: Dictionary in sim.get_stock_reserve_report():
		if entry.item_id == "core:plank":
			check(int(entry.stock) >= 35, "Playing the scenario keeps the protected stock physically in the warehouse")

func _test_choice_and_materials() -> void:
	var sim = fixture()
	sim.advance_minutes(2)
	check(sim.get_npc_personal_goal(NPC).get("goal",{}).is_empty(),"No unpermitted furnishings")
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(1)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	check(not report.goal.is_empty() and not String(report.goal.reason_key).is_empty(),"Resident notices a need and explains a stable project")
	check(String(report.status) == "materials" and not report.missing.is_empty(),"Missing real warehouse material is explained")
	var selected: Dictionary = report.goal.duplicate(true)
	sim.advance_minutes(35)
	check(sim.get_npc_personal_goal(NPC).goal.cell == selected.cell,"Waiting does not teleport or replace the project")
	check(sim.state.blueprints.is_empty(),"Absent materials do not create speculative blueprints")
	var before := JSON.stringify(sim.export_state())
	sim.get_npc_personal_goal(NPC)
	check(JSON.stringify(sim.export_state()) == before,"Goal query is read-only")
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.needs.hunger = 30.0
	check(sim.get_npc_personal_goal(NPC).status == "needs","Food and rest explain project interruption")

func _test_completion_and_reload() -> void:
	var sim = fixture()
	stock(sim,45)
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(7)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	check(not report.goal.is_empty() and not sim.state.blueprints.is_empty(),"Resident places a personal household blueprint")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	if restored.get_npc_personal_goal(NPC) != report: print("Reload goal differs: ",report," / ",restored.get_npc_personal_goal(NPC))
	check(restored.get_npc_personal_goal(NPC) == report,"Project survives mid-work disk-format reload")
	sim.advance_minutes(180)
	restored.advance_minutes(180)
	if JSON.stringify(sim.export_state()) != JSON.stringify(restored.export_state()):
		for key: String in sim.state:
			if JSON.stringify(sim.state[key]) != JSON.stringify(restored.state[key]): print("Different state section: ",key)
	check(JSON.stringify(sim.export_state()) == JSON.stringify(restored.export_state()),"Reload preserves random choices, materials and physical work")
	var completed: Array = sim.get_npc_personal_goal(NPC).completed
	check(not completed.is_empty(),"Finished project leaves a persistent result")
	var spent := 0
	for result: Dictionary in completed:
		spent += int(sim.building_catalog.get_material_cost(String(result.building_id)).get("core:plank",0))
	var remaining := 0
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == "core:plank": remaining += int(record.amount)
	for record: Dictionary in sim.state.blueprints:
		remaining += int(record.delivered_materials.get("core:plank",0))
	remaining += int(sim.state.npcs[NPC].work_cargo.get("core:plank",0))
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id) == "core:plank": remaining += int(drop.amount)
	check(remaining + spent == 45,"Construction spends exact real materials without creation or loss")
	check(sim.get_player_energy() == 100,"NPC project does not use player energy")

func _test_authority_and_defer() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(1)
	check(sim.defer_npc_personal_goal(NPC).success,"Player may decline a self-chosen project")
	sim.advance_minutes(40)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	check(report.declined.size() > 0,"Decline persists instead of immediate identical selection")
	check(not sim.execute_construction_command({"actor_id":NPC,"action_id":"core:place_blueprint","building_id":"core:wood_wall","cell":[43,31]}).success,"NPC cannot use home permission to place arbitrary walls")
	check(not sim.execute_construction_command({"actor_id":NPC,"action_id":"core:place_blueprint","building_id":"core:table","cell":[40,40]}).success,"NPC cannot decorate outside assigned home")
	sim.set_npc_work_enabled(NPC,"build",false)
	check(sim.get_npc_personal_goal(NPC).status == "permission","Revoked construction permission is explained")
	var old := sim.export_state()
	old.version = 31
	for key: String in ["home_goal","home_goals_completed","home_goals_declined","next_home_goal_minute"]:
		old.npcs[NPC].erase(key)
	var loaded = World.new(old)
	check(loaded.get_npc_personal_goal(NPC).completed.is_empty(),"Old saves get empty goal history")

func _test_safety() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled(NPC,"build",true)
	check(not sim.NpcHomeProjects.Layout.can_place(sim,sim.state.npcs[NPC],"core:torch",Vector2i(40,30)),"Autonomous furnishing protects assigned sleeping footprint")
	sim.state.storage_zones.append({"id":"core:storage_zone_0003","cells":[[44,34]]})
	check(not sim.NpcHomeProjects.Layout.can_place(sim,sim.state.npcs[NPC],"core:torch",Vector2i(44,34)),"Autonomous furnishing protects a warehouse cell inside the home")
	for x: int in range(40,45):
		if x == 42: continue
		sim.add_structure({"building_id":"core:wood_wall","cell":[x,32]})
		sim.state.room_assignments[0].cells.erase([x,32])
	sim.notify_housing_changed(true)
	sim.state.npcs[NPC].position = [Content.cell_center(42,33).x,Content.cell_center(42,33).y]
	sim._sync_structure_navigation()
	check(sim.get_character_home(NPC).valid and sim.is_navigation_cell_walkable(Vector2i(42,32)),"Corridor fixture retains a valid external home and a free choke point")
	check(not sim.NpcHomeProjects.Layout.can_place(sim,sim.state.npcs[NPC],"core:torch",Vector2i(42,32)),"Automatic furniture cannot close the only passage through home")

func _test_interrupt_and_cancel() -> void:
	var sim = fixture()
	stock(sim,35)
	sim.set_npc_work_enabled(NPC,"build",true)
	var npc: Dictionary = sim.state.npcs[NPC]
	for _minute: int in range(40):
		sim.advance_minutes(1)
		if not npc.work_cargo.is_empty(): break
	check(not npc.work_cargo.is_empty(),"Interruption fixture carries actual building material")
	var goal: Dictionary = npc.home_goal.duplicate(true)
	npc.needs.hunger = 30.0
	sim.advance_minutes(1)
	check(npc.home_goal.cell == goal.cell and String(npc.home_goal.status) == "pending","Hunger interrupts work but preserves intention")
	check(npc.work_cargo.is_empty(),"Interrupted project releases its real cargo")
	npc.needs.hunger = 100.0
	npc.needs.energy = 100.0
	npc.needs.restedness = 100.0
	sim.advance_minutes(180)
	check(not sim.get_npc_personal_goal(NPC).completed.is_empty(),"Resident resumes and finishes after needs are met")
	var cancelled = fixture()
	stock(cancelled,35)
	cancelled.set_npc_work_enabled(NPC,"build",true)
	cancelled.advance_minutes(1)
	var planned: Dictionary = cancelled.get_npc_personal_goal(NPC).goal
	check(not planned.is_empty(),"Cancellation fixture has a real pending resident project")
	if planned.is_empty(): return
	check(cancelled.execute_construction_command({"actor_id":"core:player","action_id":"core:cancel_blueprint","cell":planned.cell}).success,"Player cancels an actual resident blueprint")
	cancelled.advance_minutes(90)
	check(cancelled.get_npc_personal_goal(NPC).declined.has(String(planned.room_id)+"|"+String(planned.building_id)),"Player cancellation suppresses the same project persistently")

func _test_existing_home_and_light() -> void:
	var sim = fixture()
	sim.state.npcs[NPC].position = [Content.cell_center(43,33).x,Content.cell_center(43,33).y]
	for entity: Dictionary in [{"building_id":"core:table","cell":[42,31]},{"building_id":"core:chair","cell":[42,32]},{"building_id":"core:torch","cell":[44,30],"lit":true}]:
		sim.add_structure(entity)
	sim._sync_structure_navigation()
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(1)
	check(sim.get_npc_personal_goal(NPC).goal.is_empty(),"Already furnished home does not spawn redundant furniture")
	var torch: Dictionary = sim.state.structures.back()
	sim.set_structure_state(torch,"lit",false)
	# A floor must not hide the actual furniture during result lookup.
	sim.replace_structures([{"building_id":"core:wood_floor","cell":[44,30]}] + sim.get_structures())
	sim.advance_minutes(35)
	var goal: Dictionary = sim.get_npc_personal_goal(NPC).goal
	check(not goal.is_empty() and String(goal.action) == "light","An existing off torch becomes a switching goal, not a new build")
	sim.advance_minutes(45)
	check(bool(sim.structure_index.of_type("core:torch")[0].lit) and not sim.get_npc_personal_goal(NPC).completed.is_empty(),"Resident walks to and switches on the real torch above its floor")
	check(sim.state.blueprints.is_empty(),"Switching a light requires no invented materials or duplicate torch")

func _test_shared_room() -> void:
	var sim = Fixture.create(true)
	var id := ""
	for candidate: String in sim.state.npcs:
		if candidate.begins_with("core:resident_"): id = candidate
	check(not id.is_empty() and sim.get_home_policy(NPC).mode == "shared", "Shared fixture uses a procedural housemate and explicit shared mode")
	if id.is_empty(): return
	stock(sim,45)
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.set_npc_work_enabled(id,"build",true)
	sim.advance_minutes(1)
	var first: Dictionary = sim.get_npc_personal_goal(NPC).goal
	var other: Dictionary = sim.get_npc_personal_goal(id).goal
	check(not first.is_empty() and not other.is_empty() and String(first.building_id) != String(other.building_id),"Residents in a shared room choose complementary projects without duplicate tables")

func _test_adopted_cancellation_and_other_worker() -> void:
	var sim = fixture()
	check(sim.execute_construction_command({"actor_id":"core:player","action_id":"core:place_blueprint","building_id":"core:table","cell":[40,33]}).success,"Player places a household project before initiative")
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(1)
	var npc: Dictionary = sim.state.npcs[NPC]
	var goal: Dictionary = npc.home_goal
	check(String(goal.building_id) == "core:table" and bool(goal.tracked) and not bool(goal.placed),"Resident adopts existing player blueprint without taking its ownership")
	check(sim.execute_construction_command({"actor_id":"core:player","action_id":"core:cancel_blueprint","cell":goal.cell}).success,"Player cancels adopted blueprint")
	sim.advance_minutes(40)
	check(npc.home_goals_declined.has(String(goal.room_id)+"|core:table"),"Cancelled adopted blueprint is not recreated")
	var guarded = fixture()
	stock(guarded,35)
	guarded.set_npc_work_enabled(NPC,"build",true)
	guarded.advance_minutes(1)
	var project: Dictionary = guarded.get_npc_personal_goal(NPC).goal
	check(not project.is_empty(),"Completion guard fixture creates an actual personal project")
	if project.is_empty(): return
	var blueprint: Dictionary = guarded._find_blueprint(project.cell)
	check(not blueprint.is_empty(),"Completion guard fixture has a real blueprint")
	if blueprint.is_empty(): return
	# Another new blueprint makes the personal placement unsafe without deleting it.
	var footprint: Array[Vector2i] = guarded.building_catalog.get_footprint_cells(String(project.building_id),Vector2i(int(project.cell[0]),int(project.cell[1])))
	var blocked := footprint[0]
	guarded.state.blueprints.append({"building_id":"core:wood_wall","cell":[blocked.x,blocked.y],"required_materials":{"core:plank":30},"delivered_materials":{},"required_work_minutes":25,"work_progress_minutes":0})
	blueprint.delivered_materials = blueprint.required_materials.duplicate()
	var before := int(blueprint.work_progress_minutes)
	guarded.state.npcs["future:resident"] = {"id":"future:resident","active":true,"home_goal":{"building_id":"core:table"}}
	check(not guarded._advance_blueprint_work(project.cell,"core:other_worker").changed and int(blueprint.work_progress_minutes) == before,"A different NPC cannot bypass original home-project completion safety")

func _test_player_does_not_block_home() -> void:
	var sim = fixture()
	sim.set_npc_work_enabled(NPC,"build",true)
	sim.advance_minutes(1)
	var goal: Dictionary = sim.get_npc_personal_goal(NPC).goal.duplicate(true)
	check(not goal.is_empty(),"Temporary blockage fixture starts with a remembered project")
	if goal.is_empty(): return
	# Reduce the bed's reachable edges to one without changing its ownership.
	for cell: Array in [[40,31],[41,31]]:
		sim.add_structure({"building_id":"core:wood_wall","cell":cell})
		sim.state.room_assignments[0].cells.erase(cell)
	sim.notify_housing_changed(true)
	sim._sync_structure_navigation()
	sim.set_player_position(Content.cell_center(42,30))
	check(sim.get_character_home(NPC).valid,"Player does not block the only bed approach under nonblocking character movement")
	sim.advance_minutes(35)
	check(sim.state.npcs[NPC].home_goal.cell == goal.cell and String(sim.state.npcs[NPC].home_goal.status) == "pending" and sim.state.npcs[NPC].home_goals_declined.is_empty(),"Temporary obstruction cannot permanently blacklist a remembered project")
	sim.set_player_position(Content.cell_center(43,34))
	check(sim.get_character_home(NPC).valid,"Assigned place stays reachable after player moves")
