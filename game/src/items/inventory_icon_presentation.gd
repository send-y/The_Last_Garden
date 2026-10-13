extends RefCounted

# This asset's blade is at the top, while its established inventory footprint
# has the wide end at the bottom. Correct presentation before applying rotation;
# occupied cells and saved layouts remain unchanged. Hand presentation stays upright.
const HOE_ICON_PATH := "res://assets/sprites/items/hoe_n.png"

static func draw_icon(canvas: CanvasItem, texture: Texture2D, bounds: Rect2,
	quarter_turns: int, inset: float = 5.0, modulate: Color = Color.WHITE, inventory_scale: Vector2 = Vector2.ZERO) -> void:
	var turns := posmod(quarter_turns, 4)
	var extent := bounds.grow(-inset).size
	if turns % 2 == 1:
		extent = Vector2(extent.y, extent.x)
	# Inventory cells describe occupied space; the artwork keeps its proportions.
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or extent.x <= 0.0 or extent.y <= 0.0:
		return
	extent = source_size * minf(extent.x / source_size.x, extent.y / source_size.y)
	var scale := Vector2(1, -1) if texture.resource_path == HOE_ICON_PATH else Vector2.ONE
	if inventory_scale != Vector2.ZERO: scale = inventory_scale
	canvas.draw_set_transform(bounds.get_center(), turns * PI / 2.0, scale)
	canvas.draw_texture_rect(texture, Rect2(-extent * 0.5, extent), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
