extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Command := preload("res://src/construction/construction_command.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)

func equip(sim, id: String) -> String:
	check(sim.try_pickup_item(id, 1).success, "Physical tool obtained: " + id)
	var instance: String = sim.get_inventory_instance_id(id, 0)
	sim.select_inventory_item(id, instance)
	return instance

func run() -> void:
	var content := Content.new()
	check(content.has_method("item_tool_work_rate"), "Catalog must expose work rate")
	check(content.has_method("item_tool_energy_multiplier"), "Catalog must expose till energy")
	if failures > 0:
		finish()
		return
	var rates := [1.0, 1.5, 2.0, 3.0]
	var energy := [1.0, 0.8, 0.65, 0.5]
	var tiers := ["", "_stone", "_copper", "_steel"]
	for type: String in ["axe", "pickaxe", "hoe", "mallet"]:
		for tier: int in range(4):
			var id: String = "core:" + type + tiers[tier]
			check(content.has_item(id), "Definition exists: " + id)
			check(content.call("item_tool_work_rate", id) == (1.0 if type == "hoe" else rates[tier]), "Literal work rate: " + id)
			check(content.call("item_tool_energy_multiplier", id) == (energy[tier] if type == "hoe" else 1.0), "Literal energy cost: " + id)
			check(FileAccess.file_exists(content.item_icon_path(id)), "Sprite exists: " + id)
	for bad: Variant in [0, -1, 1.25, INF, NAN, "2", true]:
		var item := {"id":"test:bad", "instance_based":true, "max_stack":1, "tool":{"actions":["mine"],"grip":"shaft","work_rate":bad}}
		check("work_rate" in str(Content.validate_item_tool(item)), "Invalid rate diagnosed: " + str(bad))
	for tier: int in range(4):
		var sim = World.new()
		equip(sim, "core:axe" + tiers[tier])
		var target := "core:wood_north"
		sim.set_player_position(content.get_interactable(target).position)
		check(sim.execute_resource_work("core:player", target).success, "Actual tier work")
		check(float(sim.state.resource_work.get(target, 0)) == rates[tier], "Actual progress follows rate")
		if tier == 1:
			var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
			check(float(restored.state.resource_work.get(target, 0)) == 1.5, "Fraction survives JSON load")
			check(restored.execute_resource_work("core:player", target).success and float(restored.state.resource_work.get(target, 0)) == 3.0, "Second stone action reaches three minutes")
		var total := 1
		while not sim.is_collected(target) and total < 20:
			sim.execute_resource_work("core:player", target)
			total += 1
		check(total == int(ceil(float(sim.get_resource_work_required(target)) / rates[tier])), "Completion uses correct action count")
		var farm = World.new()
		equip(farm, "core:hoe" + tiers[tier])
		farm.set_player_position(Content.cell_center(18, 29))
		var before: float = farm.get_player_energy()
		check(farm.execute_farming_command({"actor_id":"core:player","action_id":"till","cell":[18,29]}).success, "Actual single bed tilled")
		check(is_equal_approx(before - farm.get_player_energy(), float(energy[tier])), "Actual hoe energy discount")
		check(farm.get_farm_beds().size() == 1, "Hoe tills exactly one bed")
	var builder = World.new()
	var cell := Vector2i(17, 29)
	builder.set_player_position(Content.cell_center(17, 30))
	check(builder.execute_construction_command(Command.place_blueprint(cell, "core:workbench")).success, "Real workbench blueprint")
	var blueprint: Dictionary = builder._find_blueprint([17,29])
	blueprint.delivered_materials = blueprint.required_materials.duplicate(true)
	var before_state: Dictionary = builder.export_state()
	check(not builder.execute_construction_command(Command.work_blueprint(cell)).success and builder.export_state() == before_state, "No selected mallet refuses without energy/progress change")
	equip(builder, "core:mallet_stone")
	check(builder.execute_construction_command(Command.work_blueprint(cell)).success and float(blueprint.work_progress_minutes) == 1.5, "Stone mallet actually speeds construction")
	var restored_builder = World.new(JSON.parse_string(JSON.stringify(builder.export_state())))
	check(float(restored_builder._find_blueprint([17,29]).work_progress_minutes) == 1.5, "Blueprint fraction survives load")
	builder.select_inventory_item("", "")
	check(not builder.execute_construction_command(Command.work_blueprint(cell)).success, "Backpack mallet gives no benefit")
	var npc_builder = World.new(World.create_new_game_state())
	var npc: Dictionary = npc_builder.state.npcs["core:first_neighbor"]
	npc.known = true
	npc.active = true
	npc_builder.state.blueprints = [blueprint.duplicate(true)]
	npc_builder.state.blueprints[0].work_progress_minutes = 0
	npc_builder._sync_structure_navigation()
	npc_builder.set_player_position(Content.cell_center(23,24))
	var hammer_id: String = equip(npc_builder, "core:mallet_stone")
	check(npc_builder.transfer_inventory_stack_to_storage(Vector2i(23,23), "core:mallet_stone", 0).success, "Physical mallet stored for residents")
	npc.work_options.build = true
	npc.initiative_job = {"kind":"build","phase":"build","cell":[17,29],"drops":[]}
	var context: Dictionary = npc_builder.NpcPracticalWork.context_for(npc_builder, npc)
	check(String(npc.initiative_job.get("phase", "")) == "borrow" and not context.is_empty(), "NPC routes to physical mallet before construction")
	if not context.is_empty():
		npc.position = [Content.cell_center(int(context.target_cell[0]), int(context.target_cell[1])).x, Content.cell_center(int(context.target_cell[0]), int(context.target_cell[1])).y]
		check(npc_builder.NpcPracticalWork.fulfil(npc_builder, {"npc_id":String(npc.id),"context":context}), "NPC borrows actual warehouse mallet")
		check(npc.carried_instance_id == hammer_id and npc_builder.get_item_instance(hammer_id).location.kind == "npc", "Borrowing moves the same instance")
		context = npc_builder.NpcPracticalWork.context_for(npc_builder, npc)
		if not context.is_empty():
			npc.position = [Content.cell_center(int(context.target_cell[0]), int(context.target_cell[1])).x, Content.cell_center(int(context.target_cell[0]), int(context.target_cell[1])).y]
			check(npc_builder.NpcPracticalWork.fulfil(npc_builder, {"npc_id":String(npc.id),"context":context}) and float(npc_builder._find_blueprint([17,29]).work_progress_minutes) == 1.5, "NPC uses stone mallet rate in actual build work")
		else: check(false, "NPC can reach blueprint after borrowing")
	finish()

func finish() -> void:
	print("TOOL_TIERS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
