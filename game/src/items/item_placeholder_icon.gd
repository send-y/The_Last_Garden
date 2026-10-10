class_name ItemPlaceholderIcon
extends RefCounted

static var _cache: Dictionary = {}


static func texture_for(item_id: String) -> Texture2D:
	if _cache.has(item_id):
		return _cache[item_id] as Texture2D
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	match item_id:
		"core:wood", "core:firewood":
			_draw_log(image)
		"core:plank":
			_draw_plank(image)
		"core:raw_water", "core:boiled_water":
			_draw_water(image)
		"core:bucket":
			_draw_bucket(image)
		"core:carrot", "core:carrot_seed", "core:cabbage", "core:cabbage_seed", "core:potato", "core:potato_seed", "core:strawberry", "core:strawberry_seed":
			_draw_crop(image, item_id.trim_prefix("core:").trim_suffix("_seed"), item_id.ends_with("_seed"))
		_:
			_draw_generic(image)
	var texture := ImageTexture.create_from_image(image)
	_cache[item_id] = texture
	return texture


static func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py: int in range(y, y + height):
		for px: int in range(x, x + width):
			if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
				image.set_pixel(px, py, color)


static func _draw_log(image: Image) -> void:
	_rect(image, 2, 5, 12, 6, Color("38251d"))
	_rect(image, 3, 4, 10, 6, Color("9b5a36"))
	_rect(image, 4, 5, 8, 3, Color("c58450"))
	_rect(image, 2, 5, 2, 6, Color("d6a06b"))
	_rect(image, 3, 6, 1, 3, Color("f0c989"))
	_rect(image, 12, 4, 2, 7, Color("633a2a"))


static func _draw_plank(image: Image) -> void:
	_rect(image, 2, 3, 12, 10, Color("38251d"))
	_rect(image, 3, 4, 10, 8, Color("a96b43"))
	_rect(image, 4, 5, 8, 1, Color("d19b61"))
	_rect(image, 4, 8, 8, 1, Color("c18450"))
	_rect(image, 4, 10, 8, 1, Color("d19b61"))


static func _draw_water(image: Image) -> void:
	_rect(image, 5, 2, 6, 2, Color("d5c7a0"))
	_rect(image, 3, 4, 10, 9, Color("344c55"))
	_rect(image, 4, 4, 8, 8, Color("69a6aa"))
	_rect(image, 5, 6, 5, 1, Color("c2e0ca"))
	_rect(image, 7, 9, 5, 1, Color("c2e0ca"))
	_rect(image, 5, 12, 6, 2, Color("344c55"))


static func _draw_bucket(image: Image) -> void:
	_rect(image, 3, 3, 10, 2, Color("38251d"))
	_rect(image, 4, 5, 8, 8, Color("9b5a36"))
	_rect(image, 5, 6, 6, 6, Color("c58450"))
	_rect(image, 4, 12, 8, 2, Color("38251d"))
	_rect(image, 2, 4, 1, 7, Color("d6a06b"))
	_rect(image, 13, 4, 1, 7, Color("d6a06b"))
	_rect(image, 4, 1, 1, 2, Color("f0c989"))
	_rect(image, 11, 1, 1, 2, Color("f0c989"))


static func _draw_generic(image: Image) -> void:
	_rect(image, 3, 3, 10, 10, Color("38251d"))
	_rect(image, 4, 4, 8, 8, Color("d4b277"))
	_rect(image, 5, 5, 6, 6, Color("ead1a8"))


static func _draw_crop(image: Image, crop: String, seed: bool) -> void:
	var color := Color({"carrot": "d88b39", "cabbage": "82ab62", "potato": "bb986a", "strawberry": "c85465"}[crop])
	if seed:
		_rect(image, 3, 4, 10, 10, Color("38251d"))
		_rect(image, 4, 5, 8, 8, Color("ead1a8"))
		_rect(image, 5, 2, 6, 3, Color("a96b43"))
		_rect(image, 6, 7, 4, 4, color)
		_rect(image, 5, 12, 2, 1, Color("795434"))
		_rect(image, 9, 12, 2, 1, Color("795434"))
		return
	match crop:
		"carrot":
			_rect(image, 5, 5, 7, 3, color)
			_rect(image, 6, 8, 5, 3, color)
			_rect(image, 7, 11, 3, 2, color)
			_rect(image, 8, 13, 1, 1, color)
			_rect(image, 7, 1, 2, 4, Color("526d3d"))
			_rect(image, 10, 2, 2, 3, Color("82ab62"))
		"cabbage":
			_rect(image, 4, 3, 8, 10, Color("526d3d"))
			_rect(image, 2, 5, 12, 6, color)
			_rect(image, 5, 4, 6, 8, color.lightened(0.15))
			_rect(image, 7, 5, 1, 7, Color("526d3d"))
		"potato":
			_rect(image, 4, 3, 8, 10, Color("795434"))
			_rect(image, 3, 5, 10, 6, color)
			_rect(image, 5, 4, 6, 8, color)
			_rect(image, 6, 6, 1, 1, Color("795434"))
			_rect(image, 10, 9, 1, 1, Color("795434"))
		"strawberry":
			_rect(image, 3, 5, 10, 5, color)
			_rect(image, 5, 10, 6, 2, color)
			_rect(image, 7, 12, 2, 1, color)
			_rect(image, 5, 3, 6, 3, Color("526d3d"))
			for point: Vector2i in [Vector2i(5, 7), Vector2i(9, 7), Vector2i(7, 10)]:
				image.set_pixelv(point, Color("ead1a8"))
