extends RefCounted

const Topology := preload("res://src/construction/room_topology.gd")
const Content := preload("res://src/content/first_night_content.gd")
const BASE_ROOM := "core:base_house"
const MODES := ["settlement", "personal", "shared"]

static func normalize(sim) -> void:
	var raw: Variant = sim.state.get("home_policies", {})
	var normalized := {BASE_ROOM: "settlement"}
	for room: Dictionary in rooms(sim):
		var id := String(room.room_id)
		if id == BASE_ROOM: continue
		var value: Variant = raw.get(id, "") if raw is Dictionary else ""
		var mode := String(value) if value is String else ""
		if not MODES.has(mode): mode = "shared" if room.members.size() > 1 else "personal"
		# Preserve valid legacy assignments, including an inconsistent saved single-person mode.
		if mode == "personal" and room.members.size() > 1: mode = "shared"
		normalized[id] = mode
	sim.state.home_policies = normalized

static func rooms(sim) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"room_id":BASE_ROOM, "mode":"settlement", "members":_members(sim, BASE_ROOM), "valid":true}]
	var policies: Variant = sim.state.get("home_policies", {})
	for room: Dictionary in sim.state.room_assignments:
		if String(room.room_type_id) != Topology.LIVING_ROOM_ID: continue
		var id := String(room.id)
		var members := _members(sim, id)
		var value: Variant = policies.get(id, "") if policies is Dictionary else ""
		var mode := String(value) if value is String else ""
		if not MODES.has(mode): mode = "shared" if members.size() > 1 else "personal"
		var valid: bool = sim.housing.room_valid(sim,id)
		result.append({"room_id":id, "mode":mode, "members":members, "valid":valid})
	return result

static func for_character(sim, id: String) -> Dictionary:
	var room_id := _assigned_room(sim, id)
	var result := {"room_id":room_id, "mode":"", "members":[], "may_furnish":false}
	for room: Dictionary in rooms(sim):
		if String(room.room_id) != room_id: continue
		result.mode = room.mode
		result.members = room.members.duplicate()
		var npc: Dictionary = sim.state.npcs.get(id, {})
		result.may_furnish = bool(room.valid) and String(room.mode) != "settlement" and not npc.is_empty() and bool(npc.get("known",false)) and bool(npc.get("active",false)) and String(npc.get("residency","resident")) != "visitor" and bool(sim.housing.home(sim,id).valid)
		break
	return result

static func may_furnish(sim, npc: Dictionary, room_id: String) -> bool:
	var policy := for_character(sim, String(npc.get("id", "")))
	return String(policy.room_id) == room_id and bool(policy.may_furnish)

static func set_mode(sim, room_id: String, mode: String) -> Dictionary:
	if not MODES.has(mode): return sim._emit_result(false,"housing.failure.mode")
	if room_id == BASE_ROOM and mode != "settlement": return sim._emit_result(false,"housing.failure.settlement")
	for room: Dictionary in rooms(sim):
		if String(room.room_id) != room_id: continue
		if mode == "personal" and room.members.size() > 1: return sim._emit_result(false,"housing.failure.personal")
		sim.state.home_policies[room_id] = mode
		return sim._emit_result(true,"housing.mode.changed",true,false,{"mode":mode})
	return sim._emit_result(false,"housing.failure.room")

static func can_assign(sim, character_id: String, place: Dictionary) -> bool:
	var room_id := String(place.get("room_id", ""))
	for room: Dictionary in rooms(sim):
		if String(room.room_id) != room_id: continue
		if String(room.mode) != "personal": return true
		for member: String in room.members:
			if member != character_id: return false
		return true
	return false

static func _members(sim, room_id: String) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in sim.state.sleep_assignments:
		var id := String(value)
		if id != "core:player":
			var npc: Dictionary = sim.state.npcs.get(id,{})
			if npc.is_empty() or not bool(npc.get("active",false)): continue
		if _assigned_room(sim,id) == room_id: result.append(id)
	result.sort()
	return result

static func _assigned_room(sim, id: String) -> String:
	var place_id := String(sim.state.sleep_assignments.get(id,""))
	if place_id.is_empty(): return ""
	if place_id == "core:starter_bedroll": return BASE_ROOM
	var place: Dictionary = sim.housing.place(sim,place_id)
	if not place.is_empty():
		if not String(place.room_id).is_empty(): return String(place.room_id)
		# Invalid geometry keeps its occupant identities for repair and policy enforcement.
		var cell := Vector2i(int(place.cell[0]), int(place.cell[1]))
		for room: Dictionary in sim.state.room_assignments:
			if String(room.room_type_id) == Topology.LIVING_ROOM_ID and sim._room_cells_set(room.cells).has(cell): return String(room.id)
	return ""
