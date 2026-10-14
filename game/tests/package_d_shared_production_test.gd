extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Command := preload("res://src/construction/construction_command.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const NPC := Fixture.NPC
const TARGET := Vector2i(35,33)
const BENCH := Vector2i(36,34)
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func fixture(bench: bool = true, wood: int = 15):
	var sim = Fixture.create()
	sim.set_home_mode(Fixture.ROOM,"settlement")
	if bench: sim.add_structure({"building_id":"core:workbench","cell":[BENCH.x,BENCH.y],"stage_id":"core:complete"})
	sim._sync_structure_navigation()
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.first_meeting_complete = true
	npc.position = [Content.cell_center(37,33).x,Content.cell_center(37,33).y]
	check(Supply.store(sim,npc,Vector2i(37,32),"core:wood",wood) == wood,"Real shared wood is stocked")
	sim.set_stock_reserve("core:wood",5)
	sim.set_player_position(Content.cell_center(TARGET.x,TARGET.y+1))
	check(bool(sim.execute_construction_command(Command.place_blueprint(TARGET,"core:wood_wall")).success),"Real communal wall blueprint exists")
	sim.set_player_position(Content.cell_center(37,33))
	sim.set_npc_work_enabled(NPC,"build",true)
	return sim
func run() -> void:
	var sim = fixture()
	var began := false
	for i: int in range(100):
		sim.advance_minutes(1)
		if not sim.state.crafting_projects.is_empty():
			began = true
			break
	check(began,"NPC starts real plank production for a communal wall without a personal home goal")
	if began:
		var loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
		sim.advance_minutes(180)
		loaded.advance_minutes(180)
		check(loaded.export_state() == sim.export_state(),"Shared production resumes deterministically after reload")
	else: sim.advance_minutes(180)
	check(String(sim._find_structure([TARGET.x,TARGET.y]).get("building_id","")) == "core:wood_wall","Made boards are delivered and communal wall is completed")
	check(sim.StockReserves.total(sim,"core:wood") == 5,"Two batches consume ten real wood and preserve protected five")
	check(sim.get_item_count("core:plank") == 0,"NPC never consumes or creates boards in player's backpack")
	var reserve = fixture(true,5)
	reserve.advance_minutes(60)
	check(reserve.state.crafting_projects.is_empty() and reserve.StockReserves.total(reserve,"core:wood") == 5,"Shared production respects protected wood")
	var absent = fixture(false)
	absent.advance_minutes(60)
	check(absent.state.crafting_projects.is_empty() and absent.StockReserves.total(absent,"core:wood") == 15,"Absent station never creates boards off screen")
	var cancelled = fixture()
	for i: int in range(100):
		cancelled.advance_minutes(1)
		if not cancelled.state.crafting_projects.is_empty(): break
	check(not cancelled.state.crafting_projects.is_empty(),"Cancellation fixture has paid production")
	if not cancelled.state.crafting_projects.is_empty():
		var project: Dictionary = cancelled.state.crafting_projects[0]
		var inputs: Dictionary = project.reserved_inputs.duplicate(true)
		var progress: int = project.work_progress_minutes
		cancelled.set_player_position(Content.cell_center(TARGET.x,TARGET.y+1))
		check(bool(cancelled.execute_construction_command(Command.cancel_blueprint(TARGET)).success),"Shared blueprint really cancelled")
		cancelled.advance_minutes(2)
		check(not project.has("owner_id") and project.reserved_inputs == inputs and int(project.work_progress_minutes) == progress,"Cancelled goal releases ownership but preserves paid inputs and progress")
	var competing = fixture(true,25)
	var generated: Dictionary = competing.create_generated_npc(94,Vector2i(42,32))
	var id := String(generated.npc_id)
	competing.arrive_npc(id,Vector2i(42,32))
	competing.state.npcs[id].known = true
	competing.state.npcs[id].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	competing.set_npc_work_enabled(id,"build",true)
	competing.set_player_position(Content.cell_center(35,36))
	check(bool(competing.execute_construction_command(Command.place_blueprint(Vector2i(35,35),"core:wood_wall")).success),"Second communal blueprint exists")
	competing.NpcPracticalWork.prepare(competing)
	var claims := 0
	for worker: Dictionary in competing.state.npcs.values():
		if worker.get("initiative_job",{}).get("station_cell",[]) == [BENCH.x,BENCH.y]: claims += 1
	check(claims == 1,"Two shared workers never simultaneously claim a single station")
	print("PACKAGE_D_SHARED_PRODUCTION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
