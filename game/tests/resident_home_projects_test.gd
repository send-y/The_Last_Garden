extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const NPC := Fixture.NPC
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var probe = Fixture.create()
	check(probe.get_npc_personal_goal(NPC).has("expansion"), "Home projects expose persistent expansion requests")
	if not probe.get_npc_personal_goal(NPC).has("expansion"):
		quit(1)
		return
	_test_communal_authority()
	_test_furnishing_and_reload()
	_test_reserve_and_stale_withdrawal()
	_test_expansion_and_recovery()
	_test_shared_room()
	_test_parallel_withdrawal_and_role_change()
	_test_replaced_blueprint_and_malformed_expansion()
	_test_personal_layout_preferences()
	if failures == 0:
		print("PASS: resident homes, common-house authority, real furniture, reserves, expansion and save continuity")
	quit(0 if failures == 0 else 1)

func _test_personal_layout_preferences() -> void:
	var Layout := preload("res://src/npc_work/home_furnishing_layout.gd")
	var sim = Fixture.create()
	var npc: Dictionary = sim.state.npcs[NPC]
	var near := Vector2i(-1,-1)
	var far := Vector2i(-1,-1)
	for value: String in ["core:care", "core:independence"]:
		sim.state.npc_profiles[NPC] = {"value_ids":[value]}
		var rng := RandomNumberGenerator.new()
		rng.seed = 91
		var cell := Layout.choose_cell(sim,npc,"core:table",rng)
		check(cell != Vector2i(-1,-1) and Layout.can_place(sim,npc,"core:table",cell), "Preferences select a real safe furniture position")
		if value == "core:care": near = cell
		else: far = cell
	var bed := Fixture.ORIGIN
	check(absi(near.x-bed.x)+absi(near.y-bed.y) < absi(far.x-bed.x)+absi(far.y-bed.y), "Care and independence produce distinct table placement relative to sleeping area with identical seed")

func _test_replaced_blueprint_and_malformed_expansion() -> void:
	var Command := preload("res://src/construction/construction_command.gd")
	for replacement: String in ["core:torch", "same"]:
		for rehousing: bool in [true, false]:
			var sim = Fixture.create()
			Fixture.stock(sim, 70)
			sim.set_npc_work_enabled(NPC, "build", true)
			sim.advance_minutes(1)
			var goal: Dictionary = sim.state.npcs[NPC].home_goal
			check(not goal.is_empty() and goal.placed, "Resident creates actual owned blueprint before replacement")
			if goal.is_empty(): continue
			var cell := Vector2i(int(goal.cell[0]),int(goal.cell[1]))
			check(sim.execute_construction_command(Command.cancel_blueprint(cell)).success, "Player removes old NPC blueprint")
			var building := String(goal.building_id) if replacement == "same" else replacement
			check(sim.execute_construction_command(Command.place_blueprint(cell,building)).success, "Player places replacement blueprint")
			if rehousing:
				sim.state.sleep_assignments.erase(NPC)
				sim.NpcHomeProjects.refresh_authority(sim,sim.state.npcs[NPC])
			else:
				sim.defer_npc_personal_goal(NPC)
			check(not sim._find_blueprint([cell.x,cell.y]).is_empty(), "Rehousing or deferring preserves player's replacement even for identical furniture")
	var malformed = Fixture.create()
	malformed.state.npcs[NPC].home_expansion = {"building_id":15,"room_id":false}
	var restored = World.new(JSON.parse_string(JSON.stringify(malformed.export_state())))
	check(restored.state.npcs[NPC].home_expansion.is_empty(), "Malformed expansion safely normalizes to empty")

func _test_communal_authority() -> void:
	var state := World.create_new_game_state()
	state.day = 2
	state.flags.first_night_complete = true
	state.minute_of_day = 9 * 60
	state.elapsed_game_minutes = 1980
	state.npcs[NPC].known = true
	state.npcs[NPC].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	state.structures.append({"building_id":"core:bedroll","cell":[20,23]})
	state["sleep_assignments"] = {"core:player":"core:starter_bedroll",NPC:"core:bedroll@20,23"}
	var sim = World.new(state)
	sim.set_npc_work_enabled(NPC, "build", true)
	sim.advance_minutes(1)
	check(sim.get_npc_personal_goal(NPC).goal.is_empty() and sim.get_npc_personal_goal(NPC).status == "communal",
		"Mira cannot autonomously decorate the settlement's common house")
	check(sim.state.blueprints.is_empty(), "Common house gets no unsolicited blueprint")

func _test_furnishing_and_reload() -> void:
	var sim = Fixture.create()
	Fixture.stock(sim, 110)
	sim.set_npc_work_enabled(NPC, "build", true)
	sim.advance_minutes(5)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	check(not report.goal.is_empty() and report.housing.mode == "personal", "A bare personal home creates a real furniture intention")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(restored.get_npc_personal_goal(NPC) == report, "Goal, role and reserve reports survive JSON reload")
	sim.advance_minutes(100)
	restored.advance_minutes(100)
	check(sim.export_state() == restored.export_state(), "Reload during physical home work preserves deterministic development")
	if sim.get_npc_personal_goal(NPC).completed.is_empty():
		print("UNFINISHED_HOME ",sim.get_npc_personal_goal(NPC)," npc=",sim.state.npcs[NPC].initiative_job," pos=",sim.state.npcs[NPC].position)
	check(not sim.get_npc_personal_goal(NPC).completed.is_empty(), "Resident physically completes household furniture")
	var spent := 0
	for entity: Dictionary in sim.state.structures:
		if String(entity.building_id) in ["core:table","core:chair","core:torch"]:
			spent += int(sim.building_catalog.get_material_cost(String(entity.building_id)).get("core:plank", 0))
	var remaining := 0
	for record: Dictionary in sim.state.storage_items:
		if String(record.item_id) == "core:plank": remaining += int(record.amount)
	for blueprint: Dictionary in sim.state.blueprints:
		remaining += int(blueprint.delivered_materials.get("core:plank", 0))
	for npc: Dictionary in sim.state.npcs.values():
		remaining += int(npc.work_cargo.get("core:plank", 0))
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id) == "core:plank": remaining += int(drop.amount)
	check(remaining + spent == 110, "Furniture consumes only real planks and preserves cargo on interruption")
	var before := JSON.stringify(sim.export_state())
	sim.get_npc_personal_goal(NPC)
	check(JSON.stringify(sim.export_state()) == before, "Home report does not mutate state")

func _test_reserve_and_stale_withdrawal() -> void:
	var sim = Fixture.create()
	Fixture.stock(sim, 35)
	check(sim.set_stock_reserve("core:plank", 35).success, "Player protects all currently stored planks")
	sim.set_npc_work_enabled(NPC, "build", true)
	sim.advance_minutes(1)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	if report.status != "reserve": print("RESERVE_REPORT ",report)
	check(report.status == "reserve" and not report.protected.is_empty(), "Resident explains protected stock instead of claiming it does not exist")
	check(sim.state.blueprints.is_empty(), "Protected stock does not produce an unfunded personal blueprint")
	var goal: Dictionary = sim.state.npcs[NPC].home_goal
	check(not goal.is_empty(), "Reserve delays rather than deletes the intention")
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.initiative_job = {"kind":"build","phase":"take_materials","cell":goal.cell.duplicate(),"drops":[]}
	npc.position = [Content.cell_center(38,31).x,Content.cell_center(38,31).y]
	var source := Supply.find_stock(sim,npc,"core:plank")
	check(not source.is_empty(), "Stale context points to actual stock")
	check(not Supply.take_material(sim,npc,source,5), "Withdrawal rechecks the reserve even with a previously selected source")
	check(npc.work_cargo.is_empty(), "Protected stock did not become cargo")
	npc.initiative_job = {}
	sim.set_stock_reserve("core:plank", 0)
	sim.advance_minutes(100)
	check(not sim.get_npc_personal_goal(NPC).completed.is_empty(), "Lowering reserve lets the same project resume")

func _test_expansion_and_recovery() -> void:
	var sim = Fixture.create(false, Vector2i(3,2))
	var npc: Dictionary = sim.state.npcs[NPC]
	npc.position = [Content.cell_center(42,31).x,Content.cell_center(42,31).y]
	# Occupy the available room while leaving the assigned bed reachable.
	for cell: Array in [[42,30],[40,31]]:
		sim.add_structure({"building_id":"core:torch","cell":cell,"lit":true})
	sim._sync_structure_navigation()
	sim.set_npc_work_enabled(NPC, "build", true)
	sim.advance_minutes(1)
	var report: Dictionary = sim.get_npc_personal_goal(NPC)
	if report.expansion.is_empty(): print("EXPANSION_REPORT ",report," npc=",npc.position)
	check(report.status == "expansion" and not report.expansion.is_empty(), "A cramped room generates an explained expansion request")
	check(report.expansion.get("room_id", "") == Fixture.ROOM and report.expansion.get("building_id", "") == "core:table", "Request identifies the room and desired furniture")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(restored.get_npc_personal_goal(NPC).expansion == report.expansion, "Expansion request survives save/load")
	# Keep the same resident, request, bed and simulation while rebuilding the enclosure.
	var enlarged = Fixture.create()
	check(sim.remove_room_at(Vector2i(40,31)).success, "Player can remove the old designation before expanding the foundation")
	sim.replace_structures(enlarged.state.structures.duplicate(true))
	sim._sync_structure_navigation()
	check(sim.assign_room_type("core:living_room",Vector2i(40,31)).success, "Enlarged foundation can be designated again without prebuilding comfort furniture")
	sim.advance_minutes(35)
	check(sim.get_npc_personal_goal(NPC).expansion.is_empty() and not sim.get_npc_personal_goal(NPC).goal.is_empty(),
		"A viable enlarged room clears the request and starts a furniture intention")
	# A nearby player hears the same request without opening hidden personality fields.
	restored.set_player_position(restored.get_npc_position(NPC,Vector2.ZERO) + Vector2(0,32))
	var conversation: Dictionary = restored.choose_npc_conversation(NPC,"home")
	check(bool(conversation.get("ok",false)) and String(conversation.get("pages",[{}])[0].get("text_key","")) == "conversation.home.expansion",
		"Resident explains expansion in the home conversation")

func _test_shared_room() -> void:
	var sim = Fixture.create(true)
	for id: String in sim.state.npcs:
		if id == NPC or id.begins_with("core:resident_"):
			sim.set_npc_work_enabled(id, "build", true)
	sim.advance_minutes(1)
	var chosen: Dictionary = {}
	for npc: Dictionary in sim.state.npcs.values():
		var goal: Dictionary = npc.home_goal
		if goal.is_empty(): continue
		var key := String(goal.building_id)
		check(not chosen.has(key), "Housemates do not independently order duplicate furniture")
		chosen[key] = true
	check(chosen.size() > 0, "Shared house supports autonomous household projects")

func _test_parallel_withdrawal_and_role_change() -> void:
	var sim = Fixture.create(true)
	Fixture.stock(sim, 40)
	sim.set_stock_reserve("core:plank", 30)
	var second := "core:resident_1"
	for id: String in [NPC,second]:
		var npc: Dictionary = sim.state.npcs[id]
		npc.position = [Content.cell_center(38,31).x,Content.cell_center(38,31).y]
		npc.work_options.build = true
		npc.home_goal = sim.NpcHomeProjects.clean_goal({"building_id":"core:table","cell":[42,31],"room_id":Fixture.ROOM,
			"place_id":sim.state.sleep_assignments[id],"action":"build"})
		npc.initiative_job = {"kind":"build","phase":"take_materials","cell":[42,31],"drops":[]}
	var first: Dictionary = sim.state.npcs[NPC]
	var other: Dictionary = sim.state.npcs[second]
	var selected_before_reserve := Supply.find_stock(sim,first,"core:plank")
	sim.set_stock_reserve("core:plank", 40)
	check(not Supply.take_material(sim,first,selected_before_reserve,20), "Raising reserve invalidates an earlier stock selection")
	sim.set_stock_reserve("core:plank", 30)
	check(Supply.take_material(sim,first,selected_before_reserve,20), "First worker can take only the surplus")
	var next_source := Supply.find_stock(sim,other,"core:plank")
	check(not Supply.take_material(sim,other,next_source,20) and sim.StockReserves.total(sim,"core:plank") == 30,
		"A second worker cannot take the protected remainder")
	check(sim.set_home_mode(Fixture.ROOM,"settlement").success, "Player can make a shared house communal while supplies are in transit")
	sim.advance_minutes(1)
	check(first.initiative_job.is_empty() or String(first.initiative_job.phase) == "return", "Role change interrupts personal work and returns its real cargo")
	check(sim.get_npc_personal_goal(NPC).status == "communal", "Communal ownership explains why the furniture project stopped")
	var total: int = sim.StockReserves.total(sim,"core:plank")
	for npc: Dictionary in sim.state.npcs.values(): total += int(npc.work_cargo.get("core:plank",0))
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id) == "core:plank": total += int(drop.amount)
	check(total == 40, "Ownership change preserves all physical supplies")
