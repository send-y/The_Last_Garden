extends RefCounted

# Stack indices are per item type; removing one must not relocate other items.
static func without_stack(layout: Array, item_id: String, stack_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in layout:
		var entry := value.duplicate(true)
		if String(entry.get("item_id", "")) == item_id:
			var index := int(entry.get("stack_index", -1))
			if index == stack_index: continue
			if index > stack_index: entry.stack_index = index - 1
		result.append(entry)
	return result
