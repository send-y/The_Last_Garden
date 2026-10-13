extends RefCounted

# Half-minute steps represent the accepted rates exactly and survive JSON saves.
static func normalize(value: Variant, required: int) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0.0
	return floor(clampf(float(value), 0.0, float(required)) * 2.0) / 2.0

static func stored(value: float) -> Variant:
	if value == floor(value): return int(value)
	return value
