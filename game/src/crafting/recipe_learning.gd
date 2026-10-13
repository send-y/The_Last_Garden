extends RefCounted

static func normalize(sim, value: Variant) -> Dictionary:
	var result := {"discovered_items": {}, "unlocks": {}}
	if value is Dictionary:
		var discovered: Variant = value.get("discovered_items", {})
		if discovered is Dictionary:
			for id: Variant in discovered:
				if id is String and sim.content.has_item(id) and discovered[id] == true:
					result.discovered_items[id] = true
		var unlocks: Variant = value.get("unlocks", {})
		if unlocks is Dictionary:
			for id: Variant in unlocks:
				if id is String and sim.crafting_catalog.has_unlock(id) and unlocks[id] == true:
					result.unlocks[id] = true
	# Existing saves keep their possessions and can discover recipes from them.
	for id: String in sim.get_inventory():
		if sim.get_item_count(id) > 0: result.discovered_items[id] = true
	return result

static func discover(sim, item_id: String) -> void:
	if sim.state.get("learning") is Dictionary and sim.content.has_item(item_id):
		sim.state.learning.discovered_items[item_id] = true

static func unlocked(sim, recipe: Dictionary) -> bool:
	if recipe.is_empty(): return false
	var discovery := String(recipe.get("requires_discovery", ""))
	var research := String(recipe.get("requires_unlock", ""))
	var learning: Dictionary = sim.state.get("learning", {})
	if not discovery.is_empty() and not learning.get("discovered_items", {}).get(discovery, false): return false
	if not research.is_empty() and not learning.get("unlocks", {}).get(research, false): return false
	var grants: Array = recipe.get("unlocks", [])
	if not grants.is_empty():
		for id: String in grants:
			if not learning.get("unlocks", {}).get(id, false): return true
		return false
	return true

static func complete(sim, recipe: Dictionary) -> void:
	for id: String in recipe.get("unlocks", []): sim.state.learning.unlocks[id] = true
