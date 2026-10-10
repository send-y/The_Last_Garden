extends RefCounted

# Provisional playtest weights. They bias feasible choices; they never grant tools or permissions.
static func score(profile: Dictionary, candidate: Dictionary, context: Dictionary) -> float:
	if not bool(context.get("possible",true)): return 0.0
	var kind := String(candidate.get("kind","build"))
	var value := 1.0 + clampf(float(profile.get("skills",{}).get(kind,0)),0,5) * 0.4
	if profile.get("interests",[]).has(kind): value += 2.0
	var building := String(candidate.get("building_id",""))
	var values: Array = profile.get("value_ids",[])
	if building in ["core:table","core:chair"] and values.has("core:care"): value += 1.5
	if building == "core:torch" and values.has("core:order"): value += 1.5
	if kind == "gather" and values.has("core:independence"): value += 1.0
	if profile.get("habit_ids",[]).has("core:habit_prepare") and kind == "gather": value += 0.5
	return value

static func explain(profile: Dictionary, candidate: Dictionary) -> Dictionary:
	var kind := String(candidate.get("kind","build"))
	if profile.get("interests",[]).has(kind):
		return {"reason_key":"npc.preference.interest."+kind,"args":{},"fact_id":"aspiration_id"}
	if float(profile.get("skills",{}).get(kind,0)) >= 3:
		return {"reason_key":"npc.preference.experience."+kind,"args":{},"fact_id":"experience_id"}
	return {"reason_key":"npc.preference.useful","args":{},"fact_id":""}
