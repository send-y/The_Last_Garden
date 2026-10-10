extends SceneTree

const World := preload("res://src/simulation/world_simulation.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	var sim = World.new(World.create_new_game_state())
	check(sim.has_method("get_player_needs"), "Physical needs API must exist")
	if not sim.has_method("get_player_needs"):
		quit(1)
		return
	var before: Dictionary = sim.get_player_needs()
	sim.advance_minutes(180)
	var after: Dictionary = sim.get_player_needs()
	check(after.hunger < before.hunger and after.restedness < before.restedness, "Waking spends satiety and restedness")
	check(after.energy == before.energy, "Idle time does not spend work energy")
	check(not sim.state.has("player_psychology"), "Player has no imposed numeric emotions")
	sim.state.player_energy = 20.0
	sim.state.player_needs = {"hunger": 20.0, "restedness": 15.0}
	sim.state.inventory["core:carrot"] = 1
	var eaten: Dictionary = sim.eat_food("core:carrot")
	check(eaten.success and sim.get_item_count("core:carrot") == 0, "Food consumes an actual product")
	check(sim.get_player_needs().hunger > 20 and sim.get_player_energy() > 20, "Crops restore satiety and energy")
	check(sim.get_player_needs().restedness == 15.0, "Food never replaces sleep")
	var energy: float = sim.get_player_energy()
	var elapsed: int = sim.get_elapsed_game_minutes()
	sim.rest_player()
	check(sim.get_player_energy() > energy, "Short rest restores energy")
	check(sim.get_player_needs().restedness <= 15, "Short rest does not cure sleep deprivation")
	check(sim.get_elapsed_game_minutes() == elapsed + 15, "Rest advances the real world")
	var legacy: Dictionary = sim.export_state()
	legacy.version = 27
	legacy.erase("player_needs")
	legacy.player_energy = 43.0
	var migrated = World.new(legacy)
	check(migrated.get_player_energy() == 43 and migrated.get_player_needs().restedness == 100, "Old saves migrate fairly without resetting energy")
	check(migrated.state.version == World.SAVE_VERSION and migrated.state.inventory == legacy.inventory, "Migration preserves inventory")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(is_equal_approx(restored.get_player_needs().hunger, sim.get_player_needs().hunger) and is_equal_approx(restored.get_player_needs().restedness, sim.get_player_needs().restedness), "Physical needs survive JSON reload")
	_test_sleep()
	_test_npc()
	_test_shared_supply()
	_test_psychology()
	_test_soft_limits_and_invalid_save()
	_test_sleep_and_meal_edges()
	if failures == 0:
		print("PASS: physical needs, food, rest, sleep, NPC psychology and migration")
	quit(0 if failures == 0 else 1)

func _test_sleep() -> void:
	for minute: int in [23 * 60, 7 * 60 - 1]:
		var state := World.create_new_game_state()
		state.minute_of_day = minute
		state.player_energy = 10.0
		state.player_needs = {"hunger": 60.0, "restedness": 10.0}
		state.flags.repair_stage = 2
		state.flags.bed_ready = true
		var sim = World.new(state)
		sim.set_player_position(sim.get_interaction_target_position("core:bed_site"))
		var result: Dictionary = sim.execute_interaction("core:bed_site")
		check(result.success, "Sleep is possible at a prepared bed")
		if minute == 23 * 60:
			check(sim.get_player_needs().restedness == 100 and sim.get_player_energy() == 100, "A covered full night restores sleep and energy")
		else:
			check(sim.get_player_energy() < 20 and sim.get_player_needs().restedness < 20, "A one minute nap cannot restore a full night")

func _test_npc() -> void:
	var state := World.create_new_game_state()
	state.day = 2
	state.minute_of_day = 9 * 60
	state.flags.first_night_complete = true
	var sim = World.new(state)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	check(npc.needs.has("restedness") and npc.has("psychology"), "NPC shares physical needs and has its own psychology")
	npc.needs.hunger = 10.0
	npc.personal_inventory["core:food"] = 1
	var initial_rest: float = npc.needs.restedness
	sim.advance_minutes(25)
	check(npc.personal_inventory["core:food"] == 0 and npc.needs.hunger > 10, "NPC walks to and eats real personal food")
	check(npc.needs.restedness < initial_rest, "NPC waking uses the shared sleep rule")
	check(sim.get_npc_psychology("core:first_neighbor").has("reasons"), "NPC UI can read actual mood reasons")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(is_equal_approx(restored.get_npc_psychology("core:first_neighbor").mood, sim.get_npc_psychology("core:first_neighbor").mood) and restored.get_npc_psychology("core:first_neighbor").effects == sim.get_npc_psychology("core:first_neighbor").effects, "NPC psychology survives reload")

func _active_world():
	var state := World.create_new_game_state()
	state.day = 2
	state.minute_of_day = 9 * 60
	state.flags.first_night_complete = true
	return World.new(state)

func _test_shared_supply() -> void:
	var sim = _active_world()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.needs.hunger = 10.0
	npc.personal_inventory = {"core:food": 0}
	var cell := Vector2i(23, 23)
	sim.set_player_position(Vector2(cell * 32) + Vector2(16, 48))
	sim.state.inventory["core:cabbage"] = 1
	check(sim.transfer_inventory_stack_to_storage(cell, "core:cabbage", 0).success, "Harvest can enter real communal warehouse")
	var pantry_before: Array = sim.get_storage_items()
	var meal: Dictionary = sim.NpcFoodSupply.find_meal(sim, npc)
	check(not meal.is_empty() and meal.source == "storage", "Hungry resident can find a crop on communal storage")
	check(not sim.NpcFoodSupply.fulfil(sim, {"npc_id": npc.id, "meal": meal}), "Food cannot be consumed remotely")
	check(sim.get_storage_items() == pantry_before, "Remote attempt preserves all stock")
	sim.advance_minutes(1)
	check(int(sim.get_storage_contents(cell).get("core:cabbage", 0)) == 1, "Food stays in warehouse during travel")
	sim.advance_minutes(35)
	check(int(sim.get_storage_contents(cell).get("core:cabbage", 0)) == 0 and npc.needs.hunger > 45, "Resident walks to warehouse and eats exactly one crop")
	var after: Dictionary = sim.get_npc_needs(String(npc.id))
	check(not sim.NpcFoodSupply.fulfil(sim, {"npc_id": npc.id, "meal": meal}), "Replaying a consumed meal cannot duplicate food")
	check(sim.get_npc_needs(String(npc.id)) == after, "Stale meal gives no free nutrition")
	check(sim.get_storage_items().size() == pantry_before.size() - 1, "Eating does not delete pantry tools")
	# A warehouse fully enclosed by walls must not provide remote food.
	var blocked = _active_world()
	var resident: Dictionary = blocked.state.npcs["core:first_neighbor"]
	resident.personal_inventory = {"core:food": 0}
	resident.needs.hunger = 10.0
	blocked.state.storage_items.append({"cell": [22,22], "item_id": "core:carrot", "amount": 1, "origin": [0,0], "rotation": 0, "stack_index": 0, "placement_id": "test:food"})
	var walls: Array[Vector2i] = [Vector2i(21,22), Vector2i(23,22), Vector2i(22,21), Vector2i(22,23)]
	blocked.npc_autonomy.set_structure_cells(walls)
	blocked.advance_minutes(30)
	check(int(blocked.get_storage_contents(Vector2i(22, 22)).get("core:carrot", 0)) == 1, "Unreachable pantry cannot magically feed a resident")

func _test_psychology() -> void:
	var sim = _active_world()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	sim.set_player_position(sim.get_npc_position(String(npc.id), Vector2.ZERO))
	sim.execute_interaction(String(npc.id))
	sim.execute_interaction(String(npc.id))
	check(npc.psychology.effects.size() == 1, "Repeated conversation cannot stack mood bonuses")
	var deadline: int = npc.psychology.effects[0].until
	check(deadline == sim.get_elapsed_game_minutes() + 720, "Conversation deadline uses absolute time")
	npc.needs.hunger = 0.0
	npc.needs.restedness = 5.0
	npc.personal_inventory = {"core:food": 0}
	var original_mood: float = npc.psychology.mood
	var original_wellbeing: float = npc.psychology.wellbeing
	sim.advance_minutes(60)
	check(npc.psychology.mood < original_mood, "Poor physical conditions affect NPC mood")
	check(absf(float(npc.psychology.wellbeing) - original_wellbeing) < 1, "Wellbeing does not instantly follow one bad hour")
	var restored = World.new(JSON.parse_string(JSON.stringify(sim.export_state())) as Dictionary)
	check(restored.state.npcs[npc.id].psychology.effects[0].until == deadline, "Mood effect deadline survives reload")
	sim.advance_minutes(660)
	check(npc.psychology.effects.is_empty(), "Temporary effect expires across advancing world time")

func _test_soft_limits_and_invalid_save() -> void:
	var state := World.create_new_game_state()
	state.player_needs = {"hunger": -50.0, "restedness": "bad"}
	state.npcs["core:first_neighbor"].psychology = {"mood": INF, "wellbeing": -2, "effects": "bad"}
	var sim = World.new(state)
	check(sim.get_player_needs().hunger == 0 and sim.get_player_needs().restedness == 100, "Malformed physical save has finite safe defaults")
	var psychology: Dictionary = sim.get_npc_psychology("core:first_neighbor")
	check(psychology.mood == 60 and psychology.wellbeing == 0 and psychology.effects.is_empty(), "Malformed psychology is normalized")
	sim.state.player_energy = 0.0
	sim.state.player_needs = {"hunger": 0.0, "restedness": 0.0}
	check(sim.get_player_work_speed_multiplier() >= 0.5, "Combined fatigue never turns into a hard work lock")
	var shared: Dictionary = sim.needs.normalize({"hunger": 72.0, "energy": 82.0, "restedness": 100.0})
	sim.needs.advance(shared, "awake", false)
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.active = true
	sim.advance_minutes(1)
	check(sim.get_npc_needs(String(npc.id)) == shared, "Player and NPC physical update uses the same rules")

func _test_sleep_and_meal_edges() -> void:
	var sim = _active_world()
	var npc: Dictionary = sim.state.npcs["core:first_neighbor"]
	npc.activity_id = "core:resting"
	npc.position = [816.0, 752.0]
	npc.needs = {"hunger": 10.0, "energy": 100.0, "restedness": 40.0}
	npc.personal_inventory = {"core:food": 10}
	sim.advance_minutes(40)
	check(int(npc.personal_inventory["core:food"]) < 10 and float(npc.needs.hunger) > 10, "A sleepy resident may leave daytime rest to eat")
	var physical := {"hunger": 50.0, "energy": 95.0, "restedness": 95.0}
	sim.needs.advance(physical, "sleeping", false)
	check(float(physical.energy) > 94 and float(physical.restedness) > 94, "One poor sleeping minute must not erase earned reserves")
	var state := World.create_new_game_state()
	state.flags.repair_stage = 2
	state.player_energy = 10.0
	state.minute_of_day = 419
	var late = World.new(state)
	var preview: float = late.get_sleep_energy_preview()
	late._sleep_until_morning()
	check(is_equal_approx(preview, late.get_player_energy()) and preview < 20, "Sleep preview reflects the actual remaining night")
	state.inventory["core:food"] = 1
	var supper = World.new(state)
	preview = supper.get_sleep_energy_preview()
	supper._sleep_until_morning()
	check(is_equal_approx(preview, supper.get_player_energy()), "Sleep preview includes the existing automatic berry supper")
