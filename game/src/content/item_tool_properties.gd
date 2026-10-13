extends RefCounted

static func validate(item: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "Item %s tool" % String(item.get("id", "<missing>"))
	if item.has("deprecated") and typeof(item.deprecated) != TYPE_BOOL:
		errors.append("Item %s deprecated: expected bool" % String(item.get("id", "<missing>")))
	if not item.has("tool"):
		return errors
	var tool: Variant = item.tool
	if not tool is Dictionary:
		errors.append(prefix + ": expected object")
		return errors
	if typeof(item.get("instance_based")) != TYPE_BOOL or item.get("instance_based") != true:
		errors.append(prefix + ".instance_based: must be true")
	if not integer(item.get("max_stack")) or item.get("max_stack") != 1:
		errors.append(prefix + ".max_stack: must be 1")
	for field: Variant in tool:
		if field not in ["actions", "grip", "water_capacity", "work_rate", "till_energy_multiplier"]:
			errors.append(prefix + "." + str(field) + ": unknown field")
	var actions: Variant = tool.get("actions")
	var normalized: Array[String] = []
	if actions is Array:
		for action: Variant in actions:
			if not action is String or action in normalized:
				errors.append(prefix + ".actions: unique strings required")
			else:
				normalized.append(action)
	normalized.sort()
	if not actions is Array or normalized not in [["chop", "clear_bush"], ["mine"], ["till"], ["water"], ["build"]]:
		errors.append(prefix + ".actions: unsupported set")
	var water := normalized == ["water"]
	if tool.get("grip") != ("carry" if water else "shaft"):
		errors.append(prefix + ".grip: invalid grip for actions")
	if water:
		var capacity: Variant = tool.get("water_capacity")
		if not integer(capacity) or float(capacity) < 1 or float(capacity) > 16:
			errors.append(prefix + ".water_capacity: integer in 1..16 required")
	elif tool.has("water_capacity"):
		errors.append(prefix + ".water_capacity: only allowed for water")
	if tool.has("work_rate"):
		var rate: Variant = tool.work_rate
		if not (typeof(rate) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(rate)) or float(rate) < 1.0 or float(rate) > 16.0 or float(rate) * 2.0 != floor(float(rate) * 2.0):
			errors.append(prefix + ".work_rate: half steps in 1..16 required")
		elif normalized in [["water"], ["till"]] and float(rate) != 1.0:
			errors.append(prefix + ".work_rate: action has no timed work")
	if tool.has("till_energy_multiplier"):
		var multiplier: Variant = tool.till_energy_multiplier
		if normalized != ["till"] or not (typeof(multiplier) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(multiplier)) or float(multiplier) <= 0.0 or float(multiplier) > 1.0:
			errors.append(prefix + ".till_energy_multiplier: till-only number in (0,1] required")
	return errors

static func integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))
