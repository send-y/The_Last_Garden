extends RefCounted
const Production := preload("res://src/npc_work/npc_home_production.gd")
const Supply := preload("res://src/npc_work/npc_work_supplies.gd")
const Localized := preload("res://src/localization/localized_text.gd")
const Memory := preload("res://src/simulation/npc_memory.gd")
const PATH := "res://content/core/workbench_requests.json"
const STATUSES := ["approaching","offered","accepted","declined","fulfilled","cancelled"]
static var _config: Dictionary = {}

static func validate_data(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in data:
		if field not in ["schema_version","repeat_after_minutes","request_key","accepted_key","declined_key","fulfilled_key"]: errors.append("Unsupported workshop request field: " + field)
	if data.get("schema_version") != 1: errors.append("Invalid workshop request schema")
	var minutes: Variant = data.get("repeat_after_minutes")
	if not (minutes is int or minutes is float) or not is_finite(float(minutes)) or float(minutes) != floor(float(minutes)) or float(minutes) <= 0: errors.append("Invalid workshop request cooldown")
	for field: String in ["request_key","accepted_key","declined_key","fulfilled_key"]:
		if not data.get(field) is String or String(data.get(field,"")).is_empty(): errors.append("Missing workshop request line: " + field)
	return errors

static func config() -> Dictionary:
	if _config.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		var errors := validate_data(raw if raw is Dictionary else {})
		for error: String in errors: push_error(error)
		if errors.is_empty(): _config = raw
	return _config

static func number(raw: Variant, fallback: int = 0) -> int:
	return clampi(int(raw),0,2147483647) if (raw is int or raw is float) and is_finite(float(raw)) else fallback

static func normalize(npc: Dictionary) -> void:
	var raw: Variant = npc.get("workbench_request",{})
	var result: Dictionary = {}
	if raw is Dictionary and String(raw.get("status","")) in STATUSES:
		var cell: Variant = raw.get("cell",[])
		if cell is Array and cell.size() == 2:
			var valid := true
			for value: Variant in cell:
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or float(value) < 0 or float(value) >= 128: valid = false
			if valid:
				result = {"status":String(raw.status),"cell":[int(cell[0]),int(cell[1])],"serial":maxi(1,number(raw.get("serial"),1)),"next_minute":number(raw.get("next_minute"))}
	npc.workbench_request = result

static func need(sim, npc: Dictionary) -> Dictionary:
	if not Production.authorized(sim,npc):
		for blueprint: Dictionary in sim.state.blueprints:
			if not Supply.HomeStock.owner(sim,blueprint.cell).is_empty() or not Supply.HomeStock.can_work(sim,blueprint.cell): continue
			var count := int(blueprint.required_materials.get("core:plank",0)) - int(blueprint.delivered_materials.get("core:plank",0)) - int(npc.work_cargo.get("core:plank",0))
			if count <= 0 or not sim.NpcPracticalWork.Planner.material_source(sim,npc,blueprint).is_empty(): continue
			var copy := npc.duplicate(true)
			copy.initiative_job = {"kind":"build","phase":"craft_take","cell":blueprint.cell.duplicate(),"production_scope":"communal"}
			var readiness := Production.report(sim,copy,{"core:plank":count})
			if not readiness.is_empty(): return {"cell":blueprint.cell.duplicate(),"reason":String(readiness.reason)}
		return {}
	var goal := Production.goal(sim,npc)
	var missing: Dictionary = Supply.HomeStock.report(sim,npc,goal).missing
	var report := Production.report(sim,npc,missing)
	return {"cell":goal.cell.duplicate(),"reason":String(report.reason)} if not report.is_empty() else {}

static func observe(sim, npc: Dictionary) -> void:
	var request: Dictionary = npc.get("workbench_request",{})
	if request.is_empty() or String(request.status) not in ["approaching","offered","accepted"]: return
	if not bool(npc.get("work_options",{}).get("build",false)):
		request.status = "cancelled"
		return
	var reason := need(sim,npc)
	if reason.is_empty():
		request.status = "cancelled"
	elif String(reason.reason) == "ready" or String(reason.reason) == "working" or String(reason.reason) in ["wood","wood_reserve"]:
		# These states all prove an accessible free station. Busy alone does not.
		if String(request.status) == "accepted":
			request.status = "fulfilled"
			remember(sim,npc,"fulfilled")
			sim._emit_result(true,String(config().fulfilled_key),true,false,{"name":Localized.text_reference(sim.npc_catalog.get_definition(String(npc.id)).name_key)})
		else: request.status = "cancelled"

static func prepare(sim, npc: Dictionary) -> Dictionary:
	if config().is_empty(): return {}
	if not bool(npc.work_options.build) or not bool(npc.known) or not bool(npc.active): return {}
	if float(npc.needs.hunger) <= 55 or float(npc.needs.energy) < 30 or sim.get_minute_of_day() < 9*60 or sim.get_minute_of_day() >= 19*60: return {}
	var request: Dictionary = npc.get("workbench_request",{})
	if not request.is_empty() and String(request.status) != "approaching":
		if String(request.status) in ["offered","accepted"] or sim.get_elapsed_game_minutes() < int(request.next_minute): return {}
	var reason := need(sim,npc)
	if reason.is_empty() or String(reason.reason) != "station": return {}
	if request.is_empty() or String(request.get("status","")) != "approaching":
		request = {"status":"approaching","cell":reason.cell.duplicate(),"serial":int(request.get("serial",0))+1,"next_minute":sim.get_elapsed_game_minutes()+int(config().repeat_after_minutes)}
		npc.workbench_request = request
	var target := Supply.work_cell(sim,npc,sim._world_position_to_cell(sim.get_player_position()))
	if target == Vector2i(-1,-1): return {}
	return {"target_cell":[target.x,target.y],"travel_activity":"core:work_travel","arrival_activity":"core:workshop_request","workbench_request":true}

static func fulfil(sim, npc: Dictionary) -> bool:
	var request: Dictionary = npc.get("workbench_request",{})
	if String(request.get("status","")) != "approaching" or sim.get_npc_position(String(npc.id),Vector2.ZERO).distance_to(sim.get_player_position()) > sim.content.INTERACTION_RANGE: return false
	var current := need(sim,npc)
	if current.is_empty() or String(current.reason) != "station":
		request.status = "cancelled"
		return false
	request.status = "offered"
	sim._emit_result(true,String(config().request_key),true,false,{"name":Localized.text_reference(sim.npc_catalog.get_definition(String(npc.id)).name_key)})
	return true

static func available(npc: Dictionary) -> bool:
	return String(npc.get("workbench_request",{}).get("status","")) == "offered"

static func answer(sim, npc: Dictionary, accepted: bool) -> Dictionary:
	if not available(npc): return {}
	npc.workbench_request.status = "accepted" if accepted else "declined"
	remember(sim,npc,String(npc.workbench_request.status))
	sim.event_emitted.emit({"type":"state_changed"})
	return {"text_key":String(config().accepted_key if accepted else config().declined_key),"text_args":{},"facts":[]}

static func remember(sim, npc: Dictionary, event: String) -> void:
	var id := "core:workbench_request_%d_%s" % [int(npc.workbench_request.serial),event]
	if Memory.has_memory(npc.memories,id): return
	var cell: Array = npc.workbench_request.cell
	var memory := Memory.create_first_shared_wall(sim.get_day(),sim.get_minute_of_day(),Vector2i(int(cell[0]),int(cell[1])))
	memory.memory_id = id
	memory.event_id = "core:workbench_" + event
	memory.relationship_effects = {"trust":1.0 if event in ["accepted","fulfilled"] else 0.0,"warmth":0.0,"respect":0.0}
	npc.memories.append(memory)
