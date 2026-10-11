extends SceneTree
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const HomeFixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Production := preload("res://src/npc_work/npc_home_production.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world_script: Variant = World
	var blocked := Fixture.catalog(["core:wood"])
	var sim = world_script.new({}, blocked)
	sim.try_pickup_item("test:axe_variant", 1)
	sim.select_inventory_item("test:axe_variant", sim.get_inventory_instance_id("test:axe_variant", 0))
	var tree: Dictionary = sim.get_surface_trees()[0]
	for target: String in ["core:wood_north", String(tree.id)]:
		sim.set_player_position(sim.get_interaction_target_position(target))
		var before: Dictionary = sim.export_state()
		check(not sim.execute_resource_work("core:player", target).success and sim.export_state() == before, "Disabled wood refuses without mutation: " + target)
	sim._update_tree_stage(String(tree.id), "stump")
	sim.set_player_position(sim.get_interaction_target_position(String(tree.id)))
	var before: Dictionary = sim.export_state()
	check(not sim.execute_resource_work("core:player", String(tree.id)).success and sim.export_state() == before, "Disabled stump refuses without energy, drops or progress")
	var normal := Fixture.world()
	var cell := Vector2i(-1, -1)
	for y: int in range(24, 40):
		for x: int in range(10, 30):
			if cell.x < 0 and normal.farming._soil_allowed(normal, Vector2i(x,y)): cell = Vector2i(x,y)
	check(cell.x >= 0, "Fixture has valid soil")
	normal.state.farming.beds.append({"cell": [cell.x,cell.y], "crop_id": "carrot", "growth": 123, "wet_until": 1440, "last_update": 0, "harvests": 2})
	var saved := normal.export_state()
	var control := Fixture.world(saved)
	check(control.farming.bed_at(control,cell).get("crop_id", "") == "carrot" and control.farming.bed_at(control,cell).growth == 123, "Active control crop survives reload")
	for id: String in ["core:carrot_seed", "core:carrot"]:
		var inactive = world_script.new(saved, Fixture.catalog([id]))
		var bed: Dictionary = inactive.farming.bed_at(inactive,cell)
		check(bed.get("crop_id", "") == "carrot" and int(bed.get("growth",0)) == 123 and int(bed.get("harvests",0)) == 2, "Deprecated source retains saved cultivation: " + id)
		inactive.advance_minutes(1)
		check(int(bed.get("growth",0)) == 123, "Inactive saved cultivation is frozen")
		var reloaded = world_script.new(JSON.parse_string(JSON.stringify(inactive.export_state())), Fixture.catalog([id]))
		check(reloaded.farming.bed_at(reloaded,cell).get("crop_id", "") == "carrot", "Inactive crop survives another reload")
		inactive.set_player_position(inactive.content.cell_center(cell.x,cell.y))
		inactive.state.player_furniture_use = {"chair_cell":[cell.x,cell.y],"approach":[cell.x,cell.y],"kind":"rest","until":0}
		before = inactive.export_state()
		check(not inactive.execute_farming_command({"actor_id":"core:player","action_id":"harvest","cell":[cell.x,cell.y]}).success and inactive.export_state() == before, "Inactive source produces no forbidden harvest")
		inactive.state.farming.beds[0].crop_id = ""
		inactive.state.inventory["core:carrot_seed"] = 1
		before = inactive.export_state()
		check(not inactive.execute_farming_command({"actor_id":"core:player","action_id":"plant","item_id":"core:carrot_seed","cell":[cell.x,cell.y]}).success and inactive.export_state() == before, "Inactive source cannot start new planting")
	var craft_state := normal.export_state()
	craft_state.structures.append({"building_id":"core:workbench","cell":[22,29]})
	craft_state.crafting_projects = [{"cell":[22,29],"recipe_id":"core:saw_planks","reserved_inputs":{"core:wood":5},"required_work_minutes":10,"work_progress_minutes":3}]
	for id: String in ["core:plank", "core:wood"]:
		var loaded = world_script.new(craft_state,Fixture.catalog([id]))
		var recovered := 0
		for drop: Dictionary in loaded.state.world_drops:
			if String(drop.item_id) == "core:wood": recovered += int(drop.amount)
		check(loaded.state.crafting_projects.is_empty() and recovered == 5, "Disabled recipe refunds committed materials: " + id)
		var roundtrip = world_script.new(JSON.parse_string(JSON.stringify(loaded.export_state())), Fixture.catalog([id]))
		var recovered_again := 0
		for drop: Dictionary in roundtrip.state.world_drops:
			if String(drop.item_id) == "core:wood": recovered_again += int(drop.amount)
		check(recovered_again == 5, "Recipe recovery is not duplicated on reload")
	var home = HomeFixture.create()
	home.add_structure({"building_id":"core:workbench","cell":[36,34],"stage_id":"core:complete"})
	home.set_npc_work_enabled(HomeFixture.NPC,"build",true)
	var resident: Dictionary = home.state.npcs[HomeFixture.NPC]
	resident.home_goal = home.NpcHomeProjects.clean_goal({"building_id":"core:torch","cell":[43,34],"room_id":HomeFixture.ROOM,"place_id":"core:bedroll@40,30"})
	check(Production.authorized(home,resident), "Active NPC production control is authorized")
	var retired = world_script.new(home.export_state(),Fixture.catalog(["core:plank"]))
	resident = retired.state.npcs[HomeFixture.NPC]
	resident.position = [retired.content.cell_center(36,34).x,retired.content.cell_center(36,34).y]
	before = retired.export_state()
	check(not retired.CraftingSystem.work_npc_project(retired,resident,[36,34],Production.RECIPE).success and retired.export_state() == before, "NPC cannot start disabled recipe with empty requirements")
	check(not Production.authorized(retired,resident) and Production.choose(retired,resident,{"core:plank":1}).is_empty(), "Disabled source cannot authorize a resident crafting job")
	print("ITEM_SOURCE_COMPATIBILITY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
