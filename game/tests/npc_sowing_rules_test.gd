extends "res://tests/npc_crop_harvest_rules_test.gd"

func run() -> void:
	var sim = fixture()
	var cell := soil(sim)
	var point := Content.cell_center(cell.x,cell.y)
	sim.state.farming.beds.append({"cell":[cell.x,cell.y],"crop_id":"", "growth":0,"wet_until":0,"last_update":0,"harvests":0,"shared_harvest":true})
	if not sim.farming.has_method("plant_for_actor") or not sim.farming.has_method("extract_for_worker"):
		check(false,"Missing authoritative NPC sowing/extraction")
		quit(1); return
	var npc: Dictionary = sim.state.npcs[ID]
	npc.position = [point.x,point.y]
	npc.work_options.sow = true
	sim.set_player_position(point)
	check(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"set_maintained_crop","cell":[cell.x,cell.y],"crop_id":"potato","enabled":true}).success),"Player assigns maintained crop without seeds")
	var bed: Dictionary = sim.farming.bed_at(sim,cell)
	var before := JSON.stringify(sim.export_state())
	check(not bool(sim.farming.plant_for_actor(sim,ID,cell,"core:potato_seed").success),"No cargo seed refuses")
	check(JSON.stringify(sim.export_state())==before,"Refusal is atomic")
	npc.work_cargo["core:potato_seed"] = 2
	npc.work_options.sow = false
	check(not bool(sim.farming.plant_for_actor(sim,ID,cell,"core:potato_seed").success),"Permission required")
	npc.work_options.sow = true
	npc.position = [0.0,0.0]
	check(not bool(sim.farming.plant_for_actor(sim,ID,cell,"core:potato_seed").success),"Real proximity required")
	npc.position = [point.x,point.y]
	check(bool(sim.farming.plant_for_actor(sim,ID,cell,"core:potato_seed").success),"Sow real seed")
	check(int(npc.work_cargo["core:potato_seed"])==1 and bed.crop_id=="potato","Consumes exactly one seed")
	check(not bool(sim.farming.plant_for_actor(sim,ID,cell,"core:potato_seed").success),"Repeated sow refuses")
	bed.growth = 4320
	check(bool(sim.farming.harvest_for_actor(sim,"core:player",cell).success),"Harvest current crop")
	check(bed.crop_id=="" and bed.planned_crop_id=="potato" and bed.maintain_crop,"Plan survives harvest")
	var loaded = World.new(sim.export_state())
	check(loaded.get_farm_bed(cell).planned_crop_id=="potato" and loaded.state.npcs[ID].work_options.sow,"Plan and permission survive load")
	npc.work_cargo["core:food"] = 1
	var result: Dictionary = sim.farming.extract_for_worker(sim,ID,"core:food")
	check(bool(result.success) and int(result.amount)>=2 and int(result.amount)<=4,"Existing random food seeds")
	check(not npc.work_cargo.has("core:food"),"Extraction consumes real product")
	before = JSON.stringify(sim.export_state())
	check(not bool(sim.farming.extract_for_worker(sim,ID,"core:food").success) and before==JSON.stringify(sim.export_state()),"No duplicated extraction")
	print("PASS: sowing authority and persisted plan" if failures==0 else "FAIL: sowing rules")
	quit(0 if failures==0 else 1)
