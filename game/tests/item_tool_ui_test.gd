extends Node
const Main := preload("res://src/main/main.tscn")
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
var main
var hud: FirstNightHud
var player: PlayerController
func _ready() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)
func move(cell: Vector2i) -> void:
	player.position = Session.simulation.content.cell_center(cell.x, cell.y)
	Session.set_player_position(player.position)
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	Session.set_paused(true, false)
	var state := preload("res://tests/fixtures/stocked_tool_state.gd").prepare(World.create_new_game_state())
	state.storage_items = []
	state.item_instances = []
	for index: int in range(3):
		var id: String = ["test:axe_variant", "test:bucket_variant", "test:hoe_variant"][index]
		state.item_instances.append({"item_id": id, "instance_id": "core:item_instance_%06d" % (index + 1), "state": {"charges": 0} if index == 1 else {}, "location": {"kind": "inventory", "id": ""}})
	state.hotbar_slots = ["core:item_instance_000001", "core:item_instance_000002", "core:item_instance_000003", "", ""]
	Session.simulation = Fixture.world(state)
	Session.simulation.event_emitted.connect(Session._on_simulation_event)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.set_process(false)
	player = main.get_node("Player")
	player.set_physics_process(false)
	hud = main.get_node("Hud/HudRoot")
	click((hud.get_node("Hotbar/Slot1") as Control).get_global_rect().get_center())
	await get_tree().process_frame
	check(Session.get_active_item_instance().item_id == "test:axe_variant", "Actual hotbar click equips variant")
	check(player._visual.get("_held_grip") == "shaft", "Player receives catalog grip")
	check((player._visual.get("_held_texture") as Texture2D).resource_path == Session.simulation.content.item_icon_path("test:axe_variant"), "Player reads active catalog icon")
	var tree := "core:wood_north"
	player.position = Session.simulation.content.get_interactable(tree).position
	Session.set_player_position(player.position)
	main._start_player_resource_work(tree)
	check(main._active_resource_id == tree, "Main hold precheck accepts compatible variant")
	main._clear_player_resource_work()
	if failures > 0:
		finish()
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	var panel: InventoryPanel = hud._inventory_panel
	var grid: InventoryGrid = panel._inventory_grid
	var before := Session.get_inventory_layout()
	for placement: Dictionary in grid._placements:
		if placement.item_id == "test:hoe_variant":
			click(grid.get_global_transform_with_canvas() * (Vector2(placement.origin) * grid.CELL_SIZE + Vector2(15,15)))
			break
	await get_tree().process_frame
	check(Session.get_active_item_instance().item_id == "test:hoe_variant" and grid.is_holding_item() and Session.get_inventory_layout() == before, "Backpack click equips and carries without repacking")
	check(grid._dragged_footprint() == Session.simulation.content.item_footprint("test:hoe_variant"), "Held footprint reads injected catalog")
	grid._drag_rotation = 1
	check(grid._dragged_footprint() == Session.simulation.content.item_footprint("test:hoe_variant", 1), "Variant rotation matches catalog cells")
	grid.return_held_item()
	hud.toggle_inventory()
	var soil := Vector2i(18,29)
	move(soil)
	var world: FirstNightWorld = main.get_node("World")
	world.select_at_world_position(player.position)
	world.interact_with_selection()
	check(not Session.get_farm_bed(soil).is_empty(), "World interaction recognizes variant hoe")
	hud.handle_hotbar_key(1)
	move(Vector2i(6,27))
	world.select_at_world_position(player.position)
	world.interact_with_selection()
	await get_tree().process_frame
	check(Session.get_active_item_instance().state.charges == 4 and hud._hotbar_charges[1].text == "4/4", "World fill and hotbar show 4/4")
	move(soil)
	world.select_at_world_position(player.position)
	world.interact_with_selection()
	var farm: FarmingPanel = hud._farming_panel
	var water: Button = farm._column.get_node("WaterButton")
	check(not water.disabled, "Variant enables actual water button")
	water.pressed.emit()
	await get_tree().process_frame
	check(Session.get_active_item_instance().state.charges == 3 and hud._hotbar_charges[1].text == "3/4", "Water click updates instance and hotbar")
	farm.close_requested.emit()
	hud.toggle_inventory()
	await get_tree().process_frame
	for placement: Dictionary in grid._placements:
		if placement.item_id == "test:bucket_variant":
			panel._on_inventory_selection_changed(placement)
	check("3/4" in panel._details_label.text, "Backpack shows catalog capacity")
	# Reload updates consumers to a new catalog with the same instance and a boundary capacity.
	var raw := Fixture.data()
	for item: Dictionary in raw.items:
		if item.id == "test:bucket_variant":
			item.tool.water_capacity = 16
			for charge: int in range(5,17): item.icon_state_paths[str(charge)] = item.icon_state_paths["4"]
	var path := "user://tool_ui_boundary_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var content := FirstNightContent.new(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var current := Session.get_state()
	for record: Dictionary in current.item_instances:
		if record.item_id == "test:bucket_variant": record.state.charges = 16
	Session.simulation = World.new(current, content)
	Session.simulation.event_emitted.connect(Session._on_simulation_event)
	Session._publish_reloaded_state(true)
	hud.toggle_inventory()
	for size: Vector2i in [Vector2i(640,480), Vector2i(1280,720)]:
		get_window().size = size
		get_window().content_scale_size = size
		await get_tree().process_frame
		await get_tree().process_frame
		check(hud._hotbar_charges[1].text == "16/16" and hud._hotbar_charges[1].size.x >= hud._hotbar_charges[1].get_minimum_size().x, "16/16 fits window " + str(size))
	hud.handle_hotbar_key(3)
	await get_tree().process_frame
	check(player._visual.get("_held_texture") == null, "Empty slot clears visual after reload")
	finish()
func finish() -> void:
	print("ITEM_TOOL_UI: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
