extends "res://src/characters/npc_catalog.gd"

# Profiles are immutable snapshots. Runtime needs, inventory and knowledge live in sim.state.npcs.
var _profiles: Dictionary = {}

func get_profile(npc_id: String) -> Dictionary:
	return (_profiles.get(npc_id, {}) as Dictionary).duplicate(true)

func talk(npcs: Dictionary, npc_id: String) -> Dictionary:
	if _profiles.has(npc_id):
		# Generated identities are disclosed by acknowledged conversation pages only.
		return {"success":false,"message_key":"conversation.open","message_args":{},"changed":false}
	return super.talk(npcs,npc_id)

func add(profile: Dictionary, initial_state: Dictionary) -> Dictionary:
	var npc_id := String(profile.get("id", ""))
	if not npc_id.contains(":") or _definitions_by_id.has(npc_id):
		return {"ok":false, "reason_id":"core:duplicate_or_invalid_npc"}
	if not profile.get("appearance", {}) is Dictionary or String(profile.get("name_key", "")).is_empty():
		return {"ok":false, "reason_id":"core:invalid_saved_profile"}
	_profiles[npc_id] = profile.duplicate(true)
	var offset := posmod(int(profile.get("seed",0)),3)
	_definitions_by_id[npc_id] = {
		"id":npc_id, "name_key":profile.name_key,
		"unknown_label_key":"npc.generic.traveler.name", "role":"generated_resident",
		"spawn":"manual", "position_cell":[24,29], "appearance_seed_offset":0,
		"greeting_key":"npc.generated.greeting", "repeat_line_key":"npc.generated.repeat", "context_lines":{},
		"autonomy":{"initial_hunger":72.0,"initial_energy":82.0,"personal_food":0,
			"meal_cell":[20+offset,28],"rest_cell":[25+offset,23],"morning_cell":[24+offset,29],"day_cell":[16+offset,30],"evening_cell":[20+offset,28]}}
	_definition_order.append(npc_id)
	var npc: Dictionary = super.create_initial_states(int(profile.get("seed", 0)))[npc_id]
	npc.merge(initial_state.duplicate(true), true)
	npc.id = npc_id
	npc.appearance = profile.appearance.duplicate(true)
	npc.appearance_seed = int(profile.get("seed", 0))
	npc["residency"] = String(initial_state.get("residency", "visitor"))
	npc["known_facts"] = initial_state.get("known_facts", {}).duplicate(true)
	if not initial_state.has("personal_inventory"):
		npc.personal_inventory = profile.get("starting_items", {}).duplicate(true)
	return {"ok":true,"npc_id":npc_id,"state":npc}

func to_save() -> Dictionary:
	return _profiles.duplicate(true)

func restore(raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for raw_id: Variant in raw:
		var npc_id := String(raw_id)
		if _profiles.has(npc_id): continue # Idempotent, never overwrite a person.
		if not raw[raw_id] is Dictionary or String(raw[raw_id].get("id", "")) != npc_id:
			errors.append("Invalid profile " + npc_id)
			continue
		if not bool(add(raw[raw_id], {}).get("ok", false)): errors.append("Cannot restore " + npc_id)
	return errors
