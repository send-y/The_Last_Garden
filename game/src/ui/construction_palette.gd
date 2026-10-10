class_name ConstructionPalette
extends Control

signal build_mode_toggled(active: bool)
signal building_selected(building_id: String)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const BuildingCatalogScript := preload("res://src/construction/building_catalog.gd")
const BUTTON_NORMAL: Texture2D = preload("res://assets/sprites/ui/bb_normal.png")
const BUTTON_ACTIVE: Texture2D = preload("res://assets/sprites/ui/bb_active.png")

const CATEGORIES: Array[Dictionary] = [
	{"id": "core:wall", "label_key": "ui.construction.category.walls"},
	{"id": "core:floor", "label_key": "ui.construction.category.floors"},
	{"id": "core:furniture", "label_key": "ui.construction.category.furniture"},
	{"id": "other", "label_key": "ui.construction.category.other"},
]

var _menu_open: bool = false
var _selected_building_id: String = "core:wood_wall"
var _active_category_id: String = "core:wall"
var _definitions: Array[Dictionary] = []
var _category_group: ButtonGroup
var _building_group: ButtonGroup

@onready var _build_button: TextureButton = $BuildButton as TextureButton
@onready var _build_menu: PanelContainer = $BuildMenu as PanelContainer
@onready var _mode_button: Button = $BuildMenu/Margin/Column/ModeButton as Button
@onready var _categories: HBoxContainer = $BuildMenu/Margin/Column/Categories as HBoxContainer
@onready var _choices: GridContainer = $BuildMenu/Margin/Column/Scroll/Choices as GridContainer


func _ready() -> void:
	_build_menu.add_theme_stylebox_override("panel", _menu_style())
	UiSkin.apply_card_button(_mode_button)
	_definitions = BuildingCatalogScript.new().all_definitions()
	_category_group = ButtonGroup.new()
	_building_group = ButtonGroup.new()
	_building_group.allow_unpress = false
	_build_choices()
	_build_category_buttons()
	_build_button.tooltip_text = Localized.resolve("ui.construction.palette.start")
	_build_button.pressed.connect(_toggle_menu)
	_mode_button.toggled.connect(_on_mode_toggled)
	_refresh_text()
	_build_menu.hide()


func _build_category_buttons() -> void:
	for category: Dictionary in CATEGORIES:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 24)
		button.toggle_mode = true
		button.button_group = _category_group
		button.add_theme_font_size_override("font_size", 8)
		button.text = Localized.resolve(String(category["label_key"]))
		UiSkin.apply_tab_button(button)
		var category_id := String(category["id"])
		button.pressed.connect(_select_category.bind(category_id))
		_categories.add_child(button)
		if category_id == _active_category_id:
			button.button_pressed = true


func _build_choices() -> void:
	for child: Node in _choices.get_children():
		child.queue_free()

	var catalog := BuildingCatalogScript.new()
	for definition: Dictionary in _definitions:
		if _get_category_id(definition) != _active_category_id:
			continue
		_add_building_choice(definition, catalog)

	if _active_category_id == "other":
		_add_room_choice("core:storage_room", "ui.room.plan.storage")
		_add_room_choice("core:living_room", "ui.room.plan.living")


func _add_building_choice(definition: Dictionary, catalog: RefCounted) -> void:
	var building_id := String(definition.get("id", ""))
	var choice := Button.new()
	choice.custom_minimum_size = Vector2(104, 36)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.toggle_mode = true
	choice.button_group = _building_group
	choice.add_theme_font_size_override("font_size", 8)
	choice.text = _format_building_choice(definition, catalog)
	choice.tooltip_text = Localized.resolve(String(definition.get("label_key", "")))
	UiSkin.apply_tab_button(choice)
	choice.pressed.connect(_select_building.bind(building_id))
	_choices.add_child(choice)
	if building_id == _selected_building_id:
		choice.button_pressed = true


func _add_room_choice(room_type_id: String, label_key: String) -> void:
	var choice := Button.new()
	choice.custom_minimum_size = Vector2(104, 36)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.toggle_mode = true
	choice.button_group = _building_group
	choice.add_theme_font_size_override("font_size", 8)
	choice.text = Localized.resolve(label_key)
	UiSkin.apply_tab_button(choice)
	choice.pressed.connect(_select_building.bind(room_type_id))
	_choices.add_child(choice)
	if _selected_building_id == room_type_id:
		choice.button_pressed = true


func _get_category_id(definition: Dictionary) -> String:
	var category_id := String(definition.get("category_id", "other"))
	for category: Dictionary in CATEGORIES:
		if String(category["id"]) == category_id:
			return category_id
	return "other"


func _select_category(category_id: String) -> void:
	_active_category_id = category_id
	_build_choices()


func _toggle_menu() -> void:
	_menu_open = not _menu_open
	_build_menu.visible = _menu_open
	_build_button.texture_normal = BUTTON_ACTIVE if _menu_open else BUTTON_NORMAL
	_build_button.texture_hover = BUTTON_ACTIVE if _menu_open else preload("res://assets/sprites/ui/bb_hover.png")
	if not _menu_open and _mode_button.button_pressed:
		_mode_button.button_pressed = false


func _on_mode_toggled(active: bool) -> void:
	_refresh_text()
	build_mode_toggled.emit(active)


func _select_building(building_id: String) -> void:
	_selected_building_id = building_id
	building_selected.emit(building_id)


func is_build_mode_active() -> bool:
	return _mode_button.button_pressed


func _refresh_text() -> void:
	_mode_button.text = Localized.resolve(
		"ui.construction.palette.finish"
		if _mode_button.button_pressed
		else "ui.construction.palette.start"
	)


func _format_building_choice(definition: Dictionary, catalog: RefCounted) -> String:
	var name := Localized.resolve(String(definition.get("label_key", "")))
	var cost: Dictionary = catalog.get_material_cost(String(definition.get("id", "")))
	var cost_parts := PackedStringArray()
	for item_variant: Variant in cost.keys():
		var item_id := String(item_variant)
		cost_parts.append("%d %s" % [
			int(cost[item_variant]),
			Localized.resolve("item.%s.name" % item_id.replace(":", ".")),
		])
	if cost_parts.is_empty():
		return name
	return "%s\n%s" % [name, " · ".join(cost_parts)]


func _menu_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://assets/sprites/ui/back_plane.png")
	style.texture_margin_left = 24.0
	style.texture_margin_top = 24.0
	style.texture_margin_right = 24.0
	style.texture_margin_bottom = 24.0
	return style
