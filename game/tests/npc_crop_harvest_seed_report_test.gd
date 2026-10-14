extends SceneTree
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	var sim := World.new(World.create_new_game_state(1337))
	if not sim.work_metrics.has_method("record_harvest"):
		check(false,"Missing actual harvest and seed ledger"); quit(1); return
	var report = load("res://src/dev/farming_report.gd")
	sim.work_metrics.enabled = true
	sim._add_item("core:carrot",1)
	var snapshot: Dictionary = report.snapshot(sim)
	check(snapshot.carrot.seeds_total==0 and snapshot.carrot.products_total==1,"Unsown product is not counted as ready seed")
	check(not snapshot.carrot.extraction_unlocked,"Report reflects missing study table")
	var failed := sim.execute_farming_command({"actor_id":"core:player","action_id":"extract","item_id":"core:carrot"})
	check(not bool(failed.success) and sim.work_metrics.farming_snapshot(sim.get_day()).is_empty(),"Failed extraction records no seed or consumed product")
	sim.add_structure({"building_id":"core:study_table","cell":[35,30],"stage_id":"core:complete"})
	var result := sim.execute_farming_command({"actor_id":"core:player","action_id":"extract","item_id":"core:carrot"})
	check(bool(result.success),"Real crop extraction succeeds with table")
	snapshot = report.snapshot(sim)
	var amount := sim.get_item_count("core:carrot_seed")
	check(amount>=1 and amount<=5 and snapshot.carrot.seeds_total==amount and snapshot.carrot.products_total==0,"Report counts the actual random seed result")
	var ledger: Dictionary = sim.work_metrics.farming_snapshot(sim.get_day()).get("core:player",{})
	check(int(ledger.get("extracted",{}).get("core:carrot_seed",0))==amount and int(ledger.get("extraction_inputs",{}).get("core:carrot",0))==1,"Actual extraction records source and species once")
	var zones: Array = sim.state.storage_zones
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.work_cargo["core:carrot_seed"] = 2
	npc.personal_inventory["core:carrot"] = 1
	var ids: Array[String] = sim._create_resource_drops("core:player","core:carrot_seed",3,Content.cell_center(30,30))
	snapshot = report.snapshot(sim)
	check(snapshot.carrot.seeds_total==amount+5 and snapshot.carrot.seeds_by_location.npc_cargo==2 and snapshot.carrot.seeds_by_location.world_drops==3,"Physical stocks counted once by location")
	var reload := World.new(sim.export_state())
	check(report.snapshot(reload).carrot.seeds_total==snapshot.carrot.seeds_total,"Reload does not invent or lose reported seeds")
	sim._consume_items({"core:carrot_seed":amount})
	npc.work_cargo.erase("core:carrot_seed")
	for drop: Dictionary in sim.state.world_drops.duplicate():
		if ids.has(String(drop.drop_id)): sim.state.world_drops.erase(drop)
	npc.personal_inventory["core:carrot"] = 0
	snapshot = report.snapshot(sim)
	check(snapshot.carrot.flags.has("no_seeds") and snapshot.carrot.flags.has("no_product_for_extraction"),"Report explicitly marks empty seed and product stocks")
	sim.work_metrics.enabled = false
	var before := JSON.stringify(sim.work_metrics.farming_snapshot(sim.get_day()))
	sim.work_metrics.record_harvest(sim,"core:player","core:carrot",100)
	check(JSON.stringify(sim.work_metrics.farming_snapshot(sim.get_day()))==before,"Disabled diagnostic cannot accumulate fictitious harvest")
	print("PASS: actual seed balances, extraction inputs, locations and shortages" if failures==0 else "FAIL: seed report")
	quit(0 if failures==0 else 1)
