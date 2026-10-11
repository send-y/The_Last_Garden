extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Command := preload("res://src/construction/construction_command.gd")
const Catalog := preload("res://src/construction/building_catalog.gd")

class ObservedCatalog extends Catalog:
	var definitions := 0
	func get_definition(id: String) -> Dictionary:
		definitions += 1
		return super.get_definition(id)

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var sim = Fixture.create()
	for y: int in range(70,90):
		for x: int in range(70,90):
			sim.add_structure({"building_id":"core:wood_floor","cell":[x,y]})
	var catalog := ObservedCatalog.new()
	sim.building_catalog = catalog
	var target := Vector2i(41,32)
	var result: Dictionary = sim.execute_construction_command(Command.place_blueprint(target,"core:chair"))
	check(bool(result.success),"A furniture blueprint can share its cell with a floor")
	check(catalog.definitions < 80,"Placing a local project must not inspect distant structures")
	var blueprint: Dictionary = sim._find_blueprint([41,32])
	if blueprint.is_empty():
		print("Fixture placement failed: ",result)
		quit(1)
		return
	for item_id: String in blueprint.required_materials:
		blueprint.delivered_materials[item_id] = blueprint.required_materials[item_id]
	catalog.definitions = 0
	result = sim.execute_construction_command(Command.complete_blueprint(target))
	check(bool(result.success) and sim._find_blueprint([41,32]).is_empty(),"A supplied blueprint becomes a real structure")
	# Completion also synchronizes navigation; measure the overlap check
	# separately below so the known global navigation rebuild isn't mislabeled.
	catalog.definitions = 0
	result = sim.execute_construction_command(Command.place_blueprint(target,"core:chair"))
	check(not bool(result.success) and String(result.reason_id) == "core:occupied_cell","A completed same-layer structure rejects overlap immediately")
	check(catalog.definitions < 80,"Overlap rejection only inspects the actual target footprint")
	var floor_result: Dictionary = sim.execute_construction_command(Command.place_blueprint(Vector2i(40,30),"core:brick_floor"))
	check(not bool(floor_result.success) and String(floor_result.reason_id) == "core:occupied_cell","Replacing an existing floor without removal remains forbidden")
	print("CONSTRUCTION_QUERY_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
