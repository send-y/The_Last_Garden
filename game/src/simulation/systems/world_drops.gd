extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func try_pickup_item(sim, item_id: String, amount: int) -> Dictionary:
	var content: FirstNightContent = sim.content
	var normalized_id: String = content.normalize_item_id(item_id)

	if amount <= 0 or not content.has_item(normalized_id):
		return sim._emit_result(
			false,
			"world.pickup.failure.invalid_item"
		)

	if not sim._can_add_item(normalized_id, amount):
		return sim._emit_result(
			false,
			"world.pickup.failure.inventory_full"
		)

	sim._add_item(normalized_id, amount)

	return sim._emit_result(
		true,
		"world.pickup.success",
		true,
		false,
		{
			"item": Localized.resolve(
				content.item_label_key(normalized_id)
			),
			"amount": amount,
		}
	)


static func get_world_drops(sim) -> Array:
	var state: Dictionary = sim.state
	return (state.get("world_drops", []) as Array).duplicate(true)


static func get_elapsed_game_minutes(sim) -> int:
	var state: Dictionary = sim.state
	return maxi(0, int(state.get("elapsed_game_minutes", 0)))


static func drop_inventory_stack(sim, item_id: String, stack_index: int) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var normalized_id := content.normalize_item_id(item_id)
	if stack_index < 0 or not content.has_item(normalized_id):
		return sim._emit_result(false, "ui.inventory.drop.failure")
	var packed := InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content,
		state.get("inventory_layout", []) as Array, 4, 4
	)
	var stack_amount := 0
	for placement_value: Variant in packed.get("placements", []) as Array:
		if typeof(placement_value) != TYPE_DICTIONARY:
			continue
		var placement := placement_value as Dictionary
		if String(placement.get("item_id", "")) != normalized_id:
			continue
		if int(placement.get("stack_index", -1)) != stack_index:
			continue
		stack_amount = maxi(0, int(placement.get("amount", 0)))
		break
	if stack_amount <= 0:
		return sim._emit_result(false, "ui.inventory.drop.failure")
	var dropped_instance_id := ""
	if content.item_is_instance_based(normalized_id):
		dropped_instance_id = sim.get_inventory_instance_id(normalized_id, stack_index)
		if dropped_instance_id.is_empty():
			return sim._emit_result(false, "ui.inventory.drop.failure")
	else:
		if not sim._consume_items({normalized_id: stack_amount}):
			return sim._emit_result(false, "ui.inventory.drop.failure")

	var serial := maxi(1, int(state.get("next_drop_serial", 1)))
	state["next_drop_serial"] = serial + 1
	var position: Vector2 = sim.get_player_position() + Vector2(28.0, 12.0)
	var map_pixels := Vector2(FirstNightContent.MAP_SIZE) * FirstNightContent.CELL_SIZE
	position.x = clampf(position.x, 8.0, map_pixels.x - 8.0)
	position.y = clampf(position.y, 8.0, map_pixels.y - 8.0)
	var new_drop := {
		"drop_id": "core:drop_%06d" % serial,
		"item_id": normalized_id,
		"amount": stack_amount,
		"position": [position.x, position.y],
		"source_id": "core:player",
		"expires_at_game_minute": sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES,
	}
	if not dropped_instance_id.is_empty():
		new_drop["instance_id"] = dropped_instance_id
		sim._set_instance_location(dropped_instance_id, "world_drop", String(new_drop["drop_id"]))
		sim._clear_hotbar_instance(dropped_instance_id)
	(state["world_drops"] as Array).append(new_drop)
	state["inventory_layout"] = InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content, [], 4, 4
	).get("layout", [])
	return sim._emit_result(
		true,
		"ui.inventory.drop.success",
		true,
		true,
		{"item": Localized.resolve(content.item_label_key(normalized_id)), "amount": stack_amount}
	)


static func try_pickup_world_drop(sim, drop_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var drops: Array = state["world_drops"] as Array
	var drop_index: int = -1
	var drop: Dictionary = {}

	for index: int in range(drops.size()):
		var candidate_value: Variant = drops[index]
		if typeof(candidate_value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_value as Dictionary
		if String(candidate.get("drop_id", "")) != drop_id:
			continue
		drop_index = index
		drop = candidate
		break

	if drop_index < 0:
		return sim._emit_result(
			false,
			"world.pickup.failure.missing_drop"
		)

	var item_id: String = content.normalize_item_id(
		String(drop.get("item_id", ""))
	)
	var amount: int = maxi(0, int(drop.get("amount", 0)))
	if amount <= 0 or not content.has_item(item_id):
		return sim._emit_result(
			false,
			"world.pickup.failure.invalid_item"
		)

	if not sim._can_add_item(item_id, amount):
		return sim._emit_result(
			false,
			"world.pickup.failure.inventory_full"
		)

	var instance_id := String(drop.get("instance_id", ""))
	if content.item_is_instance_based(item_id):
		if instance_id.is_empty() or ItemInstanceRegistryScript.find(state, instance_id).is_empty():
			return sim._emit_result(false, "world.pickup.failure.invalid_item")
		sim._set_instance_location(instance_id, "inventory")
	else:
		sim._add_item(item_id, amount)
	drops.remove_at(drop_index)
	var result: Dictionary = sim._emit_result(
		true,
		"world.pickup.success",
		true,
		false,
		{
			"item": Localized.resolve(
				content.item_label_key(item_id)
			),
			"amount": amount,
		}
	)
	result["drop_id"] = drop_id
	result["item_id"] = item_id
	result["amount"] = amount
	return result


static func _normalize_world_drops(sim, value: Variant) -> Array[Dictionary]:
	var content: FirstNightContent = sim.content
	var normalized: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return normalized

	var known_ids: Dictionary = {}
	for drop_value: Variant in (value as Array):
		if typeof(drop_value) != TYPE_DICTIONARY:
			continue
		var drop: Dictionary = drop_value as Dictionary
		var drop_id: String = String(
			drop.get("drop_id", "")
		).strip_edges()
		var item_id: String = content.normalize_item_id(
			String(drop.get("item_id", ""))
		)
		var raw_amount: int = _safe_int(drop.get("amount"), 0)
		var amount: int = mini(raw_amount, 999)
		var position_value: Variant = drop.get("position", [])
		if (
			drop_id.is_empty()
			or known_ids.has(drop_id)
			or not content.has_item(item_id)
			or raw_amount <= 0
			or not _is_valid_position(position_value)
		):
			continue

		var position_data: Array = position_value as Array
		known_ids[drop_id] = true
		var expiry: int = _safe_int(
			drop.get(
				"expires_at_game_minute",
				sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES
			),
			sim.get_elapsed_game_minutes() + WORLD_DROP_LIFETIME_MINUTES
		)
		var recovery: bool = _safe_bool(drop.get("npc_recovery"), false) and not sim.npc_catalog.get_definition(String(drop.get("source_id", ""))).is_empty()
		if expiry <= sim.get_elapsed_game_minutes() and not recovery:
			continue
		var normalized_drop := {
			"drop_id": drop_id,
			"item_id": item_id,
			"amount": 1 if content.item_is_instance_based(item_id) else amount,
			"position": [
				float(position_data[0]),
				float(position_data[1]),
			],
			"source_id": content.normalize_object_id(
				String(drop.get("source_id", ""))
			),
			"expires_at_game_minute": expiry,
		}
		if recovery:
			normalized_drop["npc_recovery"] = true
		if content.item_is_instance_based(item_id):
			normalized_drop["instance_id"] = sim._ensure_item_instance_for_owner(
				item_id,
				String(drop.get("instance_id", "")),
				"world_drop",
				drop_id
			)
		normalized.append(normalized_drop)

	return normalized


static func _expire_world_drops(sim) -> bool:
	var state: Dictionary = sim.state
	var drops: Array = state.get("world_drops", []) as Array
	var current_minute: int = sim.get_elapsed_game_minutes()
	var kept: Array = []
	var changed := false
	for drop_value: Variant in drops:
		if typeof(drop_value) != TYPE_DICTIONARY:
			changed = true
			continue
		var drop := drop_value as Dictionary
		if not bool(drop.get("npc_recovery", false)) and int(drop.get("expires_at_game_minute", current_minute + 1)) <= current_minute:
			var instance_id := String(drop.get("instance_id", ""))
			if not instance_id.is_empty():
				sim._clear_hotbar_instance(instance_id)
				sim._remove_item_instance(instance_id)
			changed = true
			continue
		kept.append(drop)
	if changed:
		state["world_drops"] = kept
	return changed
