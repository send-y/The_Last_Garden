extends SceneTree

const Fixture := preload("res://tests/fixtures/resident_home_fixture.gd")
const Catalog := preload("res://src/construction/building_catalog.gd")
const Trace := preload("res://src/dev/diagnostic_trace.gd")
const Lighting := preload("res://src/furniture/lighting_field.gd")
class CountingCatalog extends Catalog:
	var reads := 0
	func get_definition(id: String) -> Dictionary:
		reads += 1
		return super.get_definition(id)
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	_test_storage()
	if not "--only=storage" in OS.get_cmdline_user_args():
		_test_furniture_and_light()
		_test_sequential_lights()
	print("INDEXED_CONSUMERS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func _test_storage() -> void:
	var sim = Fixture.create()
	var catalog := CountingCatalog.new()
	sim.building_catalog = catalog
	for _query: int in range(10):
		check(sim.get_storage_grid_size(Vector2i(41,31)) == Vector2i(3,3),"Floor grants the larger real storage grid")
		check(sim.get_storage_grid_size(Vector2i(7,10)) == Vector2i(3,2),"Bare ground retains the smaller storage grid")
		check(sim._storage_cell_has_floor(Vector2i(41,31)),"Storage floor membership reads the actual floor")
	check(catalog.reads == 0,"Warm storage floor queries do not inspect structure definitions")
	sim.add_structure({"building_id":"core:wood_floor","cell":[7,10]})
	check(sim.get_storage_grid_size(Vector2i(7,10)) == Vector2i(3,3),"New floor expands storage immediately")
	sim.remove_structure({"building_id":"core:wood_floor","cell":[7,10]})
	check(sim.get_storage_grid_size(Vector2i(7,10)) == Vector2i(3,2),"Removed floor shrinks storage immediately")
func _test_furniture_and_light() -> void:
	var sim = Fixture.create()
	sim.add_structure({"building_id":"core:table","cell":[41,31]})
	sim.add_structure({"building_id":"core:chair","cell":[41,32]})
	var torch := {"building_id":"core:torch","cell":[42,32],"lit":true}
	sim.add_structure(torch)
	sim.state.minute_of_day = 21 * 60
	check(sim.furniture.seat_at(sim,[41,32]).table_cell == [41,31],"Indexed table supports its actual adjacent chair")
	check(sim.is_cell_lit(Vector2i(41,32)),"Actual lit torch illuminates the chair at night")
	var texture = sim.furniture.lighting.texture(sim)
	Trace.reset()
	Trace.enabled = true
	for _query: int in range(20):
		check(sim.is_cell_lit(Vector2i(41,32)),"Warm light queries preserve real light")
		check(sim.furniture.seat_at(sim,[41,32]).table_cell == [41,31],"Warm furniture query preserves adjacency")
	Trace.enabled = false
	var spans: Dictionary = Trace.snapshot().spans
	check(spans.get("lighting.serialize_structures",{}).get("calls",0) == 0,"Warm light queries never serialize structures")
	check(spans.get("furniture.serialize_structures",{}).get("calls",0) == 0,"Warm furniture queries never serialize structures")
	check(sim.furniture.lighting.texture(sim) == texture,"Unchanged artificial light retains its texture")
	sim.set_structure_state(torch,"lit",false)
	check(not sim.is_cell_lit(Vector2i(41,32)),"Toggle is visible in the next logical light query")
	sim.remove_structure({"building_id":"core:table","cell":[41,31]})
	check(sim.furniture.seat_at(sim,[41,32]).table_cell.is_empty(),"Removed table no longer supports meals")
	var other = Fixture.create()
	other.state.minute_of_day = 21 * 60
	other.add_structure({"building_id":"core:torch","cell":[42,32],"lit":true})
	var shared := Lighting.new()
	check(shared.has_artificial_light(other,Vector2i(41,32)),"Independent world supplies its own light")
	var dark = Fixture.create()
	dark.add_structure({"building_id":"core:torch","cell":[42,32],"lit":false})
	check(other.structure_index.lighting_revision == dark.structure_index.lighting_revision,"Fixture worlds have matching lighting versions")
	check(not shared.has_artificial_light(dark,Vector2i(41,32)),"Matching versions cannot reuse another world's light mask")

func _test_sequential_lights() -> void:
	var sim = Fixture.create()
	var torches: Array[Dictionary] = []
	for i: int in range(30):
		var record := {"building_id":"core:torch","cell":[40+(i%6)*14,42+(i/6)*14],"lit":false}
		sim.add_structure(record)
		torches.append(record)
	var light = sim.furniture.lighting
	check(not light.has_artificial_light(sim,Vector2i(40,42)),"Thirty off torches supply no artificial light")
	Trace.reset()
	Trace.enabled = true
	for i: int in range(torches.size()):
		sim.set_structure_state(torches[i],"lit",true)
		var cell := Vector2i(int(torches[i].cell[0]),int(torches[i].cell[1]))
		check(light.has_artificial_light(sim,cell),"Each intermediate torch version is immediately visible")
		if i+1 < torches.size():
			var next := Vector2i(int(torches[i+1].cell[0]),int(torches[i+1].cell[1]))
			check(not light.has_artificial_light(sim,next),"Later unlit torches stay dark during sequential changes")
	Trace.enabled = false
	check(Trace.snapshot().spans.get("lighting.rebuild",{}).get("calls",0) == 30,"One mask rebuild per observed intermediate light version")
