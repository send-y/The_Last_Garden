extends "res://tests/npc_crop_harvest_work_test.gd"

func empty_bed(sim) -> Vector2i:
	var cell := add_crop(sim)
	var bed: Dictionary = sim.farming.bed_at(sim,cell)
	bed.crop_id = ""; bed.planned_crop_id = "potato"; bed.maintain_crop = true
	return cell

func drive(sim, steps: int = 16) -> void:
	var npc: Dictionary = sim.state.npcs[ID]
	for i: int in range(steps):
		var contexts: Dictionary = Practical.prepare(sim)
		var context: Dictionary = contexts.get(ID,{})
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})

func run() -> void:
	var sim = fixture()
	var cell := empty_bed(sim)
	var npc: Dictionary = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	var stock_cell: Array = sim.state.storage_zones[0].cells[0]
	sim.state.storage_items.append({"item_id":"core:potato_seed","amount":2,"cell":stock_cell.duplicate(),"rotated":false,"placement_id":"sowing-test"})
	drive(sim)
	check(sim.get_farm_bed(cell).crop_id=="potato","Planner carries communal seed and plants")
	check(sim.StockReserves.total(sim,"core:potato_seed")==1,"One physical seed spent")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	sim.work_metrics.enabled = true
	var initial_roll: int = sim.state.farming.roll_index
	drive(sim)
	check(int(sim.state.farming.roll_index)==initial_roll+1,"Missing stock leads to real food harvest and one extraction")
	check(not sim.work_metrics.farming_snapshot(sim.get_day()).get(ID,{}).get("extracted",{}).is_empty(),"Extraction attributed to resident")
	check(npc.work_cargo.is_empty(),"Random seeds and remaining food delivered")
	var total_seeds := 0
	for crop: Dictionary in sim.farming.catalog.crops: total_seeds += sim.StockReserves.total(sim,String(crop.seed_id))
	check(total_seeds>=2,"Real random seed batch in warehouse")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	npc.work_cargo["core:potato_seed"] = 1
	npc.initiative_job = {"kind":"sow","phase":"sow","cell":[cell.x,cell.y],"crop_id":"potato","seed_id":"core:potato_seed","drops":[]}
	sim = World.new(sim.export_state()); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",false)
	check(int(npc.work_cargo.get("core:potato_seed",0))==1,"Cancelled loaded job retains seed")
	drive(sim)
	check(sim.get_farm_bed(cell).crop_id=="" and sim.StockReserves.total(sim,"core:potato_seed")==1,"Cancellation returns seed without planting")
	print("PASS: physical sowing work and seed foraging" if failures==0 else "FAIL: sowing work")
	quit(0 if failures==0 else 1)
