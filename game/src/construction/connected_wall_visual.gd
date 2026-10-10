extends Sprite2D
var source_texture: Texture2D
var connection_mask := 5
func _draw() -> void:
	if source_texture == null: return
	# A wall occupies the full cell. Only its grain changes at a junction.
	draw_texture_rect(source_texture,Rect2(-16,-16,32,32),false)
	if (connection_mask & 5) != 0 and (connection_mask & 10) != 0:
		for i: int in [1,3]:
			if (connection_mask & (1 << i)) == 0: continue
			draw_set_transform(Vector2.ZERO,float(i)*PI/2)
			draw_texture_rect_region(source_texture,Rect2(0,-16,16,32),Rect2(16,0,16,32))
	draw_set_transform(Vector2.ZERO)
	if connection_mask == 15:
		draw_texture_rect_region(source_texture,Rect2(-16,-4,32,8),Rect2(0,12,32,8))
