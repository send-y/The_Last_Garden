extends "res://src/simulation/world_rules.gd"

const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

# Operates on the authoritative WorldSimulation state; owns no copy.

static func tick(sim, real_delta: float) -> bool:
	sim._minute_accumulator += real_delta * GAME_MINUTES_PER_SECOND
	var whole_minutes: int = int(floor(sim._minute_accumulator))
	if whole_minutes <= 0:
		return false

	sim._minute_accumulator -= float(whole_minutes)
	return _advance_clock(sim, whole_minutes)


static func advance_minutes(sim, amount: int) -> bool:
	if amount <= 0:
		return false
	return _advance_clock(sim, amount)


static func _advance_clock(sim, amount: int, notify: bool = true, player_activity: String = "awake") -> bool:
	var state: Dictionary = sim.state
	var npc_autonomy: NpcAutonomy = sim.npc_autonomy
	var farming: FarmingSystem = sim.farming
	if amount <= 0:
		return false
	var npc_or_world_changed := false
	var clock_span := Diagnostic.begin("clock.total") if Diagnostic.enabled else 0
	for _minute: int in range(amount):
		var span := Diagnostic.begin("clock.player_needs") if Diagnostic.enabled else 0
		var previous_minute: int = sim.get_minute_of_day()
		var next_minute := (previous_minute + 1) % MINUTES_PER_DAY
		state["minute_of_day"] = next_minute
		var flags: Dictionary = sim._flags_mutable()
		if next_minute == 0:
			state["day"] = sim.get_day() + 1
			flags["dusk_warned"] = false
			flags["late_warned"] = false
		state["elapsed_game_minutes"] = sim.get_elapsed_game_minutes() + 1
		var player_needs: Dictionary = sim.get_player_needs()
		var player_home: Dictionary = sim.housing.home(sim, "core:player")
		var seated: Dictionary = sim.furniture.comfort(sim,"core:player")
		var actual_activity := "resting_on_chair" if player_activity == "awake" and not seated.is_empty() else player_activity
		sim.needs.advance(player_needs, actual_activity, bool(player_home.covered), player_home if player_activity in ["sleeping", "resting_in_bed"] else {})
		sim.state.player_energy = player_needs.energy
		sim.state.player_needs = {"hunger": player_needs.hunger, "restedness": player_needs.restedness}
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.npc_needs_and_meals") if Diagnostic.enabled else 0
		var meals: Dictionary = {}
		for npc_id: String in sim.state.npcs:
			var npc: Dictionary = sim.state.npcs[npc_id]
			if not bool(npc.get("active", false)) or sim.npc_catalog.get_definition(npc_id).is_empty():
				continue
			var resting: bool = String(npc.get("activity_id", "")) in [NpcAutonomy.ACTIVITY_RESTING, NpcAutonomy.ACTIVITY_SLEEPING,NpcAutonomy.ACTIVITY_CHAIR_RESTING]
			var sleeping: bool = resting and String(npc.activity_id) != NpcAutonomy.ACTIVITY_CHAIR_RESTING and (next_minute >= NpcAutonomy.REST_START or next_minute < MORNING_MINUTE)
			var home: Dictionary = sim.housing.home(sim, npc_id)
			var current_cell: Vector2i = sim._world_position_to_cell(sim.get_npc_position(npc_id, Vector2.ZERO))
			var at_home: bool = bool(home.valid) and home.target_cell == [current_cell.x, current_cell.y]
			var profile: Dictionary = home if at_home else {"cap": float(sim.needs.config.poor_sleep_cap), "speed": 1.0}
			var activity := "sleeping" if sleeping else ("resting_in_bed" if resting and at_home else ("resting" if resting else "awake"))
			var comfort: Dictionary = sim.furniture.comfort(sim,npc_id)
			if resting and not sleeping and not comfort.is_empty():
				activity = "resting_on_chair"
			sim.needs.advance(npc.needs, activity, bool(home.covered), profile if sleeping or activity == "resting_in_bed" else {})
			sim.needs.advance_psychology(npc, bool(home.covered), sim.get_elapsed_game_minutes(), home,comfort)
			if float(npc.needs.hunger) <= NpcAutonomy.HUNGRY_THRESHOLD or not npc.meal_trip.is_empty():
				meals[npc_id] = sim.NpcFoodSupply.find_meal(sim, npc)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.farming_and_drops") if Diagnostic.enabled else 0
		var farming_changed: bool = farming.advance(sim)
		var drops_expired: bool = sim._expire_world_drops()
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.doors_before") if Diagnostic.enabled else 0
		var doors_changed: bool = preload("res://src/construction/world_editing.gd").open_for_npcs(sim)
		Diagnostic.end(span)
		# Preserve argument evaluation order while timing each context builder.
		var actors: Dictionary = sim._npcs_mutable()
		var player_position: Vector2 = sim.get_player_position()
		var blueprint_cells: Array[Vector2i] = sim._get_blueprint_cells()
		span = Diagnostic.begin("clock.prepare_work") if Diagnostic.enabled else 0
		var work_contexts: Dictionary = sim.NpcPracticalWork.prepare(sim)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.housing_contexts") if Diagnostic.enabled else 0
		var home_contexts: Dictionary = sim.housing.contexts(sim)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.furniture_contexts") if Diagnostic.enabled else 0
		var furniture_contexts: Dictionary = sim.furniture.npc_contexts(sim)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.autonomy") if Diagnostic.enabled else 0
		var autonomy_result: Dictionary = npc_autonomy.advance_minutes(
			actors,
			previous_minute if next_minute != 0 else -1,
			next_minute,
			player_position,
			blueprint_cells,
			meals,
			work_contexts,
			home_contexts,
			furniture_contexts
		)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.doors_after") if Diagnostic.enabled else 0
		doors_changed = preload("res://src/construction/world_editing.gd").open_for_npcs(sim) or doors_changed
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.apply_effects") if Diagnostic.enabled else 0
		var construction_changed: bool = sim._apply_autonomy_effects(
			autonomy_result.get("effects", []) as Array
		)
		Diagnostic.end(span)
		span = Diagnostic.begin("clock.observe_home_projects") if Diagnostic.enabled else 0
		sim.work_metrics.observe_minute(sim)
		for id: String in sim.npc_catalog.definition_ids():
			var resident: Dictionary = sim.state.npcs.get(id,{})
			if bool(resident.get("active",false)): sim.NpcHomeProjects.observe(sim,resident)
		Diagnostic.end(span)
		npc_or_world_changed = npc_or_world_changed or drops_expired or farming_changed
		npc_or_world_changed = npc_or_world_changed or bool(autonomy_result.get("changed", false))
		npc_or_world_changed = npc_or_world_changed or construction_changed or doors_changed
		if next_minute == MORNING_MINUTE and sim.get_day() >= 2:
			var opening_changed: bool = sim._on_world_morning(notify)
			opening_changed = preload("res://src/characters/npc_arrivals.gd").on_morning(sim) or opening_changed
			npc_or_world_changed = npc_or_world_changed or opening_changed
		if previous_minute < 17 * 60 and next_minute >= 17 * 60 and not bool(flags["dusk_warned"]):
			flags["dusk_warned"] = true
			if notify:
				sim._emit_result(true, "first_night.message.dusk", true)
		if next_minute >= LATEST_MINUTE and not bool(flags["late_warned"]):
			flags["late_warned"] = true
			if notify:
				sim._emit_result(true, "first_night.message.exhausted", true)
	var signals_span := Diagnostic.begin("clock.signals_ui_and_supply") if Diagnostic.enabled else 0
	if npc_or_world_changed:
		sim.event_emitted.emit({"type": "state_changed"})
	sim.event_emitted.emit({"type": "time_changed", "minute": sim.get_minute_of_day()})
	Diagnostic.end(signals_span)
	Diagnostic.end(clock_span)
	return true


static func get_player_energy(sim) -> float:
	var state: Dictionary = sim.state
	return float(state.get("player_energy", PLAYER_ENERGY_MAX))


static func get_player_energy_max(sim) -> float:
	return PLAYER_ENERGY_MAX


static func get_player_work_speed_multiplier(sim) -> float:
	var farming: FarmingSystem = sim.farming
	# Soft fatigue: successful work remains possible even at zero energy.
	var minimum := clampf(float(farming.catalog.settings.fatigue_minimum_work_speed), 0.01, 1.0)
	var threshold := maxf(1.0, float(farming.catalog.settings.fatigue_full_speed_energy))
	var energy_speed := minimum + (1.0 - minimum) * clampf(sim.get_player_energy() / threshold, 0.0, 1.0)
	return sim.needs.work_speed(sim.get_player_needs(), energy_speed)


static func is_roof_covered(sim) -> bool:
	return int(sim.get_flags().get("repair_stage", 0)) >= 2


static func get_sleep_energy_preview(sim, place_id: String = "") -> float:
	var minutes := MORNING_MINUTE - int(sim.get_minute_of_day())
	if minutes <= 0:
		minutes += MINUTES_PER_DAY
	var home: Dictionary = sim.housing.home(sim, "core:player") if place_id.is_empty() else sim.housing.preview_status(sim, place_id)
	var physical: Dictionary = sim.get_player_needs()
	# Preserve the opening's automatic light supper, and include it in preview.
	if sim.get_item_count(FirstNightContent.FOOD_ID) > 0:
		physical.energy = minf(PLAYER_ENERGY_MAX, float(physical.energy) + float(sim.content.item_food_profile(FirstNightContent.FOOD_ID).get("energy", 0)))
	# Match the simulation's per-minute precision, including partial late-night sleep.
	for _minute: int in range(minutes):
		sim.needs.advance(physical, "sleeping", bool(home.covered), home)
	return float(physical.energy)


static func _spend_player_work_energy(sim, multiplier: float = 1.0) -> void:
	var state: Dictionary = sim.state
	var physical: Dictionary = sim.get_player_needs()
	sim.needs.spend_work(physical, multiplier)
	state["player_energy"] = physical.energy


static func get_day(sim) -> int:
	var state: Dictionary = sim.state
	return int(state.get("day", 1))


static func get_minute_of_day(sim) -> int:
	var state: Dictionary = sim.state
	return int(state.get("minute_of_day", START_MINUTE))


static func get_time_text(sim) -> String:
	var minute: int = sim.get_minute_of_day()
	return "%02d:%02d" % [minute / 60, minute % 60]


static func _sleep_until_morning(sim) -> Dictionary:
	var state: Dictionary = sim.state
	var flags: Dictionary = sim._flags_mutable()
	var outcomes: Array[String] = []
	if bool(sim.housing.home(sim, "core:player").covered):
		outcomes.append(OUTCOME_DRY_ROOM_ID)
		flags["comfortable_sleep_completed"] = true
	else:
		outcomes.append(OUTCOME_COLD_DRAFT_ID)
	if int(flags["campfire_stage"]) >= 2:
		outcomes.append(OUTCOME_RESIDUAL_WARMTH_ID)
	if sim.get_item_count(FirstNightContent.BOILED_WATER_ID) > 0:
		outcomes.append(OUTCOME_SAFE_WATER_ID)
	if sim.get_item_count(FirstNightContent.FOOD_ID) > 0:
		sim.farming.execute(sim, {"actor_id": "core:player", "action_id": "eat", "item_id": FirstNightContent.FOOD_ID})
		outcomes.append(OUTCOME_LIGHT_SUPPER_ID)
	else:
		outcomes.append(OUTCOME_HUNGRY_SLEEP_ID)

	state["outcomes"] = outcomes
	var neighbor_was_visible: bool = sim.is_npc_visible("core:first_neighbor")
	var minute: int = sim.get_minute_of_day()
	var minutes_until_morning := MORNING_MINUTE - minute
	if minutes_until_morning <= 0:
		minutes_until_morning += MINUTES_PER_DAY
	# Sleeping advances the same world as ordinary time: crops, drops and NPC work.
	_advance_clock(sim, minutes_until_morning, false, "sleeping")
	var npc_arrived: bool = not neighbor_was_visible and sim.is_npc_visible("core:first_neighbor")
	var result: Dictionary = sim._emit_result(
		true,
		(
			"first_night.message.morning.summary_with_neighbor"
			if npc_arrived
			else "first_night.message.morning.summary"
		),
		true,
		true,
		{
			"outcomes": Localized.text_reference_list(sim._get_outcome_label_keys(outcomes)),
			"energy": roundi(sim.get_player_energy()),
			"energy_max": roundi(sim.get_player_energy_max()),
		}
	)
	return result


static func _get_outcome_label_keys(sim, outcome_ids: Array[String]) -> Array[String]:
	var label_keys: Array[String] = []
	for outcome_id: String in outcome_ids:
		var label_key: String = String(OUTCOME_LABEL_KEYS.get(outcome_id, ""))
		if not label_key.is_empty():
			label_keys.append(label_key)
	return label_keys
