extends Node

const MainScene := preload("res://src/main/main.tscn")
const Simulation := preload("res://src/simulation/first_night_simulation.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	var state := Simulation.create_new_state()
	state["item_instances"] = [
		{"instance_id": "core:item_instance_000001", "item_id": "core:hoe", "state": {}, "location": {"kind": "inventory", "id": ""}},
		{"instance_id": "core:item_instance_000002", "item_id": "core:axe", "state": {}, "location": {"kind": "inventory", "id": ""}},
		{"instance_id": "core:item_instance_000003", "item_id": "core:bucket", "state": {"charges": 0}, "location": {"kind": "inventory", "id": ""}},
	]
	state["inventory"]["core:wood"] = 1
	state["hotbar_slots"] = ["core:item_instance_000002", "", "", "", ""]
	state["next_item_instance_serial"] = 4
	Session.apply_debug_state(state, "held item integration", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	var player := main.get_node("Player") as PlayerController
	hud.toggle_inventory()
	await get_tree().process_frame
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	var grid := panel._inventory_grid
	var before := Session.get_inventory_layout()
	_click(_item_position(grid, "core:hoe"))
	await get_tree().process_frame
	if String(Session.get_active_item_instance().get("instance_id", "")) != "core:item_instance_000001":
		_fail("Backpack LMB did not equip the selected physical hoe: point=%s rect=%s selected=%s state=%s" % [_item_position(grid, "core:hoe"), grid.get_global_rect(), grid.get_selected_placement(), Session.get_state().get("selected_inventory_item")])
		return
	if not grid.is_holding_item() or Session.get_inventory_layout() != before:
		_fail("Selection did not attach the item to the cursor or changed the backpack layout")
		return
	if player._visual.get("_held_item_id") != "core:hoe" or player._visual.get("_held_texture") == null:
		_fail("The equipped hoe is not represented in the player's hand")
		return
	var saved := JSON.parse_string(JSON.stringify(Session.get_state())) as Dictionary
	var restored := Simulation.new(saved)
	if String(restored.get_active_item_instance().get("instance_id", "")) != "core:item_instance_000001":
		_fail("The backpack equipment selection did not survive JSON save/load")
		return
	var invalid := restored.select_inventory_item("core:hoe", "core:item_instance_000002")
	if bool(invalid.get("success", false)) or String(restored.get_active_item_instance().get("item_id", "")) != "core:hoe":
		_fail("A mismatched physical item was accepted or changed the previous equipment")
		return
	restored.drop_inventory_stack("core:hoe", 0)
	if not restored.get_held_item().is_empty() or not (restored.state.get("selected_inventory_item", {}) as Dictionary).is_empty():
		_fail("Dropping a selected physical tool did not clear its equipment selection")
		return
	var legacy := saved.duplicate(true)
	legacy["version"] = 25
	legacy.erase("selected_inventory_item")
	legacy["active_hotbar_slot"] = 0
	var migrated := Simulation.new(legacy)
	if String(migrated.get_active_item_instance().get("item_id", "")) != "core:axe" or migrated.get_inventory_layout() != before:
		_fail("v25 migration changed the existing hotbar selection or inventory layout")
		return
	grid.return_held_item()
	_click(_item_position(grid, "core:wood"))
	await get_tree().process_frame
	if not Session.get_active_item_instance().is_empty() or player._visual.get("_held_item_id") != "core:wood":
		_fail("Holding a stack did not replace the equipped tool")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	_click((hud.get_node("Hotbar/Slot1") as Control).get_global_rect().get_center())
	await get_tree().process_frame
	if String(Session.get_active_item_instance().get("instance_id", "")) != "core:item_instance_000002" or player._visual.get("_held_item_id") != "core:axe":
		_fail("Hotbar LMB did not put its physical axe in the player's hand")
		return
	_click((hud.get_node("Hotbar/Slot2") as Control).get_global_rect().get_center())
	await get_tree().process_frame
	if not Session.get_active_item_instance().is_empty() or player._visual.get("_held_texture") != null:
		_fail("Selecting an empty hotbar slot did not empty the hand")
		return
	hud.toggle_inventory()
	await get_tree().process_frame
	_click(_item_position(grid, "core:bucket"))
	await get_tree().process_frame
	hud.toggle_inventory()
	var shore := preload("res://src/content/first_night_content.gd").cell_center(7, 27)
	player.position = shore
	Session.set_player_position(shore)
	var fill := Session.fill_active_bucket(Vector2i(6, 27))
	await get_tree().process_frame
	if not bool(fill.get("success", false)) or (player._visual.get("_held_texture") as Texture2D).resource_path != "res://assets/sprites/items/bucket_full.png":
		_fail("Bucket filling did not update the actual held item's state and sprite: result=%s item=%s texture=%s" % [fill, Session.get_held_item(), player._visual.get("_held_texture")])
		return
	print("PASS: backpack and hotbar LMB equip actual items; stack and empty selection clear tool authority; selection does not move items")
	get_tree().quit(0)

func _item_position(grid: InventoryGrid, item_id: String) -> Vector2:
	for placement: Dictionary in grid._placements:
		if placement["item_id"] == item_id:
			return grid.get_global_transform_with_canvas() * (Vector2(placement["origin"]) * grid.CELL_SIZE + Vector2(15, 15))
	return Vector2.ZERO

func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
