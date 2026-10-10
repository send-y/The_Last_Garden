extends RefCounted

static func remember(npc: Dictionary, fact_id: String, source: Dictionary) -> bool:
	var facts: Variant = npc.get("known_facts", {})
	npc["known_facts"] = facts if facts is Dictionary else {}
	if npc.known_facts.has(fact_id): return false
	npc.known_facts[fact_id] = source.duplicate(true)
	if fact_id == "name": npc.known = true
	return true
