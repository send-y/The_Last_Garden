class_name CropCatalog
extends RefCounted

const PATH := "res://content/core/crops.json"
var settings: Dictionary = {}
var crops: Array[Dictionary] = []


func _init() -> void:
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
		crops.append(crop.duplicate(true))


func find(id: String) -> Dictionary:
	for crop: Dictionary in crops:
		if [String(crop.id), String(crop.seed_id), String(crop.product_id)].has(id):
			return crop.duplicate(true)
	return {}
