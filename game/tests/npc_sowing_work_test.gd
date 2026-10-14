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
	npc.work_cargo["core:potato_seed"] = 1
	npc.initiative_job = {"kind":"sow","phase":"sow","cell":[cell.x,cell.y],"crop_id":"potato","seed_id":"core:potato_seed","drops":[]}
	sim.farming.bed_at(sim,cell).planned_crop_id = "carrot"
	drive(sim)
	check(sim.get_farm_bed(cell).crop_id=="" and sim.StockReserves.total(sim,"core:potato_seed")==1,"Changed crop returns paid seed")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	sim.state.storage_zones = []; drive(sim)
	check(npc.initiative_job.is_empty() and int(sim.state.farming.roll_index)==0,"No delivery route prevents new seed forage")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	npc.work_cargo["core:food"] = 1
	npc.initiative_job = {"kind":"sow","phase":"seed_extract","cell":[cell.x,cell.y],"crop_id":"potato","seed_id":"core:potato_seed","food_id":"core:food","drops":[]}
	sim = World.new(sim.export_state()); npc = sim.state.npcs[ID]
	drive(sim)
	check(int(sim.state.farming.roll_index)==1,"Loaded extraction executes once")
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
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	npc.work_cargo["core:food"] = 1
	npc.initiative_job = {"kind":"sow","phase":"seed_extract","cell":[cell.x,cell.y],"crop_id":"potato","seed_id":"core:potato_seed","food_id":"core:food","drops":[]}
	npc.needs.hunger = 40.0
	npc.personal_inventory["core:food"] = 0
	var meal: Dictionary = preload("res://src/needs/npc_food_supply.gd").find_meal(sim,npc)
	check(String(meal.get("source",""))=="work_cargo","Hungry worker can eat own foraged food before extraction")
	check(not Practical.prepare(sim).has(ID) and int(npc.work_cargo.get("core:food",0))==1,"Hunger pauses extraction without losing food")
	if meal.get("target_cell",[]).size()==2:
		place_npc(sim,Vector2i(int(meal.target_cell[0]),int(meal.target_cell[1])))
		check(preload("res://src/needs/npc_food_supply.gd").fulfil(sim,{"npc_id":ID,"meal":meal}),"Actual hungry worker eats carried food")
		check(not npc.work_cargo.has("core:food"),"Meal consumes real food once")
	var laboratory: Dictionary = preload("res://src/dev/mechanics_lab_scenarios.gd").build(&"shared_crop_sowing")
	check(bool(laboratory.success) and String(laboratory.definition.description).contains("Искусственный"),"New lab checkpoint labels synthetic preparation")
	sim = laboratory.simulation
	drive(sim)
	var potatoes := 0
	for bed: Dictionary in sim.get_farm_beds():
		if String(bed.crop_id)=="potato": potatoes += 1
	check(potatoes==1,"Lab checkpoint demonstrates real seed sowing")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	var contexts: Dictionary = Practical.prepare(sim)
	var stale: Dictionary = contexts.get(ID,{})
	check(not stale.is_empty() and npc.initiative_job.get("phase","")=="seed_forage","Actual food source chosen")
	if not stale.is_empty():
		var target_id := String(npc.initiative_job.target_id)
		sim.state.farming.berry_ready_at[target_id] = sim.get_elapsed_game_minutes()+100
		place_npc(sim,Vector2i(int(stale.target_cell[0]),int(stale.target_cell[1])))
		check(not Practical.fulfil(sim,{"npc_id":ID,"context":stale}),"Consumed source refuses stale arrival")
		check(npc.work_cargo.is_empty() and int(sim.state.farming.roll_index)==0,"Stale source creates nothing")
	sim = fixture(); cell = empty_bed(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"sow",true)
	var job: Dictionary = preload("res://src/npc_work/npc_sowing.gd").choose(sim,npc)
	for phase: String in ["take_seed","sow","seed_forage","seed_collect","seed_extract","return"]:
		job.phase = phase; job.food_id = "core:food"; job.drop_id = "pending-food"
		npc.initiative_job = job.duplicate(true)
		var restored = World.new(sim.export_state())
		check(restored.state.npcs[ID].initiative_job==npc.initiative_job,"Save retains sow phase and source: "+phase)
	print("PASS: physical sowing work and seed foraging" if failures==0 else "FAIL: sowing work")
	quit(0 if failures==0 else 1)
