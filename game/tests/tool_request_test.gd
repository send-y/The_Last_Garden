extends SceneTree
const Lab := preload("res://src/dev/mechanics_lab_scenarios.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Command := preload("res://src/construction/construction_command.gd")
const Request := preload("res://src/simulation/npc_work_request.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var result: Dictionary = Lab.build(Lab.MORNING_WITH_MIRA)
	var sim = result.simulation
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.known = true
	npc.personal_inventory["core:plank"] = 30
	var id: String = sim._create_item_instances("core:mallet",1,"npc",String(npc.id))[0]
	npc.carried_instance_id = id
	sim = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	npc = sim.state.npcs["core:first_neighbor"]
	check(sim.actor_tool_supports(String(npc.id),"build"), "Owned mallet survives reload")
	var cell := Vector2i(21,29)
	check(sim.execute_construction_command(Command.place_wall_blueprint(cell)).success, "Request fixture has real wall blueprint")
	sim.set_player_position(sim.get_npc_position(String(npc.id), Vector2.ZERO))
	sim._set_instance_location(id,"inventory")
	npc.carried_instance_id = ""
	var before: Dictionary = sim.export_state()
	check(not sim.execute_npc_work_request(Request.request_construction_help(String(npc.id),cell)).success and sim.export_state() == before, "A request without an accessible mallet refuses without committing material")
	sim._set_instance_location(id,"npc",String(npc.id))
	npc.carried_instance_id = id
	check(sim.execute_npc_work_request(Request.request_construction_help(String(npc.id),cell)).success, "Explicit request is accepted with worker's mallet")
	sim.advance_minutes(14)
	check(sim._find_blueprint([21,29]).get("work_progress_minutes",0) > 0, "Explicit worker keeps and uses their mallet rather than returning it")
	sim.advance_minutes(40)
	check(not sim._find_structure([21,29]).is_empty() and sim.get_npc_work_commitment(String(npc.id)).is_empty(), "Explicit construction completes and closes commitment")
	check(sim.get_npc_memories(String(npc.id)).size() == 1, "Shared-wall memory is preserved")
	print("TOOL_REQUEST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
