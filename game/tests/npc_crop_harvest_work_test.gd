extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Practical := preload("res://src/npc_work/npc_practical_work.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const ID := "core:first_neighbor"
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func fixture():
	var state := preload("res://src/dev/package_d_scenarios.gd").day_three_state()
	state.day = 2; state.minute_of_day = 600; state.elapsed_game_minutes = 2040
	state.npcs[ID].needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	state.npcs[ID].personal_inventory = {}
	return World.new(state)
func add_crop(sim, crop_id: String = "potato") -> Vector2i:
	for y: int in range(30,36):
		for x: int in range(33,40):
			var cell := Vector2i(x,y)
			if not sim.farming._soil_allowed(sim,cell) or not sim.get_farm_bed(cell).is_empty(): continue
			var crop: Dictionary = sim.farming.catalog.find(crop_id)
			sim.state.farming.beds.append({"cell":[x,y],"crop_id":crop_id,"growth":int(crop.growth_minutes),"wet_until":0,"last_update":sim.get_elapsed_game_minutes(),"harvests":0,"shared_harvest":true})
			return cell
	return Vector2i(-1,-1)
func place_npc(sim,cell: Vector2i) -> void:
	var point := Content.cell_center(cell.x,cell.y)
	sim.state.npcs[ID].position = [point.x,point.y]
func run() -> void:
	var sim = fixture()
	var cell := add_crop(sim)
	check(bool(sim.set_npc_work_enabled(ID,"harvest",true).success),"NPC harvest option accepted")
	if not bool(sim.state.npcs[ID].work_options.get("harvest",false)):
		quit(1); return
	var npc: Dictionary = sim.state.npcs[ID]
	var contexts: Dictionary = Practical.prepare(sim)
	check(not npc.initiative_job.is_empty() and npc.initiative_job.kind=="harvest","Planner chooses harvest without borrowing")
	if npc.initiative_job.is_empty(): quit(1); return
	place_npc(sim,cell)
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[cell.x,cell.y]}})
	check(npc.initiative_job.phase=="collect" and npc.initiative_job.drops.size()>0,"Harvest proceeds to real collection")
	var restored = World.new(sim.export_state())
	check(restored.state.npcs[ID].initiative_job.drops==npc.initiative_job.drops,"Pending drops survive reload")
	sim = restored; npc = sim.state.npcs[ID]
	for step: int in range(14):
		var context: Dictionary = Practical.context_for(sim,npc) if not npc.initiative_job.is_empty() else {}
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	check(sim.StockReserves.total(sim,"core:potato")==3,"All potatoes delivered to real storage")
	check(npc.work_cargo.is_empty(),"Delivered cargo is removed once")
	check(sim.state.world_drops.is_empty(),"Collected drops are not duplicated")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true)
	sim.state.storage_zones = []
	Practical.prepare(sim)
	check(npc.initiative_job.is_empty(),"No reachable storage prevents new ordinary harvest")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true); Practical.prepare(sim)
	sim.farming.bed_at(sim,cell).crop_id = "carrot"
	sim.farming.bed_at(sim,cell).growth = 1440
	place_npc(sim,cell)
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[cell.x,cell.y]}})
	check(sim.state.world_drops.is_empty(),"Stale crop expectation does not harvest replacement")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true); Practical.prepare(sim); place_npc(sim,cell)
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[cell.x,cell.y]}})
	var drops: Array = npc.initiative_job.drops.duplicate()
	sim.set_npc_work_enabled(ID,"harvest",false)
	check(not drops.is_empty() and npc.initiative_job.get("drops",[])==drops,"Cancellation retains already harvested drop IDs")
	for step: int in range(14):
		var context: Dictionary = Practical.context_for(sim,npc) if not npc.initiative_job.is_empty() else {}
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	check(sim.StockReserves.total(sim,"core:potato")==3,"Cancelled harvest still collects and delivers paid product")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	for definition: Dictionary in sim.farming.catalog.crops:
		if definition.id=="potato": definition.yield = 25
	sim.set_npc_work_enabled(ID,"harvest",true); Practical.prepare(sim); place_npc(sim,cell)
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[cell.x,cell.y]}})
	for step: int in range(40):
		var context: Dictionary = Practical.context_for(sim,npc) if not npc.initiative_job.is_empty() else {}
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	if sim.StockReserves.total(sim,"core:potato")!=25 or not sim.state.world_drops.is_empty(): print("DEBUG oversized ",sim.StockReserves.total(sim,"core:potato")," ",npc.initiative_job," ",npc.work_cargo," ",sim.state.world_drops)
	check(sim.StockReserves.total(sim,"core:potato")==25 and sim.state.world_drops.is_empty(),"Multiple delivery trips retain crop yield above carry limit")
	sim = fixture(); cell = add_crop(sim); npc = sim.state.npcs[ID]
	sim.set_npc_work_enabled(ID,"harvest",true); Practical.prepare(sim); place_npc(sim,cell)
	Practical.fulfil(sim,{"npc_id":ID,"context":{"target_cell":[cell.x,cell.y]}})
	var zones: Array = sim.state.storage_zones.duplicate(true)
	sim.state.storage_zones = []
	for step: int in range(5):
		var context: Dictionary = Practical.context_for(sim,npc)
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	check(int(npc.work_cargo.get("core:potato",0))==3 and npc.initiative_job.get("blocked_reason","")=="storage_full_or_unreachable","Unavailable storage after harvest preserves real cargo")
	var blocked = World.new(sim.export_state())
	check(int(blocked.state.npcs[ID].work_cargo.get("core:potato",0))==3,"Blocked cargo persists through reload")
	sim.state.storage_zones = zones
	for step: int in range(8):
		var context: Dictionary = Practical.context_for(sim,npc) if not npc.initiative_job.is_empty() else {}
		if context.is_empty(): break
		place_npc(sim,Vector2i(int(context.target_cell[0]),int(context.target_cell[1])))
		Practical.fulfil(sim,{"npc_id":ID,"context":context})
	check(sim.StockReserves.total(sim,"core:potato")==3,"Restoring storage resumes delivery")
	print("PASS: physical NPC crop work, delivery, cancellation and stale goals" if failures==0 else "FAIL: NPC crop work")
	quit(0 if failures==0 else 1)
