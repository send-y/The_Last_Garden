extends Node
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
@export var sample_time_scale: float = 1.0
func _ready() -> void: call_deferred("run")
func run() -> void:
	Session.set_mechanics_lab_active(true)
	var previous_scale := Engine.time_scale
	Engine.time_scale = sample_time_scale
	var scenario := Scenarios.build(Scenarios.GENERATED_RESIDENTS)
	Session._replace_simulation(scenario.simulation.export_state())
	Session.set_paused(false,false)
	add_child(preload("res://src/main/main.tscn").instantiate())
	for frame: int in range(4): await get_tree().process_frame
	Trace.reset()
	Trace.enabled = true
	var started := Time.get_ticks_usec()
	var previous := started
	var start_minute: int = Session.simulation.get_elapsed_game_minutes()
	var frames := 0
	var peak := 0.0
	while Time.get_ticks_usec()-started < 12000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now-previous)/1000.0
		peak = maxf(peak,ms)
		Trace.frame_sample(ms,Session.simulation.get_elapsed_game_minutes())
		previous = now
		frames += 1
	Trace.enabled = false
	var report := {"scenario":"ordinary-three-residents","time_scale":sample_time_scale,"seconds":12,"frames":frames,"peak_ms":peak,"game_minutes":Session.simulation.get_elapsed_game_minutes()-start_minute,"trace":Trace.snapshot(),"limitations":"Short local sample, no performance guarantee or thirty-resident stress run."}
	var path := ProjectSettings.globalize_path("res://../artifacts/playtest-fixes-2026-10-14/step-motion-x%d.json" % int(sample_time_scale))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	Engine.time_scale = previous_scale
	var longest := 0.0
	var moving_seconds := 0.0
	for row: Dictionary in report.trace.motion.values():
		longest = maxf(longest,float(row.max_wait_seconds))
		moving_seconds += float(row.moving_seconds)
	var valid: bool = longest <= 0.05 and moving_seconds > 1.0 and int(report.game_minutes) > 0
	print("PLAYTEST_MOTION_DIAGNOSTIC: ","PASS" if valid else "FAIL"," frames=",frames," game_minutes=",report.game_minutes," peak_ms=",peak," max_idle_ms=",longest*1000.0)
	get_tree().quit(0 if valid else 1)
