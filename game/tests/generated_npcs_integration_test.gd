extends Node
const World := preload("res://src/simulation/world_simulation.gd")
const Main := preload("res://src/main/main.tscn")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _ready() -> void:
	var sim := World.new(World.create_new_game_state())
	if not sim.has_method("arrive_npc"):
		push_error("Missing multi-NPC arrivals")
		get_tree().quit(1)
		return
	var ids: Array[String] = []
	for index: int in range(3):
		var result: Dictionary = sim.create_generated_npc(94 + index, Vector2i(24 + index, 29))
		ids.append(result.npc_id)
		check(sim.arrive_npc(result.npc_id, Vector2i(24, 29)).ok, "Arrival succeeds")
	var occupied: Array[Vector2i] = []
	for id: String in ids:
		var cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(id, Vector2.ZERO))
		check(not occupied.has(cell), "Arrival cells are distinct")
		occupied.append(cell)
		check(sim.is_npc_visible(id), "Generated resident active")
		sim.state.npcs[id].known = true
	for index: int in range(3):
		sim.state.structures.append({"building_id":"core:bedroll", "cell":[20 + index * 2, 19], "stage_id":"core:complete"})
	sim._sync_structure_navigation()
	for index: int in range(3):
		check(sim.housing.assign(sim, ids[index], "core:bedroll@%d,19" % (20 + index * 2)).success, "Separate bed assignment")
	check(not sim.housing.assign(sim, ids[1], "core:bedroll@20,19").success, "Occupied bed rejected")
	check(sim.set_npc_resident(ids[0],true).ok,"Visitor becomes resident independently of discovery")
	check(sim.NpcHomeProjects.choose(sim,sim.state.npcs[ids[0]]).is_empty(),"New residents cannot furnish player's starter house without a blueprint")
	var supply := preload("res://src/npc_work/npc_work_supplies.gd")
	var first_worker: Dictionary = sim.state.npcs[ids[0]]
	var second_worker: Dictionary = sim.state.npcs[ids[1]]
	var source: Dictionary = supply.find_stock(sim,first_worker,"core:axe")
	check(not source.is_empty(),"Physical communal axe available")
	if not source.is_empty():
		var cell: Array = source.record.cell
		var first_position: Vector2 = sim.content.cell_center(int(cell[0]),int(cell[1])+1)
		var second_position: Vector2 = sim.content.cell_center(int(cell[0])+1,int(cell[1]))
		first_worker.position = [first_position.x,first_position.y]
		second_worker.position = [second_position.x,second_position.y]
		check(supply.borrow(sim,first_worker,source),"First resident borrows physical axe")
		check(not supply.borrow(sim,second_worker,source) and second_worker.carried_instance_id == "","Second resident cannot borrow same instance")
		check(sim.get_item_instance(first_worker.carried_instance_id).location.id == ids[0],"Physical tool has exactly one owner")
		supply.drop_remaining(sim,first_worker)
		first_worker.carried_instance_id = ""
	var pathfinder := preload("res://src/simulation/local_grid_pathfinder.gd").new(Vector2i(8,8),32,[])
	var blockers: Array[Vector2i] = [Vector2i(1,0)]
	check(pathfinder.next_cell(Vector2i(0,0),Vector2i(2,0),Vector2i(-1,-1),blockers) == Vector2i(0,1),"Generic pathfinder supports explicitly requested temporary blockers")
	check(pathfinder.next_cell(Vector2i(0,0),Vector2i(2,0)) == Vector2i(1,0),"Explicit temporary blockers leave no permanent navigation mutation")
	Session.set_mechanics_lab_active(true)
	Session.apply_debug_state(sim.export_state(), "generated residents integration", false)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var world: Node = main.get_node("World")
	check(view_count(world, ids) == 3, "Three procedural residents rendered")
	Session.apply_debug_state(sim.export_state(), "reload", false)
	await get_tree().process_frame
	check(view_count(world, ids) == 3, "Reload does not duplicate views")
	var dynamic: Dictionary = Session.simulation.create_generated_npc(100, Vector2i(27,29))
	Session.simulation.arrive_npc(dynamic.npc_id, Vector2i(27,29))
	await get_tree().process_frame
	check(view_count(world, [dynamic.npc_id]) == 1, "Live arrival appears without reload")
	var hunger_before: float = Session.simulation.state.npcs[ids[0]].needs.hunger
	Session.advance_debug_minutes(4)
	check(Session.simulation.state.npcs[ids[0]].needs.hunger < hunger_before, "Generated needs participate in world")
	if failures == 0: print("PASS: multiple NPC arrivals, views, reload, needs, unique beds, tool ownership and navigation")
	get_tree().quit(0 if failures == 0 else 1)
func view_count(world: Node, ids: Array) -> int:
	var count := 0
	for child: Node in world.get_children():
		if child is InteractableView and ids.has(child.object_id) and child.visible: count += 1
	return count
