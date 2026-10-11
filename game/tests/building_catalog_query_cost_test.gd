extends SceneTree
const Catalog := preload("res://src/construction/building_catalog.gd")
class ObservedCatalog extends Catalog:
	var copies := 0
	func get_definition(id: String) -> Dictionary:
		copies += 1
		return super.get_definition(id)
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var catalog := ObservedCatalog.new()
	var definitions := catalog.all_definitions()
	catalog.copies = 0
	for definition: Dictionary in definitions:
		var id := String(definition.id)
		check(catalog.get_layer_id(id) == String(definition.get("layer_id","structure")),"Layer agrees with catalog data: " + id)
		check(catalog.is_floor(id) == (String(definition.get("layer_id","structure")) == "floor"),"Floor membership agrees with layer data: " + id)
		var size := Vector2i(maxi(1,int(definition.footprint.width)),maxi(1,int(definition.footprint.height)))
		check(catalog.get_footprint_size(id) == size,"Footprint size agrees with data: " + id)
		check(catalog.get_footprint_cells(id,Vector2i(10,12)).size() == size.x*size.y,"Cells agree with footprint size: " + id)
		check(catalog.get_texture_path(id) == String(definition.get("texture_path","")),"Texture path agrees with data: " + id)
		var expected_cost: Dictionary = {}
		for item: String in definition.get("material_cost",{}): expected_cost[item] = int(definition.material_cost[item])
		check(catalog.get_material_cost(id) == expected_cost,"Returned material cost agrees with normalized catalog data: " + id)
		check(catalog.get_work_minutes(id) == int(definition.get("work_minutes",0)),"Work minutes agree with valid catalog data: " + id)
	check(catalog.copies == 0,"Primitive and small catalog queries do not deep-copy complete definitions")
	check(catalog.get_layer_id("missing") == "structure" and catalog.get_footprint_size("missing") == Vector2i.ONE and catalog.get_material_cost("missing").is_empty() and catalog.get_work_minutes("missing") == 0,"Unknown content retains query defaults")
	var cost := catalog.get_material_cost("core:table")
	var original := cost.duplicate()
	cost.clear()
	check(catalog.get_material_cost("core:table") == original,"Returned material costs do not share live catalog dictionaries")
	var original_size := catalog.get_footprint_size("core:table")
	var definition := catalog.get_definition("core:table")
	definition.footprint.width = original_size.x + 1
	check(catalog.get_footprint_size("core:table") == original_size,"Public complete definitions remain isolated")
	print("BUILDING_CATALOG_QUERY_COST: %d failures" % failures)
	quit(0 if failures == 0 else 1)
