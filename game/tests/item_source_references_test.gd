extends SceneTree
const Content := preload("res://src/content/first_night_content.gd")
const Fixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Crafting := preload("res://src/crafting/crafting_catalog.gd")
const Crops := preload("res://src/farming/crop_catalog.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var content := Content.new()
	check(content.has_method("validate_item_references"), "Sources validate references before activation")
	var sim := World.new()
	check(sim.has_method("get_item_load_diagnostics"), "Structured load diagnostics")
	if failures > 0:
		finish()
		return
	content = Fixture.catalog()
	for field: String in ["inputs", "outputs", "collect_rules.item_id", "seed_id", "product_id", "starter", "pool"]:
		for id: String in ["test:missing", "test:deprecated_axe"]:
			var refs: Array[Dictionary] = [{"source_path": "test.json", "owner_id": "test:source", "field": field, "item_id": id}]
			var errors: Array = content.call("validate_item_references", refs)
			check(errors.size() == 1 and field in str(errors) and id in str(errors) and "test.json" in str(errors) and "test:source" in str(errors), "Reference diagnostics " + field + id)
		var valid_refs: Array[Dictionary] = [{"source_path": "test.json", "owner_id": "source", "field": field, "item_id": "test:axe_variant"}]
		check(content.call("validate_item_references", valid_refs).is_empty(), "Active item allowed " + field)
	var state := World.create_new_game_state()
	state.item_instances.append_array([
		{"item_id": "test:missing"}, {"item_id": "test:missing"}, {"item_id": "core:wood"},
		{"item_id": "test:deprecated_axe", "instance_id": "core:item_instance_000009", "state": {}, "location": {"kind": "inventory", "id": ""}},
	])
	sim = Fixture.world(state)
	var diagnostics: Array = sim.call("get_item_load_diagnostics")
	check(diagnostics == [{"id": "test:missing", "count": 2, "reason": "unknown_item_definition"}, {"id": "core:wood", "count": 1, "reason": "not_instance_based"}], "Stable aggregated physical-record diagnostics")
	diagnostics[0].count = 999
	check(sim.call("get_item_load_diagnostics")[0].count == 2, "Diagnostics isolation")
	check(sim.get_item_instance("core:item_instance_000009").item_id == "test:deprecated_axe", "Saved deprecated model survives")
	check(not sim.export_state().has("item_load_diagnostics"), "No diagnostics in save")
	sim._normalize_item_instances(sim.state.item_instances, {})
	check(sim.call("get_item_load_diagnostics").is_empty(), "Each load clears diagnostics")
	var formatter = load("res://src/items/item_load_diagnostics.gd")
	var warning: String = formatter.warning_text({"id": "test:missing", "count": 2, "reason": "unknown_item_definition"})
	check("test:missing" in warning and "2" in warning and "unknown_item_definition" in warning, "Warning formatter uses structured data")
	# Negative hooks retain errors as data; each loader also reports them in the log.
	var blocked := Fixture.catalog(["core:wood", "core:carrot_seed", "core:food", "core:axe"])
	var crafting_script: Variant = Crafting
	var recipes = crafting_script.new(blocked)
	check(recipes.recipes_for_station("core:workbench").is_empty() and recipes.get_definition("core:split_firewood").is_empty(), "Actual recipe hooks reject deprecated inputs")
	var crop_script: Variant = Crops
	var crops = crop_script.new(blocked)
	check(crops.find("core:carrot").is_empty(), "Actual seed hook disables crop")
	check(not blocked.has_collect_rule("food"), "Actual collect hook disables deprecated source")
	var world_script: Variant = World
	var fresh = world_script.new({}, blocked)
	check(fresh.content == blocked, "Constructor injects content before normalization")
	var new_script: Variant = World
	var supports_content := false
	for method: Dictionary in new_script.get_script_method_list():
		if method.name == "create_new_game_state": supports_content = method.args.size() >= 2
	check(supports_content, "Public new-game factory accepts content before sources are activated")
	if not supports_content:
		finish()
		return
	var started: Dictionary = new_script.create_new_game_state(World.DEFAULT_SEED, blocked)
	fresh = world_script.new(started, blocked)
	check(fresh.get_item_instance("core:item_instance_000002").is_empty(), "Actual new game gives no deprecated starter axe")
	check(not started.item_instances.any(func(record): return String(record.item_id) == "core:axe"), "Public new-game entry validates actual starter sources")
	var outputs := Fixture.catalog(["core:plank", "core:firewood", "core:carrot", "core:pinecone"])
	var output_recipes = crafting_script.new(outputs)
	check(output_recipes.get_definition("core:saw_planks").is_empty() and output_recipes.get_definition("core:split_firewood").is_empty(), "Actual output hooks reject deprecated results while keeping unrelated tool recipes")
	var output_crops = crop_script.new(outputs)
	check(output_crops.find("core:carrot").is_empty(), "Actual product hook disables crop")
	var no_drop = world_script.new({}, outputs)
	check(no_drop.ResourceSystem._maybe_drop_pinecone(no_drop, "tree", 1, Vector2.ZERO).is_empty() and not no_drop.builtin_pinecone_enabled, "Disabled builtin drop produces no item")
	var unknown := Fixture.catalog()
	unknown._item_defs.erase("core:wood")
	unknown._item_defs.erase("core:food")
	unknown._collect_rules.clear()
	unknown._load_objects()
	check(not unknown.has_collect_rule("food"), "Unknown collect source is disabled by loader")
	var unknown_recipes = crafting_script.new(unknown)
	check(unknown_recipes.recipes_for_station("core:workbench").is_empty() and "unknown" in str(unknown_recipes.reference_errors), "Unknown inputs are disabled by actual recipe loader")
	var no_crops := Fixture.catalog(["core:carrot_seed", "core:cabbage_seed", "core:potato_seed", "core:strawberry_seed"])
	var empty_farm = world_script.new({}, no_crops)
	empty_farm.state.inventory["core:food"] = 1
	var before: Dictionary = empty_farm.export_state()
	check(empty_farm.farming.catalog.crops.is_empty() and not empty_farm.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": "core:food"}).success and empty_farm.export_state() == before, "Empty crop pool refuses without RNG or item consumption")
	finish()
func finish() -> void:
	print("ITEM_SOURCE_REFERENCES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
