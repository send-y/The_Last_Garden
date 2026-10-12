extends Node

const Main := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const IconPresentation := preload("res://src/items/inventory_icon_presentation.gd")
const OUT := "res://../artifacts/inventory-scale-2026-10-12"
var failures := 0

class IconProbe extends Node2D:
	var texture: Texture2D
	var turns := 0
	func _draw() -> void:
		IconPresentation.draw_icon(self, texture, Rect2(16, 16, 128, 192), turns)

func _ready() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)

func settle() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame

func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	motion(point)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_viewport().get_texture().get_image().save_png(OUT + "/" + name)

func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	get_window().size = Vector2i(640, 360)
	get_window().content_scale_size = Vector2i(640, 360)
	var state := Simulation.create_new_state()
	state.inventory = {"core:food": 3, "core:wood": 5}
	state.item_instances = [{"instance_id": "core:item_instance_000001", "item_id": "core:axe", "state": {}, "location": {"kind": "inventory", "id": ""}}]
	state.next_item_instance_serial = 2
	state.hotbar_slots = ["core:item_instance_000001", "", "", "", ""]
	Session.apply_debug_state(state, "inventory scale pilot", false)
	var main := Main.instantiate()
	add_child(main)
	await settle()
	var player := main.get_node("Player") as PlayerController
	player.set_physics_process(false)
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	hud.toggle_inventory()
	await settle()
	var panel := hud._inventory_panel
	var grid := panel._inventory_grid
	var hotbar := hud.get_node("Hotbar") as Control
	var original := Session.get_inventory_layout()
	for resolution: Vector2i in [Vector2i(640,360), Vector2i(1280,720), Vector2i(1270,640)]:
		get_window().size = resolution
		await settle()
		var cell_on_screen := grid.get_global_transform_with_canvas().basis_xform(Vector2(grid.CELL_SIZE, 0)).length()
		check(cell_on_screen >= 63.9, "Inventory retains a 64-pixel cell at %s (got %.2f)" % [resolution, cell_on_screen])
		check(Rect2(Vector2.ZERO, hud.size).encloses(panel.get_global_rect()), "Backpack stays inside viewport at %s" % resolution)
		check(not panel.get_global_rect().intersects(hotbar.get_global_rect()), "Hotbar remains accessible at %s" % resolution)
		check(grid.grid_columns == 4 and grid.grid_rows == 4 and Session.get_inventory_layout() == original, "Resizing preserves all 16 cells and saved placements")
	get_window().size = Vector2i(640,360)
	await settle()
	await capture("backpack-640.png")
	var axe: Dictionary = {}
	for placement: Dictionary in grid._placements:
		if placement.item_id == "core:axe": axe = placement
	var pointer := grid.get_global_transform_with_canvas() * (Vector2(axe.origin) * grid.CELL_SIZE + Vector2(20,20))
	click(pointer)
	await settle()
	check(grid.is_holding_item() and Session.get_inventory_layout() == original, "One click carries the physical axe without moving saved cells")
	check(player._visual.get("_held_texture") != null and player._visual.get("_held_item_id") == "core:axe", "Backpack selects the same axe in the character's hand")
	var cursor := grid._cursor_visual
	var start := cursor.position
	motion(pointer + Vector2(17, 9))
	await settle()
	check(cursor.position.is_equal_approx(start + Vector2(17,9)), "Large icon follows every pixel of cursor motion")
	var rotate := InputEventKey.new()
	rotate.physical_keycode = KEY_R
	rotate.keycode = KEY_R
	rotate.pressed = true
	get_viewport().push_input(rotate, true)
	await settle()
	check(grid._drag_rotation == 1 and grid._dragged_footprint() == Session.simulation.content.item_footprint("core:axe",1), "R rotates the original physical footprint")
	motion(Vector2(80,150))
	await settle()
	await capture("cursor-rotated.png")
	click(Vector2(80,150), MOUSE_BUTTON_RIGHT)
	await settle()
	check(not grid.is_holding_item() and Session.get_inventory_layout() == original, "Cancellation preserves original placement")
	# A complete click-to-place operation uses a vacant lower row for a stack.
	var wood: Dictionary = {}
	for placement: Dictionary in grid._placements:
		if placement.item_id == "core:wood": wood = placement
	click(grid.get_global_transform_with_canvas() * (Vector2(wood.origin) * grid.CELL_SIZE + Vector2(20,20)))
	var target := grid.get_global_transform_with_canvas() * ((Vector2(Vector2i(3,3) + grid._drag_grab_cell) + Vector2.ONE * 0.5) * grid.CELL_SIZE)
	click(target)
	await settle()
	var moved := false
	for placement: Dictionary in Session.get_inventory_layout():
		if placement.item_id == "core:wood": moved = placement.origin == [3,3]
	check(moved and not grid.is_holding_item(), "Second click places the stack in the selected cell")
	hud.toggle_inventory()
	await settle()
	check(is_equal_approx(hotbar.offset_bottom, -10), "Closing restores the normal hotbar position")
	# Storage reuses the larger cells and must fit without shrinking them.
	var storage := hud._storage_panel
	storage.present(Vector2i(10,10), Session.simulation.content)
	storage.show()
	await settle()
	check(Rect2(Vector2.ZERO, hud.size).encloses(storage.get_global_rect()), "Storage window fits the small viewport")
	check(storage._inventory_grid.get_global_transform_with_canvas().basis_xform(Vector2(grid.CELL_SIZE,0)).length() >= 63.9, "Storage retains the larger backpack cells")
	await capture("storage-640.png")
	await check_clipped_storage(storage)
	storage.hide()
	if DisplayServer.get_name() != "headless": await check_aspect()
	print("INVENTORY_SCALE: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func check_clipped_storage(storage: StoragePanel) -> void:
	var backpack := storage._inventory_grid
	var before := Session.get_inventory_layout()
	var food: Dictionary = {}
	for placement: Dictionary in backpack._placements:
		if placement.item_id == "core:food": food = placement
	click(backpack.get_global_transform_with_canvas() * (Vector2(food.origin) * backpack.CELL_SIZE + Vector2(32,32)))
	await settle()
	var hidden := Vector2(backpack.get_global_rect().position.x + 32, storage._items_scroll.get_global_rect().end.y + 2)
	check(backpack.get_global_rect().has_point(hidden) and not storage._items_scroll.get_global_rect().has_point(hidden), "Fixture exposes a clipped part of the larger backpack")
	click(hidden)
	await settle()
	check(backpack.is_holding_item() and Session.get_inventory_layout() == before, "Clicking a clipped row inside the panel does not place an invisible item")
	if not backpack.is_holding_item(): return
	var outside := Vector2(hidden.x, storage.get_global_rect().end.y + 3)
	check(outside.y < get_viewport().get_visible_rect().end.y and backpack.get_global_rect().has_point(outside), "Fixture exposes clipped grid pixels outside the panel but inside the screen")
	click(outside)
	await settle()
	check(not backpack.is_holding_item() and Session.simulation.get_item_count("core:food") == 0, "Outside click drops the item instead of placing it in an invisible row")
	# A transfer from the other grid must use the same clipped destination area.
	var stock := storage._storage_grid
	stock.present([{"item_id": "core:stone", "placement_id": "clip-probe", "amount": 1, "origin": Vector2i.ZERO, "footprint": [Vector2i.ZERO]}], Session.simulation.content)
	var transfers: Array[Dictionary] = []
	storage.transfer_requested.connect(func(placement: Dictionary, _from_stock: bool, _cell: Vector2i, _quick: bool) -> void: transfers.append(placement))
	click(stock.get_global_rect().position + Vector2(32,32))
	await settle()
	check(stock.is_holding_item(), "Fixture carries a visible stock item")
	click(hidden)
	await settle()
	check(transfers.is_empty() and stock.is_holding_item(), "Transfer cannot target the clipped backpack area")
	stock.return_held_item()

func check_aspect() -> void:
	var source := Image.create(32,64,false,Image.FORMAT_RGBA8)
	source.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(source)
	for turns: int in range(4):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(160,224)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var probe := IconProbe.new()
		probe.texture = texture
		probe.turns = turns
		viewport.add_child(probe)
		await settle()
		await RenderingServer.frame_post_draw
		var rect := viewport.get_texture().get_image().get_used_rect()
		var ratio := float(rect.size.x) / maxf(1,rect.size.y)
		check(absf(ratio - (0.5 if turns % 2 == 0 else 2.0)) < 0.02, "Actual icon pixels preserve source proportions at rotation %d: %s" % [turns,rect])
		viewport.queue_free()
