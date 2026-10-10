extends Node

const MainScene := preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Construction := preload("res://src/construction/construction_command.gd")
const TEST_SAVE_PATH := "user://farming_integration_test.json"
var _hud: FirstNightHud
var _world: FirstNightWorld
var _player: PlayerController


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(false)
	Session._save_store = SaveStore.new(TEST_SAVE_PATH)
	_cleanup()
	Session.set_paused(true, false)
	Session._start_new_simulation()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_hud = main.get_node("Hud/HudRoot") as FirstNightHud
	_world = main.get_node("World") as FirstNightWorld
	_player = main.get_node("Player") as PlayerController
	_player.set_physics_process(false)
	# Position fixtures isolate real World/Session/UI commands. The core suite
	# separately proves walking, earned table materials, and actual crop time.
	if not _take_tool("core:hoe", 0) or not _take_tool("core:bucket", 1):
		return
	var bush: Dictionary = Session.simulation.get_surface_berry_bushes()[0]
	_move(bush.position)
	_world.select_at_world_position(bush.position)
	_world.interact_with_selection()
	if not _check(Session.simulation.get_item_count("core:food") > 0, "world bush supplies real berries"):
		return
	_hud.toggle_inventory()
	if not _select_inventory("core:food"):
		return
	if not _check(_hud._inventory_panel._extract_button.visible and not _hud._inventory_panel._extract_button.disabled, "berries expose unlocked inventory seed action"):
		return
	if not await _check_layouts(_hud._inventory_panel, "inventory"):
		return
	_hud._inventory_panel._extract_button.pressed.emit()
	var crop: Dictionary = {}
	for definition: Dictionary in Session.simulation.farming.catalog.crops:
		if Session.simulation.get_item_count(String(definition.seed_id)) > 0:
			crop = definition
			break
	if not _check(not crop.is_empty() and int(Session.simulation.state.farming.roll_index) == 1, "inventory action commits one starter batch"):
		return
	_hud.toggle_inventory()
	var bed := Vector2i(-1, -1)
	for y: int in range(27, 40):
		for x: int in range(18, 40):
			if Session.simulation.farming._soil_allowed(Session.simulation, Vector2i(x, y)):
				bed = Vector2i(x, y)
				break
		if bed.x >= 0:
			break
	if not _check(bed.x >= 0, "ordinary map has soil near home"):
		return
	_move(Content.cell_center(bed.x, bed.y))
	_hud.handle_hotbar_key(0)
	_world.select_at_world_position(_player.global_position)
	_world.interact_with_selection()
	if not _check(not Session.get_farm_bed(bed).is_empty(), "world hoe interaction creates bed"):
		return
	_world.select_at_world_position(_player.global_position)
	_world.interact_with_selection()
	var panel := _hud._farming_panel
	if not _check(panel.visible and Session.is_paused(), "bed opens paused farming panel"):
		return
	if not await _check_layouts(panel, "empty"):
		return
	(panel._column.get_node("Plant_" + String(crop.id)) as Button).pressed.emit()
	if not _check(String(Session.get_farm_bed(bed).crop_id) == String(crop.id), "plant button consumes the actual starter seed"):
		return
	panel.close_requested.emit()
	_hud.handle_hotbar_key(1)
	_move(Content.cell_center(6, 27))
	_world.select_at_world_position(Content.cell_center(6, 27))
	_world.interact_with_selection()
	if not _check(int(Session.get_active_item_instance().state.charges) == 2, "world river fills physical bucket"):
		return
	_move(Content.cell_center(bed.x, bed.y))
	_world.select_at_world_position(_player.global_position)
	_world.interact_with_selection()
	(panel._column.get_node("WaterButton") as Button).pressed.emit()
	if not _check(int(Session.get_active_item_instance().state.charges) == 1 and int(Session.get_farm_bed(bed).wet_until) > Session.simulation.get_elapsed_game_minutes(), "water button consumes one physical charge"):
		return
	# A mature-time fixture isolates harvesting presentation; no UI-only state
	# is used as authority, and ordinary actual growth is covered in run_tests.
	Session.simulation.state.farming.beds[0].growth = int(crop.growth_minutes)
	Session.state_changed.emit()
	if not await _check_layouts(panel, "ripe"):
		return
	if not await _screenshot("--screenshot-path="):
		return
	(panel._column.get_node("HarvestButton") as Button).pressed.emit()
	if not _check(Session.simulation.get_world_drops().size() == int(crop["yield"]), "harvest button creates physical crop products"):
		return
	panel.close_requested.emit()
	for drop: Dictionary in Session.simulation.get_world_drops():
		_move(Vector2(float(drop.position[0]), float(drop.position[1])))
		if not _check(bool(Session.try_pickup_world_drop(String(drop.drop_id)).success), "physical harvest can be picked up"):
			return
	_hud.toggle_inventory()
	if not _select_inventory(String(crop.product_id)):
		return
	if not _check(_hud._inventory_panel._extract_button.disabled, "crop extraction is disabled before study table"):
		return
	_hud.toggle_inventory()
	# Material fixture only: a table must still pass actual placement, delivery,
	# and each work command. Core test earns these boards through wood/sawing.
	if not _check(bool(Session.simulation.try_pickup_item("core:plank", 10).success), "table material fixture fits"):
		return
	var table := Vector2i(21, 20)
	_move(Content.cell_center(21, 21))
	if not _check(bool(Session.execute_construction_command(Construction.place_blueprint(table, "core:study_table")).success), "table blueprint is constructible"):
		return
	if not _check(bool(Session.execute_construction_command(Construction.deliver_blueprint_materials(table)).success), "table receives authored material cost"):
		return
	for _minute: int in range(Session.simulation.building_catalog.get_work_minutes("core:study_table")):
		if not _check(bool(Session.execute_construction_command(Construction.work_blueprint(table)).success), "table work succeeds"):
			return
	_hud.toggle_inventory()
	if not _select_inventory(String(crop.product_id)):
		return
	if not _check(not _hud._inventory_panel._extract_button.disabled, "completed table unlocks inventory action"):
		return
	var seeds_before: int = Session.simulation.get_item_count(String(crop.seed_id))
	_hud._inventory_panel._extract_button.pressed.emit()
	var seed_return: int = Session.simulation.get_item_count(String(crop.seed_id)) - seeds_before
	if not _check(seed_return >= 1 and seed_return <= 5, "crop inventory action returns own 1-5 seeds"):
		return
	# One food fixture tests the selected product's Eat button at zero energy.
	Session.simulation.try_pickup_item(String(crop.product_id), 1)
	Session.simulation.state.player_energy = 0.0
	Session.state_changed.emit()
	_hud._refresh_inventory_panel()
	if not _select_inventory(String(crop.product_id)):
		return
	if not await _check_layouts(_hud._inventory_panel, "inventory") or not await _screenshot("--inventory-screenshot-path="):
		return
	_hud._inventory_panel._eat_button.pressed.emit()
	if not _check(is_equal_approx(Session.get_player_energy(), float(crop.energy)), "selected raw product restores its configured energy"):
		return
	_hud.toggle_inventory()
	_move(Content.cell_center(bed.x, bed.y))
	Session.set_paused(false, false)
	_hud.open_farming(bed)
	_hud.toggle_inventory()
	if not _check(not panel.visible and _hud.is_inventory_open() and Session.is_paused(), "farm to inventory preserves modal pause"):
		return
	_hud.toggle_inventory()
	if not _check(not Session.is_paused(), "closing switched modal restores running state"):
		return
	Session.set_paused(true, false)
	var saved := Session.get_state()
	if not _check(Session.save_game(false) and Session.load_game(), "ordinary Session round trip succeeds"):
		return
	if not _check(Session.get_state().farming == saved.farming and Session.get_state().inventory == saved.inventory, "load preserves farm, timer, draw serial and inventory"):
		return
	_cleanup()
	print("PASS: real MainScene farming UI, inventory extraction/table gate, world hoe/bucket, crop drops, raw food, modal pause, 640/wide layout, and isolated save/load")
	get_tree().quit(0)


func _take_tool(item_id: String, slot: int) -> bool:
	for stored: Dictionary in Session.simulation.get_storage_items():
		if String(stored.item_id) == item_id:
			var cell := Vector2i(int(stored.cell[0]), int(stored.cell[1]))
			_move(Content.cell_center(cell.x, cell.y))
			return _check(bool(Session.transfer_storage_stack_to_inventory(cell, String(stored.placement_id)).success) and bool(Session.assign_hotbar_slot(slot, String(stored.instance_id)).success), "original pantry tool transfer/assignment")
	return _check(false, "missing original pantry tool " + item_id)


func _select_inventory(item_id: String) -> bool:
	var grid := _hud._inventory_panel._inventory_grid
	for index: int in range(grid._placements.size()):
		if String(grid._placements[index].item_id) == item_id:
			grid._select_placement(index)
			_hud._inventory_panel._open_context_menu(grid.get_selected_placement(), grid.get_global_rect().get_center())
			return true
	return _check(false, "inventory selection missing " + item_id)


func _move(position: Vector2) -> void:
	_player.global_position = position
	Session.set_player_position(position)


func _check_layouts(panel: Control, label: String) -> bool:
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1270, 640)]:
		get_window().size = size
		await get_tree().process_frame
		await get_tree().process_frame
		if not _check(Rect2(_hud.global_position, _hud.size).encloses(panel.get_global_rect()), label + " panel must fit actual viewport %s rect=%s hud=%s" % [size, panel.get_global_rect(), _hud.size]):
			return false
		if panel is FarmingPanel:
			for child: Control in panel._column.get_children():
				if not _check(panel.get_global_rect().encloses(child.get_global_rect()) and (not child is Button or child.get_minimum_size().x <= child.size.x), "farming controls fit panel"):
					return false
		else:
			if not _check(Rect2(_hud.global_position, _hud.size).encloses(_hud._inventory_panel._context_menu.get_global_rect()), "inventory context actions fit viewport"):
				return false
		if size == Vector2i(640, 360) and label == "ripe":
			if not await _screenshot("--base-screenshot-path="):
				return false
	return true


func _screenshot(prefix: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix) and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			return _check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix(prefix)) == OK, "save optional rendered screenshot")
	return true


func _check(value: bool, message: String) -> bool:
	if not value:
		push_error("FAIL: farming UI: " + message)
		get_tree().quit(1)
	return value


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
