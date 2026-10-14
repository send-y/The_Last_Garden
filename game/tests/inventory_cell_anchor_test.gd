extends Node

const Grid := preload("res://src/ui/inventory_grid.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Main := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const OUT := "res://../artifacts/inventory-anchor-2026-10-12"
var failures := 0
var source: InventoryGrid
var destination: InventoryGrid
var layouts: Array[Dictionary] = []
var transfers: Array[Dictionary] = []
var accept_transfer := true
var content := Content.new()
const LOWER_CELL_AFTER_TURN: Array[Vector2i] = [Vector2i(0,1),Vector2i(0,0),Vector2i(0,0),Vector2i(1,0)]
const EXPECTED_ORIGINS: Array[Vector2i] = [Vector2i(2,1),Vector2i(2,2),Vector2i(2,2),Vector2i(1,2)]

func _ready() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ",label)
func settle() -> void:
	for _frame: int in range(2): await get_tree().process_frame
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event,true)
func click(point: Vector2) -> void:
	motion(point)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event,true)
func rotate() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.physical_keycode = KEY_R
	key.pressed = true
	get_viewport().push_input(key,true)
func bucket(turns: int = 0) -> Dictionary:
	return {"item_id":"core:bucket","instance_id":"anchor:bucket","amount":1,"origin":Vector2i.ZERO,"rotation":turns,"footprint":content.item_footprint("core:bucket",turns),"icon_path":content.item_icon_path("core:bucket",{"charges":2})}
func point(grid: InventoryGrid, cell: Vector2i, offset: Vector2) -> Vector2:
	return grid.get_global_transform_with_canvas() * (Vector2(cell)*grid.CELL_SIZE+offset)
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	get_window().size = Vector2i(640,360)
	get_window().content_scale_size = Vector2i(640,360)
	source = Grid.new()
	source.position = Vector2(20,42)
	add_child(source)
	destination = Grid.new()
	destination.position = Vector2(340,42)
	destination.scale = Vector2.ONE*0.85
	add_child(destination)
	source.external_transfer_target = destination
	source.layout_changed.connect(func(layout: Array[Dictionary]) -> void: layouts.append(layout.back()))
	source.cross_grid_drop_requested.connect(func(placement: Dictionary, origin: Vector2i) -> void:
		transfers.append({"placement":placement,"origin":origin})
		if accept_transfer: source.return_held_item()
	)
	await settle()
	for cross_grid: bool in [false,true]:
		var target := destination if cross_grid else source
		for pickup_offset: Vector2 in [Vector2(3,5),Vector2(61,60)]:
			for target_offset: Vector2 in [Vector2(1,1),Vector2(63,63)]:
				for turns: int in range(4):
					source.return_held_item()
					source.present([bucket()],content)
					destination.present([],content)
					layouts.clear()
					transfers.clear()
					click(point(source,Vector2i(0,1),pickup_offset))
					await settle()
					check(source.is_holding_item(),"Lower bucket cell starts carry")
					if not source.is_holding_item(): continue
					var initial_pivot := source._cursor_visual.position + (Vector2(0,1)+Vector2.ONE*0.5)*source.CELL_SIZE
					for turn: int in range(turns):
						rotate()
						await settle()
						var pivot := source._cursor_visual.position + (Vector2(LOWER_CELL_AFTER_TURN[turn+1])+Vector2.ONE*0.5)*source.CELL_SIZE
						check(pivot.is_equal_approx(initial_pivot),"Rotation stays around the grabbed cell centre at turn %d" % (turn+1))
					var pointer := point(target,Vector2i(2,2),target_offset)
					motion(pointer)
					await settle()
					if not cross_grid:
						check(source._cursor_target_cell() == EXPECTED_ORIGINS[turns],"Preview follows the cell under the cursor regardless of pixel offset at turn %d" % turns)
					# A refresh while holding must keep both the grabbed cell and pivot.
					var cursor_before := source._cursor_visual.position
					source.present([bucket()],content)
					await settle()
					check(source.is_holding_item() and source._cursor_visual.position.is_equal_approx(cursor_before),"Refresh preserves the grab anchor")
					click(pointer)
					await settle()
					if cross_grid:
						check(transfers.size() == 1 and transfers[0].origin == EXPECTED_ORIGINS[turns],"Scaled cross-grid transfer uses the grabbed cell at turn %d" % turns)
						if not transfers.is_empty(): check(transfers[0].placement.instance_id == "anchor:bucket","Transfer preserves physical identity")
					else:
						check(layouts.size() == 1 and layouts[0].origin == [EXPECTED_ORIGINS[turns].x,EXPECTED_ORIGINS[turns].y],"Click places the bucket exactly where the preview indicated at turn %d" % turns)
					check(not source.is_holding_item(),"Valid placement finishes carry")
	# Edge and blocked target must retain the item instead of relocating it.
	for target: InventoryGrid in [source,destination]:
		source.present([bucket()],content)
		destination.present([],content)
		layouts.clear()
		transfers.clear()
		click(point(source,Vector2i(0,1),Vector2(60,60)))
		await settle()
		click(point(target,Vector2i(1,0),Vector2(63,63)))
		await settle()
		check(source.is_holding_item() and layouts.is_empty() and transfers.is_empty(),"Out-of-bounds anchored placement keeps the item on the cursor")
		source.return_held_item()
	for target: InventoryGrid in [source,destination]:
		var blocker := {"item_id":"core:wood","amount":1,"origin":Vector2i(2,1),"rotation":0,"footprint":[Vector2i.ZERO]}
		accept_transfer = false
		var source_items: Array[Dictionary] = [bucket()]
		var destination_items: Array[Dictionary] = []
		if target == source: source_items.append(blocker)
		else: destination_items.append(blocker)
		source.present(source_items,content)
		destination.present(destination_items,content)
		layouts.clear()
		transfers.clear()
		click(point(source,Vector2i(0,1),Vector2(4,6)))
		await settle()
		click(point(target,Vector2i(2,2),Vector2(32,32)))
		await settle()
		check(source.is_holding_item() and layouts.is_empty() and transfers.size() == (1 if target == destination else 0),"Rejected anchored placement keeps the item on the cursor")
		source.return_held_item()
	accept_transfer = true
	# A saved item can already be rotated when picked up.
	for initial_turn: int in range(4):
		source.present([bucket(initial_turn)],content)
		destination.present([],content)
		layouts.clear()
		click(point(source,LOWER_CELL_AFTER_TURN[initial_turn],Vector2(59,2)))
		await settle()
		motion(point(source,Vector2i(2,2),Vector2(1,63)))
		await settle()
		check(source._cursor_target_cell() == EXPECTED_ORIGINS[initial_turn],"Already rotated bucket uses the actual clicked cell")
		click(point(source,Vector2i(2,2),Vector2(1,63)))
		await settle()
		check(layouts.size() == 1 and layouts[0].rotation == initial_turn and layouts[0].origin == [EXPECTED_ORIGINS[initial_turn].x,EXPECTED_ORIGINS[initial_turn].y],"Already rotated placement keeps its orientation and anchor")
	# Irregular axe: grab the last handle cell, then turn around that same cell.
	source.present([{"item_id":"core:axe","instance_id":"anchor:axe","amount":1,"origin":Vector2i.ZERO,"rotation":0,"footprint":content.item_footprint("core:axe"),"icon_path":content.item_icon_path("core:axe")}],content)
	click(point(source,Vector2i(0,2),Vector2(7,49)))
	await settle()
	var axe_anchor: Array[Vector2i] = [Vector2i(0,2),Vector2i(0,0),Vector2i(1,0),Vector2i(2,1),Vector2i(0,2)]
	var pivot := source._cursor_visual.position+(Vector2(axe_anchor[0])+Vector2.ONE*0.5)*source.CELL_SIZE
	var start := source._cursor_visual.position
	for turn: int in range(4):
		rotate()
		await settle()
		check((source._cursor_visual.position+(Vector2(axe_anchor[turn+1])+Vector2.ONE*0.5)*source.CELL_SIZE).is_equal_approx(pivot),"Irregular axe rotates around the grabbed occupied cell")
	check(source._cursor_visual.position.is_equal_approx(start),"Four rotations restore the exact cursor image position")
	motion(point(source,Vector2i(2,2),Vector2(32,32)))
	await settle()
	rotate()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		get_viewport().get_texture().get_image().save_png(OUT+"/grabbed-handle-rotated.png")
	await check_real_stack_transfer()
	print("INVENTORY_CELL_ANCHOR: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check_real_stack_transfer() -> void:
	source.return_held_item()
	source.hide()
	destination.hide()
	var state := Simulation.create_new_state()
	state.inventory = {"core:wood":3,"core:bucket":1}
	state.item_instances = []
	state.inventory_layout = [
		{"item_id":"core:wood","stack_index":0,"origin":[0,0],"rotation":0},
		{"item_id":"core:bucket","stack_index":0,"origin":[1,0],"rotation":0},
	]
	state.storage_zones = [{"id":"core:storage_zone_0001","cells":[[10,10]]}]
	state.storage_items = [{"cell":[10,10],"item_id":"core:wood","amount":2,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"}]
	Session.apply_debug_state(state,"anchor stack return",false)
	Session.set_player_position(content.cell_center(10,10))
	var main := Main.instantiate()
	add_child(main)
	await settle()
	(main.get_node("Player") as PlayerController).set_physics_process(false)
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	hud.open_storage(Vector2i(10,10))
	await settle()
	var storage := hud._storage_panel
	var stock := storage._storage_grid
	var backpack := storage._inventory_grid
	click(point(stock,Vector2i.ZERO,Vector2(2,2)))
	await settle()
	check(stock.is_holding_item(),"Real stock stack attaches to cursor")
	click(point(backpack,Vector2i(1,0),Vector2(10,1)))
	await settle()
	check(stock.is_holding_item() and Session.simulation.get_item_count("core:wood") == 3 and Session.get_storage_layout(Vector2i(10,10)).size() == 1,"Authoritative refusal preserves cursor and contents")
	click(point(backpack,Vector2i.ZERO,Vector2(63,1)))
	await settle()
	check(Session.simulation.get_item_count("core:wood") == 5 and Session.get_storage_layout(Vector2i(10,10)).is_empty() and not stock.is_holding_item(),"Returning wood to a partial stack still merges through the simulation")
	Session.simulation.try_pickup_item("core:stone",1)
	var layout: Array = Session.get_inventory_layout()
	for entry: Dictionary in layout:
		if entry.item_id == "core:stone": entry.origin = [2,0]
	Session.simulation.set_inventory_layout(layout)
	Session.simulation.state.storage_items.append({"cell":[10,10],"item_id":"core:wood","amount":2,"origin":[0,0],"rotation":0,"stack_index":0,"placement_id":"core:wood:0"})
	storage.refresh(Vector2i(10,10))
	await settle()
	click(point(stock,Vector2i.ZERO,Vector2(2,2)))
	click(point(backpack,Vector2i(2,0),Vector2(2,2)))
	await settle()
	check(stock.is_holding_item() and stock._placements[stock._dragged_placement_index].item_id == "core:stone","Real HUD exchange keeps displaced warehouse stack on cursor")
	check(Session.simulation.get_item_count("core:stone") == 0 and Session.simulation.get_item_count("core:wood") == 7,"Real HUD exchange preserves both quantities")
	click(point(backpack,Vector2i(2,0),Vector2(2,2)))
	await settle()
	check(stock.is_holding_item() and stock._placements[stock._dragged_placement_index].item_id == "core:wood" and Session.simulation.get_item_count("core:stone") == 1,"Displaced cursor item can exchange back through same HUD path")
