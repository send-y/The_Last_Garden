extends "res://src/dev/mechanics_lab.gd"

func _scenario_from_command_line() -> StringName:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lab-scenario="):
			return super._scenario_from_command_line()
	return Scenarios.SETTLEMENT_STRESS
