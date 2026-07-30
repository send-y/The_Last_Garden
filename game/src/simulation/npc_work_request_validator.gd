extends RefCounted

const WorkRequest := preload("res://src/simulation/npc_work_request.gd")
const Navigation := preload("res://src/simulation/first_night_navigation.gd")


static func validate_construction_help(command: Dictionary) -> Dictionary:
	if String(command.get("actor_id", "")) != WorkRequest.PLAYER_ACTOR_ID:
		return _failure("core:unknown_actor")

	if (
		String(command.get("action_id", ""))
		!= WorkRequest.ACTION_REQUEST_CONSTRUCTION_HELP
	):
		return _failure("core:unsupported_action")

	var npc_id: String = String(command.get("npc_id", ""))
	if not npc_id.contains(":"):
		return _failure("core:invalid_npc")

	var cell_value: Variant = command.get("target_cell", [])
	if typeof(cell_value) != TYPE_ARRAY:
		return _failure("core:invalid_cell")

	var cell_data: Array = cell_value as Array
	if cell_data.size() != 2:
		return _failure("core:invalid_cell")
	if typeof(cell_data[0]) != TYPE_INT or typeof(cell_data[1]) != TYPE_INT:
		return _failure("core:invalid_cell")

	var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
	if not Rect2i(Vector2i.ZERO, Navigation.MAP_SIZE).has_point(cell):
		return _failure("core:outside_map")

	return {
		"success": true,
		"reason_id": "core:ok",
		"npc_id": npc_id,
		"target_cell": [cell.x, cell.y],
	}


static func _failure(reason_id: String) -> Dictionary:
	return {
		"success": false,
		"reason_id": reason_id,
	}
