extends SceneTree
const Stress := preload("res://src/dev/settlement_stress_scenario.gd")
var output := ""
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--output="): output = value.trim_prefix("--output=")
	assert(not output.is_empty())
	var fixture: Dictionary = Stress.build(30)
	assert(fixture.success)
	var sim = fixture.simulation
	var result := {"initial":sim.export_state()}
	sim.advance_minutes(1)
	Stress.replenish(sim)
	result["minute_1"] = sim.export_state()
	sim.advance_minutes(1)
	Stress.replenish(sim)
	result["minute_2"] = sim.export_state()
	var file := FileAccess.open(output,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result))
	file.close()
	print("STRUCTURE_BASELINE_SAVED "+output)
	quit()
