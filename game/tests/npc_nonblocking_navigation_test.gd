extends SceneTree

const Autonomy := preload("res://src/simulation/npc_autonomy.gd")
const Pathfinder := preload("res://src/simulation/local_grid_pathfinder.gd")
class TestCatalog extends RefCounted:
	func get_definitions() -> Array[Dictionary]:
		return [{"id":"first"}, {"id":"second"}, {"id":"third"}]
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var ai := Autonomy.new(TestCatalog.new())
	var blocked: Array[Vector2i] = []
	for x: int in [0, 2]:
		for y: int in range(5): blocked.append(Vector2i(x, y))
	ai._pathfinder = Pathfinder.new(Vector2i(3, 5), 32, blocked)
	var npcs := {}
	for index: int in range(3):
		var id: String = ["first", "second", "third"][index]
		npcs[id] = {"id":id, "active":true, "position":[48.0, 144.0-index*32], "needs":{"hunger":100.0,"energy":100.0}, "activity_id":"core:morning"}
	var work := {"first":{"target_cell":[1,0], "travel_activity":"core:work_travel", "arrival_activity":"core:work_work"}}
	ai.advance_minutes(npcs, 660, 661, Vector2(48,48), [], {}, work)
	check(npcs.first.position == [48.0,112.0], "Resident must pass through another resident in a one-cell corridor")
	npcs.first.position = [48.0,80.0]
	ai.advance_minutes(npcs, 661, 662, Vector2(48,48), [], {}, work)
	check(npcs.first.position == [48.0,48.0], "Player in corridor must not block resident passage")
	ai.advance_minutes(npcs, 662, 663, Vector2(48,16), [], {}, work)
	check(npcs.first.position == [48.0,16.0], "Player occupying the destination must not block arrival")
	check(not ai.is_cell_walkable(Vector2i(0,2)), "Static walls remain blocked in NPC navigation")
	check(ai.find_temporary_rest_cell(Vector2i(1,0),Vector2i(1,4),Vector2i(1,2)) == Vector2i(1,0), "Player must not make temporary rest unreachable")
	check(ai.find_construction_work_cell(Vector2i(2,2),Vector2i(1,4),Vector2i(1,2)) == Vector2i(1,2), "Player must not prevent selection of a reachable work position")
	print("NPC_NAVIGATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
