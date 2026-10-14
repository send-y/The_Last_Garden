extends Node
const World := preload("res://src/simulation/world_simulation.gd")
const View := preload("res://src/world/interactable_view.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
var failures := 0
var view: InteractableView
func _ready() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL: ",label)
func clock_at(time: float) -> void:
	Session.simulation.state.elapsed_game_minutes = floori(time)
	Session.simulation._minute_accumulator = time-floorf(time)
func target(point: Vector2,time: float,deadline: float) -> void:
	# Fallback reproduces the old renderer with the same authoritative inputs.
	if view.has_method("set_motion_target"): view.call("set_motion_target",point,time,deadline,false)
	else: view._target_position = point
func run() -> void:
	Session.set_mechanics_lab_active(true)
	Session.set_process(false)
	Session._is_paused = false
	var initial := World.create_new_game_state()
	initial.npcs["core:first_neighbor"].active = true
	initial.npcs["core:first_neighbor"].moving = true
	initial.npcs["core:first_neighbor"].position = [560.0,976.0]
	Session._replace_simulation(initial)
	var previous_scale := Engine.time_scale
	for scale: float in [1.0,2.0]:
		Engine.time_scale = scale
		clock_at(2040.0)
		view = View.new()
		view.configure({"id":"core:first_neighbor","kind":"npc","label_key":"npc.first_neighbor.name","position":Vector2(560,976),"color":Color.WHITE})
		add_child(view)
		view.set_physics_process(false)
		var time := 2040.0
		var expected := view.position
		var longest_idle := 0.0
		var idle := 0.0
		for step: int in range(8):
			var duration: float = [1.0,2.0,0.5,1.0][step%4]
			var distance: float = [32.0,32.0,32.0,64.0][step%4]
			expected += Vector2(distance,0) if step%2 == 0 else Vector2(0,distance)
			var end := time+duration
			target(expected,time,end)
			while time < end-0.000001:
				var real_delta := minf(1.0/60.0,(end-time)/(World.GAME_MINUTES_PER_SECOND*scale))
				time += real_delta*World.GAME_MINUTES_PER_SECOND*scale
				clock_at(time)
				var before := view.position
				view._physics_process(real_delta*scale)
				idle = idle+real_delta if before.distance_to(view.position) < 0.00001 else 0.0
				longest_idle = maxf(longest_idle,idle)
			check(view.position.distance_to(expected) < 0.01,"Step reaches its deadline without accumulated lag at x%.3f" % scale)
		check(longest_idle <= 0.05,"Continuous walk has no idle longer than 50ms at x%.3f: %.3f" % [scale,longest_idle])
		print("STEP_TIMING_SAMPLE: scale=",scale," max_idle_ms=",longest_idle*1000)
		# Redirect halfway through a step without teleporting or restarting the clock.
		var start := view.position
		target(start+Vector2(32,0),time,time+1)
		time += 0.4
		clock_at(time)
		view._physics_process(0.4/World.GAME_MINUTES_PER_SECOND)
		var before_turn := view.position
		target(start+Vector2(0,32),time,time+0.6)
		check(view.position.distance_to(before_turn) < 0.01,"Redirect does not teleport visible position")
		time += 0.6
		clock_at(time)
		view._physics_process(0.6/World.GAME_MINUTES_PER_SECOND)
		check(view.position.distance_to(start+Vector2(0,32)) < 0.01,"Redirect finishes at new deadline")
		var stopped := view.position
		target(stopped,time,time+1)
		time += 2.0
		clock_at(time)
		view._physics_process(2.0/World.GAME_MINUTES_PER_SECOND)
		check(view.position == stopped,"Stopping does not continue old trajectory")
		# A duration change for the same target must rebase the remaining segment.
		target(stopped+Vector2(64,0),time,time+1)
		time += 0.25; clock_at(time)
		view._physics_process(0.25/World.GAME_MINUTES_PER_SECOND)
		var before_retime := view.position
		target(stopped+Vector2(64,0),time,time+1.5)
		check(view.position == before_retime,"Changing duration preserves visible position")
		var paused_clock: float = Session.simulation.get_presentation_game_time()
		Session._is_paused = true
		Session._process(10.0)
		view._physics_process(10.0)
		check(Session.simulation.get_presentation_game_time() == paused_clock and view.position == before_retime,"Pause freezes simulation and presentation together")
		Session._is_paused = false
		time += 1.0; clock_at(time)
		view._physics_process(1.0/World.GAME_MINUTES_PER_SECOND)
		check(view.position.distance_to(stopped+Vector2(64,0)) > 1.0,"Extended step does not finish at old deadline")
		time += 0.5; clock_at(time)
		view._physics_process(0.5/World.GAME_MINUTES_PER_SECOND)
		check(view.position.distance_to(stopped+Vector2(64,0)) < 0.01,"Retimed step finishes at new deadline after resume")
		view.queue_free()
	Engine.time_scale = previous_scale
	Trace.reset(); Trace.enabled = true
	Trace.frame_sample(51.0,2040)
	Trace.enabled = false
	check(Trace.snapshot().slow_frames.size() == 1,"Frame logger above 50ms remains available")
	print("NPC_STEP_TIMING: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
