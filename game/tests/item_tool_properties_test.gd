extends SceneTree
const Content := preload("res://src/content/first_night_content.gd")
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var content := Content.new()
	check(content.has_method("item_tool_supports"), "Catalog exposes prepared capabilities")
	check(content.has_method("validate_item_tool"), "Tool fields have a validator")
	if failures > 0:
		finish()
		return
	content = Fixture.catalog()
	for pair: Array in [["axe", "chop", "shaft"], ["pickaxe", "mine", "shaft"], ["hoe", "till", "shaft"], ["bucket", "water", "carry"]]:
		for id: String in ["core:" + pair[0], "test:" + pair[0] + "_variant"]:
			check(content.call("item_tool_supports", id, pair[1]), id + " capability from data")
			check(content.call("item_tool_grip", id) == pair[2], id + " grip")
	check(content.call("item_tool_capacity", "core:bucket") == 2, "Literal old capacity 2")
	check(content.call("item_tool_capacity", "test:bucket_variant") == 4, "Variant capacity 4")
	check(content.call("item_tool_supports", "test:deprecated_axe", "clear_bush"), "Deprecated model retains capability")
	check(not content.call("item_tool_supports", "core:wood", "chop"), "Ordinary item is not a tool")
	var copy: Dictionary = content.call("item_tool_profile", "test:axe_variant")
	copy.actions.clear()
	check(content.call("item_tool_supports", "test:axe_variant", "chop"), "Profile isolation includes actions")
	var valid := {"id": "test:bad", "instance_based": true, "max_stack": 1, "tool": {"actions": ["water"], "grip": "carry", "water_capacity": 4}}
	for capacity: Variant in [0, 17, 2.5, "4", true, INF, NAN]:
		var bad := valid.duplicate(true)
		bad.tool.water_capacity = capacity
		var errors: Array = content.call("validate_item_tool", bad)
		check("test:bad" in str(errors) and "water_capacity" in str(errors), "Reject capacity " + str(capacity))
	for capacity: int in [1, 16]:
		valid.tool.water_capacity = capacity
		check(content.call("validate_item_tool", valid).is_empty(), "Inclusive capacity boundary")
	for tool: Variant in [null, [], {}, {"actions": ["mine", "till"], "grip": "shaft"}, {"actions": ["mine", "mine"], "grip": "shaft"}, {"actions": ["mine"], "grip": "carry"}, {"actions": ["mine"], "grip": "shaft", "water_capacity": 2}, {"actions": ["water"], "grip": "carry"}, {"actions": ["mine"], "grip": "shaft", "typo": 1}]:
		var bad := valid.duplicate(true)
		bad.tool = tool
		check(not content.call("validate_item_tool", bad).is_empty(), "Reject malformed tool " + str(tool))
	for field: String in ["instance_based", "max_stack"]:
		var bad := valid.duplicate(true)
		bad[field] = false if field == "instance_based" else 2
		check(not content.call("validate_item_tool", bad).is_empty(), "Physical singleton required " + field)
	for version: int in [3, 4]:
		check(not Content.validate_item_schema({"schema_version": version, "food_schema_version": 1, "items": [valid]}).is_empty(), "Legacy schemas reject new tool fields")
	check(not Content.validate_item_schema({"schema_version": 5, "food_schema_version": 1, "tool_schema_version": 3, "items": []}).is_empty(), "Unknown tool version rejected")
	check(Content.validate_item_schema(Fixture.data()).is_empty(), "Fixture schema valid")
	check(content.call("item_tool_supports", "core:axe", "clear_bush"), "Literal base axe clears bushes")
	check(not content.call("item_tool_supports", "test:axe_variant", "water") and not content.call("item_tool_supports", "missing:axe", "chop"), "Unsupported action and unknown ID have no capability")
	var deprec_bad := valid.duplicate(true)
	deprec_bad.deprecated = "true"
	check("deprecated" in str(content.call("validate_item_tool", deprec_bad)), "Deprecated flag is strict bool")
	var reordered := {"id": "test:reordered", "instance_based": true, "max_stack": 1, "tool": {"actions": ["clear_bush", "chop"], "grip": "shaft"}}
	check(content.call("validate_item_tool", reordered).is_empty(), "Action order is immaterial")
	var duplicate := Fixture.data()
	duplicate.items.append(duplicate.items[0].duplicate(true))
	check("duplicate id" in str(Content.validate_item_schema(duplicate)), "Duplicate tool IDs rejected before caching")
	finish()
func finish() -> void:
	print("ITEM_TOOL_PROPERTIES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
