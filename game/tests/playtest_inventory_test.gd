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
	var size: Vector2i = sim.get_storage_grid_size(Vector2i(22,22))
	for index: int in range(size.x*size.y):
		sim.state.storage_items.append({"cell":[22,22],"item_id":"core:wood" if index == 0 else "core:stone","amount":2 if index == 0 else 5,"origin":[index%size.x,index/size.x],"rotation":0,"stack_index":0 if index == 0 else index-1,"placement_id":"core:wood:0" if index == 0 else "core:stone:%d" % (index-1)})
	check(sim.try_pickup_item("core:wood",4).success, "Warehouse transfer source exists")
	var result: Dictionary = sim.transfer_inventory_stack_to_storage(Vector2i(22,22),"core:wood",0,Vector2i.ZERO,0)
	if not result.success: print("WAREHOUSE_RESULT: ",result)
	check(result.success and int(result.get("amount",0)) == 3, "Exact drop fills partial stack even with full storage")
	check(int(sim.state.storage_items[0].amount) == 5 and sim.get_item_count("core:wood") == 1, "Excess remains in backpack without resource loss")
	sim.state.storage_items[0].amount = 2
	check(sim.store_item_in_storage(Vector2i(22,22),"core:wood").success,"Whole-resource transfer also fills existing storage stack")
	check(int(sim.state.storage_items[0].amount) == 3 and sim.get_item_count("core:wood") == 0,"Whole-resource transfer conserves all quantities")
	sim = fresh()
	sim.set_player_position(sim.content.cell_center(22,22))
	sim.state.storage_items = [{"cell":[22,22],"item_id":"core:wood","amount":3,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"}]
	sim.try_pickup_item("core:wood",8)
	var source_origin: Vector2i = place(sim,"core:wood",0).origin
	var other_origin: Vector2i = place(sim,"core:wood",1).origin
	sim.transfer_inventory_stack_to_storage(Vector2i(22,22),"core:wood",0,Vector2i.ZERO,0)
	check(place(sim,"core:wood",0).origin == source_origin and int(place(sim,"core:wood",0).amount) == 3,"Partial transfer leaves actual remaining amount in the held source stack")
	check(place(sim,"core:wood",1).origin == other_origin and int(place(sim,"core:wood",1).amount) == 3,"Partial transfer does not consolidate other source stacks")
	restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(restored.get_inventory_placements().size() == 2 and int(place(restored,"core:wood",0).amount) == 3,"Separate partial stacks survive reload without changing quantities")
	sim = fresh()
	sim.set_player_position(sim.content.cell_center(22,23))
	var stored_ids: Array[String] = sim._create_item_instances("core:bucket",1,"storage","core:bucket:0",{"charges":2})
	sim.state.storage_items.append({"cell":[22,23],"item_id":"core:bucket","amount":1,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:bucket:0","instance_id":stored_ids[0]})
	sim.try_pickup_item("core:bucket",2)
	var untouched_id := sim.get_inventory_instance_id("core:bucket",0)
	var outgoing_id := sim.get_inventory_instance_id("core:bucket",1)
	var untouched_origin: Vector2i = place(sim,"core:bucket",0).origin
	var outgoing_origin: Vector2i = place(sim,"core:bucket",1).origin
	result = sim.transfer_inventory_stack_to_storage(Vector2i(22,23),"core:bucket",1,Vector2i.ZERO,0)
	check(result.success and bool(result.get("exchanged",false)),"Equal tools can exchange between backpack and warehouse")
	check(sim.get_item_instance(outgoing_id).location.kind == "storage" and sim.get_item_instance(stored_ids[0]).location.kind == "inventory","Cross-grid exchange moves both actual physical instances")
	check(place(sim,"core:bucket",0).get("instance_id") == stored_ids[0] and place(sim,"core:bucket",0).origin == outgoing_origin,"Displaced earlier-created instance occupies the vacated source cells")
	check(place(sim,"core:bucket",1).get("instance_id") == untouched_id and place(sim,"core:bucket",1).origin == untouched_origin,"Exchange reindexes physical IDs without moving other buckets")
	result = sim.transfer_storage_stack_to_inventory(Vector2i(22,23),String(result.held_item_id)+":0",outgoing_origin,0)
	check(result.success and bool(result.get("exchanged",false)),"Reverse cross-grid exchange is supported")
	check(sim.get_item_instance(outgoing_id).location.kind == "inventory" and sim.get_item_instance(stored_ids[0]).location.kind == "storage","Reverse exchange preserves physical ownership")
	sim = fresh()
	sim.set_player_position(sim.content.cell_center(22,22))
	sim.try_pickup_item("core:wood",3)
	var original: Vector2i = place(sim,"core:wood",0).origin
	sim.state.storage_items = [{"cell":[22,22],"item_id":"core:wood","amount":5,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"}]
	result = sim.transfer_storage_stack_to_inventory(Vector2i(22,22),"core:wood:0",original,0)
	check(result.success and int(result.get("remaining_source",0)) == 3,"Taking onto partial bag stack leaves excess in warehouse")
	check(place(sim,"core:wood",0).amount == 5 and sim.state.storage_items[0].amount == 3,"Inbound partial merge conserves quantities")
	result = sim.transfer_storage_stack_to_inventory(Vector2i(22,22),"core:wood:0",Vector2i(3,3),0)
	check(result.success and place(sim,"core:wood",1).get("origin") == Vector2i(3,3),"Taking to free cell uses that cell without relocating prior stack")
	check(place(sim,"core:wood",0).origin == original,"Inbound transfer preserves existing placement")
	sim = fresh()
	sim.set_player_position(sim.content.cell_center(22,23))
	stored_ids = sim._create_item_instances("core:bucket",1,"storage","core:bucket:0",{"charges":2})
	sim.state.storage_items.append({"cell":[22,23],"item_id":"core:bucket","amount":1,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:bucket:0","instance_id":stored_ids[0]})
	sim.try_pickup_item("core:bucket",1)
	untouched_id = sim.get_inventory_instance_id("core:bucket",0)
	untouched_origin = place(sim,"core:bucket",0).origin
	result = sim.transfer_storage_stack_to_inventory(Vector2i(22,23),"core:bucket:0",Vector2i(3,2),0)
	check(result.success and place(sim,"core:bucket",0).get("instance_id") == stored_ids[0] and place(sim,"core:bucket",0).origin == Vector2i(3,2),"Taking earlier-created physical tool preserves requested cells")
	check(place(sim,"core:bucket",1).get("instance_id") == untouched_id and place(sim,"core:bucket",1).origin == untouched_origin,"Taking earlier-created tool does not relocate existing one")
	print("PLAYTEST_INVENTORY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
