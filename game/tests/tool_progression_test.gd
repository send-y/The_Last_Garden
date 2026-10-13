extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Craft := preload("res://src/crafting/crafting_command.gd")
const Build := preload("res://src/construction/construction_command.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func pickup_outputs(sim) -> void:
	for drop: Dictionary in sim.get_world_drops():
		sim.set_player_position(Vector2(float(drop.position[0]), float(drop.position[1])))
		check(sim.try_pickup_world_drop(String(drop.drop_id)).success, "Physical crafted output picked up")
func work_recipe(sim, cell: Vector2i, id: String) -> void:
	sim.set_player_position(Content.cell_center(cell.x,cell.y+1))
	check(sim.execute_crafting_command(Craft.start_project(cell,id)).success, "Recipe started: " + id)
	for _step: int in range(sim.crafting_catalog.get_work_minutes(id)):
		check(sim.execute_crafting_command(Craft.work_project(cell)).success, "Craft work succeeds: " + id)
func run() -> void:
	var state := World.create_new_game_state()
	check(state.item_instances.size() == 1 and state.item_instances[0].item_id == "core:axe", "New world has only the primitive axe")
	check(Craft.new().has_method("craft_in_hands"), "Explicit handcraft command exists")
	if failures > 0: finish(); return
	var sim = World.new(state)
	var before: Dictionary = sim.export_state()
	check(not sim.execute_crafting_command(Craft.new().call("craft_in_hands","core:make_mallet")).success and sim.export_state() == before, "Undiscovered hand recipe refuses without spending/time/RNG changes")
	sim.set_player_position(Content.cell_center(22,22))
	var axe: Dictionary = sim.state.storage_items[0]
	check(sim.transfer_storage_stack_to_inventory(Vector2i(22,22),String(axe.placement_id)).success, "Starter axe is physically retrieved")
	sim.select_inventory_item("core:axe", String(axe.instance_id))
	sim.set_player_position(sim.content.get_interactable("core:repair_room").position)
	check(sim.execute_interaction("core:repair_room").success, "Optional starter-room clearing remains available")
	check(sim.get_current_objective_key() == "tool.learning.objective.gather_wood", "Opening hint explains first material before a locked hand recipe")
	sim.set_player_position(sim.content.get_interactable("core:wood_north").position)
	for _action: int in range(20):
		if sim.is_collected("core:wood_north"): break
		check(sim.execute_resource_work("core:player","core:wood_north").success, "Starter axe gathers actual wood")
	pickup_outputs(sim)
	check(sim.get_current_objective_key() == "tool.learning.objective.make_mallet", "Wood discovery points to handcraft in backpack")
	check(sim.execute_crafting_command(Craft.new().call("craft_in_hands","core:make_mallet")).success, "Mallet is made without a station after wood discovery")
	pickup_outputs(sim)
	var mallet: String = sim.get_inventory_instance_id("core:mallet",0)
	check(not mallet.is_empty(), "Handcraft creates an actual mallet instance")
	sim.select_inventory_item("core:mallet",mallet)
	# Extra wood here represents another completed tree; starter-chain resource ownership
	# above has already been exercised through real harvesting and drop pickup.
	check(sim.try_pickup_item("core:wood",4).success, "More building wood fits")
	var cell := Vector2i(17,29)
	sim.set_player_position(Content.cell_center(17,30))
	check(sim.execute_construction_command(Build.place_blueprint(cell,"core:workbench")).success, "Workbench can be planned")
	check(sim.execute_construction_command(Build.deliver_blueprint_materials(cell)).success, "Workbench uses harvested wood")
	for _step: int in range(sim.building_catalog.get_work_minutes("core:workbench")):
		check(sim.execute_construction_command(Build.work_blueprint(cell)).success, "Handcrafted mallet builds first workbench")
	sim.set_player_position(Content.cell_center(23,24))
	check(sim.transfer_inventory_stack_to_storage(Vector2i(23,23),"core:mallet",0).success, "Unused mallet can be put away to make room for the pickaxe")
	check(sim.try_pickup_item("core:wood",3).success, "Recipe materials obtained")
	work_recipe(sim, cell, "core:make_pickaxe")
	pickup_outputs(sim)
	var pick: String = sim.get_inventory_instance_id("core:pickaxe",0)
	check(not pick.is_empty(), "Bench creates physical pickaxe")
	sim.select_inventory_item("core:pickaxe",pick)
	sim.set_player_position(sim.content.get_interactable("core:stone_south").position)
	for _action: int in range(20):
		if sim.is_collected("core:stone_south"): break
		check(sim.execute_resource_work("core:player","core:stone_south").success, "Crafted primitive pick mines real stone")
	pickup_outputs(sim)
	before = sim.export_state()
	check(not sim.execute_crafting_command(Craft.start_project(cell,"core:make_axe_stone")).success and sim.export_state() == before, "Stone craft cannot bypass learning")
	for recipe: Dictionary in sim.get_crafting_recipes("core:workbench"):
		for output: String in recipe.get("outputs", {}): check(not output.ends_with("_copper") and not output.ends_with("_steel"), "Upper tiers have no ordinary source")
	# Constructed study station fixture isolates research from the already tested build loop.
	sim.add_structure({"building_id":"core:study_table","cell":[19,29]})
	sim._sync_structure_navigation()
	work_recipe(sim, Vector2i(19,29), "core:study_stone_tools")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(restored.is_recipe_unlocked("core:make_axe_stone"), "Stone learning persists after JSON reload")
	before = restored.export_state()
	check(not restored.execute_crafting_command(Craft.new().call("craft_in_hands","core:make_pickaxe")).success and restored.export_state() == before, "Bench-only tools cannot be forged in hands")
	finish()
func finish() -> void:
	print("TOOL_PROGRESSION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
