class_name CraftingCommand
extends RefCounted

const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_START_PROJECT: String = "core:start_crafting_project"
const ACTION_WORK_PROJECT: String = "core:work_crafting_project"


static func start_project(cell: Vector2i, recipe_id: String) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_START_PROJECT,
		"cell": [cell.x, cell.y],
		"recipe_id": recipe_id,
	}


static func work_project(cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_WORK_PROJECT,
		"cell": [cell.x, cell.y],
	}
