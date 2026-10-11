extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Registry := preload("res://src/inventory/item_instance_registry.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func reference(sim) -> Dictionary:
	var result: Dictionary = sim._inventory_mutable().duplicate(true)
	for id: String in sim.content.item_ids():
		if sim.content.item_is_instance_based(id): result[id] = Registry.in_location(sim.state,id,"inventory").size()
	return result
func run() -> void:
	var sim := World.new()
	sim.state.inventory["core:plank"] = 8
	var ids: Array[String] = []
	for id: String in ["core:axe","core:pickaxe","core:hoe","core:bucket"]:
		ids.append_array(sim._create_item_instances(id,30,"inventory"))
	for index: int in range(ids.size()):
		if index % 3 != 0: sim._set_instance_location(ids[index],"storage" if index % 3 == 1 else "npc","core:test")
	var expected := reference(sim)
	var before := sim.export_state()
	Trace.reset()
	Trace.enabled = true
	check(sim.get_inventory() == expected,"One-pass inventory counts agree with per-item registry queries for all owners")
	check(int(Trace.counters.get("inventory.instance_records",0)) == sim.state.item_instances.size(),"Inventory counting visits each physical instance exactly once regardless of tool types")
	Trace.enabled = false
	check(sim.export_state() == before,"Counting is read-only and derives no saved state")
	sim._set_instance_location(ids[0],"storage","core:test")
	check(sim.get_inventory() == reference(sim),"A live location change is reflected in the next query")
	sim.state.inventory["core:axe"] = 999
	check(sim.get_inventory() == reference(sim),"Legacy physical-item quantities are replaced by actual owned instances")
	var counts := sim.get_inventory()
	counts["core:plank"] = 0
	check(sim.get_inventory()["core:plank"] == 8,"Returned counts cannot mutate the player's inventory")
	print("INVENTORY_COUNT_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
