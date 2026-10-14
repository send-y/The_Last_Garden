extends "res://tests/package_d_meeting_ui_test.gd"

func _ready() -> void:
	get_tree().create_timer(40).timeout.connect(func() -> void: get_tree().quit(1))
	Session.set_mechanics_lab_active(true); Session.set_process(false)
	get_window().content_scale_size = Vector2i(640,360)
	TranslationServer.set_locale("ru")
	var sim := World.new(preload("res://src/dev/package_d_scenarios.gd").day_three_state())
	Session.apply_debug_state(sim.export_state(),"storage grid viewport fit",true)
	var main := Main.instantiate(); add_child(main); await frames()
	main.get_node("Player").set_physics_process(false)
	var hud = main.get_node("Hud/HudRoot")
	var values: Array = Session.simulation.state.storage_zones[0].cells[0]
	var cell := Vector2i(int(values[0]),int(values[1]))
	Session.simulation.set_player_position(Session.simulation.content.cell_center(cell.x,cell.y))
	hud.open_storage(cell); await frames(8)
	var panel = hud._storage_panel
	for resolution: Vector2i in [Vector2i(640,360),Vector2i(1280,720),Vector2i(1270,640)]:
		get_window().size = resolution; await frames(8)
		panel._items_scroll.scroll_vertical = 0; await frames()
		var visible_area: Rect2 = panel._items_scroll.get_global_rect()
		check(Rect2(Vector2.ZERO,hud.size).encloses(panel.get_global_rect()),"Whole storage panel fits")
		check(visible_area.encloses(panel._inventory_grid.get_global_rect()),"All backpack rows fit at "+str(resolution))
		check(visible_area.encloses(panel._storage_grid.get_global_rect()),"All storage rows fit at "+str(resolution))
		check(visible_area.encloses(panel._inventory_title.get_global_rect()) and visible_area.encloses(panel._storage_title.get_global_rect()),"Grid titles fit without scroll")
		check(panel._items_scroll.get_v_scroll_bar().max_value<=panel._items_scroll.get_v_scroll_bar().page,"No vertical item scrolling needed")
	var stock = panel._storage_grid
	var pack = panel._inventory_grid
	var axe: Dictionary = {}
	for item: Dictionary in stock._placements:
		if String(item.item_id)=="core:axe": axe = item
	check(not axe.is_empty(),"Fixture has a physical axe")
	if not axe.is_empty():
		var grabbed := Vector2i(int(axe.origin.x),int(axe.origin.y)+1)
		var pick: Vector2 = stock.get_global_transform_with_canvas()*((Vector2(grabbed)+Vector2.ONE*0.5)*stock.cell_size)
		var original_instance := String(axe.instance_id)
		var event := InputEventMouseMotion.new(); event.position = pick; event.global_position = pick; get_viewport().push_input(event,true)
		await click_at(pick)
		check(stock.is_holding_item(),"Smaller cell picks up axe by its lower occupied cell")
		var target: Vector2 = pack.get_global_transform_with_canvas()*((Vector2(2,2)+Vector2.ONE*0.5)*pack.cell_size)
		event = InputEventMouseMotion.new(); event.position = target; event.global_position = target; get_viewport().push_input(event,true)
		await click_at(target)
		check(not stock.is_holding_item(),"Smaller grids transfer held axe")
		var found := false
		for item: Dictionary in Session.get_inventory_placements():
			if String(item.get("instance_id",""))==original_instance:
				found = true
				check(item.origin==Vector2i(2,1),"Grabbed cell remains placement anchor")
		check(found,"Same physical axe transferred to backpack")
	await screenshot("storage-fitted-grids.png")
	print("PASS: storage grids fit viewport without clipping" if failures==0 else "FAIL: storage grid fit")
	get_tree().quit(0 if failures==0 else 1)

func click_at(point: Vector2) -> void:
	for pressed: bool in [true,false]:
		var button := InputEventMouseButton.new(); button.position = point; button.global_position = point
		button.button_index = MOUSE_BUTTON_LEFT; button.pressed = pressed
		get_viewport().push_input(button,true)
	await frames()
