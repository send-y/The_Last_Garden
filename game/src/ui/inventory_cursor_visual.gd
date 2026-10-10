extends Control

const IconPresentation := preload("res://src/items/inventory_icon_presentation.gd")
var texture: Texture2D
var rotation_steps: int = 0
var inset: float = 5.0
var amount: int = 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()

func _draw() -> void:
	if texture != null:
		IconPresentation.draw_icon(self, texture, Rect2(Vector2.ZERO, size), rotation_steps, inset, Color(1, 1, 1, 0.9))
		if amount > 1:
			var font_size := maxi(8, roundi(inset * 2))
			var label := str(amount)
			var extent := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			draw_rect(Rect2(size - extent - Vector2(3, 4), extent + Vector2(3, 4)), Color8(35, 27, 31, 235))
			draw_string(ThemeDB.fallback_font, size - Vector2(extent.x + 1, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color8(239, 226, 207))
