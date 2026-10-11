extends SceneTree

const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Layout := preload("res://src/npc_work/home_furnishing_layout.gd")
const Catalog := preload("res://src/construction/building_catalog.gd")

class ObservedCatalog extends Catalog:
	var footprint_reads := 0
	var floor_reads := 0
	func get_footprint_cells(id: String, origin: Vector2i) -> Array[Vector2i]:
		footprint_reads += 1
		if is_floor(id): floor_reads += 1
		return super.get_footprint_cells(id,origin)

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sim = Fixture.create()
	for y: int in range(70,90):
		for x: int in range(70,90):
			sim.add_structure({"building_id":"core:wood_floor","cell":[x,y]})
	var catalog := ObservedCatalog.new()
	sim.building_catalog = catalog
	var npc: Dictionary = sim.state.npcs[Fixture.NPC]
	var room := Layout.territory(sim,npc)
	catalog.footprint_reads = 0
	var furnishings := Layout.furnishings(sim,room)
	check(furnishings.size() == 26,"Home furnishings contain exactly the 25 local floors and bedroll")
	check(catalog.footprint_reads < 100,"Home report does not inspect hundreds of distant footprints")
	catalog.footprint_reads = 0
	check(Layout.can_place(sim,npc,"core:table",Vector2i(42,33)),"Table fits and keeps the actual home connected")
	check(catalog.footprint_reads < 100,"Furniture placement does not inspect distant structures")
	sim.add_structure({"building_id":"core:chair","cell":[42,33]})
	check(not Layout.can_place(sim,npc,"core:table",Vector2i(42,33)),"New local obstruction is immediately respected")
	check(sim.remove_structure({"building_id":"core:chair","cell":[42,33]}),"Fixture obstruction is removed through mutation API")
	check(Layout.can_place(sim,npc,"core:table",Vector2i(42,33)),"Removing the local obstruction restores placement")
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	catalog.footprint_reads = 0
	catalog.floor_reads = 0
	var before: Dictionary = sim.export_state()
	check(Layout.choose_cell(sim,npc,"core:chair",rng) == Vector2i(-1,-1),"A chair without a table has no usable position")
	check(catalog.footprint_reads < 100,"Choosing among room cells gathers furniture footprints once, not once per rejected candidate")
	check(catalog.floor_reads == 0,"Furniture search does not process floor tiles as furniture")
	check(sim.export_state() == before,"Placement search does not mutate the world")
	sim.add_structure({"building_id":"core:table","cell":[42,33]})
	sim._sync_structure_navigation()
	rng.seed = 19
	var chosen := Layout.choose_cell(sim,npc,"core:chair",rng)
	check(chosen != Vector2i(-1,-1) and Layout.can_place(sim,npc,"core:chair",chosen),"A freshly added table immediately permits a usable adjacent chair")
	sim.remove_structure({"building_id":"core:table","cell":[42,33]})
	sim._sync_structure_navigation()
	rng.seed = 19
	check(Layout.choose_cell(sim,npc,"core:chair",rng) == Vector2i(-1,-1),"A subsequent search cannot reuse furniture from a removed table")
	sim.add_structure({"building_id":"core:table","cell":[44,34]})
	check(Layout.furnishings(sim,room).size() == 26,"Furniture crossing the room boundary is not counted as fully inside")
	print("LOCAL_HOME_LAYOUT_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
