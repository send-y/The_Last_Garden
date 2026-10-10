extends Node

const MainScene: PackedScene = preload("res://src/main/main.tscn")
const Content := preload("res://src/content/first_night_content.gd")
const GRID_STEP: float = 8.0
const ROUTE_PADDING: float = 96.0
const MAX_GRID_POINTS: int = 4096
const MAX_PATH_POINTS: int = 512

var _player: CharacterBody2D
var _player_shape: CollisionShape2D
var _space: PhysicsDirectSpaceState2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# Create the ordinary start, then prevent this test from touching player saves.
	Session.set_mechanics_lab_active(false)
	Session._start_new_simulation()
	if not Session.set_mechanics_lab_active(true):
		_fail("could not isolate the ordinary new game from autosave")
		return
	Session.set_process(false)
	var main := MainScene.instantiate()
	add_child(main)
	_player = main.get_node("Player") as CharacterBody2D
	_player_shape = _player.get_node("CollisionShape2D") as CollisionShape2D
	_player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = main.get_world_2d().direct_space_state
	if _player_shape.shape == null or _player.collision_mask != 2:
		_fail("ordinary player must retain its real collision shape and world mask")
		return
	var spawn := _player.global_position
	if not spawn.is_equal_approx(Session.get_player_position()):
		_fail("ordinary scene player did not start at the simulation spawn")
		return
	var trees := Session.get_surface_trees()
	var boulders := Session.get_surface_boulders()
	if trees.is_empty() or boulders.is_empty():
		_fail("ordinary new game must contain generated trees and boulders")
		return
	var world := main.get_node("World") as FirstNightWorld
	for target: Dictionary in [trees[0], boulders[0]]:
		# Both independent routes start at the real spawn; no waypoint teleports.
		_player.global_position = spawn
		_player.velocity = Vector2.ZERO
		Session.set_player_position(spawn)
		await get_tree().physics_frame
		var target_id := String(target.get("id", ""))
		if not _has_registered_resource_blocker(world, target_id):
			_fail("generated resource %s has no registered world collider" % target_id)
			return
		var target_position: Vector2 = target.get("position", Vector2.ZERO)
		var path := _find_physical_path(spawn, target_position)
		if path.is_empty() or path.size() > MAX_PATH_POINTS:
			_fail("no bounded physical route from spawn to %s" % target_id)
			return
		for waypoint: Vector2 in path:
			var motion := waypoint - _player.global_position
			if motion.length() > GRID_STEP + 0.1:
				_fail("physical route contains an oversized movement step")
				return
			if motion.length() <= 0.01:
				continue
			var collision := _player.move_and_collide(motion)
			if collision != null or _player.global_position.distance_to(waypoint) > 0.1:
				_fail("actual player movement collided on the route to %s at %s" % [target_id, waypoint])
				return
			Session.set_player_position(_player.global_position)
		if _player.global_position.distance_to(target_position) > Content.INTERACTION_RANGE:
			_fail("physical route did not reach interaction distance of %s" % target_id)
			return
	print("PASS: ordinary player physically reaches starter tree and boulder without crossing colliders")
	get_tree().quit(0)


func _find_physical_path(spawn: Vector2, target: Vector2) -> PackedVector2Array:
	var first := Vector2i(
		floori((minf(spawn.x, target.x) - ROUTE_PADDING) / GRID_STEP),
		floori((minf(spawn.y, target.y) - ROUTE_PADDING) / GRID_STEP)
	)
	var last := Vector2i(
		ceili((maxf(spawn.x, target.x) + ROUTE_PADDING) / GRID_STEP),
		ceili((maxf(spawn.y, target.y) + ROUTE_PADDING) / GRID_STEP)
	)
	var bounds := Rect2i(first, last - first + Vector2i.ONE)
	if bounds.size.x * bounds.size.y > MAX_GRID_POINTS:
		return PackedVector2Array()
	var grid := AStarGrid2D.new()
	grid.region = bounds
	grid.cell_size = Vector2.ONE * GRID_STEP
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	var goals: Array[Vector2i] = []
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			var position := Vector2(cell) * GRID_STEP
			var clear := _player_fits_at(position)
			grid.set_point_solid(cell, not clear)
			if clear and position.distance_to(target) <= Content.INTERACTION_RANGE:
				goals.append(cell)
	var start := Vector2i(roundi(spawn.x / GRID_STEP), roundi(spawn.y / GRID_STEP))
	if grid.is_point_solid(start):
		return PackedVector2Array()
	goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) * GRID_STEP).distance_squared_to(spawn) < (Vector2(b) * GRID_STEP).distance_squared_to(spawn)
	)
	for goal: Vector2i in goals:
		var path := grid.get_point_path(start, goal)
		if not path.is_empty():
			return path
	return PackedVector2Array()


func _player_fits_at(position: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _player_shape.shape
	query.transform = _player_shape.global_transform
	query.transform.origin += position - _player.global_position
	query.margin = 0.08
	query.collision_mask = _player.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_player.get_rid()]
	return _space.intersect_shape(query, 1).is_empty()


func _has_registered_resource_blocker(world: FirstNightWorld, target_id: String) -> bool:
	for view: Node in world.get_children():
		if not view is InteractableView or (view as InteractableView).object_id != target_id:
			continue
		for child: Node in view.get_children():
			if not child is StaticBody2D or (child as StaticBody2D).collision_layer != 2:
				continue
			for shape_node: Node in child.get_children():
				if not shape_node is CollisionShape2D:
					continue
				var query := PhysicsPointQueryParameters2D.new()
				query.position = (shape_node as CollisionShape2D).global_position
				query.collision_mask = 2
				query.collide_with_bodies = true
				query.collide_with_areas = false
				for hit: Dictionary in _space.intersect_point(query):
					if hit.get("collider") == child:
						return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
