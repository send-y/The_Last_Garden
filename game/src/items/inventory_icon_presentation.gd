extends RefCounted

# This asset's blade is at the top, while its established inventory footprint
# has the wide end at the bottom. Correct presentation before applying rotation;
# occupied cells and saved layouts remain unchanged. Hand presentation stays upright.
const HOE_ICON_PATH := "res://assets/sprites/items/hoe_n.png"

static func draw_icon(canvas: CanvasItem, texture: Texture2D, bounds: Rect2,
	quarter_turns: int, inset: float = 5.0, modulate: Color = Color.WHITE) -> void:
	var turns := posmod(quarter_turns, 4)
	var extent := bounds.grow(-inset).size
	if turns % 2 == 1:
		extent = Vector2(extent.y, extent.x)
	var scale := Vector2(1, -1) if texture.resource_path == HOE_ICON_PATH else Vector2.ONE
	canvas.draw_set_transform(bounds.get_center(), turns * PI / 2.0, scale)
	canvas.draw_texture_rect(texture, Rect2(-extent * 0.5, extent), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
