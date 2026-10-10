extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func _normalize_storage_zones(sim, value: Variant) -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return zones
	var seen_ids: Dictionary = {}
	var claimed_cells: Dictionary = {}
	var map_rect := Rect2i(Vector2i.ZERO, FirstNightContent.MAP_SIZE)
	for zone_value: Variant in value as Array:
		if typeof(zone_value) != TYPE_DICTIONARY or zones.size() >= MAX_STORAGE_ZONES:
			continue
		var zone: Dictionary = zone_value as Dictionary
		var zone_id := String(zone.get("id", ""))
		var raw_cells: Variant = zone.get("cells", [])
		if (
			not zone_id.begins_with("core:storage_zone_")
			or seen_ids.has(zone_id)
			or typeof(raw_cells) != TYPE_ARRAY
			or (raw_cells as Array).is_empty()
			or (raw_cells as Array).size() > MAX_STORAGE_ZONE_CELLS
		):
			continue
		var valid_cells: Array = []
		var room_id := String(zone.get("room_id", ""))
		for cell_value: Variant in raw_cells as Array:
			if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
				continue
			var cell_data := cell_value as Array
			if not _is_whole_number(cell_data[0]) or not _is_whole_number(cell_data[1]):
				continue
			var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
			var key: String = sim._storage_cell_key([cell.x, cell.y])
			var invalid_structure: bool = sim._storage_cell_has_blocking_structure(cell)
			if room_id.begins_with("core:room_"):
				invalid_structure = sim._room_storage_cell_has_forbidden_structure(cell)
			if (
				not map_rect.has_point(cell)
				or claimed_cells.has(key)
				or invalid_structure
				or sim._world_cell_blocks_storage(cell)
			):
				continue
			claimed_cells[key] = true
			valid_cells.append([cell.x, cell.y])
		if valid_cells.is_empty():
			continue
		seen_ids[zone_id] = true
		var normalized_zone := {"id": zone_id, "cells": valid_cells}
		if room_id.begins_with("core:room_"):
			normalized_zone["room_id"] = room_id
			normalized_zone["room_type_id"] = String(zone.get("room_type_id", "core:storage_room"))
		zones.append(normalized_zone)
	return zones


static func _normalize_storage_items(sim, value: Variant, zones: Array) -> Array[Dictionary]:
	var content: FirstNightContent = sim.content
	var items: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return items
	var available_cells: Dictionary = {}
	for zone_value: Variant in zones:
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		for cell_value: Variant in (zone_value as Dictionary).get("cells", []):
			available_cells[sim._storage_cell_key(cell_value)] = true
	var occupied_by_storage_cell: Dictionary = {}
	for item_value: Variant in value as Array:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value as Dictionary
		var raw_cell: Variant = item.get("cell", [])
		var item_id := content.normalize_item_id(String(item.get("item_id", "")))
		var amount := _safe_int(item.get("amount"), 0)
		var cell_key: String = sim._storage_cell_key(raw_cell)
		if (
			not available_cells.has(cell_key)
			or not content.has_item(item_id)
			or amount <= 0
		):
			continue
		var cell := raw_cell as Array
		var origin_value: Variant = item.get("origin", [0, 0])
		var origin := Vector2i.ZERO
		if typeof(origin_value) == TYPE_ARRAY and (origin_value as Array).size() == 2:
			origin = Vector2i(int(origin_value[0]), int(origin_value[1]))
		var rotation := posmod(_safe_int(item.get("rotation", 0), 0), 4)
		var used: Dictionary = occupied_by_storage_cell.get(cell_key, {})
		var grid_size: Vector2i = sim.get_storage_grid_size(Vector2i(int(cell[0]), int(cell[1])))
		var footprint := content.item_footprint(item_id, rotation)
		var placement_id := String(item.get("placement_id", "%s:%d" % [item_id, items.size()]))
		var instance_id := ""
		if content.item_is_instance_based(item_id):
			amount = 1
			instance_id = sim._ensure_item_instance_for_owner(
				item_id, String(item.get("instance_id", "")), "storage", placement_id
			)
		if not InventoryPlacementRulesScript.can_place(
			footprint, origin, used, grid_size.x, grid_size.y
		):
			var fit := InventoryPlacementRulesScript.find_first_fit(
				content.item_footprint(item_id), used, grid_size.x, grid_size.y
			)
			origin = fit.get("origin", InventoryPlacementRulesScript.INVALID_ORIGIN)
			rotation = int(fit.get("rotation", 0))
			if origin == InventoryPlacementRulesScript.INVALID_ORIGIN:
				continue
			footprint = content.item_footprint(item_id, rotation)
		InventoryPlacementRulesScript.occupy(footprint, origin, used, placement_id)
		occupied_by_storage_cell[cell_key] = used
		var normalized_item := {
			"cell": [int(cell[0]), int(cell[1])],
			"item_id": item_id,
			"amount": mini(amount, content.item_max_stack(item_id)),
			"origin": [origin.x, origin.y],
			"rotation": rotation,
			"stack_index": maxi(0, _safe_int(item.get("stack_index", items.size()), items.size())),
			"placement_id": placement_id,
		}
		if not instance_id.is_empty():
			normalized_item["instance_id"] = instance_id
		items.append(normalized_item)
	return items


static func _recover_orphaned_storage_items(sim,
	raw_value: Variant,
	normalized_items: Array
) -> void:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	if typeof(raw_value) != TYPE_ARRAY:
		return
	var expected_amounts: Dictionary = {}
	var recovered_cells: Dictionary = {}
	for item_value: Variant in raw_value as Array:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		var item_id := content.normalize_item_id(String(item.get("item_id", "")))
		var amount := _safe_int(item.get("amount"), 0)
		var cell_value: Variant = item.get("cell", [])
		var cell_key: String = sim._storage_cell_key(cell_value)
		if not content.has_item(item_id) or amount <= 0 or cell_key.is_empty():
			continue
		if content.item_is_instance_based(item_id):
			var instance_id := String(item.get("instance_id", ""))
			var retained := false
			for normalized_value: Variant in normalized_items:
				if typeof(normalized_value) == TYPE_DICTIONARY and String((normalized_value as Dictionary).get("instance_id", "")) == instance_id and not instance_id.is_empty():
					retained = true
					break
			if retained:
				continue
			var cell_data := cell_value as Array
			var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
			if not Rect2i(Vector2i.ZERO, FirstNightContent.MAP_SIZE).has_point(cell):
				continue
			var serial := maxi(1, _safe_int(state.get("next_drop_serial", 1), 1))
			state["next_drop_serial"] = serial + 1
			var position := FirstNightContent.cell_center(cell.x, cell.y) + Vector2(12.0, 8.0)
			var map_pixels := Vector2(FirstNightContent.MAP_SIZE) * FirstNightContent.CELL_SIZE
			position.x = clampf(position.x, 8.0, map_pixels.x - 8.0)
			position.y = clampf(position.y, 8.0, map_pixels.y - 8.0)
			var recovered_instance: String = sim._ensure_item_instance_for_owner(item_id, instance_id, "world_drop", "core:drop_%06d" % serial)
			(state["world_drops"] as Array).append({
				"drop_id": "core:drop_%06d" % serial,
				"item_id": item_id,
				"instance_id": recovered_instance,
				"amount": 1,
				"position": [position.x, position.y],
				"source_id": "core:storage_recovery",
				"expires_at_game_minute": sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES,
			})
			continue
		var group_key := "%s|%s" % [cell_key, item_id]
		expected_amounts[group_key] = int(expected_amounts.get(group_key, 0)) + amount
		recovered_cells[group_key] = cell_value
	var retained_amounts: Dictionary = {}
	for item: Dictionary in normalized_items:
		var item_id := String(item.get("item_id", ""))
		var cell_key: String = sim._storage_cell_key(item.get("cell", []))
		var group_key := "%s|%s" % [cell_key, item_id]
		retained_amounts[group_key] = int(retained_amounts.get(group_key, 0)) + int(item.get("amount", 0))
	for group_key_variant: Variant in expected_amounts.keys():
		var group_key := String(group_key_variant)
		var missing_amount := int(expected_amounts[group_key]) - int(retained_amounts.get(group_key, 0))
		if missing_amount <= 0:
			continue
		var parts := group_key.split("|", false, 1)
		if parts.size() != 2:
			continue
		var item_id := String(parts[1])
		var cell_value := recovered_cells[group_key] as Array
		var cell := Vector2i(int(cell_value[0]), int(cell_value[1]))
		if not Rect2i(Vector2i.ZERO, FirstNightContent.MAP_SIZE).has_point(cell):
			continue
		var serial := maxi(1, _safe_int(state.get("next_drop_serial", 1), 1))
		state["next_drop_serial"] = serial + 1
		var position := FirstNightContent.cell_center(cell.x, cell.y) + Vector2(12.0, 8.0)
		var map_pixels := Vector2(FirstNightContent.MAP_SIZE) * FirstNightContent.CELL_SIZE
		position.x = clampf(position.x, 8.0, map_pixels.x - 8.0)
		position.y = clampf(position.y, 8.0, map_pixels.y - 8.0)
		(state["world_drops"] as Array).append({
			"drop_id": "core:drop_%06d" % serial,
			"item_id": item_id,
			"amount": missing_amount,
			"position": [position.x, position.y],
			"source_id": "core:storage_recovery",
			"expires_at_game_minute": sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES,
		})


static func _normalize_next_storage_zone_serial(sim, value: Variant, zones: Array) -> int:
	var serial := maxi(1, _safe_int(value, 1))
	while serial < 1000000:
		var candidate := "core:storage_zone_%04d" % serial
		var exists := false
		for zone_value: Variant in zones:
			if typeof(zone_value) == TYPE_DICTIONARY and String((zone_value as Dictionary).get("id", "")) == candidate:
				exists = true
				break
		if not exists:
			return serial
		serial += 1
	return serial
