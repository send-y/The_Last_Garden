extends SceneTree
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Planner := preload("res://src/npc_work/npc_work_planner.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func fixture():
	var state := preload("res://tests/fixtures/stocked_tool_state.gd").prepare(World.create_new_game_state())
	state.day = 2
	state.minute_of_day = 540
	state.elapsed_game_minutes = 1980
	state.flags.first_night_complete = true
	state.flags.repair_stage = 2
	state.npcs["core:first_neighbor"].known = true
	state.npcs["core:first_neighbor"].needs.hunger = 100.0
	for records: Array in [state.item_instances, state.storage_items]:
		for record: Dictionary in records:
			record.item_id = "test:" + String(record.item_id).trim_prefix("core:") + "_variant"
	return Fixture.world(state)
func run() -> void:
	var sim = fixture()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.work_options.gather = true
	var job: Dictionary = Planner.choose(sim, npc)
	check(not job.is_empty(), "Planner finds gathering with only JSON variants")
	var supply = Supply.new()
	var supply_script: Variant = Supply
	check(supply.has_method("find_tool_stock") and supply.has_method("borrow_tool"), "Safe capability-based borrowing API")
	if failures > 0:
		finish()
		return
	check(String(job.tool_id).begins_with("test:"), "Job stores actual model ID")
	var source: Dictionary = supply_script.find_tool_stock(sim, npc, "chop")
	check(source.record.item_id == "test:axe_variant", "First compatible stock")
	var live: Dictionary = sim.state.storage_items[0]
	var remembered: Dictionary = source.record.duplicate(true)
	live.item_id = "test:hoe_variant"
	check(source.record == remembered, "Prepared context is isolated")
	var point: Vector2 = sim.content.cell_center(int(live.cell[0]), int(live.cell[1]))
	npc.position = [point.x, point.y]
	check(not supply_script.borrow_tool(sim, npc, source, "chop"), "Stale swapped storage record rejected")
	live.item_id = "test:axe_variant"
	var id := String(source.record.instance_id)
	sim._set_instance_location(id, "npc", "someone_else")
	check(not supply_script.borrow_tool(sim, npc, source, "chop"), "Foreign registry ownership rejected")
	sim._set_instance_location(id, "storage", String(live.placement_id))
	check(supply_script.borrow_tool(sim, npc, source, "chop"), "Actual physical transfer succeeds")
	var second: Dictionary = npc.duplicate(true)
	second.id = "test:other_npc"
	second.carried_instance_id = ""
	check(not supply_script.borrow_tool(sim, second, source, "chop"), "Second resident cannot duplicate borrowed instance")
	Supply.deposit_at(sim, npc, Vector2i(int(live.cell[0]), int(live.cell[1])))
	check(String(sim.get_item_instance(id).location.kind) == "storage" and npc.carried_instance_id == "", "Exact borrowed instance returned")
	var watered = fixture()
	watered.state.farming.beds.append({"cell": [18,29], "crop_id": "carrot", "growth": 0, "wet_until": 0, "last_update": 1980, "harvests": 0})
	watered.set_npc_work_enabled("core:first_neighbor", "water", true)
	watered.advance_minutes(160)
	check(watered.get_farm_bed(Vector2i(18,29)).wet_until > watered.get_elapsed_game_minutes(), "Resident fills and waters with variant")
	var bucket: Dictionary = watered.get_item_instance("core:item_instance_000001")
	check(bucket.item_id == "test:bucket_variant" and bucket.location.kind == "storage" and bucket.state.charges == 3, "Returns same four-charge bucket with three")
	var gathering = fixture()
	gathering.set_npc_work_enabled("core:first_neighbor", "gather", true)
	gathering.advance_minutes(240)
	check(Planner.stock(gathering, "core:wood") + Planner.stock(gathering, "core:stone") > 0, "Variants produce and haul real resources")
	for phase: String in ["borrow", "refill", "work", "return"]:
		var persisted = fixture()
		var resident: Dictionary = persisted.state.npcs["core:first_neighbor"]
		resident.initiative_job = {"kind": "water", "phase": phase, "tool_id": "test:bucket_variant", "cell": [18,29], "water_cell": [12,30], "drops": []}
		if phase != "borrow":
			persisted.state.storage_items = persisted.state.storage_items.filter(func(record): return String(record.instance_id) != "core:item_instance_000001")
			persisted._set_instance_location("core:item_instance_000001", "npc", String(resident.id))
			resident.carried_instance_id = "core:item_instance_000001"
			persisted._update_instance_state(resident.carried_instance_id, {"charges": 3})
		var restored := Fixture.world(JSON.parse_string(JSON.stringify(persisted.export_state())))
		check(restored.state.npcs[resident.id].initiative_job == resident.initiative_job and restored.state.npcs[resident.id].carried_instance_id == resident.carried_instance_id, "Reload phase " + phase)
	var deprecated = fixture()
	var deprec_npc: Dictionary = deprecated.state.npcs["core:first_neighbor"]
	for records: Array in [deprecated.state.item_instances, deprecated.state.storage_items]:
		for record: Dictionary in records:
			if String(record.item_id) == "test:axe_variant": record.item_id = "test:deprecated_axe"
	var compatible: Dictionary = supply_script.find_tool_stock(deprecated, deprec_npc, "chop")
	check(not compatible.is_empty() and compatible.record.item_id == "test:deprecated_axe", "Known deprecated warehouse tool can still be borrowed")
	var anchor: Vector2 = deprecated.content.cell_center(int(compatible.record.cell[0]), int(compatible.record.cell[1]))
	deprec_npc.position = [anchor.x, anchor.y]
	check(supply_script.borrow_tool(deprecated, deprec_npc, compatible, "chop"), "Deprecated physical transfer succeeds")
	deprec_npc.initiative_job = {"kind": "gather", "phase": "work", "tool_id": "test:deprecated_axe", "cell": [18,29], "resource_item": "core:wood", "target_id": "core:wood_north", "drops": []}
	var saved := Fixture.world(JSON.parse_string(JSON.stringify(deprecated.export_state())))
	check(saved.state.npcs[deprec_npc.id].initiative_job.tool_id == "test:deprecated_axe" and saved.get_item_instance(deprec_npc.carried_instance_id).item_id == "test:deprecated_axe", "Deprecated borrowed tool and job survive reload")
	var stale = fixture()
	var stale_npc: Dictionary = stale.state.npcs["core:first_neighbor"]
	var stale_source: Dictionary = supply_script.find_tool_stock(stale, stale_npc, "chop")
	stale.state.storage_items.erase(stale_source.record)
	check(not supply_script.borrow_tool(stale, stale_npc, stale_source, "chop"), "Removed prepared source cannot be borrowed")
	finish()
func finish() -> void:
	print("ITEM_TOOL_NPC: %d failures" % failures)
	quit(0 if failures == 0 else 1)
