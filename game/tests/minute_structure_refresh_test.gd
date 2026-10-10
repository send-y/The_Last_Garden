extends Node
const Main := preload("res://src/main/main.tscn")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Command := preload("res://src/construction/construction_command.gd")
var failures := 0
func check(condition: bool,message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func frames(count: int = 3) -> void:
	for _frame: int in range(count): await get_tree().process_frame
func identities(nodes: Array) -> Array[int]:
	var result: Array[int] = []
	for node: Node in nodes: result.append(node.get_instance_id())
	return result
func _ready() -> void:
	get_tree().create_timer(30).timeout.connect(func(): get_tree().quit(1))
	Session.set_mechanics_lab_active(true)
	Session.apply_debug_state(Fixture.create().export_state(),"minute structure refresh",true)
	var main := Main.instantiate()
	add_child(main)
	await frames()
	var layer = main.get_node("World/StructureLayer")
	var bodies := identities(layer._collision_bodies)
	var sprites := identities(layer._structure_sprites)
	check(not bodies.is_empty() and not sprites.is_empty(),"Actual home has rendered sprites and physical walls")
	for _minute: int in range(3):
		Session.advance_debug_minutes(1)
		await frames()
		check(identities(layer._collision_bodies) == bodies,"NPC minute must not rebuild unchanged home collision bodies")
		check(identities(layer._structure_sprites) == sprites,"NPC minute must not recreate unchanged structure sprites")
	var sim = Session.simulation
	var cell := Vector2i(43,36)
	sim.set_player_position(Content.cell_center(43,37))
	main.get_node("Player").apply_loaded_position()
	var placement: Dictionary = sim.execute_construction_command(Command.place_blueprint(cell,"core:wood_wall"))
	if not placement.success: print("WALL_PLACEMENT ",placement)
	check(placement.success,"Player places a genuine additional wall blueprint")
	for item: String in sim.building_catalog.get_material_cost("core:wood_wall"):
		sim.state.inventory[item] = sim.building_catalog.get_material_cost("core:wood_wall")[item]
	check(sim.execute_construction_command(Command.deliver_blueprint_materials(cell)).success,"Player delivers real wall materials")
	for _work: int in range(sim.building_catalog.get_work_minutes("core:wood_wall")):
		sim.execute_construction_command(Command.work_blueprint(cell))
	await frames()
	check(layer._collision_bodies.size() == bodies.size()+1,"Completed wall adds an actual collision body")
	var changed := identities(layer._collision_bodies)
	Session.state_changed.emit()
	await frames()
	check(identities(layer._collision_bodies) == changed,"Unrelated events preserve the newly built wall")
	Session.apply_debug_state(Fixture.create().export_state(),"load earlier geometry",true)
	await frames()
	check(layer._collision_bodies.size() == bodies.size(),"Loading another structure snapshot restores correct collisions")
	if failures == 0: print("PASS: NPC minutes preserve structure nodes; actual wall completion and world reload refresh geometry")
	get_tree().quit(0 if failures == 0 else 1)
