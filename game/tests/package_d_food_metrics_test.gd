extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ",label)
func run() -> void:
	var sim := World.new()
	sim.work_metrics.enabled = true
	check(sim.work_metrics.has_method("food_snapshot"),"Actual meal consumption is observed separately from transfers")
	if not sim.work_metrics.has_method("food_snapshot"):
		print("PACKAGE_D_FOOD_METRICS: %d failures" % failures)
		quit(1)
		return
	sim.try_pickup_item("core:food",1)
	check(bool(sim.eat_food("core:food").success),"Real player meal succeeds")
	sim.eat_food("core:food")
	var metrics: Variant = sim.work_metrics
	check(metrics.food_snapshot(1).get("core:player",{}).get("core:food",0) == 1,"Failed meal never increases consumption counter")
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.active = true
	var cell := sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO))
	var effect := {"npc_id":String(npc.id),"meal":{"source":"personal","item_id":"core:food","target_cell":[cell.x,cell.y]}}
	check(bool(sim.NpcFoodSupply.fulfil(sim,effect)),"Actual NPC personal meal succeeds")
	check(metrics.food_snapshot(1).get(String(npc.id),{}).get("core:food",0) == 1,"Actual NPC portions are counted")
	var loaded := World.new(sim.export_state())
	check(loaded.work_metrics.food_snapshot(1).is_empty(),"Debug meal metrics are not persistent game state")
	print("PACKAGE_D_FOOD_METRICS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
