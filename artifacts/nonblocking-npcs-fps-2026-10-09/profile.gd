extends Node
const Main := preload("res://src/main/main.tscn")
const Scenarios := preload("res://src/dev/mechanics_lab_scenarios.gd")
const OUTPUT := "D:/The_Last_Garden/artifacts/nonblocking-npcs-fps-2026-10-09/"
func _ready() -> void: call_deferred("run")
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.apply_debug_state(Scenarios.build(Scenarios.GENERATED_RESIDENTS).state,"frame timing probe",false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := Main.instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	var hud: Control = main.get_node("Hud/HudRoot")
	var label: Label = hud.get_node("FrameRate")
	for viewport_size: Vector2i in [Vector2i(640,360),Vector2i(1280,720)]:
		DisplayServer.window_set_size(viewport_size)
		await get_tree().create_timer(0.2).timeout
		if not Rect2(Vector2.ZERO,hud.size).encloses(label.get_rect()):
			push_error("Frame rate label extends outside HUD")
			get_tree().quit(1)
			return
	var start := Time.get_ticks_usec()
	var previous := start
	var times: Array[float] = []
	var minutes_before: int = Session.simulation.get_elapsed_game_minutes()
	while Time.get_ticks_usec() - start < 20000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now-previous)/1000.0)
		previous = now
	var elapsed_ms := float(previous-start)/1000.0
	times.sort()
	var result := {"scenario":"three generated residents; stationary player; natural calendar ticks", "vsync":"disabled only in probe", "renderer":RenderingServer.get_video_adapter_name(),"seconds":elapsed_ms/1000.0,"frames":times.size(),"average_fps":times.size()*1000.0/elapsed_ms,"p99_ms":times[floori((times.size()-1)*0.99)],"maximum_ms":times.back(),"over_10_ms":times.filter(func(t):return t>10.0).size(),"game_minutes":Session.simulation.get_elapsed_game_minutes()-minutes_before,"hud_text":label.text}
	var file := FileAccess.open(OUTPUT+"profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT+"fps-hud.png")
	print("FRAME_PROFILE ",JSON.stringify(result))
	get_tree().quit(0)
