extends "res://tests/npc_crop_harvest_seven_days.gd"

func _seed_sample() -> void:
	for npc: Dictionary in sim.state.npcs.values():
		if bool(npc.get("active",false)) and bool(npc.get("known",false)) and not bool(npc.get("work_options",{}).get("sow",false)):
			sim.set_npc_work_enabled(String(npc.id),"sow",true)
	super._seed_sample()

func _maintain_plots() -> void:
	for cell: Vector2i in plots:
		var bed := sim.get_farm_bed(cell)
		if bed.is_empty(): continue
		if bool(bed.shared_harvest):
			if not bool(bed.get("maintain_crop",false)):
				_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
				sim.execute_farming_command({"actor_id":"core:player","action_id":"set_maintained_crop","cell":[cell.x,cell.y],"crop_id":String(bed.get("planned_crop_id",bed.crop_id)),"enabled":true})
		else:
			if sim.farming.harvest_ready(sim,cell):
				_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
				var result := sim.execute_farming_command({"actor_id":"core:player","action_id":"harvest","cell":[cell.x,cell.y]})
				if bool(result.success):
					_surface_route_pick_drops(sim,result.created_drop_ids)
					sim.execute_farming_command({"actor_id":"core:player","action_id":"extract","item_id":String(result.item_id)})
			if String(bed.crop_id).is_empty():
				for crop: Dictionary in sim.farming.catalog.crops:
					if sim.get_item_count(String(crop.seed_id))<=0: continue
					_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
					sim.execute_farming_command({"actor_id":"core:player","action_id":"plant","cell":[cell.x,cell.y],"item_id":String(crop.seed_id)})
					break
		bed = sim.get_farm_bed(cell)
		if String(bed.crop_id).is_empty() or int(bed.wet_until)>sim.get_elapsed_game_minutes()+180: continue
		sim.select_inventory_item("core:bucket",bucket)
		if int(sim.get_actor_tool("core:player").get("state",{}).get("charges",0))==0: _expect(_fill_crop_bucket(),"Actual water refill")
		_surface_route_move(sim,Content.cell_center(cell.x,cell.y))
		sim.execute_farming_command({"actor_id":"core:player","action_id":"water","cell":[cell.x,cell.y]})
	for crop: Dictionary in sim.farming.catalog.crops: deposit(String(crop.seed_id))

func _run() -> void:
	super._run()
	var planted := 0; var extracted := 0
	for day: int in range(1,8):
		for actor: String in sim.work_metrics.farming_snapshot(day):
			if actor=="core:player": continue
			var row: Dictionary = sim.work_metrics.farming_snapshot(day)[actor]
			for value: int in row.get("planted",{}).values(): planted += value
			for value: int in row.get("extracted",{}).values(): extracted += value
	_expect(planted>0,"Ordinary residents genuinely plant in seven-day route")
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--test-artifact-dir="): continue
		var path := arg.trim_prefix("--test-artifact-dir=").path_join("crop-seven-days.json")
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		report.npc_planted = planted; report.npc_extracted_seeds = extracted; report.failures = _failures
		report.limits = "Earned new-world route. Shared beds replanted only by residents; private bed and watering remain manual. Real seed deposits, wild food competition, no replenishment or protection."
		var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("PASS: seven-day sowing route" if _failures==0 else "FAIL: seven-day sowing route")
	quit(0 if _failures==0 else 1)
