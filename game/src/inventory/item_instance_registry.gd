class_name ItemInstanceRegistry
extends RefCounted


static func find(state: Dictionary, instance_id: String) -> Dictionary:
	for value: Variant in state.get("item_instances", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record := value as Dictionary
		if String(record.get("instance_id", "")) == instance_id:
			return record.duplicate(true)
	return {}


static func index_of(state: Dictionary, instance_id: String) -> int:
	var records: Array = state.get("item_instances", []) as Array
	for index: int in range(records.size()):
		if typeof(records[index]) == TYPE_DICTIONARY:
			if String((records[index] as Dictionary).get("instance_id", "")) == instance_id:
				return index
	return -1


static func in_location(
	state: Dictionary,
	item_id: String,
	location_kind: String,
	location_id: String = ""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in state.get("item_instances", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record := value as Dictionary
		var location: Dictionary = record.get("location", {}) as Dictionary
		if (
			String(record.get("item_id", "")) != item_id
			or String(location.get("kind", "")) != location_kind
			or (not location_id.is_empty() and String(location.get("id", "")) != location_id)
		):
			continue
		result.append(record.duplicate(true))
	return result
