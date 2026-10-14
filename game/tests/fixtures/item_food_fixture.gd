extends RefCounted

const Content := preload("res://src/content/first_night_content.gd")
const World := preload("res://src/simulation/world_simulation.gd")

static func catalog(without_food: String = ""):
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.ITEMS_PATH))
	for item: Dictionary in data.items:
		if String(item.id) == without_food:
			item.erase("food")
	var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/item_food_additions.json"))
	data.merge({"schema_version": additions.schema_version, "food_schema_version": additions.food_schema_version}, true)
	data.items.append_array(additions.items)
	var path := "user://item_food_actions_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var script: Variant = Content
	var result = script.new(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result

static func world(dining: bool = false):
	var state := World.create_new_game_state()
	state.day = 2
	state.minute_of_day = 12 * 60
	state.elapsed_game_minutes = 2160
	state.inventory = {"test:ration": 2, "core:food": 2, "core:carrot": 1}
	state.player_energy = 20.0
	state.player_needs = {"hunger": 10.0, "restedness": 30.0}
	var npc: Dictionary = state.npcs["core:first_neighbor"]
	npc.known = true
	npc.active = true
	npc.personal_inventory = {}
	npc.needs = {"hunger": 10.0, "energy": 20.0, "restedness": 30.0}
	if dining:
		state.structures.append({"building_id": "core:table", "cell": [22, 20]})
		state.structures.append({"building_id": "core:chair", "cell": [22, 21]})
	var sim = World.new(state,catalog())
	return sim
