extends "res://src/furniture/furniture_system.gd"

func approach(sim, id: String, seat: Dictionary) -> Vector2i:
	var chair := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
	var source: Vector2 = sim.get_player_position() if id == "core:player" else sim.get_npc_position(id,Vector2.ZERO)
	var from: Vector2i = sim._world_position_to_cell(source)
	if from == chair and owner(sim,seat.chair_cell) == id:
		return chair
	var blocker: Vector2i = INVALID if id == "core:player" else sim._world_position_to_cell(sim.get_player_position())
	var best := INVALID
	var distance := 1000000
	for direction: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
		var target := chair + direction
		if target == blocker or not sim.npc_autonomy.can_reach(from,target,blocker):
			continue
		var occupied := false
		for other: String in sim.state.npcs:
			if other != id and bool(sim.state.npcs[other].get("active",false)) and sim._world_position_to_cell(sim.get_npc_position(other,Vector2.ZERO)) == target:
				occupied = true
		if occupied:
			continue
		var cost := absi(from.x-target.x) + absi(from.y-target.y)
		if cost < distance:
			best = target
			distance = cost
	return best

func find_seat(sim, id: String, meal: bool, at: Vector2i = INVALID, evening: bool = false) -> Dictionary:
	refresh(sim)
	var source: Vector2 = sim.get_player_position() if id == "core:player" else sim.get_npc_position(id,Vector2.ZERO)
	var best: Dictionary = {}
	var score := INF
	for seat: Dictionary in _seats:
		if meal and seat.table_cell.is_empty():
			continue
		if at != INVALID and seat.chair_cell != [at.x,at.y] and seat.table_cell != [at.x,at.y]:
			continue
		var occupied := owner(sim,seat.chair_cell)
		if not occupied.is_empty() and occupied != id:
			continue
		var target := approach(sim,id,seat)
		if target == INVALID:
			continue
		var distance := source.distance_to(Content.cell_center(target.x,target.y))
		# A distant dining area must not make a starving resident cross the map.
		if id != "core:player" and distance > MAX_SEAT_DISTANCE:
			continue
		var chair := Vector2i(int(seat.chair_cell[0]),int(seat.chair_cell[1]))
		var lit := lighting.has_artificial_light(sim,chair) if evening else lighting.is_lit(sim,chair)
		var current := distance + (0 if lit else 8 * Content.CELL_SIZE)
		if current < score:
			score = current
			best = seat.duplicate(true)
			best.target_cell = [target.x,target.y]
	return best

