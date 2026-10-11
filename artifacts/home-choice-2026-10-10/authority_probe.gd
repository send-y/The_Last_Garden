extends SceneTree
const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Layout := preload("res://src/npc_work/home_furnishing_layout.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var result: Dictionary = {"choices":[],"minutes":[]}
	for variant: int in range(5):
		var sim = Fixture.create()
		var npc: Dictionary = sim.state.npcs[Fixture.NPC]
		if variant > 0:
			sim.add_structure({"building_id":"core:table","cell":[42,33]})
		if variant > 1:
			sim.add_structure({"building_id":"core:chair","cell":[41,33]})
		if variant > 2:
			sim.state.blueprints.append({"building_id":"core:torch","cell":[43,31]})
		if variant == 4:
			sim.state.npc_profiles[Fixture.NPC] = {"value_ids":["core:care","core:order"]}
		sim._sync_structure_navigation()
		for seed_value: int in range(8):
			for building: String in Layout.ALLOWED:
				for ignore_actors: bool in [false,true]:
					var rng := RandomNumberGenerator.new()
					rng.seed = seed_value
					var cell := Layout.choose_cell(sim,npc,building,rng,ignore_actors)
					result.choices.append({"cell":[cell.x,cell.y],"rng":str(rng.state)})
	var sim = Fixture.create()
	Fixture.stock(sim,100)
	sim.set_npc_work_enabled(Fixture.NPC,"build",true)
	for minute: int in range(240):
		if minute == 20: sim.StockReserves.set_reserve(sim,"core:plank",100)
		if minute == 40: sim.StockReserves.set_reserve(sim,"core:plank",0)
		if minute == 60: sim.set_npc_work_enabled(Fixture.NPC,"build",false)
		if minute == 65: sim.set_npc_work_enabled(Fixture.NPC,"build",true)
		if minute == 90: sim.state.npcs[Fixture.NPC].needs.hunger = 35.0
		if minute == 100: sim.state.npcs[Fixture.NPC].needs.hunger = 100.0
		sim.advance_minutes(1)
		result.minutes.append(sim.export_state())
	var args := OS.get_cmdline_user_args()
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result))
	print("AUTHORITY_PROBE: %d choices and %d minutes" % [result.choices.size(),result.minutes.size()])
	quit()
