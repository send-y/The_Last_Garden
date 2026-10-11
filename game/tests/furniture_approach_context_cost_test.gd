extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
class ObservedWorld extends World:
	var position_reads: Dictionary = {}
	func get_npc_position(id: String, fallback: Vector2) -> Vector2:
		position_reads[id] = int(position_reads.get(id,0)) + 1
		return super.get_npc_position(id,fallback)
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture = Fixture.create()
	var sim := ObservedWorld.new(fixture.export_state())
	for i: int in range(8): sim.state.npcs["test:%d" % i] = {"active":true,"position":[3168.0,3168.0]}
	for building: Dictionary in [{"building_id":"core:table","cell":[42,31]},{"building_id":"core:chair","cell":[41,31]},{"building_id":"core:chair","cell":[44,31]},{"building_id":"core:chair","cell":[42,33]}]: sim.add_structure(building)
	sim._sync_structure_navigation()
	var before: Dictionary = sim.export_state()
	sim.position_reads.clear()
	var seat: Dictionary = sim.furniture.find_seat(sim,Fixture.NPC,true)
	check(not seat.is_empty(),"The resident chooses a real chair next to a table")
	for id: String in sim.position_reads:
		if id != Fixture.NPC: check(int(sim.position_reads[id]) <= 1,"Other resident positions are read once per complete seat search: " + id)
	check(sim.export_state() == before,"Seat occupancy context does not alter the authoritative world")
	var approach: Array = seat.target_cell
	sim.state.npcs["test:0"].position = [Content.cell_center(int(approach[0]),int(approach[1])).x,Content.cell_center(int(approach[0]),int(approach[1])).y]
	var next: Dictionary = sim.furniture.find_seat(sim,Fixture.NPC,true)
	check(not next.is_empty() and next.target_cell != approach,"The next query observes a newly occupied approach immediately")
	print("FURNITURE_APPROACH_CONTEXT_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
