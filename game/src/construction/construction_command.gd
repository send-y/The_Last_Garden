class_name ConstructionCommand
extends RefCounted

const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_PLACE_BLUEPRINT: String = "core:place_blueprint"
const ACTION_CANCEL_BLUEPRINT: String = "core:cancel_blueprint"
const ACTION_DELIVER_MATERIALS: String = "core:deliver_blueprint_materials"
const ACTION_WORK_BLUEPRINT: String = "core:work_blueprint"
const ACTION_COMPLETE_BLUEPRINT: String = "core:complete_blueprint"
const WOOD_WALL_ID: String = "core:wood_wall"


static func place_wall_blueprint(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_PLACE_BLUEPRINT,
		"building_id": WOOD_WALL_ID,
		"cell": [cell.x, cell.y],
	}


static func cancel_blueprint(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_CANCEL_BLUEPRINT,
		"cell": [cell.x, cell.y],
	}


static func deliver_blueprint_materials(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_DELIVER_MATERIALS,
		"cell": [cell.x, cell.y],
	}


static func work_blueprint(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_WORK_BLUEPRINT,
		"cell": [cell.x, cell.y],
	}


static func complete_blueprint(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_COMPLETE_BLUEPRINT,
		"cell": [cell.x, cell.y],
	}
