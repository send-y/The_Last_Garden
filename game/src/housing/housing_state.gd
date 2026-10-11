extends RefCounted

const STARTER := "core:starter_bedroll"

static func normalize(sim) -> void:
	var raw: Variant = sim.state.get("sleep_assignments", {})
	var assignments: Dictionary = {}
	var taken: Dictionary = {}
	var ids: Array[String] = ["core:player"]
	for definition: Dictionary in sim.npc_catalog.get_definitions():
		ids.append(String(definition.id))
	for id: String in ids:
		var value: Variant = raw.get(id, STARTER if id == "core:player" else "") if raw is Dictionary else (STARTER if id == "core:player" else "")
		var place := String(value) if value is String else ""
		if place.length() > 128 or (not place.is_empty() and (not place.begins_with("core:") or taken.has(place))):
			place = ""
		assignments[id] = place
		if not place.is_empty():
			taken[place] = true
	var changed: bool = not (raw is Dictionary) or raw != assignments
	sim.state.sleep_assignments = assignments
	if changed: sim.notify_housing_changed()
