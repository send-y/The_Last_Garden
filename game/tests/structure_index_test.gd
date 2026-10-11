extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
const Opening := preload("res://src/simulation/systems/opening_scenario.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var sim = Fixture.create()
	Trace.reset()
	Trace.enabled = true
	for _query: int in range(5):
		check(sim.get_home_policy(Fixture.NPC).may_furnish, "Repeated home query preserves permission")
		check(sim.housing.place(sim,"core:bedroll@40,30").valid, "Repeated home query preserves actual bed")
	Trace.enabled = false
	var measured: Dictionary = Trace.snapshot()
	check(int(measured.spans.get("housing.geometry_compare",{}).get("calls",0)) == 0,
		"Unchanged home queries perform zero deep structure comparisons")
	check(sim.has_method("add_structure"), "Centralized structure mutation API exists")
	if not sim.has_method("add_structure"):
		print("STRUCTURE_INDEX: %d failures" % failures)
		quit(1)
		return
	var index = sim.structure_index
	var cell := Vector2i(41,31)
	check(index.has_floor(cell), "Primitive floor query reads the full indexed footprint")
	var revision: int = index.revision
	check(sim.add_structure({"building_id":"core:table","cell":[41,31]}), "Trusted structure insertion succeeds")
	check(index.revision == revision+1 and index.at(cell).size() == 2, "Floor and furniture coexist in indexed cell")
	check(index.at(Vector2i(42,31)).size() == 2, "Every furniture footprint cell is indexed")
	var local_cells: Array[Vector2i] = [cell,Vector2i(42,31)]
	check(index.in_cells(local_cells,false) == index.of_type("core:table"),"Furniture-only query skips floors and deduplicates a multi-cell table")
	var copy: Array = index.at(cell)
	copy[1].cell[0] = 0
	check(index.at(cell)[1].cell[0] == 41, "Returned local records do not expose live state")
	var tables: Array = index.of_type("core:table")
	check(tables.size() == 1, "Type query finds the actual table")
	check(sim.remove_structure(tables[0]), "Removal accepts the authoritative structure key")
	check(index.has_floor(cell) and index.at(cell).size() == 1, "Removing furniture preserves floor")
	check(index.in_cells(local_cells,false).is_empty(),"Removing furniture leaves no stale furniture-only result")
	check(sim.debug_validate_structures().is_empty(), "Independent validator matches authoritative state")
	var torch := {"building_id":"core:torch","cell":[44,30],"lit":true}
	sim.add_structure(torch)
	var geometry: int = index.geometry_revision
	revision = index.revision
	check(not sim.set_structure_state(torch,"lit",true), "Same-value state update is a no-op")
	check(index.revision == revision, "No-op does not invalidate caches")
	check(sim.set_structure_state(torch,"lit",false), "Torch state update uses central API")
	check(index.geometry_revision == geometry and index.revision == revision+1, "Torch state preserves geometry version")
	# Intentional fault injection: this test must not silently repair an illegal write.
	for entry: Dictionary in sim.state.structures:
		if entry.building_id == "core:torch": entry.lit = true
	check(not sim.debug_validate_structures().is_empty(), "Independent snapshot catches shared-reference state mutation")
	_test_home_facts()
	_test_first_arrival()
	_test_reference()
	print("STRUCTURE_INDEX: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_home_facts() -> void:
	var sim = Fixture.create()
	var npc := Fixture.NPC
	check(sim.get_home_policy(npc).members == [npc],"Initial personal room contains its actual resident")
	var before: Dictionary = sim.export_state()
	Trace.reset()
	Trace.enabled = true
	for _query: int in range(20): sim.get_home_policy(npc)
	Trace.enabled = false
	check(Trace.snapshot().spans.get("housing.policy_rebuild",{}).get("calls",0) == 0,"Warm home queries do not rebuild membership")
	check(sim.export_state() == before,"Derived facts do not enter the save or mutate authoritative state")
	var revision: int = sim.housing_revision
	sim.set_home_mode(Fixture.ROOM,"personal")
	check(sim.housing_revision == revision,"Same home mode does not invalidate facts")
	sim.set_home_mode(Fixture.ROOM,"shared")
	sim.add_structure({"building_id":"core:bedroll","cell":[43,33]})
	check(sim.assign_sleep_place("core:player","core:bedroll@43,33").success,"Shared home accepts a second actual bed owner")
	check(sim.get_home_policy(npc).members.size() == 2,"Assignment immediately refreshes cached room membership")
	sim.assign_sleep_place("core:player","")
	check(sim.get_home_policy(npc).members == [npc],"Release immediately removes the former room member")
	sim.state.npcs[npc].residency = "visitor"
	check(not sim.get_home_policy(npc).may_furnish,"Live visitor status overrides cached room facts")
	sim.state.npcs[npc].residency = "resident"
	sim.set_npc_active(npc,false)
	check(sim.get_home_policy(npc).members.is_empty(),"Deactivation removes inactive occupants from membership")
	sim.set_npc_active(npc,true)
	check(sim.get_home_policy(npc).members == [npc],"Activation restores the current occupant")
	sim.add_structure({"building_id":"core:wood_wall","cell":[41,30]})
	var broken: Dictionary = sim.get_home_policy(npc)
	check(not broken.may_furnish and broken.members == [npc],"Damaged enclosure preserves identities while withdrawing permission")
	sim.remove_structure({"building_id":"core:wood_wall","cell":[41,30]})
	check(sim.get_home_policy(npc).may_furnish,"Removing obstruction restores permission")
	check(sim.debug_validate_structures().is_empty(),"Legal housing mutations preserve validator consistency")
	sim.state.room_assignments[0].cells.pop_back()
	check(not sim.debug_validate_structures().is_empty(),"Validator catches housing edits made without a version change")

func _test_first_arrival() -> void:
	var sim = Fixture.create()
	sim.set_npc_active(Fixture.NPC,false)
	sim.state.flags.first_night_complete = false
	sim.add_structure({"building_id":"core:bedroll","cell":[43,33]})
	check(sim.get_home_policy(Fixture.NPC).members.is_empty(),"Warm cache excludes inactive first neighbor")
	var revision: int = sim.housing_revision
	Opening._on_world_morning(sim,false)
	check(sim.housing_revision == revision+1,"First morning arrival invalidates housing exactly once")
	check(sim.get_home_policy(Fixture.NPC).members == [Fixture.NPC],"First arrival restores retained bed membership")
	check(not sim.assign_sleep_place("core:player","core:bedroll@43,33").success,"Arrived neighbor protects personal room from another occupant")
	check(sim.debug_validate_structures().is_empty(),"First arrival preserves independent housing snapshot")
	revision = sim.housing_revision
	Opening._on_world_morning(sim,false)
	check(sim.housing_revision == revision,"Repeated morning without arrival is a no-op for housing")

func _test_reference() -> void:
	var first = Fixture.create()
	var second = Fixture.create()
	first.add_structure({"building_id":"core:table","cell":[41,31]})
	second.add_structure({"building_id":"core:torch","cell":[41,31],"lit":true})
	check(first.structure_index.revision == second.structure_index.revision,"Two worlds can have matching revision numbers")
	check(first.structure_index.at(Vector2i(41,31)) != second.structure_index.at(Vector2i(41,31)),"Matching versions never share another world's index")
	_check_reference(first)
	_check_reference(second)
	first.remove_structure(first.get_structures()[0])
	first.remove_structure({"building_id":"core:table","cell":[41,31]})
	first.add_structure({"building_id":"core:bed","cell":[41,31]})
	_check_reference(first)

func _check_reference(sim) -> void:
	var by_cell := {}
	var by_type := {}
	var floor_cells := {}
	var occupied: Array[Vector2i] = []
	var linear: Array[Dictionary] = sim.get_structures()
	for record: Dictionary in linear:
		var id := String(record.building_id)
		if not by_type.has(id): by_type[id] = []
		by_type[id].append(record)
		for cell: Vector2i in sim.building_catalog.get_footprint_cells(id,Vector2i(int(record.cell[0]),int(record.cell[1]))):
			if not by_cell.has(cell):
				by_cell[cell] = []
				occupied.append(cell)
			by_cell[cell].append(record)
			if sim.building_catalog.is_floor(id): floor_cells[cell] = true
	for cell: Vector2i in by_cell:
		check(sim.structure_index.at(cell) == by_cell[cell],"Cell query equals independent linear reference including order and footprint")
		check(sim.structure_index.has_floor(cell) == floor_cells.has(cell),"Primitive floor query equals linear reference")
	for id: String in by_type:
		check(sim.structure_index.of_type(id) == by_type[id],"Type query equals independent linear reference after removal")
	occupied.reverse()
	occupied.append_array(occupied.duplicate())
	check(sim.structure_index.in_cells(occupied) == linear,"Cell union deduplicates in original array order even with reverse input")
	check(sim.structure_index.at(Vector2i(-5,-5)).is_empty() and not sim.structure_index.has_floor(Vector2i(-5,-5)),"Empty cell has no synthetic results")
	check(sim.structure_index.of_type("missing").is_empty(),"Unknown type returns an empty result")
	check(sim.debug_validate_structures().is_empty(),"Linear reference and independent snapshot agree")
