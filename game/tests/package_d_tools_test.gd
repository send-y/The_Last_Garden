extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func store(sim, id: String) -> String:
	check(bool(sim.try_pickup_item(id,1).success), "Physical tool picked up: " + id)
	var instance: String = sim.get_inventory_instance_id(id,0)
	sim.set_player_position(Content.cell_center(23,24))
	check(bool(sim.transfer_inventory_stack_to_storage(Vector2i(23,23),id,0).success), "Physical tool stored: " + id)
	return instance
func run() -> void:
	for pair: Array in [["axe","chop"],["pickaxe","mine"],["mallet","build"],["hoe","till"]]:
		var sim = World.new(World.create_new_game_state())
		var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
		npc.active = true
		npc.known = true
		npc.position = [Content.cell_center(24,24).x,Content.cell_center(24,24).y]
		var weak := store(sim,"core:" + String(pair[0]))
		var strong := store(sim,"core:" + String(pair[0]) + "_steel")
		var chosen: Dictionary = Supply.find_tool_stock(sim,npc,String(pair[1]))
		check(chosen.get("record",{}).get("instance_id","") == strong, "Best tool selected regardless of stock order: " + String(pair[0]))
		sim.state.storage_items.reverse()
		check(Supply.find_tool_stock(sim,npc,String(pair[1])).get("record",{}).get("instance_id","") == strong, "Reversing stock does not change tier preference")
		# Stale storage claims must never authorize taking a player's tool.
		sim._set_instance_location(strong,"inventory","")
		check(Supply.find_tool_stock(sim,npc,String(pair[1])).get("record",{}).get("instance_id","") == weak, "Stale best-tool record is excluded by physical ownership")
	print("PACKAGE_D_TOOLS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
