extends RefCounted

static func normalize_water_state(raw_state: Dictionary, capacity: int) -> Dictionary:
	var result := raw_state.duplicate(true)
	var raw: Variant = result.get("charges", 0)
	var number := 0
	if typeof(raw) == TYPE_INT:
		number = clampi(raw, 0, capacity)
	elif typeof(raw) == TYPE_FLOAT and is_finite(raw) and raw == floor(raw):
		number = int(clampf(raw, 0, capacity))
	result.charges = number
	return result
