extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var path := "res://src/characters/npc_preferences.gd"
	if not FileAccess.file_exists(path):
		push_error("Missing personality influence")
		quit(1)
		return
	var preferences = load(path)
	var grower := {"skills":{"water":3,"build":1},"interests":["water"],"value_ids":["core:care"],"habit_ids":[]}
	var builder := {"skills":{"water":1,"build":3},"interests":["build"],"value_ids":["core:order"],"habit_ids":[]}
	check(preferences.score(grower,{"kind":"water"},{}) > preferences.score(grower,{"kind":"build"},{}), "Grower priorities")
	check(preferences.score(builder,{"kind":"build"},{}) > preferences.score(builder,{"kind":"water"},{}), "Builder priorities")
	check(preferences.score(builder,{"kind":"build"},{"possible":false}) == 0, "Preference cannot authorize impossible work")
	var explanation: Dictionary = preferences.explain(grower,{"kind":"water"})
	check(explanation.fact_id == "aspiration_id", "Explanation matches actual interest")
	check(preferences.explain({}, {"kind":"build"}).fact_id == "", "No invented motive for authored NPC")
	check(preferences.score(grower,{"building_id":"core:table"},{}) > preferences.score(grower,{"building_id":"core:torch"},{}),"Care influences home furnishing priorities")
	check(preferences.score(builder,{"building_id":"core:torch"},{}) > preferences.score(builder,{"building_id":"core:table"},{}),"Order influences home furnishing priorities")
	if failures == 0: print("PASS: personality weights, opposing priorities and truthful explanations")
	quit(0 if failures == 0 else 1)
