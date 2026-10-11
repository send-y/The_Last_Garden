extends SceneTree

const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	check(not Scenarios.get_definition(&"settlement_stress").is_empty(), "Thirty-resident stress scenario is available in the laboratory")
	if failures > 0:
		quit(1)
		return
	var result: Dictionary = Scenarios.build(&"settlement_stress")
	check(bool(result.success), "Stress settlement can be constructed: " + String(result.get("message", "")))
	if not result.success:
		quit(1)
		return
	var sim = result.simulation
	print("STRESS_FIXTURE built_ms=", result.get("build_ms", 0), " stacks=", sim.state.storage_items.size())
	var homes: Dictionary = {}
	var residents := 0
	for npc: Dictionary in sim.state.npcs.values():
		if not bool(npc.active): continue
		residents += 1
		check(npc.known and npc.residency == "resident", "Every participant is a known resident")
		for kind: String in ["water", "gather", "build"]:
			check(bool(npc.work_options[kind]), "Every resident has permission for " + kind)
		var home: Dictionary = sim.get_home_policy(String(npc.id))
		check(home.mode == "personal" and home.may_furnish, "Every resident may furnish a personal home")
		check(not homes.has(home.room_id), "Each resident owns a separate home")
		homes[home.room_id] = true
	check(residents == 30 and homes.size() == 30, "Exactly thirty residents occupy thirty different homes")
	check(sim.get_farm_beds().size() == 60, "Each household has two live planted beds")
	var helper = load("res://src/dev/settlement_stress_scenario.gd")
	var first: Dictionary = {}
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == "core:plank":
			first = record
			break
	check(not first.is_empty(), "Warehouse contains actual plank stacks")
	first.amount = 0
	check(helper.replenish(sim), "Consumed stock is replenished by the laboratory")
	check(int(first.amount) > 0 or not sim.state.storage_items.has(first), "Supply retains valid nonempty stacks")
	var loaded = World.new(sim.export_state())
	check(loaded.state.storage_zones.size() == sim.state.storage_zones.size() and not loaded.state.storage_zones.is_empty(), "Real warehouse zones survive reload")
	check(loaded.state.storage_items.size() == sim.state.storage_items.size(), "All real supplies and shared tools remain on warehouse after reload (%d -> %d)" % [sim.state.storage_items.size(), loaded.state.storage_items.size()])
	for tool_id: String in ["core:axe", "core:pickaxe", "core:hoe", "core:bucket"]:
		var tool_count := 0
		for record: Dictionary in loaded.state.storage_items:
			if String(record.item_id) == tool_id and not loaded.get_item_instance(String(record.get("instance_id", ""))).is_empty(): tool_count += 1
		check(tool_count == 30, "Thirty physical shared tools survive reload: %s (%d found)" % [tool_id, tool_count])
	check(loaded.state.sleep_assignments == sim.state.sleep_assignments, "Checkpoint round trip preserves all individual sleeping assignments")
	check(loaded.state.npc_profiles.size() == sim.state.npc_profiles.size(), "Round trip preserves generated identities")
	var start: int = loaded.get_elapsed_game_minutes()
	print("STRESS_FIXTURE reload validated; advancing first minute")
	loaded.advance_minutes(1)
	check(loaded.get_elapsed_game_minutes() == start + 1, "All thirty residents can execute a normal minute")
	print("SETTLEMENT_STRESS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
