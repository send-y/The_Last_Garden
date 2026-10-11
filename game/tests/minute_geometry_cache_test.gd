extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Housing := preload("res://src/housing/housing_system.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := Fixture.NPC
class CountingHousing extends Housing:
	var validations := 0
	func _validate_room(sim, room: Dictionary, boundaries: Dictionary, inside: Dictionary) -> bool:
		validations += 1
		return super._validate_room(sim,room,boundaries,inside)
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var sim = Fixture.create()
	sim.housing = CountingHousing.new()
	if not sim.housing.has_method("room_valid"):
		check(false,"Room validity must reuse the authoritative housing geometry cache")
		quit(1)
		return
	sim.housing.refresh(sim)
	var initial: int = sim.housing.validations
	check(initial == 1,"One validation builds the single room's initial geometry")
	for _query: int in range(10):
		check(sim.get_home_policy(NPC).may_furnish,"Cached room still permits its resident")
		sim.get_housing_rooms()
		sim.housing.home(sim,NPC)
	check(sim.housing.validations == initial,"Repeated reports do not repeat flood-fill validation")
	var snapshot: Dictionary = sim.export_state()
	sim.get_housing_rooms()
	check(sim.export_state() == snapshot,"Read-only geometry cache does not leak into saved world state")
	var place: Dictionary = sim.housing.place(sim,"core:bedroll@40,30")
	place.cell[0] = 1
	check(sim.housing.place(sim,"core:bedroll@40,30").cell[0] == 40,"Single-place reports are isolated copies")
	var home: Dictionary = sim.housing.home(sim,NPC)
	sim.set_player_position(Content.cell_center(int(home.target_cell[0]),int(home.target_cell[1])))
	var blocked: Dictionary = sim.housing.home(sim,NPC)
	check(not blocked.valid or blocked.target_cell != home.target_cell,"Actor obstruction is re-evaluated independently of cached geometry")
	check(sim.housing.validations == initial,"Actor movement does not invalidate room topology")
	sim.add_structure({"building_id":"core:wood_wall","cell":[41,30]})
	check(not sim.get_home_policy(NPC).may_furnish,"New wall invalidates stale room designation immediately")
	check(sim.housing.validations == initial+1,"Structure edit rebuilds room validity exactly once")
	sim.remove_structure(sim.state.structures.back())
	check(sim.get_home_policy(NPC).may_furnish,"Removing obstruction restores actual room validity")
	var before: int = sim.housing.validations
	sim.state.room_assignments[0].cells.pop_back()
	sim.notify_housing_changed(true)
	check(not sim.get_home_policy(NPC).may_furnish and sim.housing.validations == before+1,"Room boundary assignment edits invalidate cached geometry")
	if failures == 0: print("PASS: room topology reuse, live actor obstruction, structure/room edits and save isolation")
	quit(0 if failures == 0 else 1)
