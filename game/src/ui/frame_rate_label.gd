extends Label

const Localized := preload("res://src/localization/localized_text.gd")
const SAMPLE_SECONDS := 0.5
const TARGET_FPS := 100.0
const FRAME_BUDGET_MS := 1000.0 / TARGET_FPS

var last_fps := 0.0
var last_frame_ms := 0.0
var last_peak_ms := 0.0
var within_budget := false
var _elapsed := 0.0
var _frames := 0
var _peak := 0.0
var _previous_usec := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 8)
	add_theme_color_override("font_outline_color", Color("191d1b"))
	add_theme_constant_override("outline_size", 2)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tooltip_text = Localized.resolve("ui.performance.hint")
	text = "FPS —"
	_previous_usec = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	# Wall time includes stalls and pauses; engine delta can be clamped/scaled.
	sample_frame_time(float(now - _previous_usec) / 1000000.0)
	_previous_usec = now

func sample_frame_time(seconds: float) -> void:
	if seconds <= 0.0 or not is_finite(seconds):
		return
	_elapsed += seconds
	_frames += 1
	_peak = maxf(_peak, seconds)
	if _elapsed < SAMPLE_SECONDS:
		return
	last_fps = float(_frames) / _elapsed
	last_frame_ms = 1000.0 * _elapsed / float(_frames)
	last_peak_ms = 1000.0 * _peak
	within_budget = last_peak_ms <= FRAME_BUDGET_MS
	text = Localized.resolve("ui.performance.line", {
		"fps": roundi(last_fps),
		"ms": String.num(last_frame_ms, 1),
		"peak": String.num(last_peak_ms, 1),
	})
	add_theme_color_override("font_color", Color("b1d29c") if within_budget else Color("f1c075"))
	_elapsed = 0.0
	_frames = 0
	_peak = 0.0
