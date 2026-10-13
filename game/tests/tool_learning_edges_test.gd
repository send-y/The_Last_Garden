extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var state := World.create_new_game_state()
	state.storage_items.append({"cell":[22,23],"item_id":"core:wood","amount":2,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"})
	var sim = World.new(state)
	check(not sim.is_recipe_unlocked("core:make_mallet"), "Unknown warehouse material does not grant discovery at distance")
	sim.set_player_position(Content.cell_center(22,24))
	check(sim.transfer_storage_stack_to_inventory(Vector2i(22,23),"core:wood:0").success, "First wood is physically taken from warehouse")
	check(sim.is_recipe_unlocked("core:make_mallet"), "Warehouse wood unlocks basic recipe immediately, without reload")
	var worker: Dictionary = sim.state.npcs["core:first_neighbor"]
	worker.active = true
	worker.position = [Content.cell_center(18,31).x,Content.cell_center(18,31).y]
	sim.state.blueprints.append({"building_id":"core:workbench","cell":[17,29]})
	for cell: Vector2i in [Vector2i(17,28),Vector2i(17,30),Vector2i(16,29)]:
		sim.add_structure({"building_id":"core:wood_wall","cell":[cell.x,cell.y]})
	sim._sync_structure_navigation()
	var approach := Supply.build_work_cell(sim, worker, Vector2i(17,29))
	check(approach != Vector2i(-1,-1), "Wide blueprint has reachable approach beyond its occupied anchor neighbours")
	if approach != Vector2i(-1,-1):
		check(approach not in [Vector2i(17,29),Vector2i(18,29)] and Content.cell_center(approach.x,approach.y).distance_to(Content.cell_center(17,29)) <= Content.INTERACTION_RANGE, "Approach is outside footprint and within real working distance")
	print("TOOL_LEARNING_EDGES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
