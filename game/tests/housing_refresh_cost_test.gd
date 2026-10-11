extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Catalog := preload("res://src/construction/building_catalog.gd")

class ObservedCatalog extends Catalog:
	var definitions := 0
	var floor_definitions := 0
	func get_definition(id: String) -> Dictionary:
		definitions += 1
		if id == "core:wood_floor": floor_definitions += 1
		return super.get_definition(id)

var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var sim = Fixture.create()
	for y: int in range(70,90):
		for x: int in range(70,90):
			sim.add_structure({"building_id":"core:wood_floor","cell":[x,y]})
	var catalog := ObservedCatalog.new()
	sim.building_catalog = catalog
	check(bool(sim.housing.place(sim,"core:bedroll@40,30").valid),"Distant construction keeps the closed home valid")
	check(catalog.definitions < 300,"Housing refresh does not repeatedly inspect distant floors")
	check(catalog.floor_definitions == 0,"Housing furniture requirements do not inspect floor definitions that room validation ignores")
	var wall := {"building_id":"core:wood_wall","cell":[40,29]}
	check(sim.remove_structure(wall),"Boundary wall can be removed")
	check(not bool(sim.housing.place(sim,"core:bedroll@40,30").valid),"Opening the boundary invalidates assigned housing")
	check(sim.add_structure(wall),"Boundary wall can be restored")
	check(bool(sim.housing.place(sim,"core:bedroll@40,30").valid),"Restoring wall restores housing")
	print("HOUSING_REFRESH_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
