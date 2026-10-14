extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const ToolFixture := preload("res://tests/fixtures/item_tool_fixture.gd")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const BASE := "res://tests/fixtures/package_d/"
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "manifest.json"))
	var path: String = BASE + String(manifest.file)
	check(FileAccess.get_sha256(path) == String(manifest.sha256), "Archived actual player save matches its immutable checksum")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var control = World.new(raw)
	var content := ToolFixture.catalog()
	var recipe_path := "user://package_d_recipes_%d.json" % OS.get_process_id()
	var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/recipes.json"))
	var extra: Dictionary = recipes.recipes[0].duplicate(true)
	extra.id = "test:additive_recipe"
	recipes.recipes.append(extra)
	var file := FileAccess.open(recipe_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(recipes))
	file.close()
	var script: Variant = World
	var accepts_catalog := false
	for method: Dictionary in script.get_script_method_list():
		if String(method.name) == "_init": accepts_catalog = method.args.size() >= 3
	check(accepts_catalog, "Save loading accepts an extended recipe catalog")
	if not accepts_catalog:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recipe_path))
		print("PACKAGE_D_SAVE: %d failures" % failures)
		quit(1)
		return
	# Constructor injection exercises loading with BOTH extended live catalogs.
	var expanded = script.new(raw, content, recipe_path)
	check(not expanded.crafting_catalog.get_definition("test:additive_recipe").is_empty(), "Added recipe is present in the live catalog")
	var comparable: Dictionary = expanded.export_state()
	for id: String in comparable.inventory.keys():
		if not control.state.inventory.has(id):
			check(int(comparable.inventory[id]) == 0, "New catalog entry must not create player stock")
			comparable.inventory.erase(id)
	check(comparable == control.export_state(), "Additive catalogs preserve all existing normalized player progress")
	for field: String in ["item_instances", "inventory_placements", "storage_items", "structures", "blueprints", "crafting_projects"]:
		check(expanded.state.get(field, null) == control.state.get(field, null), "Physical progress survives addition: " + field)
	var reloaded = script.new(JSON.parse_string(JSON.stringify(expanded.export_state())), content, recipe_path)
	check(reloaded.export_state() == expanded.export_state(), "Second JSON round trip preserves all progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recipe_path))
	var lab: Dictionary = Scenarios.build(&"player_checkpoint")
	check(bool(lab.get("success", false)), "Lab loads archived checkpoint without touching ordinary save")
	check(lab.get("state", {}) == control.export_state(), "Lab snapshot is actual progress rather than an invented day-three world")
	var session = root.get_node("Session")
	check(not session._save_store._save_path.contains("app_userdata/The Last Garden/first_night_save.json") and session._save_store._save_path != "user://first_night_save.json", "Runner isolates autoload Session save path")
	check(FileAccess.get_sha256(path) == String(manifest.sha256), "Checks never modify archived fixture")
	print("PACKAGE_D_SAVE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
