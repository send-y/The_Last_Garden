extends RefCounted
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Command := preload("res://src/construction/construction_command.gd")

# Explicit synthetic foundations, never presented as the author's old day-three save.
static func day_three_state() -> Dictionary:
	var state := World.create_new_game_state()
	state.day = 3
	state.minute_of_day = 9*60
	state.elapsed_game_minutes = 3420
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	for node: Dictionary in state.tree_nodes:
		if Rect2i(29,23,11,11).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))):
			node.stage_id = "stump"
			state.collected[node.id] = true
	for node: Dictionary in state.resource_nodes:
		if Rect2i(29,23,11,11).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))): state.collected[node.id] = true
	var cells: Array = []
	for y: int in range(24,29):
		for x: int in range(30,35):
			var inside := x >= 31 and x <= 33 and y >= 25 and y <= 27
			if inside: cells.append([x,y])
			state.structures.append({"building_id":"core:wood_floor" if inside else ("core:wood_door" if x == 32 and y == 28 else "core:wood_wall"),"cell":[x,y],"stage_id":"core:complete"})
	state.storage_zones.append({"id":"core:storage_zone_0002","cells":cells})
	state.next_storage_zone_serial = 3
	var npc: Dictionary = state.npcs["core:first_neighbor"]
	npc.active = true
	npc.known = true
	npc.first_meeting_complete = true
	npc.position = [Content.cell_center(35,30).x,Content.cell_center(35,30).y]
	state.player_position = [Content.cell_center(34,30).x,Content.cell_center(34,30).y]
	return state

static func build(id: StringName) -> Dictionary:
	if id == &"first_meeting_hungry":
		var state := World.create_new_game_state()
		state.day = 2
		state.minute_of_day = 7*60
		state.elapsed_game_minutes = 1860
		state.flags.first_night_complete = true
		state.npcs["core:first_neighbor"].active = true
		state.npcs["core:first_neighbor"].needs.hunger = 1.0
		state.player_needs.hunger = 1.0
		var meeting := World.new(state)
		meeting.set_player_position(meeting.get_npc_position("core:first_neighbor",Vector2.ZERO)+Vector2(32,0))
		return {"success":true,"simulation":meeting,"state":meeting.export_state(),"steps":[]}
	var sim := World.new(day_three_state())
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	var stock := {"core:wood":15,"core:food":10}
	if id == &"day_three": stock["core:plank"] = 40
	# Stock is explicit debug input; transfer and placement follow real commands.
	for item: String in stock:
		var left := int(stock[item])
		for cell: Array in sim.state.storage_zones.back().cells:
			npc.position = [Content.cell_center(int(cell[0]),int(cell[1])+1).x,Content.cell_center(int(cell[0]),int(cell[1])+1).y]
			left -= Supply.store(sim,npc,Vector2i(int(cell[0]),int(cell[1])),item,left)
			if left == 0: break
		if left > 0: return {"success":false,"message":"Склад сценария не принял запас."}
	npc.position = [Content.cell_center(35,30).x,Content.cell_center(35,30).y]
	sim.set_player_position(Content.cell_center(34,30))
	sim.set_stock_reserve("core:wood",5)
	sim.try_pickup_item("core:mallet",1)
	sim.set_player_position(Content.cell_center(32,27))
	if not bool(sim.transfer_inventory_stack_to_storage(Vector2i(33,27),"core:mallet",0).success): return {"success":false}
	if id != &"missing_workbench": sim.add_structure({"building_id":"core:workbench","cell":[36,29],"stage_id":"core:complete"})
	sim._sync_structure_navigation()
	if id in [&"communal_production",&"missing_workbench"]:
		sim.set_player_position(Content.cell_center(36,32))
		if not bool(sim.execute_construction_command(Command.place_blueprint(Vector2i(36,31),"core:wood_wall")).success): return {"success":false}
		sim.set_npc_work_enabled(String(npc.id),"build",true)
	else:
		var generated := sim.create_generated_npc(94,Vector2i(35,32))
		if not bool(generated.ok) or not bool(sim.arrive_npc(String(generated.npc_id),Vector2i(35,32)).ok): return {"success":false}
	sim.set_player_position(Content.cell_center(35,32))
	return {"success":true,"simulation":sim,"state":sim.export_state(),"steps":[]}
