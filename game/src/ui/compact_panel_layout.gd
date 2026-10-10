extends RefCounted

const DEFAULT_SCALE: float = 0.9
const EDGE: float = 8.0

static func fit_centered(panel: Control, available: Vector2) -> void:
	if panel.has_method("fit_to_viewport"):
		panel.call("fit_to_viewport", available)
		return
	var extent := panel.get_combined_minimum_size()
	panel.size = extent
	var factor := minf(DEFAULT_SCALE, minf((available.x - EDGE * 2) / maxf(extent.x, 1), (available.y - EDGE * 2) / maxf(extent.y, 1)))
	panel.scale = Vector2.ONE * maxf(0.1, factor)
	panel.position = (available - extent * panel.scale) * 0.5
