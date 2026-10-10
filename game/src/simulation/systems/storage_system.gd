extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_storage_zones(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for zone_value: Variant in state.get("storage_zones", []):
		if typeof(zone_value) == TYPE_DICTIONARY:
			result.append((zone_value as Dictionary).duplicate(true))
	return result


static func get_storage_items(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for item_value: Variant in state.get("storage_items", []):
		if typeof(item_value) == TYPE_DICTIONARY:
			result.append((item_value as Dictionary).duplicate(true))
	return result


static func get_storage_contents(sim, cell: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var zone_index: int = sim._storage_zone_index_at_cell(cell)
	if zone_index < 0:
		return {}
	var zone: Dictionary = (state["storage_zones"] as Array)[zone_index] as Dictionary
	var cell_keys: Dictionary = sim._storage_zone_cell_keys(zone)
	var contents: Dictionary = {}
	for item: Dictionary in state.get("storage_items", []):
		if not cell_keys.has(sim._storage_cell_key(item.get("cell", []))):
			continue
		var item_id := String(item.get("item_id", ""))
		contents[item_id] = int(contents.get(item_id, 0)) + int(item.get("amount", 0))
	return contents


static func get_storage_layout(sim, cell: Vector2i) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var result: Array[Dictionary] = []
	var key: String = sim._storage_cell_key([cell.x, cell.y])
	for item: Dictionary in state.get("storage_items", []):
		if sim._storage_cell_key(item.get("cell", [])) != key:
			continue
		var item_id := String(item.get("item_id", ""))
		var rotation := posmod(int(item.get("rotation", 0)), 4)
		var raw_origin: Variant = item.get("origin", [0, 0])
		var origin := Vector2i.ZERO
		if typeof(raw_origin) == TYPE_ARRAY and (raw_origin as Array).size() == 2:
			origin = Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		var placement := {
			"placement_id": String(item.get("placement_id", item_id)),
			"item_id": item_id,
			"amount": int(item.get("amount", 1)),
			"origin": origin,
			"rotation": rotation,
			"footprint": content.item_footprint(item_id, rotation),
			"stack_index": int(item.get("stack_index", 0)),
			"label": Localized.resolve(content.item_label_key(item_id)),
		}
		var instance_id := String(item.get("instance_id", ""))
		var instance_state: Dictionary = {}
		if not instance_id.is_empty():
			placement["instance_id"] = instance_id
			instance_state = (sim.get_item_instance(instance_id).get("state", {}) as Dictionary).duplicate(true)
			placement["instance_state"] = instance_state
		placement["icon_path"] = content.item_icon_path(item_id, instance_state)
		result.append(placement)
	return result


static func get_storage_grid_size(sim, cell: Vector2i) -> Vector2i:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	for structure_value: Variant in state.get("structures", []):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue
		var structure := structure_value as Dictionary
		var building_id := String(structure.get("building_id", ""))
		if not building_catalog.is_floor(building_id):
			continue
		var origin_value: Variant = structure.get("cell", [])
		if typeof(origin_value) != TYPE_ARRAY or (origin_value as Array).size() != 2:
			continue
		var origin := Vector2i(int(origin_value[0]), int(origin_value[1]))
		if building_catalog.get_footprint_cells(building_id, origin).has(cell):
			return Vector2i(FLOORED_STORAGE_COLUMNS, FLOORED_STORAGE_ROWS)
	return Vector2i(STORAGE_COLUMNS, STORAGE_ROWS)


static func set_storage_layout(sim, cell: Vector2i, layout: Array[Dictionary]) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var access: Dictionary = sim._validate_storage_access(cell)
	if not bool(access.get("success", false)):
		return access
	var current: Array[Dictionary] = sim.get_storage_layout(cell)
	var grid_size: Vector2i = sim.get_storage_grid_size(cell)
	if layout.size() != current.size():
		return sim._emit_result(false, "ui.inventory.move.invalid")
	var current_ids: Dictionary = {}
	for placement: Dictionary in current:
		current_ids[sim._storage_placement_key(placement)] = true
	var supplied: Dictionary = {}
	var occupied: Dictionary = {}
	for entry: Dictionary in layout:
		var key: String = sim._storage_placement_key(entry)
		var origin_value: Variant = entry.get("origin", [])
		var rotation := _safe_int(entry.get("rotation", -1), -1)
		if (
			not current_ids.has(key) or supplied.has(key)
			or not (origin_value is Vector2i or (typeof(origin_value) == TYPE_ARRAY and (origin_value as Array).size() == 2))
			or rotation < 0 or rotation > 3
		):
			return sim._emit_result(false, "ui.inventory.move.invalid")
		supplied[key] = true
		var footprint := content.item_footprint(String(entry.get("item_id", "")), rotation)
		var origin := Vector2i.ZERO
		if origin_value is Vector2i:
			origin = origin_value
		else:
			origin = Vector2i(int(origin_value[0]), int(origin_value[1]))
		if not InventoryPlacementRulesScript.can_place(footprint, origin, occupied, grid_size.x, grid_size.y):
			return sim._emit_result(false, "ui.inventory.move.invalid")
		InventoryPlacementRulesScript.occupy(footprint, origin, occupied, key)
	for item: Dictionary in state["storage_items"] as Array:
		if sim._storage_cell_key(item.get("cell", [])) != sim._storage_cell_key([cell.x, cell.y]):
			continue
		var key: String = sim._storage_placement_key(item)
		for entry: Dictionary in layout:
			if sim._storage_placement_key(entry) == key:
				var origin_value: Variant = entry.get("origin", [])
				if origin_value is Vector2i:
					var origin: Vector2i = origin_value
					item["origin"] = [origin.x, origin.y]
				else:
					var origin: Array = origin_value as Array
					item["origin"] = [int(origin[0]), int(origin[1])]
				item["rotation"] = int(entry.get("rotation", 0))
				break
	return sim._emit_result(true, "ui.inventory.move.success", true)


static func create_storage_zone(sim, from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var first := Vector2i(mini(from_cell.x, to_cell.x), mini(from_cell.y, to_cell.y))
	var last := Vector2i(maxi(from_cell.x, to_cell.x), maxi(from_cell.y, to_cell.y))
	var map_rect := Rect2i(Vector2i.ZERO, FirstNightContent.MAP_SIZE)
	if not map_rect.has_point(first) or not map_rect.has_point(last):
		return sim._emit_result(false, "ui.storage.failure.outside_map")
	var area_size := (last.x - first.x + 1) * (last.y - first.y + 1)
	if area_size > MAX_STORAGE_ZONE_CELLS:
		return sim._emit_result(false, "ui.storage.failure.area_too_large")
	if (state.get("storage_zones", []) as Array).size() >= MAX_STORAGE_ZONES:
		return sim._emit_result(false, "ui.storage.failure.zone_limit")
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if sim._storage_zone_index_at_cell(cell) >= 0:
				return sim._emit_result(false, "ui.storage.failure.overlap")
			if sim._storage_cell_has_blocking_structure(cell) or sim._world_cell_blocks_storage(cell):
				return sim._emit_result(false, "ui.storage.failure.blocked")
	var serial := maxi(1, int(state.get("next_storage_zone_serial", 1)))
	var cells: Array = []
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			cells.append([x, y])
	var zones: Array = state.get("storage_zones", []) as Array
	zones.append({"id": "core:storage_zone_%04d" % serial, "cells": cells})
	state["storage_zones"] = zones
	state["next_storage_zone_serial"] = serial + 1
	return sim._emit_result(true, "ui.storage.zone_created", true, true, {"cells": area_size})


static func _validate_storage_access(sim, cell: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var zone_index: int = sim._storage_zone_index_at_cell(cell)
	if zone_index < 0:
		return sim._emit_result(false, "ui.storage.failure.no_zone")
	var target := FirstNightContent.cell_center(cell.x, cell.y)
	if sim.get_player_position().distance_to(target) > FirstNightContent.INTERACTION_RANGE:
		return sim._emit_result(false, "interaction.failure.too_far")
	return {
		"success": true,
		"zone": (state["storage_zones"] as Array)[zone_index] as Dictionary,
	}


static func _storage_zone_index_at_cell(sim, cell: Vector2i) -> int:
	var state: Dictionary = sim.state
	for index: int in range((state.get("storage_zones", []) as Array).size()):
		var zone_value: Variant = (state["storage_zones"] as Array)[index]
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		for cell_value: Variant in (zone_value as Dictionary).get("cells", []):
			if sim._storage_cell_key(cell_value) == sim._storage_cell_key([cell.x, cell.y]):
				return index
	return -1


static func _storage_zone_cell_keys(sim, zone: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	for cell_value: Variant in zone.get("cells", []):
		keys[sim._storage_cell_key(cell_value)] = true
	return keys


static func _storage_placement_key(sim, placement: Dictionary) -> String:
	return "%s:%d" % [
		String(placement.get("item_id", "")),
		_safe_int(placement.get("stack_index"), 0),
	]


static func _storage_item_at_key(sim, items: Array, cell_key: String) -> Dictionary:
	for item_value: Variant in items:
		if typeof(item_value) == TYPE_DICTIONARY:
			var item := item_value as Dictionary
			if sim._storage_cell_key(item.get("cell", [])) == cell_key:
				return item
	return {}


static func _storage_cell_key(sim, value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return ""
	var cell := value as Array
	if not _is_whole_number(cell[0]) or not _is_whole_number(cell[1]):
		return ""
	return "%d,%d" % [int(cell[0]), int(cell[1])]


static func _storage_cell_array(sim, cell_key: String) -> Array:
	var coordinates := cell_key.split(",", false)
	if coordinates.size() != 2:
		return []
	return [int(coordinates[0]), int(coordinates[1])]


static func _storage_cell_has_blocking_structure(sim, cell: Vector2i) -> bool:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	for key: String in ["blueprints", "structures"]:
		for value: Variant in state.get(key, []):
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var entity := value as Dictionary
			if building_catalog.is_floor(String(entity.get("building_id", ""))):
				continue
			if sim._entity_occupies_cell(entity, [cell.x, cell.y]):
				return true
	return false


static func _world_cell_blocks_storage(sim, cell: Vector2i, for_farming: bool = false) -> bool:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var farming: FarmingSystem = sim.farming
	if not for_farming and not farming.bed_at(sim, cell).is_empty():
		return true
	if WaterMapScript.contains_cell(cell):
		return true
	# Generator clearance protects resource placement and storage. Crops may
	# grow near the house; farming separately checks its floor and obstacles.
	if not for_farming and ResourceNodeCatalogScript.is_reserved_cell(cell) and not sim._storage_cell_has_floor(cell):
		return true
	for interactable: Dictionary in content.interactables():
		if not bool(interactable.get("spawn_in_world", true)):
			continue
		var world_position: Vector2 = interactable.get("position", Vector2.ZERO) as Vector2
		var object_cell := Vector2i(
			floori(world_position.x / FirstNightContent.CELL_SIZE),
			floori(world_position.y / FirstNightContent.CELL_SIZE)
		)
		if String(interactable.get("id", "")) == "core:old_tools" and sim.is_collected("core:old_tools"):
			continue
		if object_cell == cell:
			return true
	for key: String in ["resource_nodes", "tree_nodes"]:
		for node_value: Variant in state.get(key, []):
			if typeof(node_value) != TYPE_DICTIONARY:
				continue
			if sim._storage_cell_key((node_value as Dictionary).get("cell", [])) == sim._storage_cell_key([cell.x, cell.y]):
				return true
	for bush: Dictionary in sim._berry_bush_nodes:
		if sim._storage_cell_key(bush.get("cell", [])) == sim._storage_cell_key([cell.x, cell.y]):
			return true
	return false


static func _storage_cell_has_floor(sim, cell: Vector2i) -> bool:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	for structure_value: Variant in state.get("structures", []):
		if typeof(structure_value) != TYPE_DICTIONARY:
			continue
		var structure := structure_value as Dictionary
		var building_id := String(structure.get("building_id", ""))
		if not building_catalog.is_floor(building_id):
			continue
		var raw_origin: Variant = structure.get("cell", [])
		if typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
			continue
		var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
		if building_catalog.get_footprint_cells(building_id, origin).has(cell):
			return true
	return false
