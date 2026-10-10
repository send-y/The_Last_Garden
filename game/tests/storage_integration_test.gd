extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Localized := preload("res://src/localization/localized_text.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(true)
	var state: Dictionary = Simulation.create_new_state(2441)
	(state["inventory"] as Dictionary)["core:wood"] = 5
	(state["inventory"] as Dictionary)["core:food"] = 5
	(state["structures"] as Array).append({
		"building_id": "core:wood_floor",
		"cell": [10, 10],
		"stage_id": "core:complete",
	})
	Session.apply_debug_state(state, "storage integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var world := main.get_node("World") as FirstNightWorld
	var player := main.get_node("Player") as PlayerController
	for missing_icon_item: String in ["core:plank", "core:firewood"]:
		var item_view := world._create_dropped_item_view({})
		world._update_dropped_item_view(item_view, {
			"drop_id": "test_%s" % missing_icon_item,
			"item_id": missing_icon_item,
			"amount": 1,
			"position": [32.0, 32.0],
		})
		if item_view.icon == null:
			_fail("world loot %s needs a fallback icon" % missing_icon_item)
			return
	var target_cell := Vector2i(10, 10)
	var target_position := Content.cell_center(target_cell.x, target_cell.y)
	player.global_position = target_position
	Session.simulation.set_player_position(target_position)
	var created := Session.create_storage_zone(target_cell, target_cell)
	if not bool(created.get("success", false)):
		_fail("could not create the storage test zone")
		return
	world.select_at_world_position(target_position)
	world.interact_with_selection()
	await get_tree().process_frame
	if not hud.is_modal_open() or not Session.is_paused():
		_fail("interacting with a nearby storage cell must open a pausing modal")
		return
	var panel := hud.get_node("StoragePanel") as StoragePanel
	var inventory_grid := panel.get_node("Margin/Column/ItemsScroll/Grids/InventoryColumn/InventoryGrid") as InventoryGrid
	var storage_grid := panel.get_node("Margin/Column/ItemsScroll/Grids/StorageColumn/StorageGrid") as InventoryGrid
	if storage_grid.grid_columns != 3 or storage_grid.grid_rows != 3:
		_fail("a wooden floor storage cell must expand to a 3x3 grid")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	if panel.visible or not hud.is_inventory_open() or not Session.is_paused():
		_fail("opening the backpack from storage must switch modals without losing pause state")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	if hud.is_modal_open() or Session.is_paused():
		_fail("closing the switched backpack and storage must restore the original running state")
		return
	Session.set_paused(true, false)
	world.interact_with_selection()
	await get_tree().process_frame
	hud.toggle_inventory()
	await get_tree().process_frame
	if not hud.is_inventory_open() or not Session.is_paused():
		_fail("switching modal windows must preserve a pause that existed before opening storage")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	if hud.is_modal_open() or not Session.is_paused():
		_fail("closing switched modal windows must not resume a game that was already paused")
		return
	Session.set_paused(false, false)
	world.interact_with_selection()
	await get_tree().process_frame
	panel = hud.get_node("StoragePanel") as StoragePanel
	inventory_grid = panel.get_node("Margin/Column/ItemsScroll/Grids/InventoryColumn/InventoryGrid") as InventoryGrid
	var inventory_layout := Session.get_inventory_layout()
	if inventory_layout.is_empty():
		_fail("storage panel is missing the backpack placement")
		return
	var berry_icon_visible := false
	for placement: Dictionary in inventory_grid._placements:
		if String(placement.get("item_id", "")) == "core:food":
			berry_icon_visible = String(placement.get("icon_path", "")) == Content.new().item_icon_path("core:food")
	if not berry_icon_visible:
		_fail("backpack item sprites must be supplied to the inventory grid")
		return
	var moved_inventory_layout: Array[Dictionary] = inventory_layout.duplicate(true)
	for entry: Dictionary in moved_inventory_layout:
		if String(entry.get("item_id", "")) == "core:food":
			entry["origin"] = [3, 3]
	inventory_grid.layout_changed.emit(moved_inventory_layout)
	await get_tree().process_frame
	var persisted_inventory_layout := Session.get_inventory_layout()
	var berry_layout_persisted := false
	for entry: Dictionary in persisted_inventory_layout:
		if String(entry.get("item_id", "")) == "core:food" and entry.get("origin", []) == [3, 3]:
			berry_layout_persisted = true
	if not berry_layout_persisted:
		_fail("backpack reordering inside the storage panel must update the saved inventory layout")
		return
	var selected: Dictionary = {}
	for entry: Dictionary in persisted_inventory_layout:
		if String(entry.get("item_id", "")) == "core:wood":
			selected = entry.duplicate(true)
			break
	if selected.is_empty():
		_fail("storage test is missing the wood stack")
		return
	panel._on_inventory_drop_to_storage(selected, Vector2i(2, 1))
	await get_tree().process_frame
	if Session.get_inventory().get("core:wood", 0) != 0 or Session.get_storage_contents(target_cell).get("core:wood", 0) != 5:
		_fail("dragging to the ground grid must transfer the stack")
		return
	if Session.get_storage_layout(target_cell)[0].origin != Vector2i(2, 1):
		_fail("manually dragged item must land in the selected slot")
		return
	var held_index: int = int(inventory_grid._cell_to_placement.get(Vector2i(3, 3), -1))
	if held_index < 0:
		_fail("storage UI regression test could not select its backpack item")
		return
	inventory_grid._dragged_placement_index = held_index
	panel.hide()
	var hidden_click := InputEventMouseButton.new()
	hidden_click.button_index = MOUSE_BUTTON_LEFT
	hidden_click.pressed = true
	hidden_click.global_position = Vector2(-100.0, -100.0)
	inventory_grid._input(hidden_click)
	if inventory_grid.is_holding_item():
		_fail("hiding storage must cancel the cursor overlay and ignore world clicks")
		return
	panel.show()
	var close_button := panel.get_node("Margin/Column/Header/Close") as Button
	close_button.pressed.emit()
	await get_tree().process_frame
	if hud.is_modal_open() or Session.is_paused():
		_fail("closing storage must restore the previous unpaused state")
		return
	if inventory_grid.is_holding_item():
		_fail("closing storage must return a held backpack item to its slot")
		return
	world.interact_with_selection()
	await get_tree().process_frame
	var stored := Session.get_storage_layout(target_cell)
	if stored.is_empty():
		_fail("stored item is missing from the floored cell grid")
		return
	panel._on_storage_drop_to_inventory(stored[0], Vector2i(2, 3))
	await get_tree().process_frame
	if Session.get_inventory().get("core:wood", 0) != 5 or not Session.get_storage_contents(target_cell).is_empty():
		_fail("dragging from the ground grid must move contents into the backpack")
		return
	var returned_layout := Session.get_inventory_layout()
	var returned_at_target := false
	for entry: Dictionary in returned_layout:
		if String(entry.get("item_id", "")) == "core:wood" and entry.get("origin", []) == [2, 3]:
			returned_at_target = true
	if not returned_at_target:
		_fail("manually dragged item must land in the selected backpack slot")
		return
	print("PASS: storage selection, pause, and item transfers integrate with the HUD")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)
