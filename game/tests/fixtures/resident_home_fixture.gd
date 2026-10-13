extends RefCounted

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const NPC := "core:first_neighbor"
const ROOM := "core:room_0001"
const ORIGIN := Vector2i(40, 30)

static func create(shared: bool = false, interior_size: Vector2i = Vector2i(5, 5)):
	var state := preload("res://tests/fixtures/stocked_tool_state.gd").prepare(World.create_new_game_state())
	state.day = 2
	state.minute_of_day = 9 * 60
	state.elapsed_game_minutes = 1980
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	state.npcs[NPC].known = true
	state.npcs[NPC].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	state.npcs[NPC].position = [Content.cell_center(42, 32).x, Content.cell_center(42, 32).y]
	# These foundations represent already cleared building sites, not houses on live trunks.
	for node: Dictionary in state.tree_nodes:
		if Rect2i(36,28,16,10).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))):
			node.stage_id = "stump"
			state.collected[node.id] = true
	for node: Dictionary in state.resource_nodes:
		if Rect2i(35,27,18,12).has_point(Vector2i(int(node.cell[0]),int(node.cell[1]))):
			state.collected[node.id] = true
	var cells: Array = []
	for y: int in range(ORIGIN.y - 1, ORIGIN.y + interior_size.y + 1):
		for x: int in range(ORIGIN.x - 1, ORIGIN.x + interior_size.x + 1):
			var inside := x >= ORIGIN.x and x < ORIGIN.x + interior_size.x and y >= ORIGIN.y and y < ORIGIN.y + interior_size.y
			if inside:
				cells.append([x, y])
				state.structures.append({"building_id":"core:wood_floor","cell":[x,y]})
			else:
				state.structures.append({"building_id":"core:wood_door" if x == ORIGIN.x - 1 and y == ORIGIN.y + mini(2,interior_size.y-1) else "core:wood_wall","cell":[x,y]})
	state.structures.append({"building_id":"core:bedroll","cell":[40,30]})
	state.room_assignments = [{"id":ROOM,"room_type_id":"core:living_room","cells":cells}]
	state.next_room_serial = 2
	state["sleep_assignments"] = {"core:player":"core:starter_bedroll",NPC:"core:bedroll@40,30"}
	var warehouse: Array = []
	for y: int in range(31, 33):
		for x: int in range(37, 39):
			warehouse.append([x,y])
			state.structures.append({"building_id":"core:wood_floor","cell":[x,y]})
	state.storage_zones.append({"id":"core:storage_zone_0002","cells":warehouse})
	state.next_storage_zone_serial = 3
	state.player_position = [Content.cell_center(37,33).x, Content.cell_center(37,33).y]
	var sim = World.new(state)
	# Furniture workers collect their physical mallet beside the project stock,
	# rather than taking an unrelated trip to the starter house.
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == "core:mallet": record.cell = [37,31]
	if shared:
		var created: Dictionary = sim.create_generated_npc(95, Vector2i(42,33))
		var id := String(created.npc_id)
		sim.arrive_npc(id, Vector2i(42,33))
		sim.state.npcs[id].known = true
		sim.set_npc_resident(id, true)
		sim.state.npcs[id].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
		sim.add_structure({"building_id":"core:bedroll","cell":[43,33]})
		sim.state.sleep_assignments[id] = "core:bedroll@43,33"
		sim.notify_housing_changed()
		sim._sync_structure_navigation()
		if sim.has_method("set_home_mode"):
			sim.set_home_mode(ROOM, "shared")
	return sim

static func stock(sim, amount: int) -> void:
	var remaining := amount
	var original_position: Vector2 = sim.get_player_position()
	while remaining > 0:
		var count := mini(10,remaining)
		sim.state.inventory["core:plank"] = count
		var stored := false
		for zone: Dictionary in sim.state.storage_zones:
			if zone.id != "core:storage_zone_0002": continue
			for value: Array in zone.cells:
				if stored: break
				var cell := Vector2i(int(value[0]),int(value[1]))
				sim.set_player_position(Content.cell_center(cell.x,cell.y+1))
				stored = bool(sim.transfer_inventory_stack_to_storage(cell,"core:plank",0).success)
		if not stored:
			push_error("Resident fixture warehouse could not receive real planks")
			break
		remaining -= count
	sim.set_player_position(original_position)
