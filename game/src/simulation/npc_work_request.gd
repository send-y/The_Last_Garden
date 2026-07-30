extends RefCounted

const PLAYER_ACTOR_ID: String = "core:player"
const ACTION_REQUEST_CONSTRUCTION_HELP: String = "core:request_construction_help"
const HELP_BUILD_COMMITMENT_ID: String = "core:help_build"


static func request_construction_help(npc_id: String, target_cell: Vector2i) -> Dictionary:
	return {
		"actor_id": PLAYER_ACTOR_ID,
		"action_id": ACTION_REQUEST_CONSTRUCTION_HELP,
		"npc_id": npc_id,
		"target_cell": [target_cell.x, target_cell.y],
	}
