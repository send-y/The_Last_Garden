extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	if not ResourceLoader.exists("res://src/ui/frame_rate_label.gd"):
		check(false,"Frame rate indicator must exist")
		get_tree().quit(1)
		return
	var monitor = load("res://src/ui/frame_rate_label.gd").new()
	add_child(monitor)
	monitor.set_process(false)
	for i: int in range(64): monitor.sample_frame_time(0.008)
	check(is_equal_approx(monitor.last_fps,125.0),"FPS must come from actual frame intervals")
	check(is_equal_approx(monitor.last_frame_ms,8.0) and is_equal_approx(monitor.last_peak_ms,8.0),"Stable 125 FPS means eight-millisecond frames")
	check(monitor.within_budget,"Eight-millisecond frames meet 100 FPS budget")
	monitor.sample_frame_time(0.1)
	for i: int in range(60): monitor.sample_frame_time(0.008)
	check(is_equal_approx(monitor.last_peak_ms,100.0),"A 100 ms stall must remain visible even if average FPS stays above 100")
	check(monitor.last_fps > 100.0,"Stall fixture really retains an average above the target FPS")
	check(not monitor.within_budget,"A slow frame violates budget despite a high average FPS")
	check(monitor.text.contains("FPS") and monitor.text.contains("100.0"),"Readout must display FPS and the captured stall")
	check(monitor.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Performance readout must not intercept world clicks")
	print("FRAME_RATE_HUD: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
