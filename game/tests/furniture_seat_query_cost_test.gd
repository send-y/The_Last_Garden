extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Fixture.create()
	for index: int in range(12):
		var x := 70 + index*3
		sim.add_structure({"building_id":"core:table","cell":[x,70]})
		sim.add_structure({"building_id":"core:chair","cell":[x,71]})
	sim._sync_structure_navigation()
	Trace.reset()
	Trace.enabled = true
	check(sim.furniture.find_seat(sim,Fixture.NPC,true).is_empty(),"Distant tables remain beyond the established dining range")
	check(int(Trace.counters.get("astar_calls",0)) == 0,"Dining search does not calculate paths to seats whose every approach exceeds the range limit")
	Trace.enabled = false
	sim.add_structure({"building_id":"core:table","cell":[42,33]})
	sim.add_structure({"building_id":"core:chair","cell":[41,33]})
	sim._sync_structure_navigation()
	var before: Dictionary = sim.export_state()
	var seat: Dictionary = sim.furniture.find_seat(sim,Fixture.NPC,true)
	check(seat.get("chair_cell",[]) == [41,33],"A usable nearby seat is still chosen among distant furniture")
	check(sim.export_state() == before,"Seat search keeps authoritative state unchanged")
	print("FURNITURE_SEAT_QUERY_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
