extends SceneTree

class Gallery extends Node2D:
	var textures: Array[Texture2D] = []
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(20,30),"Инструменты: подготовка графики",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color8(239,226,207))
		var names: Array[String] = ["Топор","Кирка","Мотыга","Киянка"]
		var tiers: Array[String] = ["Дерево / кустарный","Камень","Медь","Сталь"]
		for column: int in range(4):
			draw_string(font,Vector2(42+column*224,60),names[column],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color8(239,226,207))
		for row: int in range(4):
			for column: int in range(4):
				var bounds := Rect2(Vector2(20+column*224,74+row*236),Vector2(212,224))
				draw_rect(bounds,Color8(91,61,49))
				draw_rect(bounds,Color8(151,109,78),false,2)
				var texture := textures[row*4+column]
				var extent := texture.get_size()
				var available := Vector2(192,192)
				extent *= minf(available.x/extent.x,available.y/extent.y)
				draw_texture_rect(texture,Rect2(bounds.position+Vector2(106,99)-extent*0.5,extent),false)
				draw_string(font,bounds.position+Vector2(10,213),tiers[row],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color8(239,226,207))
		draw_string(font,Vector2(20,1030),"Спрайты подготовлены; игровые определения и прогрессия ещё не подключены.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color8(239,226,207))

func _initialize() -> void:
	root.size = Vector2i(928,1040)
	root.content_scale_size = Vector2i(928,1040)
	call_deferred("render")

func render() -> void:
	# The startup window override is applied after SceneTree._initialize.
	root.size = Vector2i(928,1040)
	root.content_scale_size = Vector2i(928,1040)
	var session := root.get_node("Session")
	session.set_mechanics_lab_active(true)
	session.set_process(false)
	var gallery := Gallery.new()
	gallery.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(gallery)
	for tier: String in ["wood","stone","copper","steel"]:
		for kind: String in ["axe","pickaxe","hoe","mallet"]:
			var path := "res://assets/sprites/items/tool_tiers/%s_%s.png" % [kind,tier]
			var source := Image.load_from_file(path)
			if source == null or source.is_empty():
				push_error("Could not load " + path)
				quit(1)
				return
			gallery.textures.append(ImageTexture.create_from_image(source))
	gallery.queue_redraw()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://../artifacts/tool-tiers-2026-10-13/tool-family-preview.png")
	if error != OK:
		push_error("Could not save preview: %s" % error)
		quit(1)
		return
	print("PASS: rendered all 16 prepared tool assets; no gameplay simulation tests")
	quit(0)
