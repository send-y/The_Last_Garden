extends RefCounted

const Simulation := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const SPACIOUS := Vector2i(40,30)
const CRAMPED := Vector2i(47,30)
const WAREHOUSE := [Vector2i(37,31),Vector2i(38,31),Vector2i(37,32),Vector2i(38,32)]

# Explicit laboratory foundations; all residents, assignments and stock transfers
# use the same simulation commands as play. No test fixture is loaded here.
static func initial_state() -> Dictionary:
	var state := Simulation.create_new_game_state()
	state.day = 2
	state.minute_of_day = 9 * 60
	state.elapsed_game_minutes = 1980
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	# Foundations stand on previously cleared ground, including warehouse approaches.
	for node: Dictionary in state.tree_nodes:
		if Rect2i(36,28,16,10).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))):
			node.stage_id = "stump"
			state.collected[node.id] = true
	for node: Dictionary in state.resource_nodes:
		if Rect2i(35,27,18,12).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))):
			state.collected[node.id] = true
	_add_room(state, "core:room_0001", SPACIOUS, Vector2i(5,5))
	_add_room(state, "core:room_0002", CRAMPED, Vector2i(3,2))
	state.next_room_serial = 3
	# Two real furnishings leave a valid bed approach but no safe table footprint.
	state.structures.append({"building_id":"core:torch","cell":[49,30],"lit":true})
	state.structures.append({"building_id":"core:torch","cell":[47,31],"lit":true})
	var warehouse: Array = []
	for cell: Vector2i in WAREHOUSE:
		warehouse.append([cell.x,cell.y])
		state.structures.append({"building_id":"core:wood_floor","cell":[cell.x,cell.y]})
	state.storage_zones.append({"id":"core:storage_zone_0002","cells":warehouse})
	state.next_storage_zone_serial = 3
	var position := Content.cell_center(37,33)
	state.player_position = [position.x,position.y]
	return state

static func prepare(sim, steps: Array[Dictionary]) -> bool:
	for index: int in range(2):
		var cell := Vector2i(42,33) if index == 0 else Vector2i(49,31)
		var generated: Dictionary = sim.create_generated_npc(194+index,cell)
		if not bool(generated.get("ok",false)): return false
		var id := String(generated.npc_id)
		if not bool(sim.arrive_npc(id,cell).get("ok",false)): return false
		var npc: Dictionary = sim.state.npcs[id]
		npc.known = true
		if not bool(sim.set_npc_resident(id,true).get("ok",false)): return false
		npc.needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
		var bed := SPACIOUS if index == 0 else CRAMPED
		var assignment: Dictionary = sim.assign_sleep_place(id,"core:bedroll@%d,%d" % [bed.x,bed.y])
		if not bool(assignment.get("success",false)): return false
		if not bool(sim.set_npc_work_enabled(id,"build",true).get("success",false)): return false
		steps.append({"kind":"resident_home","npc_id":id,"room_id":"core:room_000%d" % (index+1),"success":true})
	for _stack: int in range(14):
		sim.state.inventory["core:plank"] = 5
		var stored := false
		for cell: Vector2i in WAREHOUSE:
			if stored: break
			sim.set_player_position(Content.cell_center(cell.x,cell.y+1))
			stored = bool(sim.transfer_inventory_stack_to_storage(cell,"core:plank",0).get("success",false))
		if not stored: return false
	sim.set_player_position(Content.cell_center(38,33))
	if not bool(sim.set_stock_reserve("core:plank",35).get("success",false)): return false
	steps.append({"kind":"protected_stock","item_id":"core:plank","stock":70,"reserved":35,"success":true})
	return true

static func _add_room(state: Dictionary, room_id: String, origin: Vector2i, size: Vector2i) -> void:
	var cells: Array = []
	for y: int in range(origin.y-1,origin.y+size.y+1):
		for x: int in range(origin.x-1,origin.x+size.x+1):
			var inside := x >= origin.x and x < origin.x+size.x and y >= origin.y and y < origin.y+size.y
			if inside:
				cells.append([x,y])
				state.structures.append({"building_id":"core:wood_floor","cell":[x,y]})
			else:
				state.structures.append({"building_id":"core:wood_door" if x == origin.x-1 and y == origin.y+mini(2,size.y-1) else "core:wood_wall","cell":[x,y]})
	state.structures.append({"building_id":"core:bedroll","cell":[origin.x,origin.y]})
	state.room_assignments.append({"id":room_id,"room_type_id":"core:living_room","cells":cells})
