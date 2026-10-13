extends SceneTree
const Catalog := preload("res://src/crafting/crafting_catalog.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ", label)
func run() -> void:
	var valid := {"id":"test:study","label_key":"test.study","station_type":"core:study_table","inputs":{"core:stone":1},"outputs":{},"work_minutes":6,"unlocks":["test:stone"]}
	check(Catalog.validate_definition(valid).is_empty(), "Research recipe may produce knowledge instead of an item")
	for field: String in ["inputs", "outputs", "unlocks"]:
		for value: Variant in [null, true, "typo", 2]:
			var bad := valid.duplicate(true)
			bad[field] = value
			check(field in str(Catalog.validate_definition(bad)), "Bad container diagnosed: " + field)
	for value: Variant in [0, -1, 2.5, "2", true, INF, NAN, 1441]:
		var bad := valid.duplicate(true)
		bad.work_minutes = value
		check("work_minutes" in str(Catalog.validate_definition(bad)), "Invalid work minutes diagnosed")
	var typo := valid.duplicate(true)
	for value: Variant in [null, true, 7, {}]:
		var bad := valid.duplicate(true)
		bad.id = value
		check("id: nonempty string required" in str(Catalog.validate_definition(bad)), "Malformed id diagnosed before String conversion")
	typo.require_unlock = "test:stone"
	check("require_unlock" in str(Catalog.validate_definition(typo)), "Unknown learning key names both owner and field")
	var duplicate := valid.duplicate(true)
	duplicate.unlocks = ["test:stone", "test:stone"]
	check("unlocks" in str(Catalog.validate_definition(duplicate)), "Duplicate unlock rejected")
	print("RECIPE_LEARNING_VALIDATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
