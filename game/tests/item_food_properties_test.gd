extends SceneTree

const Content := preload("res://src/content/first_night_content.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", description)

func _run() -> void:
	var content = Content.new()
	check(content.has_method("item_food_profile"), "Item catalog provides food properties")
	check(content.has_method("validate_item_food"), "Item food has an explicit validator")
	check(content.has_method("validate_item_schema"), "Item and food versions are validated")
	if failures > 0:
		finish()
		return
	var expected := {
		"core:food": {"satiety": 14, "energy": 5},
		"core:carrot": {"satiety": 28, "energy": 12},
		"core:cabbage": {"satiety": 45, "energy": 25},
		"core:potato": {"satiety": 30, "energy": 10},
		"core:strawberry": {"satiety": 20, "energy": 8},
	}
	for id: String in expected:
		check(content.call("item_food_profile", id) == expected[id], "Preserve literal balance for " + id)
	check(content.call("item_food_profile", "food") == expected["core:food"], "Legacy food ID still resolves")
	for id: String in ["missing:food", "core:wood", "core:carrot_seed"]:
		check(content.call("item_food_profile", id).is_empty(), "Non-food has no capability: " + id)
	var isolated: Dictionary = content.call("item_food_profile", "core:food")
	isolated.energy = 99
	check(content.call("item_food_profile", "core:food") == expected["core:food"], "Callers cannot mutate catalog food")
	check(content.call("validate_item_food", {"id": "test:empty"}).is_empty(), "Food is optional")
	for food: Variant in [null, [], {"satiety": 0, "energy": 0}, {"satiety": -1, "energy": 5},
		{"satiety": 101, "energy": 5}, {"satiety": 17.5, "energy": 0},
		{"satiety": "17", "energy": 0}, {"satiety": true, "energy": 0},
		{"satiety": INF, "energy": 0}, {"satiety": NAN, "energy": 0},
		{"satiety": 17}, {"energy": 5}, {"satiety": 17, "energy": 0, "energi": 5}]:
		var errors: Array = content.call("validate_item_food", {"id": "test:bad", "food": food})
		check(not errors.is_empty() and "test:bad" in str(errors) and "food" in str(errors), "Reject malformed food with record/field diagnostics: " + str(food))
	var typo: Array = content.call("validate_item_food", {"id": "test:typo", "food": {"satiety": 17, "energy": 0, "energi": 5}})
	check("energi" in str(typo) and "test:typo" in str(typo), "Unknown food keys identify the typo")
	check(content.call("validate_item_food", {"id": "test:valid", "food": {"satiety": 17, "energy": 0}}).is_empty(), "Satiety-only nutrition is valid")
	check(content.call("validate_item_food", {"id": "test:valid", "food": {"satiety": 0, "energy": 100}}).is_empty(), "Energy-only nutrition and inclusive maximum are valid")
	for raw: Dictionary in [{"schema_version": 99}, {"schema_version": 4, "food_schema_version": 99},
		{"schema_version": 4}, {"schema_version": 3, "items": [{"id": "test:old", "food": {"satiety": 1, "energy": 1}}]}]:
		check(not content.call("validate_item_schema", raw).is_empty(), "Unsupported/missing schema is rejected: " + str(raw))
	check(content.call("validate_item_schema", {"schema_version": 3, "items": []}).is_empty(), "Legacy catalog without food remains readable")
	for replacement: Dictionary in [{"id": "test:duplicate"}, {"id": "test:duplicate", "food": {"satiety": 17, "energi": 5}}]:
		var duplicate_errors: Array = content.call("validate_item_schema", {
			"schema_version": 4, "food_schema_version": 1, "items": [
				{"id": "test:duplicate", "food": {"satiety": 17, "energy": 0}}, replacement,
			],
		})
		check("test:duplicate" in str(duplicate_errors) and "duplicate id" in str(duplicate_errors), "Reject duplicate ID before missing/invalid food can retain an earlier profile")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.ITEMS_PATH))
	var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/item_food_additions.json"))
	data.merge({"schema_version": additions.schema_version, "food_schema_version": additions.food_schema_version}, true)
	data.items.append_array(additions.items)
	var path := "user://item_food_properties_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var script: Variant = Content
	var expanded = script.new(path)
	check(expanded.call("item_food_profile", "test:ration") == {"satiety": 17, "energy": 0}, "New food works only through catalog data")
	data.items[-1].food.satiety = 55
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(expanded.call("item_food_profile", "test:ration").satiety == 17, "Hot query does not reparse changed files")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	finish()

func finish() -> void:
	print("ITEM_FOOD_PROPERTIES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
