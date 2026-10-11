extends SceneTree

const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func astar_calls() -> int:
	return int(Trace.snapshot().counters.get("astar_calls",0))

func run() -> void:
	var sim = Fixture.create()
	var npc: Dictionary = sim.state.npcs[Fixture.NPC]
	var before: Dictionary = sim.export_state()
	Trace.reset()
	Trace.enabled = true
	check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(42,32),"A resident uses the closest reachable side of the work target")
	check(astar_calls() > 0,"Initial approach is verified using real navigation")
	Trace.reset()
	for _query: int in range(20):
		check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(42,32),"An unchanged work target keeps its valid approach")
	check(astar_calls() == 0,"Unchanged resident/target/navigation must not run repeated AStar checks")
	check(sim.export_state() == before,"Work query results remain derived runtime data outside saves")
	npc.position = [Content.cell_center(42,33).x,Content.cell_center(42,33).y]
	Trace.reset()
	check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(43,33),"Movement to a new cell chooses the closest side in the original order")
	check(astar_calls() > 0,"A resident cell change revalidates navigation")
	sim.add_structure({"building_id":"core:wood_wall","cell":[43,33]})
	sim._sync_structure_navigation()
	Trace.reset()
	check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(42,32),"A new wall invalidates the previously selected approach")
	check(astar_calls() > 0,"Navigation rebuild cannot reuse a stale reachable cell")
	for cell: Vector2i in [Vector2i(43,31),Vector2i(44,32),Vector2i(42,32)]:
		sim.add_structure({"building_id":"core:wood_wall","cell":[cell.x,cell.y]})
	sim._sync_structure_navigation()
	check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(-1,-1),"A fully enclosed target has no approach")
	sim.remove_structure({"building_id":"core:wood_wall","cell":[43,33]})
	sim._sync_structure_navigation()
	check(Supply.work_cell(sim,npc,Vector2i(43,32)) == Vector2i(43,33),"Removing a wall retries a previously unreachable target")
	var fresh = Fixture.create()
	check(Supply.work_cell(fresh,fresh.state.npcs[Fixture.NPC],Vector2i(43,32)) == Vector2i(42,32),"Another world with equal revisions cannot inherit cached approaches")
	var loaded = World.new(fresh.export_state())
	check(Supply.work_cell(loaded,loaded.state.npcs[Fixture.NPC],Vector2i(43,32)) == Vector2i(42,32),"Loading computes valid approaches from the current world")
	Trace.enabled = false
	_test_paired_minutes()
	print("NPC_WORK_QUERY_CACHE: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_paired_minutes() -> void:
	var cached = Fixture.create()
	Fixture.stock(cached,100)
	cached.set_npc_work_enabled(Fixture.NPC,"build",true)
	var uncached = World.new(cached.export_state())
	uncached.work_queries.enabled = false
	for minute: int in range(240):
		for sim in [cached,uncached]:
			if minute == 20: sim.StockReserves.set_reserve(sim,"core:plank",100)
			if minute == 40: sim.StockReserves.set_reserve(sim,"core:plank",0)
			if minute == 60: sim.set_npc_work_enabled(Fixture.NPC,"build",false)
			if minute == 65: sim.set_npc_work_enabled(Fixture.NPC,"build",true)
			if minute == 90: sim.state.npcs[Fixture.NPC].needs.hunger = 35.0
			if minute == 100: sim.state.npcs[Fixture.NPC].needs.hunger = 100.0
			sim.advance_minutes(1)
		check(cached.export_state() == uncached.export_state(),"Cache preserves authoritative work, stocks, needs and RNG at minute %d" % (minute+1))
	check(not cached.state.npcs[Fixture.NPC].home_goals_completed.is_empty(),"Paired comparison actually completes an autonomous home project")
