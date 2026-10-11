extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_room_assignments(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for room_value: Variant in state.get("room_assignments", []):
		if typeof(room_value) == TYPE_DICTIONARY:
			result.append((room_value as Dictionary).duplicate(true))
	return result


static func assign_room_type(sim, room_type_id: String, target: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	var structures: Array[Dictionary] = sim.get_structures()
	var cells: Array[Vector2i] = RoomTopologyScript.find_room_at(
		target, structures, building_catalog, FirstNightContent.MAP_SIZE
	)
	if cells.is_empty():
		return sim._emit_result(false, "ui.room.failure.not_enclosed")
	for cell: Vector2i in cells:
		if WaterMapScript.contains_cell(cell):
			return sim._emit_result(false, "ui.room.failure.invalid")
	var validation: Dictionary = RoomTopologyScript.validate(
		room_type_id, cells, structures, building_catalog
	)
	if not bool(validation.get("success", false)):
		return sim._room_validation_failure(validation)
	for room: Dictionary in sim.get_room_assignments():
		var assigned_cells: Dictionary = sim._room_cells_set(room.get("cells", []))
		for cell: Vector2i in cells:
			if assigned_cells.has(cell):
				return sim._emit_result(false, "ui.room.failure.already_assigned")
	if room_type_id == RoomTopologyScript.STORAGE_ROOM_ID:
		for zone_value: Variant in state.get("storage_zones", []):
			if typeof(zone_value) != TYPE_DICTIONARY:
				continue
			var zone: Dictionary = zone_value as Dictionary
			var zone_cells: Dictionary = sim._room_cells_set(zone.get("cells", []))
			for cell: Vector2i in cells:
				if zone_cells.has(cell):
					return sim._emit_result(false, "ui.room.failure.overlaps_storage")
	var room_serial := _safe_int(state.get("next_room_serial", 1), 1)
	var room_id := "core:room_%04d" % room_serial
	state["next_room_serial"] = room_serial + 1
	var encoded_cells: Array = []
	for cell: Vector2i in cells:
		encoded_cells.append([cell.x, cell.y])
	var assignments: Array = state.get("room_assignments", []) as Array
	assignments.append({
		"id": room_id,
		"room_type_id": room_type_id,
		"cells": encoded_cells.duplicate(true),
	})
	state["room_assignments"] = assignments
	sim.notify_housing_changed(true)
	var message_key := "ui.room.assigned.living"
	if room_type_id == RoomTopologyScript.STORAGE_ROOM_ID:
		var zone_serial := maxi(1, _safe_int(state.get("next_storage_zone_serial", 1), 1))
		var zones: Array = state.get("storage_zones", []) as Array
		zones.append({
			"id": "core:storage_zone_%04d" % zone_serial,
			"cells": encoded_cells.duplicate(true),
			"room_id": room_id,
			"room_type_id": room_type_id,
		})
		state["storage_zones"] = zones
		state["next_storage_zone_serial"] = zone_serial + 1
		message_key = "ui.room.assigned.storage"
	return sim._emit_result(true, message_key, true, true, {"cells": cells.size()})


static func remove_room_at(sim, cell: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var assignments: Array = state.get("room_assignments", []) as Array
	for room_index: int in range(assignments.size()):
		var room: Dictionary = assignments[room_index] as Dictionary
		var cells: Dictionary = sim._room_cells_set(room.get("cells", []))
		if not cells.has(cell):
			continue
		var room_id := String(room.get("id", ""))
		if String(room.get("room_type_id", "")) == RoomTopologyScript.STORAGE_ROOM_ID:
			for zone_index: int in range((state.get("storage_zones", []) as Array).size()):
				var zone: Dictionary = (state["storage_zones"] as Array)[zone_index] as Dictionary
				if String(zone.get("room_id", "")) != room_id:
					continue
				var zone_cell_keys: Dictionary = sim._storage_zone_cell_keys(zone)
				for item: Dictionary in state.get("storage_items", []):
					if zone_cell_keys.has(sim._storage_cell_key(item.get("cell", []))):
						return sim._emit_result(false, "ui.room.failure.storage_not_empty")
				(state["storage_zones"] as Array).remove_at(zone_index)
				break
		assignments.remove_at(room_index)
		sim.notify_housing_changed(true)
		return sim._emit_result(true, "ui.room.removed", true, true)
	return sim._emit_result(false, "ui.room.failure.not_assigned")


static func _normalize_room_assignments(sim, value: Variant) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return rooms
	var seen_ids: Dictionary = {}
	var claimed_cells: Dictionary = {}
	var map_rect := Rect2i(Vector2i.ZERO, FirstNightContent.MAP_SIZE)
	for room_value: Variant in value as Array:
		if (
			typeof(room_value) != TYPE_DICTIONARY
			or rooms.size() >= FirstNightContent.MAP_SIZE.x * FirstNightContent.MAP_SIZE.y
		):
			continue
		var room: Dictionary = room_value as Dictionary
		var room_id := String(room.get("id", ""))
		var room_type_id := String(room.get("room_type_id", ""))
		var limits: Vector2i = RoomTopologyScript.ROOM_LIMITS.get(room_type_id, Vector2i.ZERO)
		var raw_cells: Variant = room.get("cells", [])
		if (
			not room_id.begins_with("core:room_") or seen_ids.has(room_id)
			or limits == Vector2i.ZERO or typeof(raw_cells) != TYPE_ARRAY
			or (raw_cells as Array).size() < limits.x
			or (raw_cells as Array).size() > limits.y
		):
			continue
		var valid_cells: Array = []
		for cell_value: Variant in raw_cells as Array:
			if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
				continue
			var cell_data := cell_value as Array
			if not _is_whole_number(cell_data[0]) or not _is_whole_number(cell_data[1]):
				continue
			var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
			if (
				not map_rect.has_point(cell)
				or claimed_cells.has(cell)
				or WaterMapScript.contains_cell(cell)
			):
				continue
			claimed_cells[cell] = true
			valid_cells.append([cell.x, cell.y])
		if valid_cells.size() < limits.x or valid_cells.size() > limits.y:
			continue
		seen_ids[room_id] = true
		rooms.append({"id": room_id, "room_type_id": room_type_id, "cells": valid_cells})
	return rooms


static func _normalize_next_room_serial(sim, value: Variant, rooms: Array) -> int:
	var serial := maxi(1, _safe_int(value, 1))
	while serial < 1000000:
		var candidate := "core:room_%04d" % serial
		var exists := false
		for room: Dictionary in rooms:
			if String(room.get("id", "")) == candidate:
				exists = true
				break
		if not exists:
			return serial
		serial += 1
	return serial


static func _room_validation_failure(sim, validation: Dictionary) -> Dictionary:
	var message_key := "ui.room.failure.invalid"
	match String(validation.get("reason_id", "")):
		"core:room_too_small":
			message_key = "ui.room.failure.too_small"
		"core:room_too_large":
			message_key = "ui.room.failure.too_large"
		"core:room_missing_requirements":
			message_key = "ui.room.failure.missing_requirements"
		"core:room_storage_furniture_forbidden":
			message_key = "ui.room.failure.storage_furniture"
		"core:room_type_unknown":
			message_key = "ui.room.failure.invalid"
		"core:room_door_required":
			message_key = "ui.room.failure.door_required"
	return sim._emit_result(false, message_key)


static func _room_cells_set(sim, values: Variant) -> Dictionary:
	var cells: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return cells
	for cell_value: Variant in values as Array:
		if typeof(cell_value) != TYPE_ARRAY or (cell_value as Array).size() != 2:
			continue
		var raw_cell := cell_value as Array
		cells[Vector2i(int(raw_cell[0]), int(raw_cell[1]))] = true
	return cells


static func _building_allowed_in_assigned_rooms(sim, building_id: String, raw_origin: Array) -> bool:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	if building_catalog.is_floor(building_id):
		return true
	var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
	var footprint: Array[Vector2i] = building_catalog.get_footprint_cells(building_id, origin)
	var role := String(building_catalog.get_definition(building_id).get("room_role", ""))
	var is_boundary := bool(building_catalog.get_definition(building_id).get("room_boundary", false))
	for room: Dictionary in state.get("room_assignments", []):
		var room_cells: Dictionary = sim._room_cells_set(room.get("cells", []))
		var intersects := false
		var fully_inside := true
		for cell: Vector2i in footprint:
			if room_cells.has(cell):
				intersects = true
			else:
				fully_inside = false
		if not intersects:
			continue
		if is_boundary:
			return false
		if String(room.get("room_type_id", "")) == RoomTopologyScript.STORAGE_ROOM_ID and (
			not fully_inside or not RoomTopologyScript.ALLOWED_STORAGE_ROLES.has(role)
		):
			return false
	return true


static func _room_storage_cell_has_forbidden_structure(sim, cell: Vector2i) -> bool:
	var state: Dictionary = sim.state
	var building_catalog: BuildingCatalog = sim.building_catalog
	for entity_key: String in ["blueprints", "structures"]:
		for entity_value: Variant in state.get(entity_key, []):
			if typeof(entity_value) != TYPE_DICTIONARY:
				continue
			var entity := entity_value as Dictionary
			var building_id := String(entity.get("building_id", ""))
			if building_catalog.is_floor(building_id):
				continue
			var raw_origin: Variant = entity.get("cell", [])
			if typeof(raw_origin) != TYPE_ARRAY or (raw_origin as Array).size() != 2:
				continue
			var origin := Vector2i(int(raw_origin[0]), int(raw_origin[1]))
			if not building_catalog.get_footprint_cells(building_id, origin).has(cell):
				continue
			var role := String(building_catalog.get_definition(building_id).get("room_role", ""))
			if not RoomTopologyScript.ALLOWED_STORAGE_ROLES.has(role):
				return true
	return false
