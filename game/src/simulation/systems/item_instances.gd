extends "res://src/simulation/world_rules.gd"

const ToolState := preload("res://src/items/tool_instance_state.gd")
const LoadDiagnostics := preload("res://src/items/item_load_diagnostics.gd")

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_item_instance(sim, instance_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	return ItemInstanceRegistryScript.find(state, instance_id)


static func get_inventory_instance_id(sim, item_id: String, stack_index: int) -> String:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var instances := ItemInstanceRegistryScript.in_location(
		state, content.normalize_item_id(item_id), "inventory"
	)
	if stack_index < 0 or stack_index >= instances.size():
		return ""
	return String(instances[stack_index].get("instance_id", ""))


static func _create_item_instances(sim,
	item_id: String,
	amount: int,
	location_kind: String,
	location_id: String = "",
	initial_state: Dictionary = {}
) -> Array[String]:
	var state: Dictionary = sim.state
	var created: Array[String] = []
	var instances: Array = state.get("item_instances", []) as Array
	for _index: int in range(maxi(0, amount)):
		var serial := maxi(1, _safe_int(state.get("next_item_instance_serial", 1), 1))
		var instance_id := "core:item_instance_%06d" % serial
		while not ItemInstanceRegistryScript.find(state, instance_id).is_empty():
			serial += 1
			instance_id = "core:item_instance_%06d" % serial
		state["next_item_instance_serial"] = serial + 1
		var item_state := initial_state.duplicate(true)
		if sim.content.item_tool_supports(item_id, "water"):
			item_state = ToolState.normalize_water_state(item_state, sim.content.item_tool_capacity(item_id))
		instances.append({
			"instance_id": instance_id,
			"item_id": item_id,
			"state": item_state,
			"location": {"kind": location_kind, "id": location_id},
		})
		created.append(instance_id)
	state["item_instances"] = instances
	return created


static func _set_instance_location(sim,
	instance_id: String,
	location_kind: String,
	location_id: String = ""
) -> bool:
	var state: Dictionary = sim.state
	var index := ItemInstanceRegistryScript.index_of(state, instance_id)
	if index < 0:
		return false
	var instances: Array = state["item_instances"] as Array
	var record: Dictionary = instances[index] as Dictionary
	record["location"] = {"kind": location_kind, "id": location_id}
	if location_kind == "inventory": preload("res://src/crafting/recipe_learning.gd").discover(sim, String(record.item_id))
	instances[index] = record
	return true


static func _update_instance_state(sim, instance_id: String, item_state: Dictionary) -> bool:
	var state: Dictionary = sim.state
	var index := ItemInstanceRegistryScript.index_of(state, instance_id)
	if index < 0:
		return false
	var instances: Array = state["item_instances"] as Array
	var record: Dictionary = instances[index] as Dictionary
	record["state"] = item_state.duplicate(true)
	instances[index] = record
	return true


static func _remove_item_instance(sim, instance_id: String) -> bool:
	var state: Dictionary = sim.state
	var index := ItemInstanceRegistryScript.index_of(state, instance_id)
	if index < 0:
		return false
	(state["item_instances"] as Array).remove_at(index)
	return true


static func _clear_hotbar_instance(sim, instance_id: String) -> void:
	var state: Dictionary = sim.state
	var backpack_selection: Dictionary = state.get("selected_inventory_item", {}) as Dictionary
	if String(backpack_selection.get("instance_id", "")) == instance_id:
		state["selected_inventory_item"] = {}
	var slots: Array[String] = sim.get_hotbar_slots()
	var selected: int = sim.get_active_hotbar_slot()
	for index: int in range(slots.size()):
		if slots[index] == instance_id:
			slots[index] = ""
			if selected == index:
				state["active_hotbar_slot"] = -1
	state["hotbar_slots"] = slots


static func _inventory_counts_without_instances(sim, inventory: Dictionary) -> Dictionary:
	var content: FirstNightContent = sim.content
	var result := inventory.duplicate(true)
	for item_id: String in content.item_ids():
		if content.item_is_instance_based(item_id):
			result[item_id] = 0
	return result


static func _normalize_item_instances(sim, value: Variant, legacy_inventory: Dictionary) -> Array[Dictionary]:
	sim.item_load_diagnostics.clear()
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	var result: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	if typeof(value) == TYPE_ARRAY:
		for instance_value: Variant in value as Array:
			if typeof(instance_value) != TYPE_DICTIONARY:
				continue
			var raw := instance_value as Dictionary
			var item_id := content.normalize_item_id(String(raw.get("item_id", "")))
			if not content.item_is_instance_based(item_id):
				var reason := "not_instance_based" if content.has_item(item_id) else "unknown_item_definition"
				var found := false
				for row: Dictionary in sim.item_load_diagnostics:
					if row.id == item_id and row.reason == reason:
						row.count += 1
						found = true
						break
				if not found: sim.item_load_diagnostics.append({"id": item_id, "count": 1, "reason": reason})
				continue
			var instance_id := String(raw.get("instance_id", "")).strip_edges()
			if not instance_id.begins_with("core:item_instance_") or seen_ids.has(instance_id):
				instance_id = sim._new_item_instance_id(seen_ids)
			seen_ids[instance_id] = true
			var location_value: Variant = raw.get("location", {})
			var location: Dictionary = location_value.duplicate(true) if typeof(location_value) == TYPE_DICTIONARY else {}
			var location_kind := String(location.get("kind", "inventory"))
			if not ["inventory", "storage", "world_drop", "npc"].has(location_kind):
				location_kind = "inventory"
			var item_state_value: Variant = raw.get("state", {})
			var item_state: Dictionary = item_state_value.duplicate(true) if typeof(item_state_value) == TYPE_DICTIONARY else {}
			if content.item_tool_supports(item_id, "water"):
				item_state = ToolState.normalize_water_state(item_state, content.item_tool_capacity(item_id))
			result.append({
				"instance_id": instance_id,
				"item_id": item_id,
				"state": item_state,
				"location": {
					"kind": location_kind,
					"id": String(location.get("id", "")),
				},
			})
	for row: Dictionary in sim.item_load_diagnostics:
		push_warning(LoadDiagnostics.warning_text(row))
	state["item_instances"] = result
	for item_id: String in content.item_ids():
		if not content.item_is_instance_based(item_id):
			continue
		var inventory_count := 0
		for record_value: Variant in result:
			var record := record_value as Dictionary
			if String(record.get("item_id", "")) == item_id and String((record.get("location", {}) as Dictionary).get("kind", "")) == "inventory":
				inventory_count += 1
		var legacy_count := maxi(0, _safe_int(legacy_inventory.get(item_id, 0), 0))
		if legacy_count > inventory_count:
			var added: Array[String] = sim._create_item_instances(item_id, legacy_count - inventory_count, "inventory")
			for instance_id: String in added:
				seen_ids[instance_id] = true
	return state.get("item_instances", []) as Array[Dictionary]


static func _new_item_instance_id(sim, known_ids: Dictionary = {}) -> String:
	var state: Dictionary = sim.state
	var serial := maxi(1, _safe_int(state.get("next_item_instance_serial", 1), 1))
	var instance_id := "core:item_instance_%06d" % serial
	while known_ids.has(instance_id) or not ItemInstanceRegistryScript.find(state, instance_id).is_empty():
		serial += 1
		instance_id = "core:item_instance_%06d" % serial
	state["next_item_instance_serial"] = serial + 1
	return instance_id


static func _normalize_next_item_instance_serial(sim, value: Variant, instances: Array) -> int:
	var serial := maxi(1, _safe_int(value, 1))
	for instance_value: Variant in instances:
		if typeof(instance_value) != TYPE_DICTIONARY:
			continue
		var instance_id := String((instance_value as Dictionary).get("instance_id", ""))
		if not instance_id.begins_with("core:item_instance_"):
			continue
		var suffix := instance_id.trim_prefix("core:item_instance_")
		if suffix.is_valid_int():
			serial = maxi(serial, int(suffix) + 1)
	return serial


static func _ensure_item_instance_for_owner(sim,
	item_id: String,
	instance_id: String,
	location_kind: String,
	location_id: String
) -> String:
	var state: Dictionary = sim.state
	var content: FirstNightContent = sim.content
	if not content.item_is_instance_based(item_id):
		return ""
	var resolved_id := instance_id.strip_edges()
	var existing := ItemInstanceRegistryScript.find(state, resolved_id)
	if (
		resolved_id.is_empty() or existing.is_empty()
		or String(existing.get("item_id", "")) != item_id
	):
		resolved_id = sim._create_item_instances(item_id, 1, location_kind, location_id)[0]
	else:
		sim._set_instance_location(resolved_id, location_kind, location_id)
	return resolved_id


static func _reconcile_item_instance_locations(sim) -> void:
	var state: Dictionary = sim.state
	var referenced: Dictionary = {}
	for drop_value: Variant in state.get("world_drops", []):
		if typeof(drop_value) != TYPE_DICTIONARY:
			continue
		var drop := drop_value as Dictionary
		var instance_id := String(drop.get("instance_id", ""))
		if not instance_id.is_empty():
			referenced[instance_id] = {"kind": "world_drop", "id": String(drop.get("drop_id", ""))}
	var storage_records: Array = state.get("storage_items", []) as Array
	for index: int in range(storage_records.size() - 1, -1, -1):
		if typeof(storage_records[index]) != TYPE_DICTIONARY:
			continue
		var item := storage_records[index] as Dictionary
		var instance_id := String(item.get("instance_id", ""))
		if instance_id.is_empty():
			continue
		if referenced.has(instance_id):
			storage_records.remove_at(index)
			continue
		referenced[instance_id] = {"kind": "storage", "id": String(item.get("placement_id", ""))}
	state["storage_items"] = storage_records
	for npc_id: String in state.get("npcs", {}):
		var npc: Dictionary = state.npcs[npc_id]
		var held := String(npc.get("carried_instance_id", ""))
		var instance := ItemInstanceRegistryScript.find(state, held)
		if held.is_empty():
			continue
		var owner: Dictionary = instance.get("location", {})
		if instance.is_empty() or referenced.has(held) or String(owner.get("kind", "")) != "npc" or String(owner.get("id", "")) != npc_id:
			npc["carried_instance_id"] = ""
		else:
			if not bool(npc.get("active", false)) or sim.npc_catalog.get_definition(npc_id).is_empty():
				# Preserve the physical tool if its owner cannot participate in this world.
				referenced[held] = {"kind": "inventory", "id": ""}
				npc["carried_instance_id"] = ""
			else:
				referenced[held] = {"kind": "npc", "id": npc_id}
	var instances: Array = state.get("item_instances", []) as Array
	for index: int in range(instances.size() - 1, -1, -1):
		var instance := instances[index] as Dictionary
		var instance_id := String(instance.get("instance_id", ""))
		var location: Dictionary = instance.get("location", {}) as Dictionary
		if referenced.has(instance_id):
			instance["location"] = (referenced[instance_id] as Dictionary).duplicate(true)
			instances[index] = instance
		elif String(location.get("kind", "")) == "npc":
			instance["location"] = {"kind": "inventory", "id": ""}
		elif String(location.get("kind", "")) != "inventory":
			sim._clear_hotbar_instance(instance_id)
			instances.remove_at(index)
	state["next_item_instance_serial"] = sim._normalize_next_item_instance_serial(state.get("next_item_instance_serial", 1), instances
	)


static func _normalize_hotbar_state(sim) -> void:
	var state: Dictionary = sim.state
	var raw_slots: Variant = state.get("hotbar_slots", [])
	var slots: Array[String] = ["", "", "", "", ""]
	var seen: Dictionary = {}
	if typeof(raw_slots) == TYPE_ARRAY:
		for index: int in range(mini(5, (raw_slots as Array).size())):
			var instance_id := String((raw_slots as Array)[index])
			var instance := ItemInstanceRegistryScript.find(state, instance_id)
			if (
				instance_id.is_empty() or seen.has(instance_id) or instance.is_empty()
				or String((instance.get("location", {}) as Dictionary).get("kind", "")) != "inventory"
			):
				continue
			seen[instance_id] = true
			slots[index] = instance_id
	state["hotbar_slots"] = slots
	state["active_hotbar_slot"] = clampi(
		_safe_int(state.get("active_hotbar_slot", -1), -1), -1, 4
	)
