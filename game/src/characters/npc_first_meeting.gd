extends RefCounted
const Localized := preload("res://src/localization/localized_text.gd")
const Memory := preload("res://src/simulation/npc_memory.gd")
const PATH := "res://content/core/first_meetings.json"
static var _catalog: Dictionary = {}

static func validate_data(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in data:
		if key not in ["schema_version","default_tone","habit_tones","world_lines"]: errors.append("Unsupported first-meeting field: " + key)
	if data.get("schema_version") != 1: errors.append("Invalid first-meeting schema")
	if not data.get("default_tone") is String or String(data.get("default_tone","")).is_empty(): errors.append("Missing default tone")
	for group: String in ["habit_tones","world_lines"]:
		if not data.get(group) is Dictionary:
			errors.append("Invalid first-meeting group: " + group)
			continue
		for key: String in data[group]:
			if not data[group][key] is String or String(data[group][key]).is_empty(): errors.append("Invalid first-meeting line: " + key)
	if data.get("world_lines") is Dictionary:
		for fact: String in ["roof_food","roof_hungry","open_food","open_hungry"]:
			if not data.world_lines.has(fact): errors.append("Missing world fact: " + fact)
	return errors

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var errors := validate_data(raw if raw is Dictionary else {})
		for error: String in errors: push_error(error)
		if errors.is_empty(): _catalog = raw
	return _catalog

static func complete(npc: Dictionary) -> bool:
	return bool(npc.get("first_meeting_complete", npc.get("known", false)))

static func pages(sim, npc: Dictionary) -> Array[Dictionary]:
	var data := catalog()
	if data.is_empty(): return []
	var profile: Dictionary = sim.npc_catalog.get_profile(String(npc.id))
	var tone := String(data.default_tone)
	for habit: String in profile.get("habit_ids", []):
		if data.habit_tones.has(habit):
			tone = String(data.habit_tones[habit])
			break
	var name_key := String(sim.npc_catalog.get_definition(String(npc.id)).name_key)
	var home: Dictionary = sim.get_character_home("core:player")
	var has_roof: bool = sim.is_roof_covered() or (bool(home.get("valid",false)) and bool(home.get("covered",false)))
	var world := ("roof" if has_roof else "open") + ("_food" if player_has_food(sim) else "_hungry")
	var result: Array[Dictionary] = [
		{"text_key": tone, "text_args": {"name": Localized.text_reference(name_key)}, "facts": ["name"]},
		{"text_key": String(data.world_lines[world]), "text_args": {}, "facts": []}]
	if gift_available(npc): result.append({"text_key": "meeting.offer_food", "text_args": {}, "facts": []})
	return result

static func player_has_food(sim) -> bool:
	for id: String in sim.get_inventory():
		if sim.get_item_count(id) > 0 and not sim.content.item_food_profile(id).is_empty(): return true
	return false

static func gift_available(npc: Dictionary) -> bool:
	return int(npc.get("welcome_gift", {}).get("remaining", 0)) > 0

static func receive(sim, npc: Dictionary, decline: bool) -> Dictionary:
	var gift: Dictionary = npc.get("welcome_gift", {})
	if gift.is_empty() or int(gift.remaining) <= 0: return {"text_key":"meeting.gift.finished", "text_args":{}, "facts":[]}
	if decline:
		gift.remaining = 0
		gift.declined = true
		sim.event_emitted.emit({"type":"state_changed"})
		return {"text_key":"meeting.gift.declined", "text_args":{}, "facts":[]}
	var id := String(gift.item_id)
	var available := mini(int(gift.remaining), maxi(0, int(npc.personal_inventory.get(id,0)) - int(gift.keep)))
	var amount := available
	while amount > 0 and not sim._can_add_item(id,amount): amount -= 1
	if amount <= 0:
		return {"text_key":"meeting.gift.full" if available > 0 else "meeting.gift.wait", "text_args":{}, "facts":[]}
	# Validate first, then move the same quantities in one simulation transaction.
	npc.personal_inventory[id] = int(npc.personal_inventory[id]) - amount
	gift.remaining = int(gift.remaining) - amount
	sim._add_item(id,amount)
	if not Memory.has_memory(npc.memories,"core:welcome_food"):
		var memory := Memory.create_first_shared_wall(sim.get_day(),sim.get_minute_of_day(),sim._world_position_to_cell(sim.get_npc_position(String(npc.id),Vector2.ZERO)))
		memory.memory_id = "core:welcome_food"
		memory.event_id = "core:welcome_food_shared"
		memory.relationship_effects = {"trust":1.0,"warmth":1.0,"respect":0.0}
		npc.memories.append(memory)
	sim.event_emitted.emit({"type":"state_changed"})
	return {"text_key":"meeting.gift.partial" if int(gift.remaining) > 0 else "meeting.gift.received", "text_args":{"amount":amount}, "facts":[]}
