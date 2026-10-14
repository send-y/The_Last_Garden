extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func amount(reasons: Array, key: String) -> float:
	for value: Dictionary in reasons:
		if value.key == key: return float(value.amount)
	return 0.0
func run() -> void:
	var sim = World.new(World.create_new_game_state())
	for invalid: Variant in [-1,1.5,"two",INF,101]: check(not sim.content.validate_stump_amount("wood",{"stump_amount":invalid}).is_empty(),"Invalid stump yield is diagnosed")
	check(sim.content.validate_stump_amount("wood",{"stump_amount":2}).is_empty(),"Real stump yield is accepted")
	check(not sim.content.validate_stump_amount("food",{"stump_amount":2}).is_empty(),"Stump field on unrelated source is diagnosed")
	check(sim.building_catalog.get_material_cost("core:wood_wall") == {"core:plank":20},"New wall uses agreed twenty planks")
	check(sim.building_catalog.get_material_cost("core:wood_door") == {"core:plank":15},"New door uses agreed fifteen planks")
	var old := World.create_new_game_state()
	old.version = 37
	old.blueprints = [{"building_id":"core:wood_wall","cell":[17,29],"required_materials":{"core:plank":30},"delivered_materials":{"core:plank":30},"required_work_minutes":25,"work_progress_minutes":8}]
	var migrated = World.new(old)
	check(migrated.state.blueprints[0].required_materials == {"core:plank":20} and migrated.state.blueprints[0].delivered_materials == {"core:plank":20} and float(migrated.state.blueprints[0].work_progress_minutes) == 8,"Loaded paid wall adopts new price without losing work")
	var refunded := 0
	for drop: Dictionary in migrated.state.world_drops:
		if drop.item_id == "core:plank": refunded += int(drop.amount)
	check(refunded == 10,"Excess old wall investment is refunded as real material")
	var second_load = World.new(JSON.parse_string(JSON.stringify(migrated.export_state())))
	var twice := 0
	for drop: Dictionary in second_load.state.world_drops:
		if drop.item_id == "core:plank": twice += int(drop.amount)
	check(twice == refunded,"Loading again does not duplicate price refund")
	var energy_sim = World.new(World.create_new_game_state())
	energy_sim.try_pickup_item("core:axe",1)
	energy_sim.select_inventory_item("core:axe",energy_sim.get_inventory_instance_id("core:axe",0))
	var actions := 0
	for node: Dictionary in energy_sim.get_surface_trees():
		energy_sim.set_player_position(node.position)
		for step: int in range(8):
			if energy_sim.execute_resource_work("core:player",String(node.id)).success: actions += 1
		if actions >= 96: break
	check(actions >= 96 and energy_sim.get_player_energy() >= 70,"Early work budget preserves energy after ninety-six actual chopping actions")
	check(sim.get_storage_grid_size(Vector2i(22,22)) == Vector2i(4,4),"Floored storage provides sixteen cells")
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.needs.hunger = 55.01
	npc.needs.restedness = 55.01
	var before: Array = sim.needs.reasons(npc,true,0)
	npc.needs.hunger = 54.99
	npc.needs.restedness = 54.99
	var after: Array = sim.needs.reasons(npc,true,0)
	check(absf(amount(before,"needs.reason.fed")-amount(after,"needs.reason.hungry")) < 1,"Crossing hunger threshold does not abruptly change mood contribution")
	check(absf(amount(before,"needs.reason.slept")-amount(after,"needs.reason.sleepy")) < 1,"Crossing sleep threshold does not abruptly change mood contribution")
	npc.needs.hunger = 0.0
	check(amount(sim.needs.reasons(npc,true,0),"needs.reason.hungry") < amount(after,"needs.reason.hungry"),"Deeper hunger increases negative contribution")
	sim.try_pickup_item("core:axe",1)
	sim.select_inventory_item("core:axe",sim.get_inventory_instance_id("core:axe",0))
	var tree: Dictionary = sim.get_surface_trees()[0]
	sim.set_player_position(tree.position)
	for step: int in range(8): sim.execute_resource_work("core:player",String(tree.id))
	var wood_before := 0
	for drop: Dictionary in sim.state.world_drops:
		if drop.item_id == "core:wood": wood_before += int(drop.amount)
	sim = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	for step: int in range(4): sim.execute_resource_work("core:player",String(tree.id))
	var wood_after := 0
	for drop: Dictionary in sim.state.world_drops:
		if drop.item_id == "core:wood": wood_after += int(drop.amount)
	check(wood_after > wood_before and wood_after-wood_before <= 2,"Removing a stump yields a small real wood amount after reload")
	var snapshot := JSON.stringify(sim.export_state())
	check(not sim.execute_resource_work("core:player",String(tree.id)).success and JSON.stringify(sim.export_state()) == snapshot,"Depleted stump cannot yield again")
	print("PLAYTEST_ECONOMY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
