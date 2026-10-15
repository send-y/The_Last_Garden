extends "res://tests/npc_crop_harvest_rules_test.gd"
func run() -> void:
	var sim = fixture(); var cell := soil(sim)
	sim.state.farming.beds.append({"cell":[cell.x,cell.y],"crop_id":"","growth":0,"wet_until":0,"last_update":0,"harvests":0,"shared_harvest":false})
	if not sim.farming.has_method("primary_action"):
		check(false,"Missing farming primary action"); quit(1); return
	sim._add_item("core:potato_seed",2)
	sim.set_player_position(Content.cell_center(cell.x,cell.y))
	sim.select_inventory_item("core:potato_seed")
	check(sim.farming.primary_action(sim,cell)=={"action_id":"plant","item_id":"core:potato_seed"},"Selected seed chooses direct plant")
	var action: Dictionary = sim.farming.primary_action(sim,cell)
	action.actor_id = "core:player"; action.cell = [cell.x,cell.y]
	check(bool(sim.execute_farming_command(action).success) and sim.get_item_count("core:potato_seed")==1,"Direct action consumes one real seed")
	check(sim.farming.primary_action(sim,cell).is_empty(),"Unripe crop opens settings instead of planting twice")
	var bed: Dictionary = sim.farming.bed_at(sim,cell); bed.growth = 4320
	check(sim.farming.primary_action(sim,cell)=={"action_id":"harvest"},"Ripe crop chooses direct harvest even with seeds selected")
	print("PASS: farming primary actions" if failures==0 else "FAIL: farming primary action")
	quit(0 if failures==0 else 1)
