extends RefCounted

# Historical budgets only preserve investment when loading older plans.
const BEFORE_PLAYTEST := {
	"core:wood_wall": {"core:plank": 30},
	"core:wood_door": {"core:plank": 25},
}

static func delivered_limit(building_id: String, item_id: String, current: int,
	saved_required: Dictionary, legacy_wall: bool) -> int:
	var old: int = int(BEFORE_PLAYTEST.get(building_id, {}).get(item_id, current))
	var raw: Variant = saved_required.get(item_id)
	var matches := (raw is int or raw is float) and is_finite(float(raw)) and float(raw) == float(old)
	if matches or (legacy_wall and building_id == "core:wood_wall" and item_id == "core:plank"):
		return maxi(current, old)
	return current
