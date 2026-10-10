extends RefCounted

const KINDS := ["water", "gather", "build"]
const PHASES := ["borrow", "refill", "work", "collect", "take_materials", "deliver", "build", "return", "switch_on", "craft_take", "craft"]

static func normalize(npc: Dictionary, content) -> void:
	var raw: Variant = npc.get("work_options", {})
	var options: Dictionary = {}
	for kind: String in KINDS:
		options[kind] = raw is Dictionary and raw.get(kind, false) is bool and raw.get(kind, false)
	npc.work_options = options
	npc.initiative_choice_index = number(npc.get("initiative_choice_index"))
	npc.next_initiative_minute = number(npc.get("next_initiative_minute"))
	npc.carried_instance_id = String(npc.get("carried_instance_id", ""))
	var cargo: Dictionary = {}
	raw = npc.get("work_cargo", {})
	if raw is Dictionary:
		for id: String in raw:
			if content.has_item(id) and not content.item_is_instance_based(id) and number(raw[id]) > 0:
				cargo[id] = number(raw[id])
	npc.work_cargo = cargo
	raw = npc.get("initiative_job", {})
	var job: Dictionary = {}
	if raw is Dictionary and KINDS.has(String(raw.get("kind", ""))) and PHASES.has(String(raw.get("phase", ""))):
		job = {"kind": String(raw.kind), "phase": String(raw.phase)}
		for key: String in ["tool_id", "target_id", "resource_item"]:
			if raw.has(key):
				job[key] = String(raw[key])
		var cell: Variant = raw.get("cell", [])
		if cell is Array and cell.size() == 2 and (cell[0] is int or cell[0] is float) and (cell[1] is int or cell[1] is float):
			job.cell = [number(cell[0]), number(cell[1])]
		else:
			job = {}
		if not job.is_empty():
			if String(job.phase) in ["craft_take", "craft"]:
				var station: Variant = raw.get("station_cell", [])
				if not station is Array or station.size() != 2 or String(raw.get("recipe_id", "")) != "core:saw_planks" or not valid_cell_coordinate(station[0]) or not valid_cell_coordinate(station[1]):
					npc.initiative_job = {}
					return
				else:
					job.station_cell = [number(station[0]),number(station[1])]
					job.recipe_id = "core:saw_planks"
			var water: Variant = raw.get("water_cell", [])
			if water is Array and water.size() == 2:
				job.water_cell = [number(water[0]), number(water[1])]
			elif raw.has("water_cell"):
				job.water_cell = []
			job.drops = []
			if raw.get("drops", []) is Array:
				for id: Variant in raw.get("drops", []):
					if id is String and not job.drops.has(id):
						job.drops.append(id)
	npc.initiative_job = job

static func number(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	return clampi(int(value), 0, 2147483647)

static func valid_cell_coordinate(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) < 128 and float(value) == floor(float(value))
