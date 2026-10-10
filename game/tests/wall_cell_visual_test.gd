extends Node
const Wall := preload("res://src/construction/connected_wall_visual.gd")
const TEXTURE := preload("res://assets/sprites/structures/wood_wall.png")
var failures := 0
func _ready() -> void:
	get_tree().create_timer(20).timeout.connect(func(): get_tree().quit(1))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for i: int in range(16):
		var wall := Wall.new()
		wall.source_texture = TEXTURE
		wall.connection_mask = i
		wall.position = Vector2((i%8)*32+16,(i/8)*32+16)
		viewport.add_child(wall)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	for i: int in range(16):
		for y: int in range(32):
			for x: int in range(32):
				if rendered.get_pixel((i%8)*32+x,(i/8)*32+y).a < 0.99:
					failures += 1
	if failures:
		push_error("Walls leave %d transparent pixels inside their occupied cells" % failures)
	else:
		print("PASS: All 16 wall connection masks fill their entire 32x32 cell")
	var directory := "D:/The_Last_Garden/artifacts/wall-door-visual-fix-2026-10-09"
	DirAccess.make_dir_recursive_absolute(directory)
	rendered.save_png(directory+"/wall-masks.png")
	get_tree().quit(1 if failures else 0)
