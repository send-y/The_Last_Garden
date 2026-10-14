extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func transfer_inventory_stack_to_storage(sim,
	cell: Vector2i,
	item_id: String,
	stack_index: int,
	destination_origin: Vector2i = Vector2i(-1, -1),
	destination_rotation: int = -1
) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var access: Dictionary = sim._validate_storage_access(cell)
	if not bool(access.get("success", false)):
		return access
	var normalized_id := content.normalize_item_id(item_id)
	var packed := InventoryPackerScript.pack_with_layout(sim.get_inventory(), content, state.get("inventory_layout", []), 4, 4)
	var selected: Dictionary = {}
	for placement_value: Variant in packed.get("placements", []):
		var placement: Dictionary = placement_value as Dictionary
		if String(placement.item_id) == normalized_id and int(placement.stack_index) == stack_index:
			selected = placement
			break
	if selected.is_empty():
		return sim._emit_result(false, "ui.storage.failure.none_to_store")
	if destination_origin.x >= 0 and destination_origin.y >= 0:
		var stock: Dictionary = preload("res://src/inventory/inventory_storage_exchange.gd").at(sim.get_storage_layout(cell),destination_origin,content)
		if not stock.is_empty() and (stock.item_id != normalized_id or content.item_is_instance_based(normalized_id)):
			for described: Dictionary in sim.get_inventory_placements():
				if described.item_id == normalized_id and int(described.stack_index) == stack_index: selected = described; break
			var exchange: Dictionary = preload("res://src/inventory/inventory_storage_exchange.gd").exchange(sim,cell,selected,stock,selected.origin,posmod(destination_rotation,4),destination_origin,int(stock.rotation),false)
			if bool(exchange.success): return exchange
			return sim._emit_result(false,"ui.storage.failure.no_capacity")
	if not content.item_is_instance_based(normalized_id):
		return preload("res://src/inventory/storage_stack_transfer.gd").store_stack(sim,cell,selected,packed.layout,destination_origin,destination_rotation)
	var used: Dictionary = {}
	var grid_size: Vector2i = sim.get_storage_grid_size(cell)
	var next_index := 0
	for stored: Dictionary in state["storage_items"] as Array:
		if sim._storage_cell_key(stored.get("cell", [])) != sim._storage_cell_key([cell.x, cell.y]):
			continue
		var stored_origin_data: Array = stored.get("origin", [0, 0]) as Array
		var stored_origin := Vector2i(int(stored_origin_data[0]), int(stored_origin_data[1]))
		var stored_id := String(stored.get("item_id", ""))
		var stored_rotation := posmod(int(stored.get("rotation", 0)), 4)
		var stored_footprint := content.item_footprint(stored_id, stored_rotation)
		var placement_key: String = sim._storage_placement_key(stored)
		InventoryPlacementRulesScript.occupy(stored_footprint, stored_origin, used, placement_key)
		if stored_id == normalized_id:
			next_index = maxi(next_index, int(stored.get("stack_index", -1)) + 1)
	var fit: Dictionary = {}
	if destination_origin.x >= 0 and destination_origin.y >= 0:
		var rotation := posmod(destination_rotation, 4)
		var requested_footprint := content.item_footprint(normalized_id, rotation)
		if not InventoryPlacementRulesScript.can_place(requested_footprint, destination_origin, used, grid_size.x, grid_size.y):
			return sim._emit_result(false, "ui.storage.failure.no_capacity")
		fit = {"origin": destination_origin, "rotation": rotation}
	else:
		fit = InventoryPlacementRulesScript.find_first_fit(content.item_footprint(normalized_id), used, grid_size.x, grid_size.y)
	var origin: Vector2i = fit.get("origin", InventoryPlacementRulesScript.INVALID_ORIGIN)
	if origin == InventoryPlacementRulesScript.INVALID_ORIGIN:
		return sim._emit_result(false, "ui.storage.failure.no_capacity")
	var amount := int(selected.get("amount", 0))
	var item_instance_id := ""
	if content.item_is_instance_based(normalized_id):
		item_instance_id = sim.get_inventory_instance_id(normalized_id, stack_index)
		if item_instance_id.is_empty():
			return sim._emit_result(false, "ui.storage.failure.none_to_store")
	var inventory: Dictionary = sim._inventory_mutable()
	inventory[normalized_id] = maxi(0, int(inventory.get(normalized_id, 0)) - amount)
	var remaining_layout: Array[Dictionary] = []
	for layout_value: Variant in packed.layout:
		if typeof(layout_value) != TYPE_DICTIONARY:
			continue
		var layout_entry := (layout_value as Dictionary).duplicate(true)
		if String(layout_entry.get("item_id", "")) == normalized_id:
			var layout_stack_index := int(layout_entry.get("stack_index", -1))
			if layout_stack_index == stack_index:
				continue
			if layout_stack_index > stack_index:
				layout_entry["stack_index"] = layout_stack_index - 1
		remaining_layout.append(layout_entry)
	# The raw resource dictionary excludes physical tools. Repack only after the
	# selected instance changes ownership, using the actual remaining inventory.
	state["inventory_layout"] = remaining_layout
	var rotation := int(fit.get("rotation", 0))
	var placement_id := "%s:%d" % [normalized_id, next_index]
	var stored_item := {
		"cell": [cell.x, cell.y], "item_id": normalized_id, "amount": amount,
		"origin": [origin.x, origin.y], "rotation": rotation,
		"stack_index": next_index, "placement_id": placement_id,
	}
	if not item_instance_id.is_empty():
		stored_item["instance_id"] = item_instance_id
		sim._set_instance_location(item_instance_id, "storage", placement_id)
		sim._clear_hotbar_instance(item_instance_id)
	(state["storage_items"] as Array).append(stored_item)
	if not item_instance_id.is_empty():
		state["inventory_layout"] = InventoryPackerScript.pack_with_layout(
			sim.get_inventory(), content, state.get("inventory_layout", []) as Array, 4, 4
		).get("layout", [])
	return sim._emit_result(true, "ui.storage.transfer.stored", true, true, {"amount": amount, "item": Localized.resolve(content.item_label_key(normalized_id))})


static func transfer_storage_stack_to_inventory(sim,
	cell: Vector2i,
	placement_id: String,
	destination_origin: Vector2i = Vector2i(-1, -1),
	destination_rotation: int = -1
) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var access: Dictionary = sim._validate_storage_access(cell)
	if not bool(access.get("success", false)):
		return access
	var storage_items: Array = state["storage_items"] as Array
	for index: int in range(storage_items.size()):
		var item: Dictionary = storage_items[index] as Dictionary
		if sim._storage_cell_key(item.get("cell", [])) != sim._storage_cell_key([cell.x, cell.y]) or String(item.get("placement_id", "")) != placement_id:
			continue
		var item_id := String(item.get("item_id", ""))
		var amount := int(item.get("amount", 0))
		var item_instance_id := String(item.get("instance_id", ""))
		if destination_origin.x >= 0 and destination_origin.y >= 0:
			var bag: Dictionary = preload("res://src/inventory/inventory_storage_exchange.gd").at(sim.get_inventory_placements(),destination_origin,content)
			if not bag.is_empty() and (bag.item_id != item_id or content.item_is_instance_based(item_id)):
				var exchange: Dictionary = preload("res://src/inventory/inventory_storage_exchange.gd").exchange(sim,cell,bag,item,destination_origin,int(bag.rotation),Vector2i(int(item.origin[0]),int(item.origin[1])),posmod(destination_rotation,4),true)
				if bool(exchange.success): return exchange
				return sim._emit_result(false,"ui.storage.failure.inventory_full")
		if not content.item_is_instance_based(item_id):
			return preload("res://src/inventory/storage_stack_return.gd").take(sim,item,index,destination_origin,destination_rotation)
		if not sim._can_add_item(item_id, amount):
			return sim._emit_result(false, "ui.storage.failure.inventory_full")
		var candidate_inventory: Dictionary = sim.get_inventory()
		var previous_amount := int(candidate_inventory.get(item_id, 0))
		candidate_inventory[item_id] = previous_amount + amount
		var packed_candidate: Dictionary = sim._pack_inventory_storage_return(candidate_inventory,
			item_id,
			previous_amount,
			destination_origin,
			destination_rotation
		)
		if (
			not bool(packed_candidate.get("requested_layout_valid", false))
			or not (packed_candidate.get("overflow", {}) as Dictionary).is_empty()
		):
			return sim._emit_result(false, "ui.storage.failure.inventory_full")
		var candidate_layout: Array[Dictionary] = packed_candidate.get("layout", [])
		if not item_instance_id.is_empty():
			var ids_by_old_index: Dictionary = {}
			for placement: Dictionary in sim.get_inventory_placements():
				if placement.item_id == item_id: ids_by_old_index[int(placement.stack_index)] = String(placement.instance_id)
			ids_by_old_index[previous_amount] = item_instance_id
			var future_indices: Dictionary = {}
			var next_index := 0
			for instance: Dictionary in state.item_instances:
				if instance.item_id != item_id: continue
				if instance.instance_id != item_instance_id and instance.location.kind != "inventory": continue
				future_indices[String(instance.instance_id)] = next_index
				next_index += 1
			for entry: Dictionary in candidate_layout:
				if entry.item_id == item_id: entry.stack_index = int(future_indices[ids_by_old_index[int(entry.stack_index)]])
		state["inventory"] = sim._inventory_counts_without_instances(candidate_inventory)
		state["inventory_layout"] = candidate_layout
		preload("res://src/crafting/recipe_learning.gd").discover(sim, item_id)
		if not item_instance_id.is_empty():
			sim._set_instance_location(item_instance_id, "inventory")
		if not content.item_tool_profile(item_id).is_empty():
			sim._flags_mutable()["tools_found"] = true
		storage_items.remove_at(index)
		return sim._emit_result(true, "ui.storage.transfer.taken", true, true, {"amount": amount, "item": Localized.resolve(content.item_label_key(item_id))})
	return sim._emit_result(false, "ui.storage.failure.none_to_take")


static func _pack_inventory_storage_return(sim,
	candidate_inventory: Dictionary,
	item_id: String,
	previous_amount: int,
	destination_origin: Vector2i,
	destination_rotation: int
) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var current_inventory: Dictionary = sim.get_inventory()
	var current_pack := InventoryPackerScript.pack_with_layout(
		current_inventory,
		content,
		state.get("inventory_layout", []) as Array,
		4,
		4
	)
	if not (current_pack.get("overflow", {}) as Dictionary).is_empty():
		return {"layout": [], "overflow": {item_id: 1}}
	var candidate_layout: Array[Dictionary] = (current_pack.get("layout", []) as Array).duplicate(true)
	var occupied: Dictionary = {}
	var has_destination := destination_origin.x >= 0 and destination_origin.y >= 0
	var max_stack := content.item_max_stack(item_id)
	var target_stack_index := int(previous_amount / max_stack)
	var destination_rotation_normalized := posmod(destination_rotation, 4) if destination_rotation >= 0 else 0
	var destination_entry_found := false
	for placement_value: Variant in current_pack.get("placements", []):
		var placement := placement_value as Dictionary
		var placement_item_id := String(placement.get("item_id", ""))
		var stack_index := int(placement.get("stack_index", -1))
		var is_destination_stack := (
			has_destination
			and placement_item_id == item_id
			and stack_index == target_stack_index
		)
		if is_destination_stack:
			continue
		InventoryPlacementRulesScript.occupy(
			placement.get("footprint", []) as Array[Vector2i],
			placement.get("origin", Vector2i.ZERO),
			occupied,
			"%s:%d" % [placement_item_id, stack_index]
		)
	for placement_value: Variant in current_pack.get("placements", []):
		var placement := placement_value as Dictionary
		if (
			not has_destination
			or String(placement.get("item_id", "")) != item_id
			or int(placement.get("stack_index", -1)) != target_stack_index
		):
			continue
		if not InventoryPlacementRulesScript.can_place(
			content.item_footprint(item_id, destination_rotation_normalized),
			destination_origin,
			occupied,
			4,
			4
		):
			return {"layout": [], "overflow": {item_id: 1}}
		destination_entry_found = true
		for layout_entry: Dictionary in candidate_layout:
			if (
				String(layout_entry.get("item_id", "")) == item_id
				and int(layout_entry.get("stack_index", -1)) == target_stack_index
			):
				layout_entry["origin"] = [destination_origin.x, destination_origin.y]
				layout_entry["rotation"] = destination_rotation_normalized
				break
		InventoryPlacementRulesScript.occupy(
			content.item_footprint(item_id, destination_rotation_normalized),
			destination_origin,
			occupied,
			"%s:%d" % [item_id, target_stack_index]
		)
	if has_destination and not destination_entry_found:
		if not InventoryPlacementRulesScript.can_place(
			content.item_footprint(item_id, destination_rotation_normalized),
			destination_origin,
			occupied,
			4,
			4
		):
			return {"layout": [], "overflow": {item_id: 1}}
		candidate_layout.append({
			"item_id": item_id,
			"stack_index": target_stack_index,
			"origin": [destination_origin.x, destination_origin.y],
			"rotation": destination_rotation_normalized,
		})
		InventoryPlacementRulesScript.occupy(
			content.item_footprint(item_id, destination_rotation_normalized),
			destination_origin,
			occupied,
			"%s:%d" % [item_id, target_stack_index]
		)
	var previous_stack_count := int(ceil(float(previous_amount) / float(max_stack)))
	var candidate_amount := int(candidate_inventory.get(item_id, 0))
	var candidate_stack_count := int(ceil(float(candidate_amount) / float(max_stack)))
	for stack_index: int in range(previous_stack_count, candidate_stack_count):
		if has_destination and stack_index == target_stack_index:
			continue
		var fit := InventoryPlacementRulesScript.find_first_fit(
			content.item_footprint(item_id), occupied, 4, 4
		)
		var origin: Vector2i = fit.get(
			"origin", InventoryPlacementRulesScript.INVALID_ORIGIN
		)
		if origin == InventoryPlacementRulesScript.INVALID_ORIGIN:
			return {"layout": [], "overflow": {item_id: 1}}
		var rotation := int(fit.get("rotation", 0))
		candidate_layout.append({
			"item_id": item_id,
			"stack_index": stack_index,
			"origin": [origin.x, origin.y],
			"rotation": rotation,
		})
		InventoryPlacementRulesScript.occupy(
			content.item_footprint(item_id, rotation),
			origin,
			occupied,
			"%s:%d" % [item_id, stack_index]
		)
	return InventoryPackerScript.pack_with_layout(
		candidate_inventory,
		content,
		candidate_layout,
		4,
		4
	)


static func remove_storage_zone_at(sim, cell: Vector2i) -> Dictionary:
	var state: Dictionary = sim.state
	var zone_index: int = sim._storage_zone_index_at_cell(cell)
	if zone_index < 0:
		return sim._emit_result(false, "ui.storage.failure.no_zone")
	var zone: Dictionary = (state["storage_zones"] as Array)[zone_index] as Dictionary
	var zone_cells: Dictionary = sim._storage_zone_cell_keys(zone)
	for item: Dictionary in state.get("storage_items", []):
		if zone_cells.has(sim._storage_cell_key(item.get("cell", []))):
			return sim._emit_result(false, "ui.storage.failure.not_empty")
	(state["storage_zones"] as Array).remove_at(zone_index)
	return sim._emit_result(true, "ui.storage.zone_removed", true, true)


static func store_item_in_storage(sim, cell: Vector2i, item_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var access: Dictionary = sim._validate_storage_access(cell)
	if not bool(access.get("success", false)):
		return access
	var normalized_item_id := content.normalize_item_id(item_id)
	if not content.has_item(normalized_item_id):
		return sim._emit_result(false, "ui.storage.failure.invalid_item")
	var inventory: Dictionary = sim._inventory_mutable()
	var available := int(inventory.get(normalized_item_id, 0))
	if available <= 0:
		return sim._emit_result(false, "ui.storage.failure.none_to_store")
	var moved := 0
	while sim.get_item_count(normalized_item_id) > 0:
		var result: Dictionary = transfer_inventory_stack_to_storage(sim,cell,normalized_item_id,0)
		if not bool(result.get("success",false)): break
		var amount := int(result.get("amount",0))
		if amount <= 0: break
		moved += amount
	if moved <= 0: return sim._emit_result(false,"ui.storage.failure.no_capacity")
	return sim._emit_result(true,"ui.storage.transfer.stored",true,true,{
		"item":Localized.resolve(content.item_label_key(normalized_item_id)),"amount":moved})


static func take_item_from_storage(sim, cell: Vector2i, item_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var access: Dictionary = sim._validate_storage_access(cell)
	if not bool(access.get("success", false)):
		return access
	var normalized_item_id := content.normalize_item_id(item_id)
	if not content.has_item(normalized_item_id):
		return sim._emit_result(false, "ui.storage.failure.invalid_item")
	var storage_items: Array = state["storage_items"] as Array
	var cell_key: String = sim._storage_cell_key([cell.x, cell.y])
	var available := 0
	for item: Dictionary in storage_items:
		if (
			String(item.get("item_id", "")) == normalized_item_id
			and cell_key == sim._storage_cell_key(item.get("cell", []))
		):
			available += int(item.get("amount", 0))
	if available <= 0:
		return sim._emit_result(false, "ui.storage.failure.none_to_take")
	var low := 0
	var high := available
	while low < high:
		var middle := int(ceil(float(low + high + 1) * 0.5))
		if sim._can_add_item(normalized_item_id, middle):
			low = middle
		else:
			high = middle - 1
	if low <= 0:
		return sim._emit_result(false, "ui.storage.failure.inventory_full")
	var remaining := low
	for index: int in range(storage_items.size() - 1, -1, -1):
		var item: Dictionary = storage_items[index] as Dictionary
		if (
			String(item.get("item_id", "")) != normalized_item_id
			or cell_key != sim._storage_cell_key(item.get("cell", []))
		):
			continue
		var removed := mini(remaining, int(item.get("amount", 0)))
		item["amount"] = int(item.get("amount", 0)) - removed
		remaining -= removed
		if int(item.get("amount", 0)) <= 0:
			storage_items.remove_at(index)
		if remaining <= 0:
			break
	sim._add_item(normalized_item_id, low)
	return sim._emit_result(true, "ui.storage.transfer.taken", true, true, {
		"item": Localized.resolve(content.item_label_key(normalized_item_id)),
		"amount": low,
	})
