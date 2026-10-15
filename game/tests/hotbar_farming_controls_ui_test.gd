extends "res://tests/package_d_meeting_ui_test.gd"

func _ready() -> void:
	get_tree().create_timer(45).timeout.connect(func() -> void: get_tree().quit(1))
	Session.set_mechanics_lab_active(true); Session.set_process(false)
	TranslationServer.set_locale("ru")
	var source := World.new(preload("res://src/dev/package_d_scenarios.gd").day_three_state())
	var values: Array = source.state.storage_zones[0].cells[0]
	var stock_cell := Vector2i(int(values[0]),int(values[1]))
	source.set_player_position(source.content.cell_center(stock_cell.x,stock_cell.y))
	source._add_item("core:bucket",1)
	var bucket_id := source.get_inventory_instance_id("core:bucket",0)
	source.assign_hotbar_slot(2,bucket_id); source.select_hotbar_slot(2)
	Session.apply_debug_state(source.export_state(),"hotbar ghosts and farming E",false)
	var main := Main.instantiate(); add_child(main); await frames()
	var player = main.get_node("Player"); player.set_physics_process(false)
	var hud = main.get_node("Hud/HudRoot")
	var world = main.get_node("World")
	check(bool(Session.transfer_inventory_stack_to_storage(stock_cell,"core:bucket",0).success),"Real transfer removes assigned bucket")
	await frames()
	check(hud._hotbar_icons[2].texture!=null and hud._hotbar_icons[2].self_modulate.a<0.5,"Absent physical item has translucent hotbar icon")
	check(hud._hotbar_buttons[2].tooltip_text.contains("вне рюкзака"),"Ghost tooltip explains unavailable item")
	hud.handle_hotbar_key(2)
	check(Session.get_active_item_instance().is_empty(),"Selecting ghost leaves hand empty")
	await screenshot("hotbar-ghost.png")
	var placement := ""
	for record: Dictionary in Session.simulation.state.storage_items:
		if String(record.get("instance_id",""))==bucket_id: placement = String(record.placement_id)
	check(bool(Session.transfer_storage_stack_to_inventory(stock_cell,placement).success),"Same bucket returns through real transfer")
	await frames()
	check(is_equal_approx(hud._hotbar_icons[2].self_modulate.a,1.0) and String(Session.get_active_item_instance().get("instance_id",""))==bucket_id,"Return restores full icon and selected physical item")
	var sim = Session.simulation
	var cell := Vector2i(-1,-1)
	for y: int in range(30,40):
		for x: int in range(30,40):
			if sim.farming._soil_allowed(sim,Vector2i(x,y)): cell = Vector2i(x,y); break
		if cell.x>=0: break
	sim.state.farming.beds.append({"cell":[cell.x,cell.y],"crop_id":"","growth":0,"wet_until":0,"last_update":sim.get_elapsed_game_minutes(),"harvests":0,"shared_harvest":false,"maintain_crop":false,"planned_crop_id":"","planting_id":0})
	sim._add_item("core:potato_seed",2)
	Session.select_inventory_item("core:potato_seed")
	var at: Vector2 = sim.content.cell_center(cell.x,cell.y)
	sim.set_player_position(at); player.global_position = at
	world.select_at_world_position(at); await frames()
	await press_e()
	check(sim.get_farm_bed(cell).crop_id=="potato" and sim.get_item_count("core:potato_seed")==1,"Actual E plants held seed once")
	check(not hud._farming_panel.visible,"Direct planting does not open menu")
	sim.farming.bed_at(sim,cell).growth = 4320
	world.select_at_world_position(at); await frames()
	world.interact_with_selection(false); await frames()
	check(hud._farming_panel.visible,"RMB path retains ripe bed settings")
	hud._farming_panel.close_requested.emit(); await frames()
	var previous: int = potato_count(sim)
	await screenshot("farming-harvest-e.png")
	await press_e()
	check(sim.get_farm_bed(cell).crop_id=="" and potato_count(sim)==previous+3,"Actual E harvests physical crop products, including automatic pickup")
	check(not hud._farming_panel.visible,"Direct harvest does not open menu")
	var distant := at+Vector2(300,0)
	sim.set_player_position(distant); player.global_position = distant
	world.select_at_world_position(at); await press_e()
	check(sim.get_farm_bed(cell).crop_id=="" and sim.get_item_count("core:potato_seed")==1,"Distant E does not consume seed")
	print("PASS: ghost rendering, actual E planting and harvesting" if failures==0 else "FAIL: hotbar/farming controls UI")
	get_tree().quit(0 if failures==0 else 1)

func press_e() -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new(); event.keycode = KEY_E
		event.physical_keycode = KEY_E; event.pressed = pressed
		get_viewport().push_input(event,true)
	await frames()

func potato_count(sim) -> int:
	var amount: int = sim.get_item_count("core:potato")
	for drop: Dictionary in sim.state.world_drops:
		if String(drop.item_id)=="core:potato": amount += int(drop.amount)
	return amount
