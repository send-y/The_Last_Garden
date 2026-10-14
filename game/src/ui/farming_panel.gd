class_name FarmingPanel
extends PanelContainer

signal close_requested
const Localized := preload("res://src/localization/localized_text.gd")
const Crops := preload("res://src/farming/crop_catalog.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
var cell := Vector2i(-1, -1)
var _column: VBoxContainer
var _crops: CropCatalog:
	get: return Session.simulation.farming.catalog
var _confirm_remove := false


func _ready() -> void:
	name = "FarmingPanel"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -145
	offset_right = 145
	offset_top = -130
	offset_bottom = 130
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	_column = VBoxContainer.new()
	margin.add_child(_column)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("493c2e")
	style.set_border_width_all(2)
	style.border_color = Color("b49469")
	add_theme_stylebox_override("panel", style)
	hide()


func present(target_cell: Vector2i) -> void:
	cell = target_cell
	_confirm_remove = false
	refresh()


func refresh() -> void:
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var status := Label.new()
	status.name = "Status"
	status.add_theme_font_size_override("font_size", 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(260, 34)
	status.text = Session.simulation.farming.status(Session.simulation, cell)
	_column.add_child(status)
	var bed := Session.get_farm_bed(cell)
	if bed.is_empty():
		close_requested.emit()
		return
	var shared := CheckButton.new()
	shared.name = "SharedHarvestPermission"
	shared.text = Localized.resolve("farming.shared.button")
	shared.tooltip_text = Localized.resolve("farming.shared.hint")
	shared.set_pressed_no_signal(bool(bed.get("shared_harvest",false)))
	shared.toggled.connect(func(enabled: bool) -> void:
		Session.execute_farming_command({"actor_id":"core:player","action_id":"set_shared_harvest","cell":[cell.x,cell.y],"enabled":enabled})
	)
	_column.add_child(shared)
	var crop := _crops.find(String(bed.crop_id))
	if crop.is_empty():
		for definition: Dictionary in _crops.crops:
			var seed_id := String(definition.seed_id)
			var count: int = Session.simulation.get_item_count(seed_id)
			_button("Plant_" + String(definition.id), Localized.resolve("farming.plant_button", {
				"crop": Localized.text_reference(String(definition.name_key)), "amount": count,
			}), "plant", seed_id, count <= 0)
	else:
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 11)
		var food: Dictionary = Session.simulation.content.item_food_profile(String(crop.product_id))
		info.text = Localized.resolve("farming.crop_info", {"yield": int(crop["yield"]), "energy": int(food.get("energy", 0))})
		_column.add_child(info)
		_button("HarvestButton", Localized.resolve("farming.harvest_button"), "harvest", "",
			int(bed.growth) < Session.simulation.farming._required_growth(bed, crop))
	var bucket: Dictionary = Session.get_active_item_instance()
	var has_water := Session.simulation.actor_tool_supports("core:player", "water") and int((bucket.get("state", {}) as Dictionary).get("charges", 0)) > 0
	var wet := int(bed.wet_until) > Session.simulation.get_elapsed_game_minutes()
	_button("WaterButton", Localized.resolve("farming.water_button" if has_water else "farming.equip_bucket"), "water", "", wet or not has_water)
	_button("RemoveButton", Localized.resolve("farming.remove_button"), "remove")
	var close := Button.new()
	close.add_theme_font_size_override("font_size", 12)
	close.name = "CloseButton"
	close.text = Localized.resolve("farming.close_button")
	UiSkin.apply_tab_button(close)
	close.pressed.connect(func() -> void: close_requested.emit())
	_column.add_child(close)


func _button(node_name: String, text: String, action: String, item_id: String = "", disabled: bool = false) -> void:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 12)
	button.name = node_name
	button.text = text
	UiSkin.apply_tab_button(button)
	button.disabled = disabled
	button.pressed.connect(func() -> void:
		if action == "remove" and not _confirm_remove:
			_confirm_remove = true
			button.text = Localized.resolve("farming.confirm_remove")
			return
		Session.execute_farming_command({"actor_id": "core:player", "action_id": action,
			"cell": [cell.x, cell.y], "item_id": item_id})
	)
	_column.add_child(button)
