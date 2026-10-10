extends RefCounted

const PATH := "res://content/core/npc_generation.json"
const GROUPS := ["names", "communities", "heritages", "childhoods", "experiences", "values", "habits", "aspirations", "departures"]
var data: Dictionary = {}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data = parsed

func validate() -> Array[String]:
	return validate_data(data)

static func validate_data(raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var settings: Variant = raw.get("settings",{})
	if not settings is Dictionary:
		errors.append("Invalid settings")
	elif int(settings.get("min_age",18)) < 18 or int(settings.get("max_age",65)) > 100 or int(settings.get("min_age",18)) > int(settings.get("max_age",65)):
		errors.append("Invalid age range")
	for group: String in GROUPS:
		if not raw.get(group, []) is Array or (raw.get(group, []) as Array).is_empty():
			errors.append("Empty or invalid group: " + group)
			continue
		for value: Variant in raw[group]:
			if not value is Dictionary:
				errors.append("Invalid component in " + group)
				continue
			var id := String(value.get("id", ""))
			if not id.contains(":") or seen.has(id): errors.append("Invalid or duplicate id: " + id)
			seen[id] = true
			var weight: Variant = value.get("weight", 1.0)
			if not (weight is int or weight is float) or not is_finite(float(weight)) or float(weight) <= 0:
				errors.append("Invalid weight: " + id)
			if not value.get("requires", {}) is Dictionary or not value.get("excludes", []) is Array:
				errors.append("Invalid constraints: " + id)
			elif value.get("requires", {}) is Dictionary:
				for field: String in value.get("requires",{}):
					if not value.requires[field] is Array: errors.append("Constraint must be an array: " + id)
	if raw.get("values", []) is Array and raw.get("values", []).size() < 2: errors.append("Two values required")
	return errors

static func find(raw: Dictionary, group: String, id: String) -> Dictionary:
	for component: Dictionary in raw.get(group, []):
		if String(component.get("id", "")) == id: return component
	return {}

static func compatible(component: Dictionary, selected: Dictionary, age: int) -> bool:
	if age < int(component.get("min_age", 0)): return false
	if String(component.get("technology", "craft")) not in ["manual", "craft", "repair"]: return false
	if int(component.get("training_years", 0)) > maxi(0, age - 12): return false
	for field: String in component.get("requires", {}):
		var actual: Variant = selected.get(field, "")
		var allowed: Array = component.requires[field]
		if actual is Array:
			var matched := false
			for value: Variant in actual:
				if allowed.has(value): matched = true
			if not matched: return false
		elif not allowed.has(actual): return false
	for id: Variant in component.get("excludes", []):
		for value: Variant in selected.values():
			if (value is String and id is String and value == id) or (value is Array and value.has(id)): return false
	return true
