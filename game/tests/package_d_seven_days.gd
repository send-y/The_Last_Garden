extends "res://tests/run_tests.gd"

var sim: World
var checkpoints: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var station := Vector2i(-1,-1)
var axe := ""
var roof_minute := -1
var first_lines: Array = []
var food_start: Dictionary = {}

func _run() -> void:
	var comparisons: Array[Dictionary] = []
	for cost: float in [0.25,0.33]:
		comparisons.append(control(cost))
		if _failures > 0: break
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-artifact-dir="): path = arg.trim_prefix("--test-artifact-dir=").path_join("seven-days.json")
	_expect(not path.is_empty(),"Control report has an isolated artifact path")
	if not path.is_empty():
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"comparisons":comparisons,"failures":_failures,"limitations":"Scripted ordinary-route control with walking, real harvest/craft/storage, initial roof, floor blueprints, conversations, eating and sleeping. No artificial replenishment. Floor queue does not constitute finished new rooms; no crop plot is scripted. This does not prove feel, evening target energy, seven days without all hunger, or the author's warehouse tempo."},"\t"))
		file.close()
	print("PACKAGE_D_SEVEN_DAYS: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)

func control(cost: float) -> Dictionary:
	checkpoints = []
	rows = []
	first_lines = []
	sim = Simulation.new(Simulation.create_new_game_state(1337))
	sim.needs.config.work_energy_cost = cost
	sim.work_metrics.enabled = true
	sim.work_metrics.minute_observed.connect(sample_control)
	food_start = food_stock()
	sample_control()
	axe = _surface_route_take_tool(sim,"core:axe")
	_surface_route_interact(sim,"core:repair_room")
	_surface_route_harvest(sim,sim.get_surface_trees())
	var made := sim.execute_crafting_command(CraftingCommandScript.craft_in_hands("core:make_mallet"))
	_expect(bool(made.get("success",false)),"Ordinary mallet crafted")
	_surface_route_pick_drops(sim,made.get("created_drop_ids",[]))
	station = _surface_route_build_workbench(sim)
	_surface_route_saw_planks(sim,station)
	_surface_route_interact(sim,"core:repair_room")
	roof_minute = sim.get_elapsed_game_minutes()
	_surface_route_interact(sim,"core:repair_room")
	# Continue the first day; do not replace it with a day-two stocked fixture.
	while sim.get_day() <= 7 and _failures == 0:
		var day := sim.get_day()
		if day >= 2 and not bool(sim.state.npcs["core:first_neighbor"].first_meeting_complete): meet_mira()
		if day >= 2 and sim.state.blueprints.is_empty(): queue_floors()
		if sim.get_minute_of_day() >= 21*60:
			rows.append({"day":day,"food":food_stock(),"consumed_portions":sim.work_metrics.food_snapshot(day),"needs":sim.get_player_needs(),"energy":sim.get_player_energy(),"rooms":sim.state.room_assignments.size(),"structures":sim.state.structures.size(),"resident_work":sim.work_metrics.snapshot(day),"summary":sim.work_metrics.summary(day)})
			print("CONTROL cost=",cost," day=",day," energy=",sim.get_player_energy()," work=",sim.work_metrics.summary(day).work_per_resident)
			if day == 7: break
			_surface_route_interact(sim,"core:bed_site")
			continue
		var elapsed := sim.get_elapsed_game_minutes()
		if float(sim.get_player_needs().hunger) < 60:
			if sim.get_item_count("core:food") > 0: sim.eat_food("core:food")
			else: forage()
		elif sim.get_player_energy() < 20:
			sim.rest_player()
		elif sim.get_item_count("core:wood") >= 5:
			if day >= 2 and not sim.state.blueprints.is_empty(): deposit("core:wood")
			else:
				saw()
				deposit("core:plank")
		else:
			deposit("core:pinecone")
			sim.select_inventory_item("core:axe",axe)
			var trees: Array[Dictionary] = sim.get_surface_trees().filter(func(tree: Dictionary) -> bool: return String(tree.get("presentation_id","")) != "surface_stump" and not sim.is_collected(String(tree.id)))
			_surface_route_harvest(sim,trees)
		if sim.get_elapsed_game_minutes() == elapsed: sim.advance_minutes(1)
	_expect(rows.size() == 7,"Actual seven calendar days are observed")
	return {"work_energy_cost":cost,"food_start":food_start,"first_roof_elapsed_minutes":roof_minute,"checkpoints":checkpoints.duplicate(true),"days":rows.duplicate(true),"first_meeting":first_lines.duplicate(true)}

func meet_mira() -> void:
	var id := "core:first_neighbor"
	for attempt: int in range(20):
		if sim.get_player_position().distance_to(sim.get_npc_position(id,Vector2.ZERO)) <= 48.0: break
		_surface_route_move(sim,sim.get_npc_position(id,Vector2.ZERO),32.0)
	var view := sim.choose_npc_conversation(id,"greeting")
	_expect(bool(view.ok),"Actual first meeting succeeds on ordinary route")
	if not bool(view.ok): return
	first_lines = view.pages.duplicate(true)
	for i: int in range(view.pages.size()): sim.acknowledge_npc_utterance(id,String(view.utterance_id),i)
	var gift := sim.choose_npc_conversation(id,"take_supplies")
	if bool(gift.ok):
		for i: int in range(gift.pages.size()): sim.acknowledge_npc_utterance(id,String(gift.utterance_id),i)
	sim.close_npc_conversation()
	# A second physically crafted mallet enables shared construction.
	if sim.get_inventory_instance_id("core:mallet",0) != "": _surface_route_store_item(sim,"core:mallet",sim.get_inventory_instance_id("core:mallet",0))
	sim.set_npc_work_enabled(id,"build",true)

func queue_floors() -> void:
	var placed := 0
	for y: int in range(27,34):
		for x: int in range(17,29):
			if placed >= 12: return
			var result := sim.execute_construction_command(ConstructionCommandScript.place_blueprint(Vector2i(x,y),"core:wood_floor"))
			if bool(result.success): placed += 1

func saw() -> void:
	_surface_route_move(sim,Content.cell_center(station.x,station.y))
	var result := sim.execute_crafting_command(CraftingCommandScript.start_project(station,"core:saw_planks"))
	if not bool(result.success): sim.advance_minutes(1); return
	for i: int in range(sim.crafting_catalog.get_work_minutes("core:saw_planks")):
		sim.advance_minutes(1)
		result = sim.execute_crafting_command(CraftingCommandScript.work_project(station))
	_surface_route_pick_drops(sim,result.get("created_drop_ids",[]))

func deposit(id: String) -> void:
	if sim.get_item_count(id) <= 0: return
	for cell: Vector2i in Simulation.STARTER_PANTRY_CELLS:
		_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
		sim.transfer_inventory_stack_to_storage(cell,id,0)
		if sim.get_item_count(id) <= 0: return

func forage() -> void:
	var bushes := sim.get_surface_berry_bushes()
	bushes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return sim.get_player_position().distance_squared_to(a.position) < sim.get_player_position().distance_squared_to(b.position))
	for bush: Dictionary in bushes:
		if not sim.farming.berry_ready(sim,String(bush.id)) or _surface_route_path(sim,bush.position,Content.INTERACTION_RANGE).is_empty(): continue
		_surface_route_move(sim,bush.position)
		sim.execute_interaction(String(bush.id))
		if sim.get_item_count("core:food") > 0: sim.eat_food("core:food")
		return
	sim.advance_minutes(1)

func food_stock() -> Dictionary:
	var personal: Dictionary = {}
	for id: String in sim.state.npcs: personal[id] = int(sim.state.npcs[id].personal_inventory.get("core:food",0))
	return {"player":sim.get_item_count("core:food"),"storage":sim.StockReserves.total(sim,"core:food"),"residents":personal}

func sample_control() -> void:
	if sim.get_minute_of_day() in [660,900,1260]: checkpoints.append({"day":sim.get_day(),"time":sim.get_time_text(),"energy":sim.get_player_energy(),"satiety":sim.get_player_needs().hunger,"food":food_stock()})
