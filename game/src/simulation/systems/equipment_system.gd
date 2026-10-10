extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_hotbar_slots(sim) -> Array[String]:
	var state: Dictionary = sim.state
	var result: Array[String] = []
	for value: Variant in state.get("hotbar_slots", []):
		result.append(String(value))
	while result.size() < 5:
		result.append("")
	return result.slice(0, 5)


static func get_active_hotbar_slot(sim) -> int:
	var state: Dictionary = sim.state
	return clampi(_safe_int(state.get("active_hotbar_slot", -1), -1), -1, 4)


static func get_active_item_instance(sim) -> Dictionary:
	var state: Dictionary = sim.state
	var selected: Dictionary = state.get("selected_inventory_item", {}) as Dictionary
	if not selected.is_empty():
		var selected_instance := ItemInstanceRegistryScript.find(state, String(selected.get("instance_id", "")))
		if String(selected_instance.get("item_id", "")) == String(selected.get("item_id", "")) and String((selected_instance.get("location", {}) as Dictionary).get("kind", "")) == "inventory":
			return selected_instance
		return {}
	var slot: int = sim.get_active_hotbar_slot()
	if slot < 0:
		return {}
	var slots: Array[String] = sim.get_hotbar_slots()
	var instance_id := slots[slot]
	if instance_id.is_empty():
		return {}
	var instance := ItemInstanceRegistryScript.find(state, instance_id)
	if String((instance.get("location", {}) as Dictionary).get("kind", "")) != "inventory":
		return {}
	return instance


static func get_held_item(sim) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var selected: Dictionary = state.get("selected_inventory_item", {}) as Dictionary
	if not selected.is_empty():
		var item_id := String(selected.get("item_id", ""))
		if content.item_is_instance_based(item_id):
			return sim.get_active_item_instance()
		if int(sim.get_inventory().get(item_id, 0)) > 0:
			return {"item_id": item_id, "state": {}}
		return {}
	return sim.get_active_item_instance()


static func select_inventory_item(sim, item_id: String, instance_id: String = "") -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var normalized_id := content.normalize_item_id(item_id)
	if not item_id.is_empty():
		if not content.has_item(normalized_id) or int(sim.get_inventory().get(normalized_id, 0)) <= 0:
			return {"success": false}
		if content.item_is_instance_based(normalized_id):
			var instance := ItemInstanceRegistryScript.find(state, instance_id)
			if String(instance.get("item_id", "")) != normalized_id or String((instance.get("location", {}) as Dictionary).get("kind", "")) != "inventory":
				return {"success": false}
		else:
			instance_id = ""
	state["selected_inventory_item"] = {} if item_id.is_empty() else {"item_id": normalized_id, "instance_id": instance_id}
	state["active_hotbar_slot"] = -1
	# Equipment selection is quiet and does not repack the backpack.
	sim.event_emitted.emit({"type": "state_changed"})
	return {"success": true}


static func assign_hotbar_slot(sim, slot_index: int, instance_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	if slot_index < 0 or slot_index >= 5:
		return sim._emit_result(false, "ui.hotbar.failure.invalid_slot")
	var instance := ItemInstanceRegistryScript.find(state, instance_id)
	if instance.is_empty() or String((instance.get("location", {}) as Dictionary).get("kind", "")) != "inventory":
		return sim._emit_result(false, "ui.hotbar.failure.item_missing")
	var slots: Array[String] = sim.get_hotbar_slots()
	for index: int in range(slots.size()):
		if slots[index] == instance_id:
			slots[index] = ""
	slots[slot_index] = instance_id
	state["hotbar_slots"] = slots
	return sim._emit_result(true, "ui.hotbar.assigned", true)


static func select_hotbar_slot(sim, slot_index: int) -> Dictionary:
	var state: Dictionary = sim.state
	if slot_index < 0 or slot_index >= 5:
		return sim._emit_result(false, "ui.hotbar.failure.invalid_slot")
	state["active_hotbar_slot"] = slot_index
	state["selected_inventory_item"] = {}
	return sim._emit_result(true, "ui.hotbar.selected", true)


static func fill_active_bucket(sim, water_cell: Vector2i) -> Dictionary:
	return fill_bucket_for_actor(sim, "core:player", water_cell)


static func fill_bucket_for_actor(sim, actor_id: String, water_cell: Vector2i) -> Dictionary:
	if not WaterMapScript.contains_cell(water_cell):
		return sim._emit_result(false, "ui.bucket.failure.not_water")
	var active: Dictionary = sim.get_actor_tool(actor_id)
	if String(active.get("item_id", "")) != "core:bucket":
		return sim._emit_result(false, "ui.bucket.failure.not_equipped")
	var target_position := FirstNightContent.cell_center(water_cell.x, water_cell.y)
	var actor: Dictionary = sim._get_resource_actor_position(actor_id)
	if not bool(actor.get("found", false)) or (actor.position as Vector2).distance_to(target_position) > FirstNightContent.INTERACTION_RANGE:
		return sim._emit_result(false, "interaction.failure.too_far")
	if not _has_actor_water_line_of_sight(sim, water_cell, actor.position):
		return sim._emit_result(false, "ui.bucket.failure.blocked")
	var instance_id := String(active.get("instance_id", ""))
	var instance_state: Dictionary = active.get("state", {}) as Dictionary
	if int(instance_state.get("charges", 0)) >= 2:
		return sim._emit_result(true, "ui.bucket.full", false)
	instance_state["charges"] = 2
	sim._update_instance_state(instance_id, instance_state)
	return sim._emit_result(true, "ui.bucket.filled", true, true, {"charges": 2})


static func _has_water_line_of_sight(sim, target_cell: Vector2i) -> bool:
	return _has_actor_water_line_of_sight(sim, target_cell, sim.get_player_position())


static func _has_actor_water_line_of_sight(sim, target_cell: Vector2i, player_position: Vector2) -> bool:
	var from_cell := Vector2i(
		floori(player_position.x / FirstNightContent.CELL_SIZE),
		floori(player_position.y / FirstNightContent.CELL_SIZE)
	)
	var delta := target_cell - from_cell
	var steps := maxi(absi(delta.x), absi(delta.y))
	if steps <= 1:
		return true
	var structures: Array = sim.get_structures()
	for step: int in range(1, steps):
		var cell := from_cell + Vector2i(
			roundi(float(delta.x) * float(step) / float(steps)),
			roundi(float(delta.y) * float(step) / float(steps))
		)
		if cell == from_cell or cell == target_cell:
			continue
		if sim._cell_blocks_water_line_of_sight(cell, structures):
			return false
	return true


static func _cell_blocks_water_line_of_sight(sim,
	cell: Vector2i,
	structures: Array[Dictionary]
) -> bool:
	var building_catalog: BuildingCatalog = sim.building_catalog
	if (cell.x >= 19 and cell.x <= 28 and cell.y == 17) or (cell.y >= 18 and cell.y <= 25 and (cell.x == 19 or cell.x == 28)):
		return true
	if cell.y == 25 and cell.x >= 19 and cell.x <= 23:
		return true
	for structure: Dictionary in structures:
		var building_id := String(structure.get("building_id", ""))
		var definition := building_catalog.get_definition(building_id)
		if not bool(definition.get("blocks_movement", false)):
			continue
		var origin_value: Variant = structure.get("cell", [])
		if typeof(origin_value) != TYPE_ARRAY or (origin_value as Array).size() != 2:
			continue
		var origin := Vector2i(int(origin_value[0]), int(origin_value[1]))
		if building_catalog.get_footprint_cells(building_id, origin).has(cell):
			return true
	return false
