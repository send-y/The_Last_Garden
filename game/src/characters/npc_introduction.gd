extends RefCounted
const Localized := preload("res://src/localization/localized_text.gd")
const Catalog := preload("res://src/characters/npc_generation_catalog.gd")
const GROUPS := {"community_id":"communities","childhood_id":"childhoods","experience_id":"experiences","aspiration_id":"aspirations","departure_id":"departures","heritage_ids":"heritages","value_ids":"values","habit_ids":"habits"}

static func field_reference(profile: Dictionary, field: String) -> Variant:
	if field == "name": return Localized.text_reference(String(profile.get("name_key","npc.generic.traveler.name")))
	if field == "age_years": return int(profile.get(field,0))
	var catalog := Catalog.new()
	var raw: Variant = profile.get(field,"")
	var ids: Array = raw if raw is Array else [raw]
	var keys: Array[String] = []
	for id: Variant in ids:
		var component := Catalog.find(catalog.data,String(GROUPS.get(field,"")),String(id))
		keys.append(String(profile.get("component_labels",{}).get(String(id),component.get("label_key","conversation.undocumented"))))
	return Localized.text_reference_list(keys,"; ")

static func describe(profile: Dictionary, known_facts: Dictionary) -> Dictionary:
	var facts: Array[Dictionary] = []
	for field: String in known_facts:
		if field == "name": continue
		if not GROUPS.has(field) and field != "age_years": continue
		facts.append({"fact_id":field,"label_key":"conversation.fact."+field,"value":field_reference(profile,field),"source":known_facts[field].duplicate(true)})
	return {"name_key":String(profile.get("name_key","npc.generic.traveler.name")) if known_facts.has("name") else "npc.generic.traveler.name", "facts":facts}
