extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var sim = World.new()
	if not sim.has_method("edit_world"):
		check(false,"World editing must be authoritative, not only hide visuals")
		quit(1)
		return
	var at := Vector2i(43,36)
	sim.state.structures.append({"building_id":"core:wood_wall","cell":[43,36]})
	sim._sync_structure_navigation()
	check(not sim.is_navigation_cell_walkable(at),"Wall blocks navigation before dismantling")
	check(not sim.edit_world("dismantle",at).success,"Distant dismantling rejected")
	sim.set_player_position(Content.cell_center(43,37))
	check(not sim.edit_world("dismantle",at,"","core:first_neighbor").success,"Only player can dismantle")
	var removed: Dictionary = sim.edit_world("dismantle",at)
	check(removed.success and sim._find_structure([43,36]).is_empty(),"Nearby wall is actually removed")
	check(sim.is_navigation_cell_walkable(at),"Dismantling updates navigation")
	check(int(sim.get_item_count("core:plank")) == 15,"Half of wall materials returned")
	check(not sim.edit_world("dismantle",at).success and sim.get_item_count("core:plank") == 15,"Repeated command cannot duplicate refunds")
	sim.state.structures.append({"building_id":"core:wood_door","cell":[43,36],"open":false})
	check(sim.edit_world("toggle_door",at).success and sim._find_structure([43,36]).open,"Door opens")
	var loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(loaded._find_structure([43,36]).open,"Open door survives JSON save")
	check(sim.edit_world("toggle_door",at).success and not sim._find_structure([43,36]).open,"Door closes")
	sim.set_player_position(Content.cell_center(43,36))
	sim.edit_world("toggle_door",at)
	check(not sim.edit_world("toggle_door",at).success,"Door cannot close on an actor")
	var bush: Dictionary = sim.get_surface_berry_bushes()[0]
	sim.set_player_position(bush.position)
	check(not sim.edit_world("clear_bush",Vector2i.ZERO,String(bush.id)).success,"Clearing requires a selected physical axe")
	sim._add_item("core:axe",1)
	for instance: Dictionary in sim.state.item_instances:
		if String(instance.item_id) == "core:axe":
			sim.select_inventory_item("core:axe",String(instance.instance_id))
			break
	check(sim.edit_world("clear_bush",Vector2i.ZERO,String(bush.id)).success,"Bush can be uprooted")
	check(sim.should_hide_interactable(String(bush.id),"food"),"Uprooted bush hidden immediately")
	check(not sim.execute_interaction(String(bush.id)).success,"Hidden bush cannot still be harvested")
	loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	loaded.state.elapsed_game_minutes += 4*24*60
	loaded.farming.advance(loaded)
	check(loaded.should_hide_interactable(String(bush.id),"food"),"Cleared bush stays removed after save and regrowth interval")
	check(not loaded.edit_world("clear_bush",Vector2i.ZERO,String(bush.id)).success,"Removal cannot be repeated")
	var legacy: Dictionary = sim.export_state()
	legacy.version = 34
	legacy.erase("removed_bushes")
	legacy.structures = [{"building_id":"core:wood_door","cell":[43,36]}]
	loaded = World.new(legacy)
	check(loaded.state.removed_bushes.is_empty() and loaded._find_structure([43,36]).open,"Old saves retain their passable doors and bushes")
	legacy.removed_bushes = ["broken"]
	loaded = World.new(legacy)
	check(loaded.state.removed_bushes.is_empty(),"Malformed removal data safely ignored")
	var crowded = World.new()
	crowded.state.inventory["core:wood"] = 80
	crowded.state.structures.append({"building_id":"core:wood_wall","cell":[43,36]})
	crowded.set_player_position(Content.cell_center(43,37))
	var refund: Dictionary = crowded.edit_world("dismantle",at)
	var planks := crowded.get_item_count("core:plank")
	for drop: Dictionary in crowded.state.world_drops:
		if drop.item_id == "core:plank": planks += int(drop.amount)
	check(refund.success and planks == 15 and not refund.dropped.is_empty(),"Full backpack preserves refund as physical drops")
	crowded.state.structures.append({"building_id":"core:bedroll","cell":[43,36]})
	crowded.state.sleep_assignments["core:first_neighbor"] = "core:bedroll@43,36"
	check(crowded.edit_world("dismantle",at).success and crowded.state.sleep_assignments["core:first_neighbor"].is_empty(),"Removed sleeping place releases assignment")
	crowded.state.structures.append({"building_id":"core:workbench","cell":[43,36]})
	crowded.state.crafting_projects.append({"cell":[43,36],"reserved_inputs":{"core:wood":2}})
	check(not crowded.edit_world("dismantle",at).success,"Workbench with reserved project inputs cannot be destroyed")
	var npc_world = preload("res://tests/fixtures/resident_home_fixture.gd").create()
	var door: Dictionary = npc_world._find_structure([39,32])
	door.open = false
	npc_world.state.npcs["core:first_neighbor"].position = [Content.cell_center(40,32).x,Content.cell_center(40,32).y]
	npc_world.advance_minutes(1)
	check(door.open,"Resident opens an approachable closed door during simulation")
	var storage_world = preload("res://tests/fixtures/resident_home_fixture.gd").create()
	preload("res://tests/fixtures/resident_home_fixture.gd").stock(storage_world,10)
	storage_world.set_player_position(Content.cell_center(37,32))
	check(not storage_world.get_storage_contents(Vector2i(37,31)).is_empty(),"Storage guard fixture has actual materials")
	check(not storage_world.edit_world("dismantle",Vector2i(37,31)).success,"Stock must be removed before its storage floor")
	storage_world.set_player_position(Content.cell_center(38,31))
	check(storage_world.housing.room_valid(storage_world,"core:room_0001"),"Home initially enclosed")
	check(storage_world.edit_world("dismantle",Vector2i(39,31)).success,"Boundary wall can be dismantled")
	check(not storage_world.housing.room_valid(storage_world,"core:room_0001"),"Removing wall invalidates actual enclosure cache")
	print("WORLD_EDITING: %d failures" % failures)
	quit(1 if failures else 0)
