class_name ConstructionValidator
extends RefCounted

const Command := preload(
	"res://src/construction/construction_command.gd"
)
const Navigation := preload(
	"res://src/simulation/first_night_navigation.gd"
)


static func validate_place_blueprint(command: Dictionary) -> Dictionary:
	if String(command.get("actor_id", "")) != Command.PLAYER_ACTOR_ID:
		return _failure("core:unknown_actor")

	if String(command.get("action_id", "")) != Command.ACTION_PLACE_BLUEPRINT:
		return _failure("core:unsupported_action")

	if String(command.get("building_id", "")) != Command.WOOD_WALL_ID:
		return _failure("core:unsupported_building")

	var cell_value: Variant = command.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY:
		return _failure("core:invalid_cell")

	var cell_data: Array = cell_value as Array
	if cell_data.size() != 2:
		return _failure("core:invalid_cell")

	if (
		typeof(cell_data[0]) != TYPE_INT
		or typeof(cell_data[1]) != TYPE_INT
	):
		return _failure("core:invalid_cell")

	var cell := Vector2i(
		int(cell_data[0]),
		int(cell_data[1])
	)
	var map_rect := Rect2i(
		Vector2i.ZERO,
		Navigation.MAP_SIZE
	)

	if not map_rect.has_point(cell):
		return _failure("core:outside_map")

	if Navigation.blocked_cells().has(cell):
		return _failure("core:blocked_cell")

	return {
		"success": true,
		"reason_id": "core:ok",
		"building_id": Command.WOOD_WALL_ID,
		"cell": [cell.x, cell.y],
	}


static func validate_cancel_blueprint(command: Dictionary) -> Dictionary:
	return _validate_cell_command(
		command,
		Command.ACTION_CANCEL_BLUEPRINT
	)


static func validate_deliver_materials(command: Dictionary) -> Dictionary:
	return _validate_cell_command(
		command,
		Command.ACTION_DELIVER_MATERIALS
	)


static func validate_work_blueprint(command: Dictionary) -> Dictionary:
	return _validate_cell_command(
		command,
		Command.ACTION_WORK_BLUEPRINT
	)


static func validate_complete_blueprint(command: Dictionary) -> Dictionary:
	return _validate_cell_command(
		command,
		Command.ACTION_COMPLETE_BLUEPRINT
	)


static func _validate_cell_command(
	command: Dictionary,
	expected_action_id: String
) -> Dictionary:
	if String(command.get("actor_id", "")) != Command.PLAYER_ACTOR_ID:
		return _failure("core:unknown_actor")

	if String(command.get("action_id", "")) != expected_action_id:
		return _failure("core:unsupported_action")

	var cell_value: Variant = command.get("cell", [])
	if typeof(cell_value) != TYPE_ARRAY:
		return _failure("core:invalid_cell")

	var cell_data: Array = cell_value as Array
	if cell_data.size() != 2:
		return _failure("core:invalid_cell")

	if (
		typeof(cell_data[0]) != TYPE_INT
		or typeof(cell_data[1]) != TYPE_INT
	):
		return _failure("core:invalid_cell")

	var cell := Vector2i(
		int(cell_data[0]),
		int(cell_data[1])
	)
	var map_rect := Rect2i(
		Vector2i.ZERO,
		Navigation.MAP_SIZE
	)

	if not map_rect.has_point(cell):
		return _failure("core:outside_map")

	return {
		"success": true,
		"reason_id": "core:ok",
		"cell": [cell.x, cell.y],
	}


static func _failure(reason_id: String) -> Dictionary:
	return {
		"success": false,
		"reason_id": reason_id,
	}
