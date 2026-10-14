extends RefCounted

# Opt-in observations, never part of a save or simulation decision.
var enabled := false
signal minute_observed
var _days: Dictionary = {}
var _last_kind: Dictionary = {}
func _row(day: int, npc_id: String) -> Dictionary:
	if not _days.has(day): _days[day] = {}
	if not _days[day].has(npc_id):
		_days[day][npc_id] = {"work_units":0.0,"sample_minutes":0,"idle_minutes":0,"travel_minutes":0,"needs_minutes":0,"blocked_minutes":0,"task_changes":0}
	return _days[day][npc_id]
func record_work(sim, npc_id: String, amount: float) -> void:
	if not enabled or npc_id == "core:player" or amount <= 0: return
	_row(sim.get_day(),npc_id).work_units += amount
func observe_minute(sim) -> void:
	if not enabled: return
	for id: String in sim.state.npcs:
		var npc: Dictionary = sim.state.npcs[id]
		if not bool(npc.get("active",false)): continue
		var row := _row(sim.get_day(),id)
		row.sample_minutes += 1
		var job: Dictionary = npc.get("initiative_job",{})
		var kind := String(job.get("kind",""))
		var activity := String(npc.get("activity_id",""))
		if activity in ["core:sleeping","core:resting","core:chair_resting","core:going_to_rest","core:eating","core:table_eating","core:going_to_meal","core:collecting_meal","core:waiting_for_food"]: row.needs_minutes += 1
		elif not String(job.get("blocked_reason","")).is_empty(): row.blocked_minutes += 1
		elif bool(npc.get("moving",false)) and not job.is_empty(): row.travel_minutes += 1
		elif job.is_empty() and npc.get("work_commitment",{}).is_empty(): row.idle_minutes += 1
		if not kind.is_empty():
			var previous := String(_last_kind.get(id,""))
			if not previous.is_empty() and previous != kind: row.task_changes += 1
			_last_kind[id] = kind
	minute_observed.emit()
func snapshot(day: int) -> Dictionary:
	return _days.get(day,{}).duplicate(true)
func summary(day: int) -> Dictionary:
	var rows: Dictionary = _days.get(day,{})
	var units := 0.0
	var minutes := 0
	var idle := 0
	var changes := 0
	for row: Dictionary in rows.values():
		units += float(row.work_units)
		minutes += int(row.sample_minutes)
		idle += int(row.idle_minutes)
		changes += int(row.task_changes)
	return {"work_per_resident":units/maxi(1,rows.size()),"idle_percent":100.0*idle/maxi(1,minutes),"changes_per_hour":60.0*changes/maxi(1,minutes),"residents":rows.size(),"sample_minutes":minutes}
