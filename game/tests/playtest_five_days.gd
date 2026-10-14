extends "res://tests/run_tests.gd"

# Reuses the established walking/action helpers, never the stocked fixture.
var sim: World
var checks: Array[Dictionary] = []
var days: Array[Dictionary] = []
var first_cover := -1
var station := Vector2i(-1,-1)
var beginning := 0

func _run() -> void:
	TranslationServer.set_locale("ru")
	sim = Simulation.new(Simulation.create_new_game_state(1337))
	beginning = sim.get_elapsed_game_minutes()
	sim.work_metrics.enabled = true
	sim.work_metrics.minute_observed.connect(sample)
	sample()
	var axe := _surface_route_take_tool(sim,"core:axe")
	_expect(not axe.is_empty(),"Ordinary starter axe is retrieved")
	if _failures > 0: finish(); return
	_surface_route_interact(sim,"core:repair_room")
	_surface_route_harvest(sim,sim.get_surface_trees())
	var crafted := sim.execute_crafting_command(CraftingCommandScript.craft_in_hands("core:make_mallet"))
	_expect(bool(crafted.get("success",false)),"First mallet is actually crafted from harvested logs")
	_surface_route_pick_drops(sim,crafted.get("created_drop_ids",[]))
	_expect(not sim.get_inventory_instance_id("core:mallet",0).is_empty(),"No fixture mallet is required")
	station = _surface_route_build_workbench(sim)
	if _failures > 0: finish(); return
	_surface_route_saw_planks(sim,station)
	_surface_route_interact(sim,"core:repair_room")
	if sim.is_roof_covered(): first_cover = sim.get_elapsed_game_minutes()-beginning
	_surface_route_interact(sim,"core:repair_room")
	_surface_route_interact(sim,"core:bed_site")
	_surface_route_store_item(sim,"core:mallet",sim.get_inventory_instance_id("core:mallet",0))
	_surface_route_move(sim,Content.cell_center(22,22))
	sim.store_item_in_storage(Vector2i(22,22),"core:pinecone")
	# Earn two communal axes through the same real recipe and warehouse transfer.
	for index: int in range(2):
		if sim.get_item_count("core:wood") < 3:
			sim.select_inventory_item("core:axe",axe)
			_surface_route_harvest(sim,sim.get_surface_trees().filter(func(t: Dictionary): return t.get("presentation_id","") != "surface_stump"))
		craft_recipe("core:make_axe")
		var instance := sim.get_inventory_instance_id("core:axe",1)
		if not instance.is_empty(): _surface_route_store_item(sim,"core:axe",instance)
	for day: int in range(1,6):
		if day > 1:
			var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
			npc.known = true # Scheduled acquaintance; no needs or inventories are filled.
			for kind: String in ["gather","water","build"]: sim.set_npc_work_enabled(String(npc.id),kind,true)
		if day == 3:
			var generated := sim.create_generated_npc(94,Vector2i(24,29))
			_expect(bool(generated.ok) and bool(sim.arrive_npc(generated.npc_id,Vector2i(24,29)).ok),"Scheduled third-day arrival uses normal generation")
			if generated.ok:
				sim.state.npcs[String(generated.npc_id)].known = true
				for kind: String in ["gather","water","build"]: sim.set_npc_work_enabled(String(generated.npc_id),kind,true)
		while sim.get_day() == day and sim.get_minute_of_day() < 21*60:
			var minute := sim.get_minute_of_day()
			var before_minute := sim.get_elapsed_game_minutes()
			if minute % 120 == 0 and sim.get_item_count("core:wood") < 15 and warehouse_use() < 56:
				deposit_resources()
				sim.select_inventory_item("core:axe",axe)
				_surface_route_harvest(sim,sim.get_surface_trees().filter(func(t: Dictionary): return t.get("presentation_id","") != "surface_stump"))
			elif minute % 120 == 30 and sim.get_item_count("core:wood") >= 5 and warehouse_use() < 56:
				craft_recipe("core:saw_planks")
				deposit_resources()
			elif minute % 120 == 60:
				for bush: Dictionary in sim.get_surface_berry_bushes():
					if sim.farming.berry_ready(sim,String(bush.id)):
						_surface_route_move(sim,bush.position)
						sim.execute_interaction(String(bush.id))
						break
				if sim.get_item_count("core:food") > 0: sim.eat_food("core:food")
			else: sim.advance_minutes(1)
			if sim.get_elapsed_game_minutes() == before_minute: sim.advance_minutes(1)
			if _failures > 0: finish(); return
		var occupied := 0
		for record: Dictionary in sim.state.storage_items: occupied += sim.content.item_footprint(String(record.item_id),int(record.rotation)).size()
		days.append({"day":day,"storage_occupied_subcells":occupied,"storage_capacity_subcells":sim.state.storage_zones[0].cells.size()*16,"residents":sim.work_metrics.snapshot(day),"summary":sim.work_metrics.summary(day)})
		if day < 5:
			_surface_route_move(sim,sim.content.get_interactable("core:bed_site").position)
			_expect(bool(sim.execute_interaction("core:bed_site").get("success",false)),"Actual covered-house sleep advances to next morning")
	finish()

func craft_recipe(id: String) -> void:
	_surface_route_move(sim,Content.cell_center(station.x,station.y))
	var result := sim.execute_crafting_command(CraftingCommandScript.start_project(station,id))
	_expect(bool(result.get("success",false)),"Scheduled real recipe starts: "+id)
	if not bool(result.get("success",false)): return
	for minute: int in range(sim.crafting_catalog.get_work_minutes(id)):
		sim.advance_minutes(1)
		result = sim.execute_crafting_command(CraftingCommandScript.work_project(station))
	_expect(String(result.get("reason_id","")) == "core:crafting_completed","Scheduled recipe produces real outputs")
	_surface_route_pick_drops(sim,result.get("created_drop_ids",[]))

func deposit_resources() -> void:
	for cell: Vector2i in Simulation.STARTER_PANTRY_CELLS:
		_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
		for id: String in ["core:plank","core:pinecone","core:food"]:
			if sim.get_item_count(id) > 0: sim.store_item_in_storage(cell,id)

func warehouse_use() -> int:
	var result := 0
	for item: Dictionary in sim.state.storage_items: result += sim.content.item_footprint(String(item.item_id),int(item.rotation)).size()
	return result

func sample() -> void:
	if sim.get_minute_of_day() in [660,900,1260]: checks.append({"day":sim.get_day(),"time":sim.get_time_text(),"energy":sim.get_player_energy(),"satiety":sim.get_player_needs().hunger,"restedness":sim.get_player_needs().restedness})

func finish() -> void:
	_expect(first_cover >= 0,"Scheduled route obtains first covered shelter")
	_expect(days.size() == 5,"Five days are observed")
	var report := {"seed":1337,"first_roof_after_game_minutes":first_cover,"checks":checks,"days":days,"schedule":"Day 1: ordinary axe, harvest, hand-crafted mallet, workbench, boards, starter roof and bed, two crafted communal axes. Days 1-5: every 120 minutes harvest if wood<15; at +30 saw boards; production stops once warehouse uses 56/64 subcells. Before harvest/after sawing store planks, pinecones and spare food across pantry cells; +60 forage/eat; otherwise wait. Covered sleep after 21. Day 2 acquaintance enables work; day 3 generated resident arrives. Walking uses actual movement speed and paths.","limitations":"Scripted control with considerable waiting, no furniture projects/farm beds; not a manual playtest, not a proof of 14-16 hours continuous work, new-room completion or NPC productivity under an expanded queue.","failures":_failures,"end_npcs":sim.state.npcs,"end_tool_locations":sim.state.item_instances,"end_storage":sim.state.storage_items}
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../artifacts/playtest-fixes-2026-10-14/five-days.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("PLAYTEST_FIVE_DAYS: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)
