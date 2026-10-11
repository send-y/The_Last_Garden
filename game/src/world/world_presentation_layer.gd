extends Node2D

const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")
var draw_callback: Callable
var trace_label := ""
var _snapshot: Variant
var _initialized := false

func refresh(inputs: Variant, force: bool = false) -> bool:
	if not force and _initialized and _snapshot == inputs: return false
	_snapshot = inputs.duplicate(true) if inputs is Array or inputs is Dictionary else inputs
	_initialized = true
	queue_redraw()
	return true

func _draw() -> void:
	var span := Diagnostic.begin(trace_label) if Diagnostic.enabled else 0
	draw_callback.call(self)
	Diagnostic.end(span)
