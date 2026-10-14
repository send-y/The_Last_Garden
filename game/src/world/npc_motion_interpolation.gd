extends RefCounted

# Presentation only. Absolute game times keep speed changes and pauses on the
# same clock as simulation; no guessed pixel speed or accumulated frame delta.
var _from := Vector2.ZERO
var target := Vector2.ZERO
var _started := 0.0
var _deadline := 0.0
var _last_clock := 0.0
var _initialized := false

func reset(point: Vector2, now: float) -> void:
	_from = point
	target = point
	_started = now
	_deadline = now
	_last_clock = now
	_initialized = true

func retarget(point: Vector2, now: float, deadline: float, snap: bool = false) -> void:
	if not _initialized or snap or now < _last_clock-0.000001:
		reset(point,now)
		return
	if point.distance_squared_to(target) <= 0.0000000001 and absf(deadline-_deadline) <= 0.000001: return
	# Complete/sample the previous step at this exact clock before redirecting.
	_from = sample(now)
	target = point
	_started = now
	_deadline = maxf(now,deadline)

func sample(now: float) -> Vector2:
	_last_clock = now
	if now >= _deadline or _deadline <= _started: return target
	var progress := clampf((now-_started)/(_deadline-_started),0.0,1.0)
	return _from.lerp(target,progress)
