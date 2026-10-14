extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Practical := preload("res://src/npc_work/npc_practical_work.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const ID := "core:first_neighbor"
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func fixture():
	var state := World.create_new_game_state()
	state.day = 2
	state.minute_of_day = 10*60
	state.elapsed_game_minutes = 2040
	state.npcs[ID].active = true
	state.npcs[ID].known = true
	state.npcs[ID].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	return World.new(state)
func run() -> void:
	var sim = fixture()
	sim.try_pickup_item("core:axe",1)
	var axe := sim.get_inventory_instance_id("core:axe",0)
	sim.select_inventory_item("core:axe",axe)
	var npc_axes: Array[String] = sim._create_item_instances("core:axe_stone",1,"npc",ID)
	var npc: Dictionary = sim.state.npcs[ID]
	npc.carried_instance_id = npc_axes[0]
	var target := "core:wood_north"
	var point: Vector2 = sim.content.get_interactable(target).position
	sim.set_player_position(point)
	npc.position = [point.x,point.y]
	check(sim.execute_resource_work("core:player",target).success,"Player starts shared resource")
	check(sim.execute_resource_work(ID,target).success,"NPC adds actual work with another physical tool")
	check(float(sim.state.resource_work.get(target,0)) == 2.5,"Shared target retains sum of player and stone tool work")
	sim.select_inventory_item("","")
	var before := JSON.stringify(sim.export_state())
	check(not sim.execute_resource_work("core:player",target).success and JSON.stringify(sim.export_state()) == before,"Unselected tool cannot erase another actor progress")
	sim = fixture()
	npc = sim.state.npcs[ID]
	var buckets: Array[String] = sim._create_item_instances("core:bucket",1,"npc",ID,{"charges":2})
	npc.carried_instance_id = buckets[0]
	npc.work_options.water = true
	npc.position = [560.0,944.0]
	for x: int in [18,19]: sim.state.farming.beds.append({"cell":[x,29],"crop_id":"carrot","growth":0,"wet_until":0,"last_update":2040,"harvests":0})
	npc.initiative_job = {"kind":"water","phase":"work","tool_id":"core:bucket","cell":[18,29],"drops":[]}
	check(Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[17,29]}}),"NPC executes first real watering action")
	check(npc.initiative_job.phase == "work" and npc.initiative_job.cell == [19,29],"NPC continues next dry bed without returning a charged bucket")
	check(npc.carried_instance_id == buckets[0],"Same physical bucket remains in use")
	sim.state.farming.beds[1].wet_until = sim.get_elapsed_game_minutes()+1440
	sim.state.farming.beds.append({"cell":[20,29],"crop_id":"carrot","growth":0,"wet_until":0,"last_update":2040,"harvests":0})
	Practical.context_for(sim,npc)
	check(npc.initiative_job.cell == [20,29] and npc.carried_instance_id == buckets[0],"Already-watered target is replaced before travelling with same bucket")
	npc.needs.energy = 17.0
	Practical.prepare(sim)
	check(npc.carried_instance_id == buckets[0] and sim.get_item_instance(buckets[0]).location.kind == "npc","Urgent rest retains physical tool")
	check(not npc.initiative_job.is_empty(),"Urgent rest suspends rather than forgets useful task")
	check(sim.state.world_drops.is_empty(),"Urgent needs do not discard communal supplies")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())))
	check(restored.state.npcs[ID].carried_instance_id == buckets[0],"Suspended tool survives reload")
	sim = fixture()
	npc = sim.state.npcs[ID]
	npc.work_options.gather = true
	var borrowed: Array[String] = sim._create_item_instances("core:axe",1,"npc",ID)
	npc.carried_instance_id = borrowed[0]
	var tree: Dictionary = sim.get_surface_trees().filter(func(value: Dictionary): return int(value.get("yield_amount",0)) < 15)[0]
	npc.position = [tree.position.x,tree.position.y]
	var tree_cell: Vector2i = sim._world_position_to_cell(tree.position)
	npc.initiative_job = {"kind":"gather","phase":"work","tool_id":"core:axe","resource_item":"core:wood","target_id":String(tree.id),"cell":[tree_cell.x,tree_cell.y],"drops":[]}
	var current: Vector2i = Supply.cell_of(sim,npc)
	for step: int in range(8): Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[current.x,current.y]}})
	for drop: Dictionary in sim.state.world_drops.duplicate():
		if npc.initiative_job.drops.has(drop.drop_id): Supply.collect(sim,npc,drop)
	var continued: Dictionary = Practical.context_for(sim,npc)
	check(not continued.is_empty() and npc.initiative_job.phase == "work" and npc.initiative_job.target_id != tree.id,"After real harvesting and collection resident chooses another tree")
	check(npc.carried_instance_id == borrowed[0] and int(npc.work_cargo.get("core:wood",0)) > 0,"Batch keeps same axe and real gathered cargo")
	var stale_id := String(npc.initiative_job.target_id)
	var stale: Dictionary = sim._resolve_interaction_target(stale_id)
	sim.try_pickup_item("core:axe",1)
	sim.select_inventory_item("core:axe",sim.get_inventory_instance_id("core:axe",0))
	sim.set_player_position(stale.position)
	for step: int in range(8): sim.execute_resource_work("core:player",stale_id)
	Practical.context_for(sim,npc)
	check(npc.initiative_job.target_id != stale_id and npc.carried_instance_id == borrowed[0],"Player-felled target is replaced before travel instead of chopping new stump")
	sim.state.storage_zones = [{"id":"test:full","cells":[[22,22]]}]
	sim.state.storage_items = []
	for index: int in range(16): sim.state.storage_items.append({"cell":[22,22],"item_id":"core:stone","amount":5,"origin":[index%4,index/4],"rotation":0,"stack_index":index,"placement_id":"core:stone:%d" % index})
	npc.initiative_job.phase = "return"
	check(Practical.context_for(sim,npc).is_empty() and npc.initiative_job.get("blocked_reason","") == "storage_full_or_unreachable","Full warehouse explains why supplies cannot be returned")
	check(sim.get_item_instance(borrowed[0]).location.kind == "npc" and sim.state.world_drops.all(func(d: Dictionary): return not d.has("instance_id")),"Full warehouse never discards borrowed tool")
	npc.needs.hunger = 0.0
	Practical.prepare(sim)
	check(npc.carried_instance_id == borrowed[0] and not npc.initiative_job.is_empty(),"Hunger suspends a blocked return without losing ownership")
	npc.needs.hunger = 100.0
	sim.state.storage_items.clear()
	continued = Practical.context_for(sim,npc)
	check(not continued.is_empty(),"Return resumes when warehouse capacity becomes available")
	if not continued.is_empty():
		npc.position = [sim.content.cell_center(int(continued.target_cell[0]),int(continued.target_cell[1])).x,sim.content.cell_center(int(continued.target_cell[0]),int(continued.target_cell[1])).y]
		Practical.fulfil(sim,{"npc_id":ID,"context":continued})
		check(sim.get_item_instance(borrowed[0]).location.kind == "storage" and npc.work_cargo.is_empty(),"Resumed arrival returns actual axe and cargo to warehouse")
	sim = fixture()
	npc = sim.state.npcs[ID]
	npc.work_options.build = true
	var mallets: Array[String] = sim._create_item_instances("core:mallet",1,"npc",ID)
	npc.carried_instance_id = mallets[0]
	npc.position = [560.0,976.0]
	sim.state.blueprints = []
	for x: int in [17,18]: sim.state.blueprints.append({"building_id":"core:wood_floor","cell":[x,29],"stage_id":"core:blueprint","required_materials":{"core:plank":10},"delivered_materials":{"core:plank":10},"required_work_minutes":4,"work_progress_minutes":3 if x == 17 else 0})
	npc.initiative_job = {"kind":"build","phase":"build","tool_id":"core:mallet","cell":[17,29],"drops":[]}
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[17,30]}})
	check(npc.initiative_job.phase == "build" and npc.initiative_job.cell == [18,29] and npc.carried_instance_id == mallets[0],"Finishing construction reuses mallet for next paid blueprint")
	print("PLAYTEST_NPC_WORK: %d failures" % failures)
	quit(0 if failures == 0 else 1)
