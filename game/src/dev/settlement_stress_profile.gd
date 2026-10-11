extends Node

const Lab := preload("res://src/dev/settlement_stress.tscn")
const Content := preload("res://src/content/first_night_content.gd")
var durations: Array[float] = []
var minute_costs: Array[float] = []
var minute_samples: Array[Dictionary] = []
var output := "res://../artifacts/settlement-stress-2026-10-10"
var phase := "work"
var seconds := 45.0
var view := "player"
var tag := "profile"
var disable_light_refresh := false

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-seconds="): seconds = clampf(argument.trim_prefix("--profile-seconds=").to_float(), 5.0, 300.0)
		if argument.begins_with("--profile-phase="): phase = argument.trim_prefix("--profile-phase=")
		if argument.begins_with("--profile-output="): output = argument.trim_prefix("--profile-output=")
		if argument.begins_with("--profile-tag="): tag = argument.trim_prefix("--profile-tag=")
		if argument.begins_with("--profile-view="): view = argument.trim_prefix("--profile-view=")
		if argument == "--profile-disable-light-refresh": disable_light_refresh = true
	Session.set_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var setup_start := Time.get_ticks_usec()
	var lab = Lab.instantiate()
	add_child(lab)
	if lab._stress_participants.is_empty() and lab._active_scenario_id != lab.Scenarios.GENERATED_RESIDENTS:
		push_error("Stress profile failed to create its settlement")
		get_tree().quit(1)
		return
	var setup_ms := float(Time.get_ticks_usec() - setup_start) / 1000.0
	print("STRESS_SETUP milliseconds=", setup_ms)
	var sim = Session.simulation
	if phase in ["night", "sleep"]:
		sim.state.minute_of_day = 21 * 60
		sim.state.elapsed_game_minutes = 2700
		for npc: Dictionary in sim.state.npcs.values():
			npc.needs.hunger = 95.0
			if phase == "sleep" and bool(npc.active):
				var home: Dictionary = sim.housing.home(sim, String(npc.id))
				var target: Array = home.target_cell
				var place := Content.cell_center(int(target[0]), int(target[1]))
				npc.position = [place.x, place.y]
				npc.target_cell = target.duplicate()
				npc.activity_id = "core:sleeping"
				npc.needs.energy = 55.0
				npc.needs.restedness = 55.0
		Session.state_changed.emit()
	Session.set_paused(phase == "paused", false)
	var camera: Camera2D = lab.get_node("Game/Player/Camera2D")
	if view == "overview":
		lab._set_stress_overview(true)
	else:
		camera.top_level = true
		camera.global_position = Content.cell_center(24, 29) if lab._stress_participants.is_empty() else Content.cell_center(21, 51)
		camera.reset_smoothing()
	await get_tree().create_timer(2.0).timeout
	if disable_light_refresh:
		# A diagnostic control only. In paused idle play Main._process only
		# updates the light field; this does not implement a game optimization.
		lab.get_node("Game").set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var csv := FileAccess.open(output + "/" + tag + "-frames.csv", FileAccess.WRITE)
	csv.store_line("elapsed_ms,frame_ms")
	var initial_wet := wet_beds(sim)
	var before_tree: Array = sim.state.tree_nodes.duplicate(true)
	var before_collected: Dictionary = sim.state.collected.duplicate(true)
	var starting_minutes: int = sim.get_elapsed_game_minutes()
	var start := Time.get_ticks_usec()
	var previous := start
	var next_tick := start + 1333333
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		durations.append(frame_ms)
		csv.store_line("%.3f,%.3f" % [float(now - start) / 1000.0, frame_ms])
		previous = now
		if view != "overview" and not lab._stress_participants.is_empty():
			var progress := float(now - start) / (seconds * 1000000.0)
			camera.global_position = Content.cell_center(21 + int(progress * 5.0) * 16, 51 + int(progress * 4.0) * 14)
		if now >= next_tick and phase != "paused":
			var tick_start := Time.get_ticks_usec()
			Session.advance_debug_minutes(1)
			var cost := float(Time.get_ticks_usec() - tick_start) / 1000.0
			minute_costs.append(cost)
			minute_samples.append({"minute": sim.get_elapsed_game_minutes(), "ms": cost, "activities": activity_counts(sim)})
			var progress_file := FileAccess.open(output + "/" + tag + "-progress.json", FileAccess.WRITE)
			progress_file.store_string(JSON.stringify({"ticks": minute_costs.size(), "last_minute_ms": cost, "elapsed_seconds": float(Time.get_ticks_usec() - start) / 1000000.0}))
			progress_file.close()
			# One real minute per tick, including all normal UI signals and supply.
			# Do not hide slow ticks in one unbounded catch-up batch.
			next_tick = Time.get_ticks_usec() + 1333333
	var end := Time.get_ticks_usec()
	# Include the last tick if it was the event that exceeded the duration.
	if end - previous > 1000:
		durations.append(float(end - previous) / 1000.0)
		csv.store_line("%.3f,%.3f" % [float(end - start) / 1000.0, float(end - previous) / 1000.0])
	csv.close()
	var completed := 0
	var resident_count := 0
	for npc: Dictionary in sim.state.npcs.values():
		if bool(npc.active):
			resident_count += 1
			completed += npc.home_goals_completed.size()
	var result := {"residents": resident_count, "houses": sim.state.room_assignments.size(), "structures": sim.state.structures.size(),
		"storage_stacks": sim.state.storage_items.size(), "tool_instances": sim.state.item_instances.size(),
		"phase": phase, "view": view, "scenario": String(lab._active_scenario_id),
		"diagnostic_light_refresh_disabled": disable_light_refresh,
		"renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(),
		"logical_viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"vsync": "disabled for probe", "clock": "one minute per 1.333s after previous tick; no catch-up batches",
		"setup_ms": setup_ms, "seconds": float(end - start) / 1000000.0,
		"frames": durations.size(), "average_fps": float(durations.size()) * 1000000.0 / float(end - start),
		"frame_ms": stats(durations), "minute_cpu_ms": stats(minute_costs),
		"game_minutes": sim.get_elapsed_game_minutes() - starting_minutes,
		"over_10_ms": durations.filter(func(value: float) -> bool: return value > 10.0).size(),
		"over_33_ms": durations.filter(func(value: float) -> bool: return value > 33.333).size(),
		"wet_beds_added": wet_beds(sim) - initial_wet, "home_goals_completed": completed,
		"gathering_changed_resources": before_tree != sim.state.tree_nodes or before_collected != sim.state.collected,
		"crafting_projects": sim.state.crafting_projects.size(), "activities": activity_counts(sim),
		"minute_samples": minute_samples}
	var file := FileAccess.open(output + "/" + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	if DisplayServer.get_name() != "headless":
		lab._set_stress_overview(true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + "/" + tag + "-overview.png")
	result.erase("minute_samples")
	print("SETTLEMENT_PROFILE ", JSON.stringify(result))
	get_tree().quit(0)

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in ordered: total += value
	return {"mean": total / ordered.size(), "p50": ordered[floori((ordered.size() - 1) * 0.5)],
		"p95": ordered[floori((ordered.size() - 1) * 0.95)], "p99": ordered[floori((ordered.size() - 1) * 0.99)],
		"p999": ordered[floori((ordered.size() - 1) * 0.999)], "max": ordered.back()}

func wet_beds(sim) -> int:
	var count := 0
	for bed: Dictionary in sim.state.farming.beds:
		if int(bed.wet_until) > sim.get_elapsed_game_minutes(): count += 1
	return count

func activity_counts(sim) -> Dictionary:
	var result := {}
	for npc: Dictionary in sim.state.npcs.values():
		if not bool(npc.active): continue
		var key := String(npc.activity_id)
		result[key] = int(result.get(key, 0)) + 1
	return result
