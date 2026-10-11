extends SceneTree

const Trace := preload("res://src/dev/diagnostic_trace.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Pathfinder := preload("res://src/simulation/local_grid_pathfinder.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original := World.new()
	var initial := original.export_state()
	var plain := World.new(initial)
	var traced := World.new(initial)
	Trace.reset()
	Trace.enabled = false
	plain.advance_minutes(2)
	check(Trace.snapshot().spans.is_empty(), "Normal simulation does not collect diagnostic data")
	Trace.enabled = true
	traced.advance_minutes(2)
	Trace.enabled = false
	check(plain.export_state() == traced.export_state(), "Opt-in timers preserve authoritative simulation state")
	var report := Trace.snapshot()
	check(int(report.spans["clock.total"].calls) == 1, "Clock span encloses the whole advance request")
	check(int(report.spans["clock.player_needs"].calls) == 2, "Each minute is counted separately")
	var inclusive: int = report.spans["clock.total"].inclusive_us
	var self_total := 0
	for row: Dictionary in report.spans.values():
		check(int(row.self_us) >= 0 and int(row.inclusive_us) >= int(row.self_us), "Nested timings remain valid")
		self_total += int(row.self_us)
	check(self_total == inclusive, "Exclusive times partition the measured clock without double counting")
	Trace.reset()
	Trace.enabled = true
	var path := Pathfinder.new(Vector2i(8, 8), 32, [])
	check(path.next_cell(Vector2i(0, 0), Vector2i(7, 7)) != Vector2i.ZERO, "Navigation still returns a real next step")
	Trace.enabled = false
	check(int(Trace.snapshot().counters.astar_calls) == 1, "Native path searches are counted")
	print("DIAGNOSTIC_TRACE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
