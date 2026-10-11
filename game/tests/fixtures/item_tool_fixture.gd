extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const World := preload("res://src/simulation/world_simulation.gd")

static func data() -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.ITEMS_PATH))
	var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/item_tool_additions.json"))
	result.merge({"schema_version": 5, "food_schema_version": 1, "tool_schema_version": 1}, true)
	result.items.append_array(additions.items)
	return result

static func catalog(deprecated_ids: Array[String] = []) -> FirstNightContent:
	var raw := data()
	for item: Dictionary in raw.items:
		if String(item.id) in deprecated_ids:
			item.deprecated = true
	var path := "user://item_tools_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var result := Content.new(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result

static func world(initial_state: Dictionary = {}) -> WorldSimulation:
	var script: Variant = World
	return script.new(initial_state, catalog())
