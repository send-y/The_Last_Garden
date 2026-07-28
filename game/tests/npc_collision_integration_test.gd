extends Node

const MainScene := preload("res://src/main/main.tscn")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")


func _ready() -> void:
	Session.set_mechanics_lab_active(true)
	var fresh_result: Dictionary = LabScenarios.build(LabScenarios.FRESH_START)
	Session.apply_debug_state(fresh_result["state"] as Dictionary, "collision test", false)
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().physics_frame

	var world: Node = main.get_node("World")
	var mira: InteractableView
	for child: Node in world.get_children():
		if child is InteractableView and (child as InteractableView).object_id == "core:first_neighbor":
			mira = child as InteractableView
			break
	if mira == null:
		push_error("Mira view not found.")
		get_tree().quit(1)
		return

	var hidden_position: Vector2 = mira.global_position
	var hidden_hits: Array[Dictionary] = _body_hits(main, hidden_position)
	var morning_result: Dictionary = LabScenarios.build(LabScenarios.MORNING_WITH_MIRA)
	Session.apply_debug_state(morning_result["state"] as Dictionary, "collision test", false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	Session.advance_debug_minutes(119)
	await get_tree().physics_frame
	var old_position: Vector2 = mira.global_position
	Session.advance_debug_minutes(1)
	await get_tree().create_timer(2.0).timeout
	await get_tree().physics_frame
	var new_position: Vector2 = mira.global_position

	var old_hits: Array[Dictionary] = _body_hits(main, old_position)
	var new_hits: Array[Dictionary] = _body_hits(main, new_position)
	var passed: bool = (
		hidden_hits.is_empty()
		and old_hits.is_empty()
		and new_hits.size() == 1
	)
	if passed:
		print("PASS: hidden NPC collision is disabled and follows visible Mira")
		get_tree().quit(0)
		return

	push_error(
		"NPC collision mismatch: hidden=%d old=%d new=%d" % [
			hidden_hits.size(),
			old_hits.size(),
			new_hits.size(),
		]
	)
	get_tree().quit(1)


func _body_hits(main: Node2D, point: Vector2) -> Array[Dictionary]:
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = point
	parameters.collision_mask = 2
	parameters.collide_with_areas = false
	parameters.collide_with_bodies = true
	return main.get_world_2d().direct_space_state.intersect_point(parameters)
