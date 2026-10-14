extends "res://tests/package_d_seven_days.gd"

const FarmReport := preload("res://src/dev/farming_report.gd")
const Water := preload("res://src/world/water_map.gd")
var day_starts: Dictionary = {}
var day_ends: Dictionary = {}
var plots: Array[Vector2i] = []
var hoe := ""
var bucket := ""

func _run() -> void:
	sim = Simulation.new(Simulation.create_new_game_state(1337))
	sim.work_metrics.enabled = true
	sim.work_metrics.minute_observed.connect(_seed_sample)
	_seed_sample()
	axe = _surface_route_take_tool(sim,"core:axe")
	_surface_route_interact(sim,"core:repair_room")
	_surface_route_harvest(sim,sim.get_surface_trees())
	var made := sim.execute_crafting_command(CraftingCommandScript.craft_in_hands("core:make_mallet"))
	_expect(bool(made.get("success",false)),"Earned mallet crafted")
	_surface_route_pick_drops(sim,made.get("created_drop_ids",[]))
	station = _surface_route_build_workbench(sim)
	_surface_route_saw_planks(sim,station)
	_surface_route_interact(sim,"core:repair_room")
	_surface_route_interact(sim,"core:repair_room")
	# Earn the study table before using crop products as seed input.
	while sim.get_item_count("core:plank")<10 and _failures==0:
		if sim.get_item_count("core:wood")<int(sim.crafting_catalog.get_inputs("core:saw_planks").get("core:wood",0)):
			sim.select_inventory_item("core:axe",axe)
			_surface_route_harvest(sim,sim.get_surface_trees().filter(func(tree: Dictionary) -> bool: return not sim.is_collected(String(tree.id)) and String(tree.get("presentation_id",""))!="surface_stump"))
			deposit("core:pinecone")
		_crop_craft("core:saw_planks")
	_build_study_table()
	_surface_route_store_item(sim,"core:mallet",sim.get_inventory_instance_id("core:mallet",0))
	while sim.get_item_count("core:wood")<7 and _failures==0:
		sim.select_inventory_item("core:axe",axe)
		_surface_route_harvest(sim,sim.get_surface_trees().filter(func(tree: Dictionary) -> bool: return not sim.is_collected(String(tree.id)) and String(tree.get("presentation_id",""))!="surface_stump"))
		deposit("core:pinecone")
	_surface_route_store_item(sim,"core:axe",axe)
	_crop_craft("core:make_hoe")
	hoe = sim.get_inventory_instance_id("core:hoe",0)
	_crop_craft("core:make_bucket")
	bucket = sim.get_inventory_instance_id("core:bucket",0)
	deposit("core:wood"); deposit("core:plank"); deposit("core:pinecone")
	for i: int in range(2):
		_collect_seed_food()
		var extracted := sim.execute_farming_command({"actor_id":"core:player","action_id":"extract","item_id":"core:food"})
		_expect(bool(extracted.success),"Ordinary initial food supplies actual random seeds")
		if _failures>0: break
	_prepare_plots()
	var limit := sim.get_elapsed_game_minutes()+8*1440
	while sim.get_day()<=7 and _failures==0 and sim.get_elapsed_game_minutes()<limit:
		var before := sim.get_elapsed_game_minutes()
		var day := sim.get_day()
		if day>=2 and not bool(sim.state.npcs["core:first_neighbor"].first_meeting_complete): meet_mira()
		for npc: Dictionary in sim.state.npcs.values():
			if bool(npc.active) and bool(npc.known) and not bool(npc.work_options.harvest): sim.set_npc_work_enabled(String(npc.id),"harvest",true)
		if sim.get_minute_of_day()>=21*60:
			print("FARM_CONTROL day=",day," stocks=",JSON.stringify(FarmReport.snapshot(sim)))
			if day==7: break
			_surface_route_interact(sim,"core:bed_site")
			continue
		if float(sim.get_player_needs().hunger)<60:
			if sim.get_item_count("core:food")>0: sim.eat_food("core:food")
			else: forage()
		elif sim.get_player_energy()<20: sim.rest_player()
		else:
			_maintain_plots()
			if sim.get_elapsed_game_minutes()==before: sim.advance_minutes(10)
		if sim.get_elapsed_game_minutes()==before: sim.advance_minutes(1)
	_seed_sample()
	var days: Array = []
	var produced := 0; var eaten := 0; var ordinary_stock_meal := false
	var producers: Dictionary = {}; var eaters: Dictionary = {}
	for day: int in range(1,8):
		if not day_ends.has(day): continue
		var row := FarmReport.day_balance(sim,day_starts[day],day_ends[day],day)
		row.day = day; row.work = sim.work_metrics.snapshot(day)
		days.append(row)
		for actor: String in row.farming_events:
			for item: String in row.farming_events[actor].get("harvested",{}):
				produced += int(row.farming_events[actor].harvested[item])
				if actor!="core:player": producers[item] = actor
		for actor: String in row.meals:
			for item: String in row.meals[actor]:
				if sim.farming.catalog.find(item).is_empty(): continue
				eaten += int(row.meals[actor][item])
				if actor!="core:player": eaters[item] = actor
	for item: String in producers:
		if eaters.has(item) and eaters[item]!=producers[item]: ordinary_stock_meal = true
	_expect(days.size()==7,"All seven real calendar days recorded")
	_expect(produced>0,"Genuine planted and watered crop reaches harvest")
	_expect(eaten>0 and ordinary_stock_meal,"Another resident eats genuinely produced common crop")
	var report_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-artifact-dir="): report_path = arg.trim_prefix("--test-artifact-dir=").path_join("crop-seven-days.json")
	_expect(not report_path.is_empty(),"Route report is isolated")
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"seed":1337,"days":days,"harvested_units":produced,"crop_meals":eaten,"different_resident_ate_crop":ordinary_stock_meal,"failures":_failures,"limits":"Scripted farm route with earned tools/table, random seeds, real growth, player watering and NPC harvest. No replenishment or food protection. Daily snapshots at last observed minute; test ends at day 7 evening. Hunger/seed shortage can remain."},"\t")); file.close()
	print("PASS: seven-day ordinary crop route and seed report" if _failures==0 else "FAIL: crop seven-day route")
	quit(0 if _failures==0 else 1)

func _crop_seed_snapshot(world) -> Dictionary:
	return FarmReport.snapshot(world)

func _seed_sample() -> void:
	var day := sim.get_day()
	var snapshot := _crop_seed_snapshot(sim)
	if not day_starts.has(day): day_starts[day] = snapshot.duplicate(true)
	day_ends[day] = snapshot

func _crop_craft(recipe: String) -> void:
	if _failures>0: return
	_surface_route_move(sim,Content.cell_center(station.x,station.y))
	var result := sim.execute_crafting_command(CraftingCommandScript.start_project(station,recipe))
	if not bool(result.success): print("RECIPE_REFUSED ",recipe," ",result," inventory=",sim.get_inventory()," needs=",sim.get_player_needs())
	_expect(bool(result.success),"Real farm preparation recipe starts: "+recipe)
	if not bool(result.success): return
	for i: int in range(sim.crafting_catalog.get_work_minutes(recipe)):
		sim.advance_minutes(1)
		result = sim.execute_crafting_command(CraftingCommandScript.work_project(station))
	_expect(String(result.get("reason_id",""))=="core:crafting_completed","Real preparation recipe completes: "+recipe)
	_surface_route_pick_drops(sim,result.get("created_drop_ids",[]))

func _build_study_table() -> void:
	if _failures>0: return
	var chosen := Vector2i(-1,-1)
	for y: int in range(27,34):
		for x: int in range(30,39):
			var cell := Vector2i(x,y)
			var result := sim.execute_construction_command(ConstructionCommandScript.place_blueprint(cell,"core:study_table"))
			if bool(result.success): chosen = cell; break
		if chosen.x>=0: break
	_expect(chosen.x>=0,"Actual study table blueprint can be placed")
	if chosen.x<0: return
	_surface_route_move(sim,Content.cell_center(chosen.x,chosen.y))
	_expect(bool(sim.execute_construction_command(ConstructionCommandScript.deliver_blueprint_materials(chosen)).success),"Earned planks delivered to table")
	var mallet := sim.get_inventory_instance_id("core:mallet",0)
	_expect(not mallet.is_empty(),"Earned physical mallet is still owned")
	sim.select_inventory_item("core:mallet",mallet)
	for i: int in range(sim.building_catalog.get_work_minutes("core:study_table")):
		sim.advance_minutes(1)
		var result := sim.execute_construction_command(ConstructionCommandScript.work_blueprint(chosen))
		_expect(bool(result.success),"Actual table work succeeds")
	_expect(sim.farming.extraction_unlocked(sim),"Built study table unlocks extraction")

func _collect_seed_food() -> void:
	if sim.get_item_count("core:food")>0: return
	for bush: Dictionary in sim.get_surface_berry_bushes():
		if not sim.farming.berry_ready(sim,String(bush.id)) or _surface_route_path(sim,bush.position,Content.INTERACTION_RANGE).is_empty(): continue
		_surface_route_move(sim,bush.position)
		sim.execute_interaction(String(bush.id))
		return
	_expect(false,"Ordinary reachable berries needed for initial seeds")

func _prepare_plots() -> void:
	for crop: Dictionary in sim.farming.catalog.crops:
		while sim.get_item_count(String(crop.seed_id))>0 and plots.size()<6 and _failures==0:
			var cell := Vector2i(-1,-1)
			for y: int in range(29,37):
				for x: int in range(29,41):
					var candidate := Vector2i(x,y)
					if sim.farming._soil_allowed(sim,candidate) and sim.get_farm_bed(candidate).is_empty() and not _surface_route_path(sim,Content.cell_center(x,y),Content.INTERACTION_RANGE).is_empty(): cell = candidate; break
				if cell.x>=0: break
			if cell.x<0: break
			_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
			sim.select_inventory_item("core:hoe",hoe)
			_expect(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"till","cell":[cell.x,cell.y]}).success),"Physical hoe tills reachable soil")
			_expect(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"plant","cell":[cell.x,cell.y],"item_id":String(crop.seed_id)}).success),"Actual seed planted")
			sim.execute_farming_command({"actor_id":"core:player","action_id":"set_shared_harvest","cell":[cell.x,cell.y],"enabled":plots.size()>0})
			plots.append(cell)
	_expect(plots.size()>1,"Real seeds support personal and common test plots")
	_maintain_plots()

func _fill_crop_bucket() -> bool:
	sim.select_inventory_item("core:bucket",bucket)
	var waters := Water.surface_cells()
	waters.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return sim.get_player_position().distance_squared_to(Content.cell_center(a.x,a.y))<sim.get_player_position().distance_squared_to(Content.cell_center(b.x,b.y)))
	for cell: Vector2i in waters:
		if _surface_route_path(sim,Content.cell_center(cell.x,cell.y),Content.INTERACTION_RANGE).is_empty(): continue
		_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
		return bool(sim.fill_active_bucket(cell).success)
	return false

func _maintain_plots() -> void:
	for cell: Vector2i in plots:
		var bed := sim.get_farm_bed(cell)
		if bed.is_empty(): continue
		if sim.farming.harvest_ready(sim,cell) and not bool(bed.shared_harvest):
			_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
			var result := sim.execute_farming_command({"actor_id":"core:player","action_id":"harvest","cell":[cell.x,cell.y]})
			if bool(result.success):
				_surface_route_pick_drops(sim,result.created_drop_ids)
				sim.execute_farming_command({"actor_id":"core:player","action_id":"extract","item_id":String(result.item_id)})
			bed = sim.get_farm_bed(cell)
		if String(bed.crop_id).is_empty():
			for crop: Dictionary in sim.farming.catalog.crops:
				if sim.get_item_count(String(crop.seed_id))<=0: continue
				_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
				sim.execute_farming_command({"actor_id":"core:player","action_id":"plant","cell":[cell.x,cell.y],"item_id":String(crop.seed_id)})
				break
			bed = sim.get_farm_bed(cell)
		if String(bed.crop_id).is_empty() or int(bed.wet_until)>sim.get_elapsed_game_minutes()+180: continue
		sim.select_inventory_item("core:bucket",bucket)
		if int(sim.get_actor_tool("core:player").get("state",{}).get("charges",0))==0:
			_expect(_fill_crop_bucket(),"Physical river refill succeeds")
		_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
		sim.execute_farming_command({"actor_id":"core:player","action_id":"water","cell":[cell.x,cell.y]})
