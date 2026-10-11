extends Node

const Fixture := preload("res://tests/fixtures/item_food_fixture.gd")
const World := preload("res://src/simulation/world_simulation.gd")
const Content := preload("res://src/content/first_night_content.gd")
const Supply := preload("res://src/needs/npc_food_supply.gd")
const Feedback := preload("res://src/needs/household_feedback.gd")
const InventoryScene := preload("res://src/ui/inventory_panel.tscn")
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL: ", message)

func _run() -> void:
	_test_player_and_seeds()
	_test_non_edible_crop()
	_test_npc_food()
	_test_table_and_sleep()
	await _test_menu()
	print("ITEM_FOOD_ACTIONS: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _test_player_and_seeds() -> void:
	var sim = Fixture.world()
	var rng_before: int = sim.state.farming.roll_index
	check(sim.eat_food("test:ration").success, "Player can eat food outside crops with zero energy")
	check(sim.get_item_count("test:ration") == 1, "Eating consumes exactly one physical unit")
	check(sim.get_player_needs().hunger == 27 and sim.get_player_energy() == 20, "Player receives catalog nutrition 17/0")
	check(sim.get_player_needs().restedness == 30 and sim.state.farming.roll_index == rng_before, "Food does not replace sleep or draw seeds")
	var before: Dictionary = sim.export_state()
	check(not sim.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": "test:ration"}).success and sim.export_state() == before, "New food cannot extract seeds or mutate inventory/RNG")
	check(not sim.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": "core:carrot"}).success and sim.export_state() == before, "Locked extraction does not consume products or draw RNG")
	check(sim.farming.has_method("can_extract_seeds"), "Seed capability is independent from food")
	if sim.farming.has_method("can_extract_seeds"):
		check(sim.farming.call("can_extract_seeds", "core:food") and sim.farming.call("can_extract_seeds", "core:carrot"), "Berries and crop products support seeds")
		check(not sim.farming.call("can_extract_seeds", "core:carrot_seed") and not sim.farming.call("can_extract_seeds", "test:ration"), "Seeds and unrelated food do not support extraction")
	check(sim.eat_food("core:carrot").success and sim.get_player_needs().hunger == 55 and sim.get_player_energy() == 32, "Existing carrot preserves its literal nutrition")
	sim.state.inventory["core:wood"] = 1
	before = sim.export_state()
	check(not sim.eat_food("core:wood").success and sim.export_state() == before, "Non-food command refuses without side effects")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.state.seed) ^ 57391
	var crop: Dictionary = sim.farming.catalog.crops[rng.randi_range(0, sim.farming.catalog.crops.size() - 1)]
	var amount: int = rng.randi_range(2, 4)
	check(sim.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": "core:food"}).success, "Berry extraction still works before study")
	check(sim.get_item_count(String(crop.seed_id)) == amount and sim.state.farming.roll_index == 1, "Committed berry result preserves original RNG stream")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	restored.content = Fixture.catalog()
	check(restored.state.version == 36 and restored.get_item_count("test:ration") == 1, "New food inventory survives unchanged save format")

func _test_non_edible_crop() -> void:
	var sim = Fixture.world()
	sim.content = Fixture.catalog("core:carrot")
	sim.add_structure({"building_id": "core:study_table", "cell": [22, 20], "stage_id": "core:complete"})
	var before: Dictionary = sim.export_state()
	check(not sim.eat_food("core:carrot").success and sim.export_state() == before, "Crop without food cannot be eaten or change state")
	check(sim.farming.can_extract_seeds("core:carrot"), "Non-edible crop keeps independent seed capability")
	check(sim.execute_farming_command({"actor_id": "core:player", "action_id": "extract", "item_id": "core:carrot"}).success, "Non-edible crop can still provide its own seeds")
	check(sim.get_item_count("core:carrot") == 0 and sim.get_item_count("core:carrot_seed") >= 1 and sim.state.farming.roll_index == 1, "Independent extraction consumes one product and commits one RNG draw")

func _test_npc_food() -> void:
	var sim = Fixture.world()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.personal_inventory = {"test:ration": 1}
	var meal: Dictionary = Supply.find_meal(sim, npc)
	check(String(meal.get("item_id", "")) == "test:ration", "NPC discovers new food in personal inventory")
	check(Feedback._food(sim, npc).severity == "good", "Household feedback recognizes new personal food")
	if not meal.is_empty():
		npc.position = _position(meal.target_cell)
		check(Supply.fulfil(sim, {"npc_id": npc.id, "meal": meal}), "NPC consumes its real new food")
		check(npc.personal_inventory["test:ration"] == 0 and npc.needs.hunger == 27 and npc.needs.energy == 20 and npc.needs.restedness == 30, "NPC receives the same 17/0 without restoring sleep")
		var before: Dictionary = sim.export_state()
		check(not Supply.fulfil(sim, {"npc_id": npc.id, "meal": meal}) and sim.export_state() == before, "Stale personal request cannot duplicate a meal")
	npc.personal_inventory = {}
	npc.needs.hunger = 10.0
	npc.position = _position([22, 23])
	sim.state.storage_items = [{"placement_id": "test:food", "item_id": "test:ration", "amount": 1, "cell": [22, 24], "rotated": false}]
	meal = Supply.find_meal(sim, npc)
	check(String(meal.get("source", "")) == "storage" and String(meal.get("item_id", "")) == "test:ration", "NPC discovers new food in shared stock")
	check(Feedback._food(sim, npc).severity == "good", "Household feedback recognizes new stored food")
	if not meal.is_empty():
		npc.position = _position(meal.target_cell)
		check(Supply.fulfil(sim, {"npc_id": npc.id, "meal": meal}), "NPC consumes a real shared portion")
		check(sim.state.storage_items.is_empty() and npc.needs.hunger == 27, "Shared food is spent exactly once and feeds from the same profile")
		var before: Dictionary = sim.export_state()
		check(not Supply.fulfil(sim, {"npc_id": npc.id, "meal": meal}) and sim.export_state() == before, "Stale shared request cannot feed twice")

func _test_table_and_sleep() -> void:
	var sim = Fixture.world(true)
	sim.set_player_position(Content.cell_center(22, 22))
	check(sim.furniture.options(sim, Vector2i(22, 20)).foods.has("test:ration"), "Table offers new food")
	check(sim.execute_furniture_command(Vector2i(22, 20), "eat", "test:ration").success and sim.get_item_count("test:ration") == 1, "Eating at a table spends new food")
	check(sim.get_player_needs().hunger > 26 and sim.get_player_needs().hunger <= 27, "Table uses catalog satiety before five minutes of time")
	sim = Fixture.world()
	sim.state.minute_of_day = 23 * 60 + 50
	sim.state.inventory = {"core:food": 1}
	var preview: float = sim.get_sleep_energy_preview()
	check(sim._sleep_until_morning().success, "Automatic berry supper and night still complete")
	check(is_equal_approx(preview, sim.get_player_energy()) and sim.get_item_count("core:food") == 0, "Sleep preview and actual supper use the same unchanged nutrition")

func _test_menu() -> void:
	var session = get_tree().root.get_node("Session")
	session.set_mechanics_lab_active(true)
	var sim = Fixture.world()
	session.simulation = sim
	var panel = InventoryScene.instantiate()
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	host.add_child(panel)
	await get_tree().process_frame
	for id: String in ["test:ration", "core:food", "core:carrot", "core:carrot_seed", "core:wood"]:
		panel.call("_on_inventory_selection_changed", {"item_id": id, "amount": 1, "label": id})
		var edible: bool = id in ["test:ration", "core:food", "core:carrot"]
		var seeds: bool = id in ["core:food", "core:carrot"]
		check(panel.get("_eat_button").visible == edible, "Menu shares food capability: " + id)
		check(panel.get("_extract_button").visible == seeds, "Menu keeps independent seed capability: " + id)
		if id == "core:carrot":
			check(panel.get("_extract_button").disabled, "Crop seed extraction retains research gate")
		if id == "test:ration":
			check("17" in panel.get("_details_label").text, "Menu reads new catalog nutrition")
	host.queue_free()
	await get_tree().process_frame

func _position(cell: Array) -> Array:
	var point := Content.cell_center(int(cell[0]), int(cell[1]))
	return [point.x, point.y]
