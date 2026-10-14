extends Node
const Grid := preload("res://src/ui/inventory_grid.gd")
const Dropped := preload("res://src/items/dropped_item.tscn")
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _ready() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var sim = World.new(World.create_new_game_state())
	sim.try_pickup_item("core:wood",1)
	sim.try_pickup_item("core:stone",1)
	var content = sim.content
	var grid := Grid.new()
	grid.position = Vector2(20,20)
	add_child(grid)
	grid.layout_changed.connect(func(layout: Array[Dictionary]) -> void:
		if sim.set_inventory_layout(layout).success: grid.present(sim.get_inventory_placements(),content)
	)
	grid.present(sim.get_inventory_placements(),content)
	var wood: Dictionary = grid._placements[0]
	var stone: Dictionary = grid._placements[1]
	var source: Vector2i = wood.origin
	var target: Vector2i = stone.origin
	grid._begin_hand(0,Vector2(source)*grid.CELL_SIZE+Vector2(10,10))
	grid._finish_drag(target)
	check(grid._placements[0].origin == target and grid._placements[1].origin == source,"Occupied equal shape swaps positions through simulation")
	check(grid.is_holding_item() and grid._placements[grid._dragged_placement_index].item_id == stone.item_id,"Displaced item remains under cursor")
	grid.return_held_item()
	check(sim.get_item_count("core:wood") == 1 and sim.get_item_count("core:stone") == 1,"Swap conserves resources")
	var drop = Dropped.instantiate()
	drop.position = Vector2(320,90)
	drop.configure("test:tool","core:axe",1,load(content.item_icon_path("core:axe")))
	add_child(drop)
	await get_tree().process_frame
	var sprite: Sprite2D = drop.get_node("Icon")
	var extent := sprite.texture.get_size()*sprite.scale
	check(maxf(extent.x,extent.y) <= 32,"Ground icon stays inside one world cell independently of PNG resolution")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/playtest-fixes-2026-10-14/items-ui.png"))
		grid.queue_free()
		drop.queue_free()
		var state := World.create_new_game_state()
		state.player_position = [720.0,720.0]
		state.storage_items.append({"cell":[22,23],"item_id":"core:wood","amount":5,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"})
		state.storage_items.append({"cell":[22,23],"item_id":"core:stone","amount":3,"origin":[1,0],"rotation":0,"stack_index":0,"placement_id":"core:stone:0"})
		Session._replace_simulation(state)
		check(Session.get_storage_layout(Vector2i(22,23)).size() == 2,"World miniature fixture keeps two stored stacks")
		var main := preload("res://src/main/main.tscn").instantiate()
		add_child(main)
		main.get_node("Player/Camera2D").position_smoothing_enabled = false
		main.get_node("Player/Camera2D").reset_smoothing()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var world_view: Node2D = main.get_node("World")
		var storage_layer: Node2D = world_view._presentation_layers.storage
		storage_layer.hide()
		await RenderingServer.frame_post_draw
		var background := get_viewport().get_texture().get_image()
		storage_layer.show()
		await RenderingServer.frame_post_draw
		var foreground := get_viewport().get_texture().get_image()
		var visible_changes := 0
		for y: int in range(32):
			for x: int in range(32):
				var pixel := Vector2i(get_viewport().get_stretch_transform()*world_view.get_global_transform_with_canvas()*Vector2(22*32+x,23*32+y))
				if foreground.get_pixelv(pixel) != background.get_pixelv(pixel): visible_changes += 1
		check(visible_changes > 0,"Storage miniature pixels are visible above the wooden floor")
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/playtest-fixes-2026-10-14/storage-miniatures.png"))
	print("PLAYTEST_ITEM_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
