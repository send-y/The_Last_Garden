extends SceneTree
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
func run() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in Scenarios.definitions(): ids.append(String(entry.id))
	for obsolete: String in ["prepared_evening","morning_with_mira","mira_resting","mira_after_shared_wall","settlement_stress","stress_gather","stress_production"]:
		check(not ids.has(obsolete),"Historical scenario removed from regular menu: " + obsolete)
		check(not Scenarios.get_definition(StringName(obsolete)).is_empty(),"Historical regression entry remains accessible explicitly")
	for current: String in ["day_three","first_meeting_hungry","communal_production","missing_workbench"]:
		check(ids.has(current),"Current scenario is present: " + current)
		check(bool(Scenarios.build(StringName(current)).get("success",false)),"Current scenario loads safely: " + current)
	var fresh: Dictionary = Scenarios.build(&"fresh_start")
	check(fresh.get("state",{}) == World.new(World.create_new_game_state()).export_state(),"Fresh lab start matches ordinary new game")
	var day_three: Dictionary = Scenarios.build(&"day_three")
	if bool(day_three.get("success",false)):
		var sim = day_three.simulation
		check(sim.get_day() == 3 and sim.state.storage_zones.back().cells.size() == 9,"Synthetic day-three scenario has a world warehouse of three by three cells")
		check(sim.state != Scenarios.build(&"player_checkpoint").get("state",{}),"Synthetic start is distinguished from actual archived playthrough")
	print("PACKAGE_D_LAB: %d failures" % failures)
	quit(0 if failures == 0 else 1)
