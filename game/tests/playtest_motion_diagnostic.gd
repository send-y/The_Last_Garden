extends Node
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	Session.set_mechanics_lab_active(true)
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
	var report := {"scenario":"ordinary-three-residents","seconds":12,"frames":frames,"peak_ms":peak,"game_minutes":Session.simulation.get_elapsed_game_minutes()-start_minute,"trace":Trace.snapshot(),"limitations":"Short local sample, no performance guarantee or thirty-resident stress run."}
	var path := ProjectSettings.globalize_path("res://../artifacts/playtest-fixes-2026-10-14/motion-diagnostic.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PLAYTEST_MOTION_DIAGNOSTIC: PASS frames=",frames," game_minutes=",report.game_minutes," peak_ms=",peak)
	get_tree().quit(0)
