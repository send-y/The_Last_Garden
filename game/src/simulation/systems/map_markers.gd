extends "res://src/simulation/world_rules.gd"

# Operates on the authoritative WorldSimulation state; owns no copy.

static func get_markers(sim) -> Array[Dictionary]:
	var state: Dictionary = sim.state
	var result: Array[Dictionary] = []
	for marker_variant: Variant in state.get("markers", []):
		if typeof(marker_variant) == TYPE_DICTIONARY:
			result.append((marker_variant as Dictionary).duplicate(true))
	return result


static func create_marker(sim, marker_name: String, color: Color) -> Dictionary:
	var state: Dictionary = sim.state
	var safe_name := marker_name.strip_edges().substr(0, 32)
	if safe_name.is_empty():
		return sim._emit_result(false, "ui.marker.failure.empty_name")
	var markers: Array[Dictionary] = sim.get_markers()
	if markers.size() >= 64:
		return sim._emit_result(false, "ui.marker.failure.limit")
	var serial := maxi(1, int(state.get("next_marker_serial", 1)))
	var marker := {
		"id": "core:marker_%04d" % serial,
		"name": safe_name,
		"color": color.to_html(false),
		"enabled": true,
		"position": [sim.get_player_position().x, sim.get_player_position().y],
	}
	markers.append(marker)
	state["markers"] = markers
	state["next_marker_serial"] = serial + 1
	return sim._emit_result(true, "ui.marker.created", true, false, {"name": safe_name})


static func rename_marker(sim, marker_id: String, marker_name: String) -> Dictionary:
	var state: Dictionary = sim.state
	var safe_name := marker_name.strip_edges().substr(0, 32)
	if safe_name.is_empty():
		return sim._emit_result(false, "ui.marker.failure.empty_name")
	for marker: Dictionary in state.get("markers", []):
		if String(marker.get("id", "")) != marker_id:
			continue
		marker["name"] = safe_name
		return sim._emit_result(true, "ui.marker.renamed", true, false, {"name": safe_name})
	return sim._emit_result(false, "ui.marker.failure.missing")


static func set_marker_enabled(sim, marker_id: String, enabled: bool) -> Dictionary:
	var state: Dictionary = sim.state
	for marker: Dictionary in state.get("markers", []):
		if String(marker.get("id", "")) != marker_id:
			continue
		if bool(marker.get("enabled", true)) == enabled:
			return sim._emit_result(true, "ui.marker.enabled" if enabled else "ui.marker.disabled")
		marker["enabled"] = enabled
		return sim._emit_result(
			true,
			"ui.marker.enabled" if enabled else "ui.marker.disabled",
			true
		)
	return sim._emit_result(false, "ui.marker.failure.missing")


static func remove_marker(sim, marker_id: String) -> Dictionary:
	var state: Dictionary = sim.state
	var markers: Array = state.get("markers", []) as Array
	for index: int in range(markers.size()):
		if String((markers[index] as Dictionary).get("id", "")) != marker_id:
			continue
		markers.remove_at(index)
		state["markers"] = markers
		return sim._emit_result(true, "ui.marker.removed", true)
	return sim._emit_result(false, "ui.marker.failure.missing")


static func _normalize_markers(sim, value: Variant) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return markers
	var seen_ids: Dictionary = {}
	for marker_variant: Variant in value as Array:
		if typeof(marker_variant) != TYPE_DICTIONARY or markers.size() >= 64:
			continue
		var marker: Dictionary = marker_variant as Dictionary
		var marker_id := String(marker.get("id", ""))
		var marker_name := String(marker.get("name", "")).strip_edges().substr(0, 32)
		var color_text := String(marker.get("color", ""))
		var position: Variant = marker.get("position", [])
		if (
			not marker_id.begins_with("core:marker_")
			or seen_ids.has(marker_id)
			or marker_name.is_empty()
			or not _is_valid_hex_color(color_text)
			or not _is_valid_position(position)
		):
			continue
		var coordinates := position as Array
		var x := float(coordinates[0])
		var y := float(coordinates[1])
		if (
			x < 0.0 or y < 0.0
			or x >= float(FirstNightContent.MAP_SIZE.x * FirstNightContent.CELL_SIZE)
			or y >= float(FirstNightContent.MAP_SIZE.y * FirstNightContent.CELL_SIZE)
		):
			continue
		seen_ids[marker_id] = true
		markers.append({
			"id": marker_id,
			"name": marker_name,
			"color": color_text.to_lower(),
			"enabled": bool(marker.get("enabled", true)),
			"position": [x, y],
		})
	return markers


static func _normalize_next_marker_serial(sim, value: Variant, markers: Array) -> int:
	var serial := maxi(1, _safe_int(value, 1))
	while serial < 1000000:
		var candidate := "core:marker_%04d" % serial
		var exists := false
		for marker_variant: Variant in markers:
			if typeof(marker_variant) == TYPE_DICTIONARY and String((marker_variant as Dictionary).get("id", "")) == candidate:
				exists = true
				break
		if not exists:
			return serial
		serial += 1
	return serial
