extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const LabScenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Session.set_mechanics_lab_active(true)
	var scenario: Dictionary = LabScenarios.build(
		LabScenarios.SURFACE_BOULDERS
	)
	if not bool(scenario.get("success", false)):
		_fail("could not build surface boulders scenario")
		return
	if not Session.apply_debug_state(
		scenario.get("state", {}) as Dictionary,
		"boulder depth integration test",
		false
	):
		_fail("could not install surface boulders scenario")
		return

	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Session.apply_debug_state(
		scenario.get("state", {}) as Dictionary,
		"boulder view refresh check",
		false
	)
	await get_tree().physics_frame

	var world := main.get_node("World") as FirstNightWorld
	var boulder: InteractableView
	for child: Node in world.get_children():
		if (
			child is InteractableView
			and (child as InteractableView).presentation_id == "surface_boulder"
		):
			boulder = child as InteractableView
			break
	if boulder == null:
		_fail("surface boulder view not found")
		return

	var blocking_body: StaticBody2D
	for child: Node in boulder.get_children():
		if child is StaticBody2D:
			blocking_body = child as StaticBody2D
			break
	if blocking_body == null or blocking_body.collision_layer != 2:
		_fail("boulder does not block player movement")
		return
	if blocking_body.get_child_count() != 1:
		_fail("boulder view was reconfigured with duplicate collision nodes")
		return
	var collision := blocking_body.get_child(0) as CollisionShape2D
	var shape := collision.shape as RectangleShape2D
	if (
		shape == null
		or shape.size != Vector2(64.0, 18.0)
		or collision.position != Vector2(0.0, 22.0)
	):
		_fail("boulder blocker must use the shallow lower hitbox")
		return

	var point_parameters := PhysicsPointQueryParameters2D.new()
	point_parameters.collision_mask = 2
	point_parameters.collide_with_areas = false
	point_parameters.collide_with_bodies = true
	point_parameters.position = boulder.global_position + Vector2(0.0, 22.0)
	var blocker_hits: Array[Dictionary] = (
		main.get_world_2d().direct_space_state.intersect_point(point_parameters)
	)
	if blocker_hits.is_empty():
		_fail("physics query did not find the boulder body")
		return
	var matching_views: int = 0
	for child: Node in world.get_children():
		if (
			child is InteractableView
			and (child as InteractableView).object_id == boulder.object_id
		):
			matching_views += 1
	if matching_views != 1:
		_fail("world refresh duplicated the boulder view")
		return

	boulder.update_boulder_depth_order(boulder.global_position.y + 21.0)
	if (
		boulder.z_as_relative
		or boulder.z_index != PlayerController.DEPTH_SORT_Z_INDEX + 1
		or (_get_player(main).z_index != PlayerController.DEPTH_SORT_Z_INDEX)
	):
		_fail("boulder should draw in front when player passes above")
		return
	boulder.update_boulder_depth_order(boulder.global_position.y + 23.0)
	if boulder.z_index != PlayerController.DEPTH_SORT_Z_INDEX - 1:
		_fail("player should draw in front when passing below")
		return

	Session.set_player_position(boulder.global_position)
	for _minute: int in range(Session.get_resource_work_required(boulder.object_id)):
		Session.execute_resource_work("core:player", boulder.object_id)
	if boulder.visible or blocking_body.collision_layer != 0:
		_fail("depleted invisible boulder must not keep blocking the player")
		return

	print("PASS: boulder lower collision and player depth sorting")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FAIL: %s" % message)
	get_tree().quit(1)


func _get_player(main: Node) -> PlayerController:
	return main.get_node("Player") as PlayerController
