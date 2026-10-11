extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_inventory(sim) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var inventory: Dictionary = sim._inventory_mutable().duplicate(true)
	for item_id: String in content.item_ids():
		if not content.item_is_instance_based(item_id):
			continue
		if sim.Diagnostic.enabled:
			sim.Diagnostic.counters["inventory.instance_records"] = int(sim.Diagnostic.counters.get("inventory.instance_records",0)) + sim.state.get("item_instances",[]).size()
		inventory[item_id] = ItemInstanceRegistryScript.in_location(
			state, item_id, "inventory"
		).size()
	return inventory


static func get_inventory_placements(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var packed := InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content, state.get("inventory_layout", []) as Array, 4, 4
	)
	var instances_by_item: Dictionary = {}
	for instance_value: Variant in state.get("item_instances", []):
		if typeof(instance_value) != TYPE_DICTIONARY:
			continue
		var instance := instance_value as Dictionary
		var location: Dictionary = instance.get("location", {}) as Dictionary
		if String(location.get("kind", "")) != "inventory":
			continue
		var item_id := String(instance.get("item_id", ""))
		var list: Array = instances_by_item.get(item_id, []) as Array
		list.append(instance)
		instances_by_item[item_id] = list
	var result: Array[Dictionary] = []
	for placement_value: Variant in packed.get("placements", []):
		if typeof(placement_value) != TYPE_DICTIONARY:
			continue
		var placement := (placement_value as Dictionary).duplicate(true)
		var item_id := String(placement.get("item_id", ""))
		if content.item_is_instance_based(item_id):
			var instances: Array = instances_by_item.get(item_id, []) as Array
			var stack_index := int(placement.get("stack_index", -1))
			if stack_index >= 0 and stack_index < instances.size():
				var instance := instances[stack_index] as Dictionary
				placement["instance_id"] = String(instance.get("instance_id", ""))
				placement["instance_state"] = (instance.get("state", {}) as Dictionary).duplicate(true)
		placement["icon_path"] = content.item_icon_path(
			item_id, placement.get("instance_state", {}) as Dictionary
		)
		placement["label"] = Localized.resolve(content.item_label_key(item_id))
		result.append(placement)
	return result


static func get_inventory_layout(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var layout: Array[Dictionary] = []
	for entry_value: Variant in state.get("inventory_layout", []):
		if typeof(entry_value) == TYPE_DICTIONARY:
			layout.append((entry_value as Dictionary).duplicate(true))
	return layout


static func get_item_count(sim, item_id: String) -> int:
	var content: FirstNightContent = sim.content
	return int(sim.get_inventory().get(content.normalize_item_id(item_id), 0))


static func eat_food(sim, item_id: String = FirstNightContent.FOOD_ID) -> Dictionary:
	return sim.execute_farming_command({"actor_id": PLAYER_ACTOR_ID, "action_id": "eat", "item_id": item_id})


static func set_inventory_layout(sim, layout: Array[Dictionary]) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var current: Dictionary = InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content, state.get("inventory_layout", []) as Array, 4, 4
	)
	var expected_placements: Array = current.get("placements", []) as Array
	if layout.size() != expected_placements.size():
		return sim._emit_result(false, "ui.inventory.move.invalid")
	var expected_ids: Dictionary = {}
	for placement_variant: Variant in expected_placements:
		var placement: Dictionary = placement_variant as Dictionary
		expected_ids["%s:%d" % [
			String(placement.get("item_id", "")),
			int(placement.get("stack_index", 0)),
		]] = true
	var supplied_ids: Dictionary = {}
	for entry: Dictionary in layout:
		var key := "%s:%d" % [
			String(entry.get("item_id", "")),
			_safe_int(entry.get("stack_index"), -1),
		]
		var origin: Variant = entry.get("origin", [])
		var rotation: int = _safe_int(entry.get("rotation"), -1)
		if (
			not expected_ids.has(key)
			or supplied_ids.has(key)
			or typeof(origin) != TYPE_ARRAY
			or (origin as Array).size() != 2
			or rotation < 0 or rotation > 3
		):
			return sim._emit_result(false, "ui.inventory.move.invalid")
		supplied_ids[key] = true
	var result: Dictionary = InventoryPackerScript.pack_with_layout(
		sim.get_inventory(), content, layout, 4, 4
	)
	if not bool(result.get("requested_layout_valid", false)):
		return sim._emit_result(false, "ui.inventory.move.invalid")
	state["inventory_layout"] = result.get("layout", [])
	return sim._emit_result(true, "ui.inventory.move.success", true)


static func _can_add_item(sim, item_id: String, amount: int) -> bool:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var normalized_id: String = content.normalize_item_id(item_id)
	var candidate_inventory: Dictionary = sim.get_inventory()
	candidate_inventory[normalized_id] = (
		int(candidate_inventory.get(normalized_id, 0)) + amount
	)

	var packed: Dictionary = InventoryPackerScript.pack_with_layout(
		candidate_inventory,
		content,
		state.get("inventory_layout", []) as Array
	)
	var overflow: Dictionary = (
		packed.get("overflow", {}) as Dictionary
	)

	return overflow.is_empty()


static func _add_item(sim, item_id: String, amount: int) -> void:
	var content: FirstNightContent = sim.content
	var normalized_id: String = content.normalize_item_id(item_id)
	if content.item_is_instance_based(normalized_id):
		sim._create_item_instances(normalized_id, amount, "inventory")
		return
	var inventory: Dictionary = sim._inventory_mutable()
	inventory[normalized_id] = int(inventory.get(normalized_id, 0)) + amount


static func _consume_items(sim, costs: Dictionary) -> bool:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		if int(sim.get_inventory().get(item_id, 0)) < required_amount:
			return false
	for item_variant: Variant in costs.keys():
		var item_id: String = content.normalize_item_id(String(item_variant))
		var required_amount: int = int(costs[item_variant])
		if content.item_is_instance_based(item_id):
			var instances := ItemInstanceRegistryScript.in_location(
				state, item_id, "inventory"
			)
			for index: int in range(mini(required_amount, instances.size())):
				var instance_id := String(instances[index].get("instance_id", ""))
				sim._clear_hotbar_instance(instance_id)
				sim._remove_item_instance(instance_id)
		else:
			var inventory: Dictionary = sim._inventory_mutable()
			inventory[item_id] = int(inventory.get(item_id, 0)) - required_amount
	return true
