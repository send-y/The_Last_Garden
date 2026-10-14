class_name CharacterNeeds
extends RefCounted

# Shared physical rules. UI never owns or advances needs.
const CONFIG_PATH := "res://content/core/needs.json"
var config: Dictionary

func _init() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) as Dictionary

static func value(raw: Variant, fallback: float) -> float:
	if raw is float or raw is int:
		if is_finite(float(raw)):
			return clampf(float(raw), 0, 100)
	return fallback

static func normalize(raw: Variant, hunger: float = 90, energy: float = 100) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {"hunger": value(source.get("hunger"), hunger),
		"energy": value(source.get("energy"), energy),
		"restedness": value(source.get("restedness"), 100)}

static func normalize_psychology(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var effects: Array[Dictionary] = []
	var seen: Dictionary = {}
	var raw_effects: Variant = source.get("effects", [])
	if raw_effects is Array:
		for effect: Variant in raw_effects:
			if not effect is Dictionary:
				continue
			var id := String(effect.get("id", ""))
			if not ["conversation", "shared_wall", "table_meal"].has(id) or seen.has(id):
				continue
			var deadline: Variant = effect.get("until", 0)
			if not (deadline is int or deadline is float) or not is_finite(float(deadline)):
				continue
			seen[id] = true
			effects.append({"id": id, "until": maxi(0, int(deadline))})
	return {"mood": value(source.get("mood"), 60),
		"wellbeing": value(source.get("wellbeing"), 60), "effects": effects}

func advance(needs: Dictionary, activity: String, covered: bool, sleep_profile: Dictionary = {}) -> void:
	var sleeping := activity == "sleeping"
	needs.hunger = maxf(0, float(needs.hunger) - float(config.sleep_satiety_cost if sleeping else config.awake_satiety_cost))
	if sleeping:
		var cap := minf(100.0 if covered else float(config.poor_sleep_cap), float(sleep_profile.get("cap", 100)))
		var speed := clampf(float(sleep_profile.get("speed", 1)), 0.1, 3.0)
		# Poor sleep approaches its quality limit gradually, never in one frame.
		needs.energy = move_toward(float(needs.energy), cap, float(config.sleep_energy_gain) * speed)
		needs.restedness = move_toward(float(needs.restedness), cap, float(config.sleep_restedness_gain) * speed)
	else:
		if activity == "resting_in_bed":
			var cap := minf(100.0 if covered else float(config.poor_sleep_cap), float(sleep_profile.get("cap", 100)))
			var speed := clampf(float(sleep_profile.get("speed", 1)), 0.1, 3.0)
			needs.energy = minf(100, float(needs.energy) + float(config.rest_energy_gain) * speed)
			# A nap repairs some sleep debt; generic sitting rest only restores energy.
			needs.restedness = minf(100, maxf(float(needs.restedness), minf(cap, float(needs.restedness) + float(config.sleep_restedness_gain) * speed * 0.5)))
		else:
			needs.restedness = maxf(0, float(needs.restedness) - float(config.awake_restedness_cost))
		if activity in ["resting","resting_on_chair"]:
			needs.energy = minf(100, float(needs.energy) + float(config.rest_energy_gain) * (float(config.get("chair_rest_speed",1.2)) if activity == "resting_on_chair" else 1.0))
	# Store decimal precision explicitly so a JSON round trip cannot drift.
	for key: String in ["hunger", "energy", "restedness"]:
		needs[key] = roundf(float(needs[key]) * 1000.0) / 1000.0

func spend_work(needs: Dictionary, multiplier: float = 1.0) -> void:
	needs.energy = maxf(0, float(needs.energy) - float(config.work_energy_cost) * multiplier)

func food_profile(item_id: String, items: FirstNightContent) -> Dictionary:
	return items.item_food_profile(item_id)

func feed(needs: Dictionary, profile: Dictionary) -> void:
	needs.hunger = minf(100, float(needs.hunger) + float(profile.satiety))
	needs.energy = minf(100, float(needs.energy) + float(profile.energy))

func work_speed(needs: Dictionary, energy_speed: float) -> float:
	# Use the worst restriction, never multiply penalties into a hard lock.
	var hunger_speed := lerpf(0.65, 1, clampf(float(needs.hunger) / 25, 0, 1))
	var sleep_speed := lerpf(0.65, 1, clampf(float(needs.restedness) / 25, 0, 1))
	return minf(energy_speed, minf(hunger_speed, sleep_speed))

func add_effect(npc: Dictionary, id: String, now: int) -> void:
	var psychology: Dictionary = npc.psychology
	var effects: Array = psychology.effects
	for index: int in range(effects.size() - 1, -1, -1):
		if String(effects[index].id) == id:
			effects.remove_at(index)
	effects.append({"id": id, "until": now + (180 if id == "table_meal" else (720 if id == "conversation" else 2880))})

func reasons(npc: Dictionary, covered: bool, now: int, home: Dictionary = {}, furniture: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var needs: Dictionary = npc.needs
	result.append({"key": "needs.reason.fed" if float(needs.hunger) >= 55 else "needs.reason.hungry", "amount": physical_mood_contribution(float(needs.hunger))})
	result.append({"key": "needs.reason.slept" if float(needs.restedness) >= 55 else "needs.reason.sleepy", "amount": physical_mood_contribution(float(needs.restedness))})
	result.append({"key": "needs.reason.home" if covered else "needs.reason.draft", "amount": 8 if covered else -6})
	if bool(home.get("valid", false)):
		var bed: bool = String(home.get("building_id", "")) == "core:bed"
		result.append({"key": "needs.reason.personal_bed" if bed else "needs.reason.personal_bedroll", "amount": 6 if bed else 3})
	for effect: Dictionary in npc.psychology.effects:
		if int(effect.until) > now:
			result.append({"key": "needs.reason." + String(effect.id), "amount": 6 if effect.id in ["conversation","table_meal"] else 8})
	if bool(furniture.get("seated",false)) and bool(furniture.get("dark",false)):
		result.append({"key":"needs.reason.lit_seat" if bool(furniture.lit) else "needs.reason.dark_seat","amount":3 if bool(furniture.lit) else -3})
	return result

static func physical_mood_contribution(level: float) -> float:
	var current := clampf(level,0,100)
	return 8.0*(current-55.0)/45.0 if current >= 55.0 else -18.0*(55.0-current)/55.0

func advance_psychology(npc: Dictionary, covered: bool, now: int, home: Dictionary = {}, furniture: Dictionary = {}) -> void:
	var psychology: Dictionary = npc.psychology
	var effects: Array = psychology.effects
	for index: int in range(effects.size() - 1, -1, -1):
		if int(effects[index].until) <= now:
			effects.remove_at(index)
	var target := 50.0
	for reason: Dictionary in reasons(npc, covered, now, home, furniture):
		target += float(reason.amount)
	psychology.mood = move_toward(float(psychology.mood), clampf(target, 0, 100), float(config.mood_change_per_minute))
	psychology.wellbeing = lerpf(float(psychology.wellbeing), float(psychology.mood), 1.0 / float(config.wellbeing_response_minutes))
	psychology.mood = roundf(float(psychology.mood) * 1000.0) / 1000.0
	psychology.wellbeing = roundf(float(psychology.wellbeing) * 10000.0) / 10000.0
