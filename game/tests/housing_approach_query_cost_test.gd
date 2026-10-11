extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Catalog := preload("res://src/construction/building_catalog.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func calls() -> int: return int(Trace.snapshot().counters.get("astar_calls",0))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Fixture.create()
	var before: Dictionary = sim.export_state()
	Trace.reset()
	Trace.enabled = true
	var initial: Dictionary = sim.housing.home(sim,Fixture.NPC)
	check(bool(initial.valid),"An assigned resident has a real reachable sleep approach")
	Trace.reset()
	for i: int in range(20): check(sim.housing.home(sim,Fixture.NPC) == initial,"Repeated housing profile preserves all current values")
	check(calls() == 0,"An unchanged sleep approach avoids repeated AStar searches")
	check(sim.export_state() == before,"Approach queries never add runtime caches to authority or saves")
	initial.target_cell[0] = 99
	check(sim.housing.home(sim,Fixture.NPC).target_cell[0] != 99,"Returned housing profiles remain isolated")
	sim.state.npcs[Fixture.NPC].position = [Content.cell_center(42,33).x,Content.cell_center(42,33).y]
	Trace.reset()
	check(bool(sim.housing.home(sim,Fixture.NPC).valid) and calls() > 0,"A resident cell change rechecks the sleep approach")
	var old: Array = sim.housing.home(sim,Fixture.NPC).target_cell
	sim.set_player_position(Content.cell_center(int(old[0]),int(old[1])))
	Trace.reset()
	check(sim.housing.home(sim,Fixture.NPC).target_cell != old and calls() > 0,"Moving the player onto an approach invalidates it")
	var blocked: Array = sim.housing.home(sim,Fixture.NPC).target_cell
	sim.add_structure({"building_id":"core:wood_wall","cell":blocked})
	sim._sync_structure_navigation()
	Trace.reset()
	check(not bool(sim.housing.home(sim,Fixture.NPC).valid),"A wall at the remaining side makes the assigned place unavailable")
	sim.remove_structure({"building_id":"core:wood_wall","cell":blocked})
	sim._sync_structure_navigation()
	check(bool(sim.housing.home(sim,Fixture.NPC).valid),"Removing the obstruction rechecks a previously unavailable place")
	var fresh = Fixture.create()
	var place: Dictionary = fresh.housing.place(fresh,String(fresh.state.sleep_assignments[Fixture.NPC]))
	var expected: Dictionary = fresh.housing.home(fresh,Fixture.NPC)
	fresh.housing = sim.housing
	Trace.reset()
	check(fresh.housing.approach(fresh,Fixture.NPC,place) == Vector2i(int(expected.target_cell[0]),int(expected.target_cell[1])) and calls() > 0,"A different navigator with equal revision numbers cannot inherit approaches")
	var rooms: Array = fresh.state.room_assignments[0].cells
	rooms.erase(expected.target_cell)
	fresh.notify_housing_changed(true)
	Trace.reset()
	check(fresh.housing.approach(fresh,Fixture.NPC,place) != Vector2i(int(expected.target_cell[0]),int(expected.target_cell[1])) and calls() > 0,"Changing room cells invalidates approach containment without a navigation edit")
	rooms.append(expected.target_cell.duplicate())
	fresh.notify_housing_changed(true)
	check(fresh.housing.approach(fresh,Fixture.NPC,place) == Vector2i(int(expected.target_cell[0]),int(expected.target_cell[1])),"Restoring room cells restores the original approach order")
	fresh.building_catalog = Catalog.new()
	Trace.reset()
	check(fresh.housing.approach(fresh,Fixture.NPC,place) == Vector2i(int(expected.target_cell[0]),int(expected.target_cell[1])) and calls() > 0,"Replacing the footprint catalog cannot reuse old approach queries")
	Trace.enabled = false
	var cached = Fixture.create()
	Fixture.stock(cached,100)
	cached.set_npc_work_enabled(Fixture.NPC,"build",true)
	var reference = World.new(cached.export_state())
	reference.housing.approach_cache_enabled = false
	for minute: int in range(240):
		for actual in [cached,reference]:
			if minute == 20: actual.StockReserves.set_reserve(actual,"core:plank",100)
			if minute == 40: actual.StockReserves.set_reserve(actual,"core:plank",0)
			if minute == 60: actual.set_npc_work_enabled(Fixture.NPC,"build",false)
			if minute == 65: actual.set_npc_work_enabled(Fixture.NPC,"build",true)
			if minute == 90: actual.state.npcs[Fixture.NPC].needs.hunger = 35.0
			if minute == 100: actual.state.npcs[Fixture.NPC].needs.hunger = 100.0
			actual.advance_minutes(1)
		if cached.export_state() != reference.export_state():
			check(false,"Complete authority matches uncached approaches at minute %d" % (minute+1))
			break
	print("HOUSING_APPROACH_QUERY_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
