extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var sim := World.new(preload("res://src/dev/package_d_scenarios.gd").day_three_state())
	var values: Array = sim.state.storage_zones[0].cells[0]
	var cell := Vector2i(int(values[0]),int(values[1]))
	sim.set_player_position(sim.content.cell_center(cell.x,cell.y))
	sim._add_item("core:bucket",1)
	var id := sim.get_inventory_instance_id("core:bucket",0)
	check(bool(sim.assign_hotbar_slot(2,id).success),"Assign physical bucket")
	sim.select_hotbar_slot(2)
	check(bool(sim.transfer_inventory_stack_to_storage(cell,"core:bucket",0).success),"Store assigned physical bucket")
	check(sim.get_hotbar_slots()[2]==id,"Storage preserves ghost binding")
	check(sim.get_active_item_instance().is_empty() and sim.get_held_item().is_empty(),"Ghost has no physical tool authority")
	sim = World.new(sim.export_state())
	check(sim.get_hotbar_slots()[2]==id,"Ghost survives reload")
	sim._add_item("core:bucket",1)
	check(sim.get_active_item_instance().is_empty(),"Another identical bucket does not replace reserved instance")
	var placement := ""
	for record: Dictionary in sim.state.storage_items:
		if String(record.get("instance_id",""))==id: placement = String(record.placement_id)
	check(bool(sim.transfer_storage_stack_to_inventory(cell,placement).success),"Same physical bucket returns")
	check(String(sim.get_active_item_instance().get("instance_id",""))==id,"Return restores original selected slot automatically")
	var index := -1
	for item: Dictionary in sim.get_inventory_placements():
		if String(item.get("instance_id",""))==id: index = int(item.stack_index)
	check(bool(sim.drop_inventory_stack("core:bucket",index).success),"Drop assigned bucket on map")
	check(sim.get_hotbar_slots()[2]==id and sim.get_active_item_instance().is_empty(),"Ground drop leaves unavailable ghost")
	sim = World.new(sim.export_state())
	check(sim.get_hotbar_slots()[2]==id and sim.get_active_item_instance().is_empty(),"Ground ghost survives reload without tool authority")
	var drop_id := ""
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.get("instance_id",""))==id: drop_id = String(drop.drop_id)
	check(bool(sim.try_pickup_world_drop(drop_id).success),"Pick up same bucket")
	check(String(sim.get_active_item_instance().get("instance_id",""))==id,"Pickup restores same slot")
	index = -1
	for item: Dictionary in sim.get_inventory_placements():
		if String(item.get("instance_id",""))==id: index = int(item.stack_index)
	sim.drop_inventory_stack("core:bucket",index)
	var replacement := sim.get_inventory_instance_id("core:bucket",0)
	check(bool(sim.assign_hotbar_slot(2,replacement).success),"Player can replace reserved binding")
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.get("instance_id",""))==id: drop_id = String(drop.drop_id)
	sim.try_pickup_world_drop(drop_id)
	check(sim.get_hotbar_slots()[2]==replacement,"Returning former item does not override new assignment")
	print("PASS: physical hotbar ghosts and return" if failures==0 else "FAIL: hotbar ghost")
	quit(0 if failures==0 else 1)
