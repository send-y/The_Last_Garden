extends RefCounted

const Diagnostic := preload("res://src/dev/diagnostic_trace.gd")

const Content := preload("res://src/content/first_night_content.gd")
const RADIUS := 4
var _index: RefCounted
var _lighting_revision := -1
var _values: Dictionary = {}
var _texture: ImageTexture

func refresh(sim) -> void:
	if _texture != null and _index == sim.structure_index and _lighting_revision == sim.structure_index.lighting_revision: return
	var span := Diagnostic.begin("lighting.rebuild") if Diagnostic.enabled else 0
	_index = sim.structure_index
	_lighting_revision = _index.lighting_revision
	_values.clear()
	var walls: Dictionary = {}
	# Static house walls and constructed walls stop light; furniture does not.
	for x: int in range(19,29):
		walls[Vector2i(x,17)] = true
	for y: int in range(18,26):
		walls[Vector2i(19,y)] = true
		walls[Vector2i(28,y)] = true
	for x: int in range(19,29):
		if x != 24:
			walls[Vector2i(x,25)] = true
	var sources: Array[Vector2i] = []
	for structure: Dictionary in _index.of_type("core:torch"):
		if bool(structure.get("lit",true)): sources.append(Vector2i(int(structure.cell[0]),int(structure.cell[1])))
	for definition: Dictionary in sim.building_catalog.all_definitions():
		var id := String(definition.id)
		if not bool(definition.get("room_boundary",false)) or id == "core:wood_door": continue
		for structure: Dictionary in _index.of_type(id):
			var cell := Vector2i(int(structure.cell[0]),int(structure.cell[1]))
			for part: Vector2i in sim.building_catalog.get_footprint_cells(id,cell):
				walls[part] = true
	for source: Vector2i in sources:
		var queue: Array[Vector2i] = [source]
		var seen: Dictionary = {source:0}
		var cursor := 0
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			var strength := maxf(0.0, 1.0 - source.distance_to(cell) / float(RADIUS + 1))
			_values[cell] = maxf(strength, float(_values.get(cell,0)))
			for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next := cell + direction
				if seen.has(next) or walls.has(next) or not Rect2i(Vector2i.ZERO,Content.MAP_SIZE).has_point(next) or source.distance_to(next) > RADIUS or int(seen[cell]) >= RADIUS + 2:
					continue
				seen[next] = int(seen[cell]) + 1
				queue.append(next)
	var mask := Image.create(Content.MAP_SIZE.x,Content.MAP_SIZE.y,false,Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	for cell: Vector2i in _values:
		mask.set_pixel(cell.x,cell.y,Color(float(_values[cell]),0,0,1))
	_texture = ImageTexture.create_from_image(mask)
	Diagnostic.end(span)

func is_lit(sim, cell: Vector2i) -> bool:
	if sim.get_minute_of_day() >= 7 * 60 and sim.get_minute_of_day() < 18 * 60:
		return true
	return has_artificial_light(sim,cell)

func has_artificial_light(sim, cell: Vector2i) -> bool:
	refresh(sim)
	return float(_values.get(cell,0)) >= 0.2

func texture(sim) -> ImageTexture:
	refresh(sim)
	return _texture
