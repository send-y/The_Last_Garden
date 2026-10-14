extends "res://tests/npc_crop_harvest_rules_test.gd"
func run() -> void:
	var sim = fixture(); var cell := soil(sim)
	sim.set_player_position(Content.cell_center(cell.x,cell.y))
	sim._add_item("core:hoe",1)
	sim.select_inventory_item("core:hoe",sim.get_inventory_instance_id("core:hoe",0))
	check(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"till","cell":[cell.x,cell.y]}).success),"Real till command")
	check(World.new(sim.export_state()).get_farm_beds()==sim.get_farm_beds(),"Empty newly tilled bed retains exact state on reload")
	sim._add_item("core:potato_seed",1)
	check(bool(sim.execute_farming_command({"actor_id":"core:player","action_id":"plant","cell":[cell.x,cell.y],"item_id":"core:potato_seed"}).success),"Real player planting")
	check(World.new(sim.export_state()).get_farm_beds()==sim.get_farm_beds(),"Player planting retains exact state on reload")
	print("PASS: new beds are normalized before saving" if failures==0 else "FAIL: new bed reload")
	quit(0 if failures==0 else 1)
