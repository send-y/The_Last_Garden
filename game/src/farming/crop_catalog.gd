class_name CropCatalog
extends RefCounted

const PATH := "res://content/core/crops.json"
var settings: Dictionary = {}
var crops: Array[Dictionary] = []


var reference_errors: Array[String] = []

func _init(item_content: FirstNightContent = null) -> void:
	var content := item_content if item_content != null else FirstNightContent.new()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read crop catalog")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		push_error("Invalid crop catalog")
		return
	settings = parsed
	for value: Variant in settings.get("crops", []):
		if not value is Dictionary:
			continue
		var crop: Dictionary = value
		if not ["single", "multiple", "perennial"].has(crop.get("harvest_mode")):
			push_error("Invalid crop harvest mode")
			continue
		if int(crop.get("growth_minutes", 0)) <= 0 or int(crop.get("yield", 0)) <= 0:
			push_error("Invalid crop growth or yield")
			continue
		var refs: Array[Dictionary] = []
		for field: String in ["seed_id", "product_id"]:
			refs.append({"source_path": PATH, "owner_id": String(crop.get("id", "")), "field": field, "item_id": String(crop.get(field, ""))})
		var errors := content.validate_item_references(refs)
		reference_errors.append_array(errors)
		content.report_reference_errors(errors)
		if errors.is_empty():
			crops.append(crop.duplicate(true))


func find(id: String) -> Dictionary:
	for crop: Dictionary in crops:
		if [String(crop.id), String(crop.seed_id), String(crop.product_id)].has(id):
			return crop.duplicate(true)
	return {}
