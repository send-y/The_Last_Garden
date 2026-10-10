extends "res://src/simulation/first_night_simulation.gd"

var target_resolution_count: int = 0

func _resolve_interaction_target(target_id: String) -> Dictionary:
	target_resolution_count += 1
	return super._resolve_interaction_target(target_id)
