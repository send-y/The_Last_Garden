extends Node

const Simulation := preload("res://src/simulation/first_night_simulation.gd")
const WaterMap := preload("res://src/world/water_map.gd")
const ResourceNodeCatalog := preload("res://src/content/resource_node_catalog.gd")
const MainScene: PackedScene = preload("res://src/main/main.tscn")
const SaveStore := preload("res://src/save/first_night_save_store.gd")
const TEST_SAVE_PATH := "user://starting_pantry_integration_test.json"
const PantryCells: Array[Vector2i] = [
	Vector2i(22, 22), Vector2i(23, 22),
	Vector2i(22, 23), Vector2i(23, 23),
]
const TOOL_IDS: Array[String] = [
	"core:axe", "core:pickaxe", "core:hoe", "core:bucket",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(false)
	Session._save_store = SaveStore.new(TEST_SAVE_PATH)
	Session._start_new_simulation()
	var zone_list := Session.get_storage_zones()
	if zone_list.size() != 1 or (zone_list[0].get("cells", []) as Array).size() != 4:
		var blockers: Array[String] = []
		for cell: Vector2i in PantryCells:
			blockers.append("%s:%s/%s water=%s reserved=%s" % [cell, Session.simulation._storage_cell_has_blocking_structure(cell), Session.simulation._world_cell_blocks_storage(cell), WaterMap.contains_cell(cell), ResourceNodeCatalog.is_reserved_cell(cell)])
		_fail("ordinary new game must create one 2x2 pantry zone; zones=%s blockers=%s" % [zone_list, blockers])
		return
	for cell: Vector2i in PantryCells:
		if Session.get_storage_grid_size(cell) != Vector2i(3, 3):
			_fail("each wooden pantry floor cell must expose a 3x3 storage grid")
			return
	var all_stored := _all_stored_placements()
	if all_stored.size() != 4:
		_fail("the pantry must contain exactly four physical tool instances")
		return
	var seen: Dictionary = {}
	for placement: Dictionary in all_stored:
		var item_id := String(placement.get("item_id", ""))
		seen[item_id] = true
		if String(placement.get("instance_id", "")).is_empty():
			_fail("%s must have a persistent item instance" % item_id)
			return
	if seen.size() != TOOL_IDS.size():
		_fail("the pantry is missing one or more required items")
		return
	for placement: Dictionary in all_stored:
		var footprint: Array = placement.get("footprint", [])
		var origin: Vector2i = placement.get("origin", Vector2i.ZERO)
		var cell := Vector2i(int((placement.get("cell", []) as Array)[0]), int((placement.get("cell", []) as Array)[1]))
		for offset_value: Variant in footprint:
			var offset: Vector2i = offset_value
			if origin.x + offset.x >= 3 or origin.y + offset.y >= 3:
				_fail("a stored item exceeds its real 3x3 floor-cell bounds")
				return
		if not PantryCells.has(cell):
			_fail("a starter tool was stored outside the old-house pantry")
			return
	var bucket_instance_id := _instance_id_for("core:bucket")
	if int(Session.get_item_instance(bucket_instance_id).get("state", {}).get("charges", -1)) != 0:
		_fail("the starter bucket must be empty")
		return
	if not Session.simulation.should_hide_interactable("core:old_tools", "tools"):
		_fail("the hidden legacy tool source should not duplicate the pantry tools")
		return
	Session.simulation.set_player_position(_cell_center(PantryCells[0]))
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hud := main.get_node("Hud/HudRoot") as FirstNightHud
	hud.open_storage(PantryCells[0])
	await get_tree().process_frame
	var storage_panel := hud.get_node("StoragePanel") as StoragePanel
	var storage_grid := storage_panel.get_node("Margin/Column/ItemsScroll/Grids/StorageColumn/StorageGrid") as InventoryGrid
	var storage_title := storage_panel.get_node("Margin/Column/ItemsScroll/Grids/StorageColumn/StorageTitle") as Label
	if not storage_panel.visible or storage_grid.grid_columns != 3 or storage_grid.grid_rows != 3 or not storage_title.text.contains("3×3"):
		_fail("opening a starter pantry cell must show its floored 3x3 inventory")
		return
	for placement: Dictionary in storage_grid._placements:
		var item_id := String(placement.get("item_id", ""))
		var icon_path := String(placement.get("icon_path", ""))
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			_fail("the pantry item %s must resolve to its imported sprite" % item_id)
			return
		if item_id == "core:bucket" and not icon_path.ends_with("bucket_not_full.png"):
			_fail("the empty starter bucket must display its empty sprite")
			return
	(storage_panel.get_node("Margin/Column/Header/Close") as Button).pressed.emit()
	await get_tree().process_frame

	var storage_cell := PantryCells[0]
	Session.simulation.set_player_position(_cell_center(storage_cell))
	for slot_index: int in range(TOOL_IDS.size()):
		var item_id := TOOL_IDS[slot_index]
		var item_cell := _home_cell_for(item_id)
		var placement_id := _placement_id_for(item_id)
		var before_instance_id := _instance_id_for(item_id)
		Session.simulation.set_player_position(_cell_center(item_cell))
		var taken := Session.transfer_storage_stack_to_inventory(item_cell, placement_id)
		if not bool(taken.get("success", false)):
			_fail("could not retrieve %s from the pantry: %s" % [item_id, taken])
			return
		var assigned := Session.assign_hotbar_slot(slot_index, before_instance_id)
		if not bool(assigned.get("success", false)):
			_fail("could not assign %s to the hotbar" % item_id)
			return
		hud.handle_hotbar_key(slot_index)
		if String(Session.get_active_item_instance().get("instance_id", "")) != before_instance_id:
			_fail("could not select %s from the hotbar" % item_id)
			return
		hud.refresh()
		var icon := hud._hotbar_icons[slot_index].texture as Texture2D
		var expected_icon := Session.simulation.content.item_icon_path(item_id)
		if icon == null or icon.resource_path != expected_icon:
			_fail("hotbar selection must display the connected sprite for %s" % item_id)
			return
		if hud._hotbar_buttons[slot_index].modulate != Color("ffe59c"):
			_fail("selecting %s through the hotbar must highlight its slot" % item_id)
			return
		if slot_index == TOOL_IDS.size() - 1:
			continue
		var inventory_entry := _inventory_placement(item_id)
		var returned := Session.transfer_inventory_stack_to_storage(
			item_cell,
			item_id,
			int(inventory_entry.get("stack_index", -1))
		)
		if not bool(returned.get("success", false)):
			_fail("could not return %s to the pantry" % item_id)
			return
		if _instance_id_for(item_id) != before_instance_id:
			_fail("returning %s must preserve its exact instance" % item_id)
			return
	if not bool(Session.get_flags().get("tools_found", false)):
		_fail("taking a physical tool must advance the tools-found milestone")
		return

	var water_cells := WaterMap.surface_cells()
	if water_cells.is_empty():
		_fail("the ordinary world must contain a water cell for the bucket test")
		return
	var water_cell := water_cells[0]
	Session.simulation.set_player_position(_cell_center(water_cell))
	var filled := Session.fill_active_bucket(water_cell)
	if not bool(filled.get("success", false)):
		_fail("the selected bucket should fill at the surface river: %s" % filled)
		return
	if int(Session.get_active_item_instance().get("state", {}).get("charges", 0)) != 2:
		_fail("filling the bucket should persist two charges on this instance")
		return
	var filled_bucket_icon := ""
	for placement: Dictionary in Session.get_inventory_placements():
		if String(placement.get("instance_id", "")) == bucket_instance_id:
			filled_bucket_icon = String(placement.get("icon_path", ""))
	if not filled_bucket_icon.ends_with("bucket_full.png"):
		_fail("a filled bucket must display its full sprite in the inventory data")
		return
	hud.refresh()
	var hotbar_icon := hud._hotbar_icons[3].texture as Texture2D
	if hotbar_icon == null or not hotbar_icon.resource_path.ends_with("bucket_full.png"):
		_fail("the hotbar must display the selected bucket's current state sprite")
		return

	var saved_text := JSON.stringify(Session.get_state())
	var saved_value: Variant = JSON.parse_string(saved_text)
	if typeof(saved_value) != TYPE_DICTIONARY:
		_fail("the new game state did not serialize")
		return
	var loaded := Simulation.new(saved_value as Dictionary)
	if _loaded_storage_item_count(loaded) != 3:
		_fail("save/load must preserve the three tools remaining in storage")
		return
	var loaded_bucket := loaded.get_item_instance(bucket_instance_id)
	if int(loaded_bucket.get("state", {}).get("charges", 0)) != 2:
		_fail("save/load must preserve the filled state of the bucket instance")
		return
	var loaded_instances: Array = loaded.state.get("item_instances", []) as Array
	if loaded_instances.size() != TOOL_IDS.size():
		_fail("save/load must preserve exactly four tool instances without duplicates")
		return
	var loaded_ids: Dictionary = {}
	var loaded_items: Dictionary = {}
	for instance_value: Variant in loaded_instances:
		var instance := instance_value as Dictionary
		var instance_id := String(instance.get("instance_id", ""))
		var item_id := String(instance.get("item_id", ""))
		if loaded_ids.has(instance_id):
			_fail("save/load duplicated physical item instance %s" % instance_id)
			return
		loaded_ids[instance_id] = true
		loaded_items[item_id] = int(loaded_items.get(item_id, 0)) + 1
	for item_id: String in TOOL_IDS:
		if int(loaded_items.get(item_id, 0)) != 1:
			_fail("save/load must preserve exactly one %s" % item_id)
			return
	if loaded.get_hotbar_slots()[3] != bucket_instance_id or String(loaded.get_active_item_instance().get("instance_id", "")) != bucket_instance_id:
		_fail("save/load must preserve bucket hotbar assignment and selection")
		return
	var old_save := Simulation.create_new_state(5391)
	old_save["version"] = 17
	var loaded_old_save := Simulation.new(old_save)
	if not (loaded_old_save.state.get("storage_zones", []) as Array).is_empty() or not (loaded_old_save.state.get("item_instances", []) as Array).is_empty():
		_fail("loading an older save must not seed a pantry or starter items")
		return
	print("PASS: ordinary new-game pantry, item instances, hotbar, river bucket, and legacy saves")
	_cleanup_test_saves()
	get_tree().quit(0)


func _all_stored_placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell: Vector2i in PantryCells:
		for placement: Dictionary in Session.get_storage_layout(cell):
			var with_cell := placement.duplicate(true)
			with_cell["cell"] = [cell.x, cell.y]
			result.append(with_cell)
	return result


func _placement_id_for(item_id: String) -> String:
	for placement: Dictionary in _all_stored_placements():
		if String(placement.get("item_id", "")) == item_id:
			return String(placement.get("placement_id", ""))
	return ""


func _instance_id_for(item_id: String) -> String:
	for placement: Dictionary in _all_stored_placements():
		if String(placement.get("item_id", "")) == item_id:
			return String(placement.get("instance_id", ""))
	for instance: Dictionary in Session.get_state().get("item_instances", []):
		if String(instance.get("item_id", "")) == item_id:
			return String(instance.get("instance_id", ""))
	return ""


func _home_cell_for(item_id: String) -> Vector2i:
	for cell: Vector2i in PantryCells:
		for placement: Dictionary in Session.get_storage_layout(cell):
			if String(placement.get("item_id", "")) == item_id:
				return cell
	return Vector2i(-1, -1)


func _loaded_storage_item_count(simulation: FirstNightSimulation) -> int:
	var count := 0
	for cell: Vector2i in PantryCells:
		count += simulation.get_storage_layout(cell).size()
	return count


func _inventory_placement(item_id: String) -> Dictionary:
	for placement: Dictionary in Session.get_inventory_layout():
		if String(placement.get("item_id", "")) == item_id:
			return placement
	return {}


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * 32) + Vector2(16, 16)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	_cleanup_test_saves()
	get_tree().quit(1)


func _cleanup_test_saves() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
