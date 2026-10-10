extends RefCounted

const Catalog := preload("res://src/characters/npc_generation_catalog.gd")
const Appearance := preload("res://src/characters/character_appearance.gd")
const FIELDS := {"community_id":"communities", "childhood_id":"childhoods", "experience_id":"experiences", "aspiration_id":"aspirations", "departure_id":"departures"}

func generate(seed_value: int, npc_id: String, catalog: Dictionary) -> Dictionary:
	if not npc_id.contains(":") or not Catalog.validate_data(catalog).is_empty():
		return {"ok":false, "profile":{}, "reason_id":"core:invalid_generation_catalog"}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var settings: Dictionary = catalog.get("settings", {})
	for _attempt: int in range(clampi(int(settings.get("max_attempts", 32)), 1, 64)):
		var profile := {"id":npc_id, "seed":seed_value, "generator_version":1,
			"age_years":rng.randi_range(int(settings.get("min_age",18)),int(settings.get("max_age",65))),
			"technology":"craft", "value_ids":[], "habit_ids":[], "heritage_ids":[], "history_facts":[], "beliefs":[]}
		var name: Dictionary = pick(catalog.names, profile, rng)
		profile["name"] = String(name.get("name", ""))
		profile["name_key"] = String(name.get("label_key", ""))
		profile["community_id"] = String(pick(catalog.communities,profile,rng).get("id",""))
		profile["birthplace_id"] = profile.community_id
		profile.heritage_ids = [String(pick(catalog.heritages, profile, rng).get("id", ""))]
		for field: String in ["childhood_id","experience_id"]:
			profile[field] = String(pick(catalog[FIELDS[field]],profile,rng).get("id",""))
		var first_value := pick(catalog.values, profile, rng)
		profile["value_one"] = String(first_value.get("id", ""))
		var second_value := pick(catalog.values, profile, rng, [profile.value_one])
		profile.value_ids = [profile.value_one, String(second_value.get("id", ""))]
		profile.erase("value_one")
		profile.habit_ids = [String(pick(catalog.habits, profile, rng).get("id", ""))]
		for field: String in ["aspiration_id","departure_id"]:
			profile[field] = String(pick(catalog[FIELDS[field]],profile,rng).get("id",""))
		var experience := Catalog.find(catalog, "experiences", profile.experience_id)
		var aspiration := Catalog.find(catalog, "aspirations", profile.aspiration_id)
		profile["skills"] = (experience.get("skills", {}) as Dictionary).duplicate(true)
		profile["interests"] = (aspiration.get("interests", []) as Array).duplicate()
		profile["starting_items"] = (experience.get("starting_items", {}) as Dictionary).duplicate(true)
		profile["appearance"] = Appearance.new().generate_npc_appearance(seed_value)
		profile["component_labels"] = {}
		for group: String in Catalog.GROUPS:
			for component: Dictionary in catalog[group]:
				profile.component_labels[String(component.id)] = String(component.get("label_key","conversation.undocumented"))
		for field: String in ["childhood_id", "experience_id", "departure_id"]:
			profile.history_facts.append({"id":profile[field], "kind":"personal", "source":"self"})
		profile.history_facts.append({"id":profile.heritage_ids[0], "kind":"family_account", "source":"family", "historical":true})
		if validate_profile(profile, catalog).is_empty():
			return {"ok":true, "profile":profile, "reason_id":""}
	return {"ok":false, "profile":{}, "reason_id":"core:no_compatible_profile"}

func pick(options: Array, selected: Dictionary, rng: RandomNumberGenerator, excluded: Array = []) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total := 0.0
	for option: Dictionary in options:
		if excluded.has(option.id) or not Catalog.compatible(option, selected, int(selected.age_years)): continue
		candidates.append(option)
		total += float(option.get("weight", 1))
	if candidates.is_empty(): return {}
	var roll := rng.randf() * total
	for candidate: Dictionary in candidates:
		roll -= float(candidate.get("weight", 1))
		if roll <= 0: return candidate
	return candidates[-1]

func validate_profile(profile: Dictionary, catalog: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var age := int(profile.get("age_years", 0))
	if age < 18 or age > 100: errors.append("Unsupported age")
	if String(profile.get("technology", "")) not in ["manual", "craft", "repair"]: errors.append("Unsupported technology")
	for field: String in FIELDS:
		var component := Catalog.find(catalog, FIELDS[field], String(profile.get(field, "")))
		if component.is_empty() or not Catalog.compatible(component, profile, age): errors.append("Incompatible " + field)
	for field: String in ["heritage_ids", "value_ids", "habit_ids"]:
		var group: String = {"heritage_ids":"heritages","value_ids":"values","habit_ids":"habits"}[field]
		for id: String in profile.get(field, []):
			var component := Catalog.find(catalog, group, id)
			if component.is_empty(): errors.append("Unknown " + id)
			elif not Catalog.compatible(component, profile, age): errors.append("Incompatible " + id)
			else:
				for other: String in component.get("excludes", []):
					if profile.get(field, []).has(other): errors.append("Conflicting " + id)
	for fact: Dictionary in profile.get("history_facts", []):
		if String(fact.get("kind", "")) != "personal": continue
		if bool(fact.get("historical", false)) and not fact.has("years_ago"):
			errors.append("Undated firsthand history")
		if fact.has("years_ago") and int(fact.years_ago) + int(fact.get("minimum_age", 0)) > age:
			errors.append("History exceeds lifetime")
	return errors
