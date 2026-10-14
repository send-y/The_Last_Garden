extends RefCounted

# Opt-in diagnostic spans. No authoritative simulation state is stored here.
static var enabled := false
static var spans: Dictionary = {}
static var stack: Array[Dictionary] = []
static var counters: Dictionary = {}
static var slow_paths: Array[Dictionary] = []
static var motion: Dictionary = {}
static var slow_frames: Array[Dictionary] = []

static func reset() -> void:
	spans.clear()
	stack.clear()
	counters.clear()
	slow_paths.clear()
	motion.clear()
	slow_frames.clear()

static func motion_sample(id: String, moving: bool, displacement: float, delta: float) -> void:
	if not enabled: return
	if not motion.has(id): motion[id] = {"samples":0,"moving_seconds":0.0,"waiting_while_moving_seconds":0.0,"max_wait_seconds":0.0,"current_wait_seconds":0.0}
	var row: Dictionary = motion[id]
	row.samples += 1
	if moving:
		row.moving_seconds += delta
		if displacement <= 0.00001:
			row.waiting_while_moving_seconds += delta
			row.current_wait_seconds += delta
			row.max_wait_seconds = maxf(row.max_wait_seconds,row.current_wait_seconds)
		else: row.current_wait_seconds = 0.0
	else: row.current_wait_seconds = 0.0

static func frame_sample(ms: float, minute: int) -> void:
	if not enabled or ms <= 50: return
	if slow_frames.size() < 100: slow_frames.append({"ms":ms,"elapsed_game_minute":minute})

static func begin(label: String) -> int:
	if not enabled: return 0
	stack.append({"label": label, "start": Time.get_ticks_usec(), "child_us": 0})
	return stack.size()

static func end(token: int) -> void:
	if token == 0: return
	assert(stack.size() == token, "Diagnostic spans must close in nesting order")
	var entry: Dictionary = stack.pop_back()
	var duration: int = Time.get_ticks_usec() - int(entry.start)
	var label: String = entry.label
	if not spans.has(label): spans[label] = {"calls": 0, "inclusive_us": 0, "self_us": 0, "maximum_us": 0}
	var row: Dictionary = spans[label]
	row.calls += 1
	row.inclusive_us += duration
	row.self_us += maxi(0, duration - int(entry.child_us))
	row.maximum_us = maxi(int(row.maximum_us), duration)
	if not stack.is_empty(): stack.back().child_us += duration

static func path_sample(from: Vector2i, to: Vector2i, size: int, elapsed_us: int) -> void:
	if not enabled: return
	counters["astar_calls"] = int(counters.get("astar_calls", 0)) + 1
	var key := "astar_no_route" if size == 0 else "astar_route_found"
	counters[key] = int(counters.get(key, 0)) + 1
	if elapsed_us < 1000: return
	slow_paths.append({"from": [from.x, from.y], "to": [to.x, to.y], "path_cells": size,
		"us": elapsed_us, "caller": String(stack.back().label) if not stack.is_empty() else "outside_span"})
	slow_paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.us) > int(b.us))
	if slow_paths.size() > 20: slow_paths.resize(20)

static func snapshot() -> Dictionary:
	assert(stack.is_empty(), "Unclosed diagnostic span")
	return {"spans": spans.duplicate(true), "counters": counters.duplicate(), "slow_paths": slow_paths.duplicate(true),"motion":motion.duplicate(true),"slow_frames":slow_frames.duplicate(true)}
