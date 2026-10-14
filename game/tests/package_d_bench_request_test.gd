extends "res://tests/package_d_shared_production_test.gd"

func run() -> void:
	var sim = fixture(false)
	var npc: Dictionary = sim.state.npcs[NPC]
	var offers := 0
	for i: int in range(60):
		sim.advance_minutes(1)
		if String(npc.get("workbench_request",{}).get("status","")) == "offered":
			offers += 1
			break
	check(offers == 1,"Resident physically approaches player and offers one missing-workbench request")
	if offers == 0: print("REQUEST_DIAGNOSTIC: ",npc.get("workbench_request",{})," pos=",npc.position," activity=",npc.activity_id)
	check(sim.get_npc_position(NPC,Vector2.ZERO).distance_to(sim.get_player_position()) <= Content.INTERACTION_RANGE,"Request is spoken within actual interaction range")
	if offers == 0:
		print("PACKAGE_D_BENCH_REQUEST: %d failures" % failures)
		quit(1)
		return
	var serial: int = npc.workbench_request.serial
	sim.advance_minutes(30)
	check(int(npc.workbench_request.serial) == serial,"Pending request never repeats each work planning tick")
	sim.set_player_position(sim.get_npc_position(NPC,Vector2.ZERO)+Vector2(32,0))
	var response: Dictionary = sim.choose_npc_conversation(NPC,"bench_accept")
	check(bool(response.get("ok",false)) and String(npc.workbench_request.status) == "accepted","Player accepts structured request through conversation")
	var loaded = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(loaded.state.npcs[NPC].workbench_request == npc.workbench_request,"Request survives JSON reload")
	loaded.add_structure({"building_id":"core:workbench","cell":[BENCH.x,BENCH.y],"stage_id":"core:complete"})
	loaded._sync_structure_navigation()
	loaded.advance_minutes(220)
	check(String(loaded.state.npcs[NPC].workbench_request.status) == "fulfilled","Actual accessible workbench fulfils accepted request")
	check(String(loaded._find_structure([TARGET.x,TARGET.y]).get("building_id","")) == "core:wood_wall","Resident really uses new workbench to complete intended shared wall")
	sim = fixture(false)
	sim.advance_minutes(30)
	npc = sim.state.npcs[NPC]
	sim.set_player_position(sim.get_npc_position(NPC,Vector2.ZERO)+Vector2(32,0))
	sim.choose_npc_conversation(NPC,"bench_decline")
	check(String(npc.get("workbench_request",{}).get("status","")) == "declined","Refusal is handled without disabling build permission")
	check(bool(npc.work_options.build),"Refusal never blocks resident's life or work permissions")
	var memories: int = npc.memories.size()
	sim.choose_npc_conversation(NPC,"bench_decline")
	check(npc.memories.size() == memories,"Repeated refusal does not duplicate memory")
	sim.advance_minutes(90)
	check(String(npc.workbench_request.status) == "declined","Cooldown prevents immediate repeated request")
	var busy = fixture(true)
	busy.state.inventory["core:wood"] = 5
	check(bool(busy._start_crafting_project([BENCH.x,BENCH.y],"core:workbench","core:saw_planks").success),"Player owns actual busy station")
	busy.advance_minutes(60)
	check(busy.state.npcs[NPC].get("workbench_request",{}).is_empty(),"Temporarily busy workbench produces waiting rather than another-building request")
	var no_task = fixture(false)
	no_task.state.blueprints.clear()
	no_task.advance_minutes(60)
	check(no_task.state.npcs[NPC].get("workbench_request",{}).is_empty(),"Without plank-dependent task there is no workshop request")
	print("PACKAGE_D_BENCH_REQUEST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
