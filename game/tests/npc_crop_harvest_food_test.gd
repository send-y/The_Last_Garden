extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Food := preload("res://src/needs/npc_food_supply.gd")
const Practical := preload("res://src/npc_work/npc_practical_work.gd")
const ID := "core:first_neighbor"
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func fixture():
	var state := preload("res://src/dev/package_d_scenarios.gd").day_three_state()
	state.minute_of_day = 600
	state.npcs[ID].needs = {"hunger":20.0,"energy":100.0,"restedness":100.0}
	state.npcs[ID].personal_inventory = {"core:food":0}
	var sim = World.new(state)
	for bush: Dictionary in sim.get_surface_berry_bushes(): sim.state.farming.berry_ready_at[String(bush.id)] = sim.get_elapsed_game_minutes()+4320
	return sim
func add_crop(sim) -> Vector2i:
	for y: int in range(30,36):
		for x: int in range(33,40):
			var cell := Vector2i(x,y)
			if sim.farming._soil_allowed(sim,cell):
				sim.state.farming.beds.append({"cell":[x,y],"crop_id":"potato","growth":4320,"wet_until":0,"last_update":sim.get_elapsed_game_minutes(),"harvests":0,"shared_harvest":true})
				return cell
	return Vector2i(-1,-1)
func arrive(sim,meal: Dictionary) -> void:
	var point := Content.cell_center(int(meal.target_cell[0]),int(meal.target_cell[1]))
	sim.state.npcs[ID].position = [point.x,point.y]
func run() -> void:
	var sim = fixture(); var cell := add_crop(sim)
	check(Food.find_meal(sim,sim.state.npcs[ID]).is_empty(),"No crop food without harvest permission")
	sim.set_npc_work_enabled(ID,"harvest",true)
	var meal: Dictionary = Food.find_meal(sim,sim.state.npcs[ID])
	check(meal.get("source","")=="crop","Hungry NPC discovers actual shared crop")
	if meal.get("source","")!="crop": quit(1); return
	var npc: Dictionary = sim.state.npcs[ID]
	var original_job := {"kind":"gather","phase":"work","tool_id":"core:axe","target_id":"core:wood_north","resource_item":"core:wood","cell":[20,27],"drops":[]}
	npc.initiative_job = original_job.duplicate(true)
	var axes: Array[String] = sim._create_item_instances("core:axe",1,"npc",ID)
	npc.carried_instance_id = axes[0]
	arrive(sim,meal)
	var hunger := float(npc.needs.hunger)
	check(Food.fulfil(sim,{"npc_id":ID,"meal":meal}),"Crop acquisition harvest step succeeds")
	check(float(npc.needs.hunger)==hunger and sim.state.world_drops.size()>0,"Harvest produces food, does not feed remotely")
	sim = World.new(sim.export_state()); npc = sim.state.npcs[ID]
	check(npc.crop_food_trip.get("phase","")=="collect","Pending food collection survives reload")
	meal = Food.find_meal(sim,npc); arrive(sim,meal)
	check(Food.fulfil(sim,{"npc_id":ID,"meal":meal}),"Physical pickup prepares one meal")
	check(int(npc.personal_inventory.get("core:potato",0))==1 and float(npc.needs.hunger)==hunger,"One real potato in personal inventory before eating")
	meal = Food.find_meal(sim,npc); arrive(sim,meal)
	check(Food.fulfil(sim,{"npc_id":ID,"meal":meal}),"Existing meal system feeds with obtained crop")
	check(float(npc.needs.hunger)>hunger and int(npc.personal_inventory.get("core:potato",0))==0,"Food is consumed exactly once")
	check(npc.initiative_job==original_job and npc.carried_instance_id==axes[0],"Suspended ordinary job and physical tool are retained")
	npc.needs.hunger = 100.0
	for step: int in range(12):
		var contexts: Dictionary = Practical.prepare(sim)
		var context: Dictionary = contexts.get(ID,{})
		if not context.has("crop_supply"): break
		arrive(sim,context)
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	check(sim.StockReserves.total(sim,"core:potato")==2,"Meal leftovers go to common stock")
	for case_id: String in ["sleep","critical","rest","personal"]:
		sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
		sim.set_npc_work_enabled(ID,"harvest",true)
		match case_id:
			"sleep": sim.state.minute_of_day = 22*60
			"critical": npc.needs.energy = 18.0
			"rest": npc.activity_id = "core:resting"; npc.needs.energy = 40.0
			"personal": sim.farming.bed_at(sim,cell).shared_harvest = false
		check(Food.find_meal(sim,npc).is_empty(),"Food acquisition respects "+case_id)
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true)
	meal = Food.find_meal(sim,npc); arrive(sim,meal)
	sim.set_npc_work_enabled(ID,"harvest",false)
	check(not Food.fulfil(sim,{"npc_id":ID,"meal":meal}) and sim.state.world_drops.is_empty(),"Permission revoked en route blocks new harvest")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true); sim.state.storage_zones = []
	npc.work_cargo = {"core:wood":20}
	meal = Food.find_meal(sim,npc); arrive(sim,meal); Food.fulfil(sim,{"npc_id":ID,"meal":meal})
	meal = Food.find_meal(sim,npc); arrive(sim,meal); Food.fulfil(sim,{"npc_id":ID,"meal":meal})
	check(int(npc.personal_inventory.get("core:potato",0))==1 and int(npc.work_cargo.get("core:wood",0))==20,"Full work cargo cannot erase meal or paid wood")
	var remaining := 0
	for drop: Dictionary in sim.state.world_drops: remaining += int(drop.amount)
	check(remaining==2,"Over-capacity food remainder stays in real protected drops")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	npc.needs.hunger = 100.0
	sim.set_npc_work_enabled(ID,"harvest",true); Practical.prepare(sim)
	var work_at: Dictionary = {"target_cell":[cell.x,cell.y]}
	arrive(sim,work_at); Practical.fulfil(sim,{"npc_id":ID,"context":work_at})
	npc.needs.hunger = 20.0
	meal = Food.find_meal(sim,npc)
	check(meal.get("source","")=="crop" and meal.get("phase","")=="collect","Hungry ordinary harvester can eat already harvested output")
	if meal.is_empty(): quit(1); return
	arrive(sim,meal); Food.fulfil(sim,{"npc_id":ID,"meal":meal})
	check(int(npc.personal_inventory.get("core:potato",0))==1,"Already paid harvest supplies real meal without new yield")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true)
	meal = Food.find_meal(sim,npc)
	var other := sim.create_generated_npc(777,Vector2i(35,32))
	check(bool(other.ok),"Second resident fixture created")
	var other_id := String(other.npc_id)
	sim.arrive_npc(other_id,Vector2i(35,32))
	sim.state.npcs[other_id].known = true
	sim.state.npcs[other_id].needs = {"hunger":20.0,"energy":100.0,"restedness":100.0}
	sim.state.npcs[other_id].personal_inventory = {"core:food":0}
	sim.set_npc_work_enabled(other_id,"harvest",true)
	check(preload("res://src/npc_work/npc_crop_harvest.gd").choose(sim,sim.state.npcs[other_id],true).is_empty(),"Another hungry actor cannot reserve same ripe bed")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true)
	sim.work_metrics.enabled = true
	sim.advance_minutes(120)
	var eaten := int(sim.work_metrics.food_snapshot(sim.get_day()).get(ID,{}).get("core:potato",0))
	check(int(sim.state.farming.harvest_count)==1 and eaten>0,"Ordinary minute autonomy approaches crop, acquires and eats real output")
	var total: int = eaten+int(npc.personal_inventory.get("core:potato",0))+int(npc.work_cargo.get("core:potato",0))+sim.StockReserves.total(sim,"core:potato")
	for drop: Dictionary in sim.state.world_drops:
		if drop.item_id=="core:potato": total += int(drop.amount)
	check(total==3,"Autonomous route conserves all harvested and eaten potatoes")
	print("PASS: crop food, rest priority, retained work and physical leftovers" if failures==0 else "FAIL: crop food")
	quit(0 if failures==0 else 1)
