extends Node

const Lab := preload("res://src/dev/settlement_stress.tscn")
const Content := preload("res://src/content/first_night_content.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
const Stress := preload("res://src/dev/settlement_stress_scenario.gd")
var output := ""
var phase := "work"
var steps := 2
var tracing := true
var natural_seconds := 12.0
var sequence := 0
var reports: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("run")

func boundary(label: String, edge: String) -> void:
	sequence += 1
	var file := FileAccess.open(output + "/boundary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence": sequence, "label": label, "edge": edge,
		"pid": OS.get_process_id(), "godot_thread_id": OS.get_thread_caller_id()}))
	file.close()
	var deadline := Time.get_ticks_msec() + 5000
	# Handshake outside the measured step. Keep deferred rendering out of the
	# native CPU snapshot until the sampler has observed the completed minute.
	while not FileAccess.file_exists(output + "/ack-%d" % sequence):
		if Time.get_ticks_msec() > deadline:
			push_error("Native diagnostic sampler did not acknowledge boundary")
			get_tree().quit(1)
			return
		OS.delay_msec(5)

func render_window(seconds: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var previous := started
	var frames := 0
	var maximum := 0.0
	var samples: Array[float] = []
	var over_100 := 0
	while Time.get_ticks_usec() - started < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		maximum = maxf(maximum,frame_ms)
		samples.append(frame_ms)
		if frame_ms >= 100.0: over_100 += 1
		previous = now
		frames += 1
	samples.sort()
	return {"frames": frames, "max_frame_ms": maximum,"frames_over_100_ms":over_100,
		"p99_frame_ms":samples[mini(samples.size()-1,int(samples.size()*0.99))] if not samples.is_empty() else 0.0}

func measure(label: String, minute: bool, seconds: float = 3.0) -> void:
	boundary(label, "before")
	var light_before := _lit_count(Session.simulation) if phase in ["evening","natural_evening"] else 0
	var light_revision: int = Session.simulation.structure_index.lighting_revision
	Trace.reset()
	Trace.enabled = tracing
	var started := Time.get_ticks_usec()
	var frames: Dictionary = {}
	if minute:
		Session.set_paused(false, false)
		Session.advance_debug_minutes(1)
	else:
		frames = await render_window(seconds)
	var elapsed := Time.get_ticks_usec() - started
	Trace.enabled = false
	var row := {"label": label, "wall_ms": float(elapsed) / 1000.0,
		"elapsed_game_minutes": Session.simulation.get_elapsed_game_minutes(),
		"trace_enabled": tracing, "trace": Trace.snapshot(), "frames": frames}
	row["structures"] = Session.simulation.state.structures.size()
	row["active_residents"] = 0
	for resident: Dictionary in Session.simulation.state.npcs.values():
		if bool(resident.get("active",false)): row.active_residents += 1
	row["structure_validation_enabled"] = "--verify-structure-index" in OS.get_cmdline_user_args()
	if phase in ["evening","natural_evening"]:
		row["lit_before"] = light_before
		row["lit_after"] = _lit_count(Session.simulation)
		row["lighting_revision_delta"] = Session.simulation.structure_index.lighting_revision - light_revision
		row["participants"] = 30
	reports.append(row)
	var file := FileAccess.open(output + "/stages.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	boundary(label, "after")
	print("DIAG_STAGE ", JSON.stringify({"label": label, "wall_ms": row.wall_ms}))

func run() -> void:
	if not OS.is_debug_build():
		get_tree().quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--diag-output="): output = argument.trim_prefix("--diag-output=")
		if argument.begins_with("--diag-phase="): phase = argument.trim_prefix("--diag-phase=")
		if argument.begins_with("--diag-minutes="): steps = clampi(argument.trim_prefix("--diag-minutes=").to_int(), 1, 3)
		if argument == "--diag-no-trace": tracing = false
		if argument.begins_with("--diag-seconds="): natural_seconds = clampf(argument.trim_prefix("--diag-seconds=").to_float(),12.0,180.0)
	if output.is_empty():
		push_error("Native sampler must supply --diag-output")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	Session.set_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var lab = Lab.instantiate()
	add_child(lab)
	if lab._stress_participants.is_empty() and phase != "ordinary":
		get_tree().quit(1)
		return
	var sim = Session.simulation
	if phase == "ordinary":
		for resident: Dictionary in sim.state.npcs.values():
			if bool(resident.get("active",false)):
				resident.work_options = {"water":true,"gather":true,"build":true}
	if phase in ["evening","natural_evening"]: _prepare_evening(sim,lab._stress_participants)
	if phase == "sleep":
		sim.state.minute_of_day = 21 * 60
		sim.state.elapsed_game_minutes = 2700
		for npc: Dictionary in sim.state.npcs.values():
			if not bool(npc.active): continue
			npc.needs.hunger = 95.0
			var home: Dictionary = sim.housing.home(sim, String(npc.id))
			var target: Array = home.target_cell
			var place := Content.cell_center(int(target[0]), int(target[1]))
			npc.position = [place.x, place.y]
			npc.target_cell = target.duplicate()
			npc.activity_id = "core:sleeping"
			npc.needs.energy = 55.0
			npc.needs.restedness = 55.0
		Session.state_changed.emit()
	var camera: Camera2D = lab.get_node("Game/Player/Camera2D")
	camera.top_level = true
	camera.global_position = Content.cell_center(44,32) if phase == "ordinary" else Content.cell_center(21,51)
	camera.reset_smoothing()
	await render_window(2.0)
	await measure("idle_before", false)
	if phase in ["natural", "ordinary","natural_evening"]:
		Session.set_paused(false,false)
		Session.set_process(true)
		await measure("natural_minutes",false,natural_seconds)
		Session.set_process(false)
		Session.set_paused(true,false)
		await measure("idle_after",false)
		print("CPU_DIAGNOSTIC_COMPLETE natural minutes")
		get_tree().quit(0)
		return
	if phase in ["frames", "redraw"]:
		var game: Node2D = lab.get_node("Game")
		var world: Node2D = lab.get_node("Game/World")
		var structures: Node2D = lab.get_node("Game/World/StructureLayer")
		world.queue_redraw()
		# Same full visual workload after splitting the original canvas into layers.
		var layers: Variant = world.get("_presentation_layers")
		if layers is Dictionary:
			for layer: Node2D in layers.values(): layer.queue_redraw()
		await measure("forced_world_redraw", false, 0.25)
		if phase == "redraw":
			print("CPU_DIAGNOSTIC_COMPLETE storage redraw")
			get_tree().quit(0)
			return
		game.set_process(false)
		await render_window(0.25)
		await measure("idle_no_light_update", false)
		game.set_process(true)
		world.set_process(false)
		structures.set_process(false)
		await render_window(0.25)
		await measure("idle_no_depth_updates", false)
		world.set_process(true)
		structures.set_process(true)
		structures.hide()
		await render_window(0.25)
		await measure("idle_no_structure_render", false)
		structures.show()
		world.hide()
		await render_window(0.25)
		await measure("idle_no_world_render", false)
		world.show()
		game.set_process(false)
		structures.set_process(false)
		world.set_process(false)
		structures.hide()
		await render_window(0.25)
		await measure("idle_no_light_depth_structure_render", false)
		print("CPU_DIAGNOSTIC_COMPLETE frame controls")
		get_tree().quit(0)
		return
	for step: int in range(steps):
		await measure("minute_%d" % (step + 1), true)
		await measure("render_after_%d" % (step + 1), false, 2.0)
	Session.set_paused(true, false)
	await measure("idle_after", false)
	print("CPU_DIAGNOSTIC_COMPLETE residents=", lab._stress_participants.size())
	get_tree().quit(0)

func _lit_count(sim) -> int:
	var count := 0
	for torch: Dictionary in sim.structure_index.of_type("core:torch"):
		if bool(torch.get("lit",true)): count += 1
	return count

func _prepare_evening(sim, participants: Array[String]) -> void:
	sim.state.minute_of_day = 18 * 60
	sim.state.elapsed_game_minutes = 2520
	for i: int in range(participants.size()):
		var origin := Stress.origin(i)
		for record: Dictionary in [
			{"building_id":"core:table","cell":[origin.x+3,origin.y+2]},
			{"building_id":"core:chair","cell":[origin.x+3,origin.y+3]},
			{"building_id":"core:torch","cell":[origin.x+5,origin.y],"lit":false}]:
			if sim._find_structure(record.cell).is_empty() or String(sim._find_structure(record.cell).building_id) != String(record.building_id): sim.add_structure(record)
			if record.building_id == "core:torch": sim.set_structure_state(record,"lit",false)
		var npc: Dictionary = sim.state.npcs[participants[i]]
		var position := Content.cell_center(origin.x+4,origin.y+1)
		npc.position = [position.x,position.y]
		npc.needs = {"hunger":100.0,"energy":100.0,"restedness":100.0}
		npc.next_initiative_minute = 2520
		npc.next_home_goal_minute = 2520
	sim._sync_structure_navigation()
	Session.state_changed.emit()
