extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := Fixture.NPC
const BENCH := Vector2i(36,34)
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func fixture(wood: int = 10, bench: bool = true, shared: bool = false):
	var sim = Fixture.create(shared)
	if bench: sim.state.structures.append({"building_id":"core:workbench","cell":[BENCH.x,BENCH.y],"stage_id":"core:complete"})
	sim._sync_structure_navigation()
	var npc: Dictionary = sim.state.npcs[NPC]
	var old: Array = npc.position.duplicate()
	npc.position = [1200.0,1072.0]
	check(Supply.store(sim,npc,Vector2i(37,32),"core:wood",wood) == wood,"Fixture stores real wood on communal warehouse")
	npc.position = old
	sim.set_npc_work_enabled(NPC,"build",true)
	npc.home_goal = sim.NpcHomeProjects.clean_goal({"building_id":"core:torch","cell":[43,34],"room_id":Fixture.ROOM,"place_id":"core:bedroll@40,30"})
	return sim
func run() -> void:
	var sim = fixture()
	sim.set_stock_reserve("core:wood",5)
	sim.advance_minutes(120)
	check(sim._find_structure([43,34]).get("building_id","") == "core:torch","Resident must make planks from real wood and finish its home project without player crafting")
	check(sim.StockReserves.total(sim,"core:wood") == 5,"One five-wood batch must preserve protected wood")
	check(sim.state.inventory.get("core:plank",0) == 0,"NPC production must not use player's inventory")
	if not ResourceLoader.exists("res://src/npc_work/npc_home_production.gd"):
		print("NPC_HOME_PRODUCTION: %d failures" % failures)
		quit(1)
		return
	test_waiting()
	test_save_and_interrupt()
	test_busy_and_revocation()
	test_multiple_batches_and_workers()
	test_stale_input_and_cancelled_blueprint()
	test_adopted_plan_and_player_recovery()
	print("NPC_HOME_PRODUCTION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func mid_work():
	var sim = fixture()
	for i: int in range(80):
		sim.advance_minutes(1)
		var project: Dictionary = sim._find_crafting_project([BENCH.x,BENCH.y])
		if project.get("owner_id","") == NPC and int(project.work_progress_minutes) > 0: return sim
	check(false,"Resident must reach bench and begin timed crafting")
	return sim
func test_waiting() -> void:
	var sim = fixture(5)
	sim.set_stock_reserve("core:wood",5)
	sim.advance_minutes(3)
	check(sim.StockReserves.total(sim,"core:wood") == 5 and sim.state.crafting_projects.is_empty(),"Protected wood must not become crafting inputs")
	check(sim.get_npc_personal_goal(NPC).production.reason == "wood_reserve","Goal explains protected input wood")
	sim = fixture(10,false)
	sim.advance_minutes(1)
	check(sim.get_npc_personal_goal(NPC).production.reason == "station","Missing workshop must be explained")
func test_save_and_interrupt() -> void:
	var sim = mid_work()
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(sim.export_state() == restored.export_state(),"Job, station ownership, inputs and work progress survive JSON reload")
	sim.advance_minutes(60)
	restored.advance_minutes(60)
	check(sim.export_state() == restored.export_state(),"Reload midway through production must continue deterministically")
	check(sim._find_structure([43,34]).get("building_id","") == "core:torch","Resumed production finishes the intended furniture")
	sim = mid_work()
	var progress: int = sim._find_crafting_project([BENCH.x,BENCH.y]).work_progress_minutes
	sim.state.npcs[NPC].needs.hunger = 1.0
	sim.advance_minutes(1)
	check(sim._find_crafting_project([BENCH.x,BENCH.y]).work_progress_minutes == progress,"Urgent hunger interrupts bench work without losing progress")
	sim.state.npcs[NPC].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	sim.advance_minutes(65)
	check(sim._find_structure([43,34]).get("building_id","") == "core:torch","Resident resumes reserved inputs after meeting needs")
	check(sim.StockReserves.total(sim,"core:wood") == 5,"Interrupted batch must not consume input twice")
func test_busy_and_revocation() -> void:
	var sim = fixture()
	sim.state.inventory["core:wood"] = 5
	check(sim._start_crafting_project([BENCH.x,BENCH.y],"core:workbench","core:saw_planks").success,"Player reserves a real workbench project")
	sim.advance_minutes(2)
	check(sim._find_crafting_project([BENCH.x,BENCH.y]).work_progress_minutes == 0,"Resident must not advance or adopt player's project")
	check(sim.StockReserves.total(sim,"core:wood") == 10,"Busy station must not withdraw communal input wood")
	check(sim.get_npc_personal_goal(NPC).production.reason == "busy","Occupied workshop must be explained")
	sim = mid_work()
	sim.set_npc_work_enabled(NPC,"build",false)
	sim.advance_minutes(1)
	var project: Dictionary = sim._find_crafting_project([BENCH.x,BENCH.y])
	check(not project.is_empty() and not project.has("owner_id"),"Revoked permission releases station while preserving unfinished work and inputs")
	check(project.reserved_inputs.get("core:wood",0) == 5,"Cancelled home authority must preserve reserved wood")

func test_multiple_batches_and_workers() -> void:
	var sim = fixture(20)
	sim.set_stock_reserve("core:wood",5)
	sim.state.npcs[NPC].home_goal = sim.NpcHomeProjects.clean_goal({"building_id":"core:table","cell":[43,34],"room_id":Fixture.ROOM,"place_id":"core:bedroll@40,30"})
	sim.advance_minutes(240)
	check(sim._find_structure([43,34]).get("building_id","") == "core:table","Resident must manufacture successive batches for a thirty-plank table")
	check(sim.StockReserves.total(sim,"core:wood") == 5,"Three batches consume exactly fifteen real wood")
	sim = fixture(10,true,true)
	var second := ""
	for id: String in sim.state.npcs:
		if id != NPC and bool(sim.state.npcs[id].active): second = id
	check(not second.is_empty(),"Shared fixture provides a second real worker")
	if second.is_empty(): return
	sim.set_npc_work_enabled(second,"build",true)
	sim.state.npcs[second].home_goal = sim.NpcHomeProjects.clean_goal({"building_id":"core:torch","cell":[40,34],"room_id":Fixture.ROOM,"place_id":"core:bedroll@43,33"})
	sim.NpcPracticalWork.prepare(sim)
	var first_claim: bool = sim.state.npcs[NPC].initiative_job.get("station_cell",[]) == [BENCH.x,BENCH.y]
	var second_claim: bool = sim.state.npcs[second].initiative_job.get("station_cell",[]) == [BENCH.x,BENCH.y]
	check(first_claim != second_claim,"Exactly one eligible worker reserves station before withdrawing input")
	var waiting: String = second if first_claim else NPC
	check(sim.state.npcs[waiting].initiative_job.is_empty(),"Other worker must wait for the same workshop")
	check(sim.get_npc_personal_goal(waiting).production.reason == "busy","Waiting worker identifies workshop contention")
	check(sim.StockReserves.total(sim,"core:wood") == 10,"Planning station contention does not spend wood")
	sim = mid_work()
	var project: Dictionary = sim._find_crafting_project([BENCH.x,BENCH.y])
	var progress: int = project.work_progress_minutes
	sim.set_player_position(Content.cell_center(BENCH.x,BENCH.y+1))
	check(not sim._advance_crafting_project([BENCH.x,BENCH.y],Content.cell_center(BENCH.x,BENCH.y)).success,"Player must not race a resident's reserved project")
	check(project.work_progress_minutes == progress,"Rejected concurrent work must not advance output")

func test_stale_input_and_cancelled_blueprint() -> void:
	var sim = fixture()
	var contexts: Dictionary = sim.NpcPracticalWork.prepare(sim)
	var context: Dictionary = contexts.get(NPC,{})
	check(not context.is_empty(),"Worker has a physical warehouse trip")
	if not context.is_empty():
		sim.state.npcs[NPC].position = [Content.cell_center(int(context.target_cell[0]),int(context.target_cell[1])).x,Content.cell_center(int(context.target_cell[0]),int(context.target_cell[1])).y]
		sim.set_stock_reserve("core:wood",10)
		check(not sim.NpcPracticalWork.fulfil(sim,{"npc_id":NPC,"context":context}),"Withdrawal must recheck changed reserve even with a stale context")
		check(sim.StockReserves.total(sim,"core:wood") == 10,"Stale request must preserve newly protected input")
	sim = mid_work()
	var goal: Dictionary = sim.state.npcs[NPC].home_goal
	var Command := preload("res://src/construction/construction_command.gd")
	check(sim.execute_construction_command(Command.cancel_blueprint(Vector2i(int(goal.cell[0]),int(goal.cell[1])))).success,"Player removes intended furniture blueprint")
	sim.advance_minutes(1)
	check(not sim._find_crafting_project([BENCH.x,BENCH.y]).has("owner_id"),"Removed blueprint releases station ownership without deleting paid work")
	var state: Dictionary = sim.export_state()
	state.npcs[NPC].initiative_job = {"kind":"build","phase":"craft","cell":[43,34],"station_cell":["bad",true],"recipe_id":"core:saw_planks"}
	var restored = World.new(state)
	check(restored.state.npcs[NPC].initiative_job.is_empty(),"Malformed saved station cells normalize safely")

func test_adopted_plan_and_player_recovery() -> void:
	var sim = fixture()
	var Command := preload("res://src/construction/construction_command.gd")
	check(sim.execute_construction_command(Command.place_blueprint(Vector2i(43,34),"core:torch")).success,"Player places an unfunded plan in resident's house")
	sim.state.npcs[NPC].home_goal.tracked = true
	sim.advance_minutes(120)
	check(sim._find_structure([43,34]).get("building_id","") == "core:torch","Resident may produce planks for an adopted player plan in its own home")
	sim = mid_work()
	sim.set_npc_work_enabled(NPC,"build",false)
	sim.advance_minutes(1)
	sim.set_player_position(Content.cell_center(BENCH.x,BENCH.y+1))
	for i: int in range(8):
		if sim._find_crafting_project([BENCH.x,BENCH.y]).is_empty(): break
		check(sim._advance_crafting_project([BENCH.x,BENCH.y],Content.cell_center(BENCH.x,BENCH.y)).success,"Player can finish released NPC work using already reserved input")
	var count := 0
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id) == "core:plank": count += int(drop.amount)
	check(count == 10 and sim.state.crafting_projects.is_empty(),"Released paid project produces exactly one batch without new input")
