extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ", label)
func fresh(): return World.new(World.create_new_game_state())
func place(sim, item: String, stack: int) -> Dictionary:
	for value: Dictionary in sim.get_inventory_placements():
		if value.item_id == item and int(value.stack_index) == stack: return value
	return {}
func run() -> void:
	var sim = fresh()
	check(sim.try_pickup_item("core:bucket", 2).success, "Fixture has two physical buckets")
	check(sim.try_pickup_item("core:wood", 5).success, "Fixture has one resource stack")
	var layout: Array[Dictionary] = [
		{"item_id":"core:bucket","stack_index":0,"origin":[0,2],"rotation":0},
		{"item_id":"core:bucket","stack_index":1,"origin":[3,2],"rotation":0},
		{"item_id":"core:wood","stack_index":0,"origin":[2,0],"rotation":0}]
	check(sim.set_inventory_layout(layout).success, "Fixture manual layout valid")
	var survivor := sim.get_inventory_instance_id("core:bucket",1)
	var ids: Array = sim.state.item_instances.map(func(v: Dictionary): return v.instance_id)
	check(sim.drop_inventory_stack("core:bucket",0).success, "Dropping one bucket succeeds")
	check(place(sim,"core:bucket",0).get("origin") == Vector2i(3,2), "Other physical bucket stays in its cells after stack reindex")
	check(place(sim,"core:bucket",0).get("instance_id") == survivor, "Visible survivor is the same physical bucket")
	check(place(sim,"core:wood",0).get("origin") == Vector2i(2,0), "Dropping tool does not sort resources")
	check(sim.state.item_instances.map(func(v: Dictionary): return v.instance_id) == ids, "Drop preserves all world instance IDs")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(place(restored,"core:bucket",0).get("instance_id") == survivor, "Remaining bucket visible after reload")
	sim.set_player_position(sim.content.cell_center(23,23))
	check(sim.try_pickup_item("core:bucket",1).success,"Additional tool can join existing manual layout")
	check(sim.set_inventory_layout([
		{"item_id":"core:bucket","stack_index":0,"origin":[3,2],"rotation":0},
		{"item_id":"core:bucket","stack_index":1,"origin":[1,2],"rotation":0},
		{"item_id":"core:wood","stack_index":0,"origin":[2,0],"rotation":0}]).success,"Both buckets have explicit nonautomatic cells")
	var kept_origin: Vector2i = place(sim,"core:bucket",1).origin
	var kept_id := sim.get_inventory_instance_id("core:bucket",1)
	check(sim.transfer_inventory_stack_to_storage(Vector2i(23,23),"core:bucket",0).success,"Tool enters warehouse")
	check(place(sim,"core:bucket",0).get("origin") == kept_origin and place(sim,"core:bucket",0).get("instance_id") == kept_id,"Warehouse transfer preserves other physical tool placement")
	sim = fresh()
	check(sim.try_pickup_item("core:bucket",1).success,"Automatic placement fixture")
	var automatic_origin: Vector2i = place(sim,"core:bucket",0).origin
	check(sim.try_pickup_item("core:carrot_seed",1).success,"Earlier catalogue item can be picked up")
	check(place(sim,"core:bucket",0).origin == automatic_origin,"Pickup never secretly relocates existing automatic tool placement")
	sim = fresh()
	check(sim.try_pickup_item("core:wood",75).success, "Fifteen resource cells fit")
	var drops: Array[String] = sim._create_resource_drops("test:partial","core:wood",8,sim.get_player_position())
	# Build one real resource pile larger than remaining backpack space.
	var pile: Dictionary = sim.state.world_drops[0]
	pile.amount = 8
	for index: int in range(sim.state.world_drops.size()-1,0,-1): sim.state.world_drops.remove_at(index)
	var picked: Dictionary = sim.try_pickup_world_drop(String(pile.drop_id))
	check(picked.success and int(picked.get("amount",0)) == 5, "Last cell picks up the amount that fits")
	check(sim.get_item_count("core:wood") == 80 and int(pile.amount) == 3, "Pickup conserves remainder on ground")
	var before := JSON.stringify(sim.export_state())
	check(not sim.try_pickup_world_drop(String(pile.drop_id)).success, "Full backpack refuses remaining pile")
	check(JSON.stringify(sim.export_state()) == before, "Refusal has no state effects")
	sim = fresh()
	sim.set_player_position(sim.content.cell_center(22,22))
	sim.state.storage_items.clear()
	for index: int in range(9):
		sim.state.storage_items.append({"cell":[22,22],"item_id":"core:wood" if index == 0 else "core:stone","amount":2 if index == 0 else 5,"origin":[index%3,index/3],"rotation":0,"stack_index":0 if index == 0 else index-1,"placement_id":"core:wood:0" if index == 0 else "core:stone:%d" % (index-1)})
	check(sim.try_pickup_item("core:wood",4).success, "Warehouse transfer source exists")
	var result: Dictionary = sim.transfer_inventory_stack_to_storage(Vector2i(22,22),"core:wood",0,Vector2i.ZERO,0)
	if not result.success: print("WAREHOUSE_RESULT: ",result)
	check(result.success and int(result.get("amount",0)) == 3, "Exact drop fills partial stack even with full storage")
	check(int(sim.state.storage_items[0].amount) == 5 and sim.get_item_count("core:wood") == 1, "Excess remains in backpack without resource loss")
	sim.state.storage_items[0].amount = 2
	check(sim.store_item_in_storage(Vector2i(22,22),"core:wood").success,"Whole-resource transfer also fills existing storage stack")
	check(int(sim.state.storage_items[0].amount) == 3 and sim.get_item_count("core:wood") == 0,"Whole-resource transfer conserves all quantities")
	print("PLAYTEST_INVENTORY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
