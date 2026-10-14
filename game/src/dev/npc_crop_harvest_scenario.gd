extends RefCounted
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")

static func build() -> Dictionary:
	var sim := World.new(preload("res://src/dev/package_d_scenarios.gd").day_three_state())
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
	npc.personal_inventory = {"core:food":0}
	sim.set_npc_work_enabled(String(npc.id),"harvest",true)
	var crops := ["carrot","potato","strawberry"]
	var planted := 0
	for y: int in range(30,35):
		for x: int in range(33,40):
			var cell := Vector2i(x,y)
			if not sim.farming._soil_allowed(sim,cell): continue
			var crop: Dictionary = sim.farming.catalog.find(crops[planted])
			sim.state.farming.beds.append({"cell":[x,y],"crop_id":crop.id,"growth":int(crop.growth_minutes),"wet_until":0,"last_update":sim.get_elapsed_game_minutes(),"harvests":0,"shared_harvest":planted>0,"planting_id":planted+1})
			planted += 1
			if planted==crops.size(): break
		if planted==crops.size(): break
	sim.state.farming.planting_serial = planted
	sim.set_player_position(Content.cell_center(34,31))
	return {"success":planted==crops.size(),"simulation":sim,"state":sim.export_state(),"steps":[]}
