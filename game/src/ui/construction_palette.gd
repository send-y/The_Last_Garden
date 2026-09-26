class_name ConstructionPalette
extends Control

signal build_mode_toggled(active: bool)
signal building_selected(building_id: String)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const BUTTON_NORMAL: Texture2D = preload("res://assets/sprites/ui/bb_normal.png")
const BUTTON_ACTIVE: Texture2D = preload("res://assets/sprites/ui/bb_active.png")

var _menu_open: bool = false
var _selected_building_id: String = "core:wood_wall"

@onready var _build_button: TextureButton = $BuildButton as TextureButton
@onready var _build_menu: PanelContainer = $BuildMenu as PanelContainer
@onready var _mode_button: Button = $BuildMenu/Margin/Column/ModeButton as Button
@onready var _wall_button: Button = $BuildMenu/Margin/Column/Wall as Button
@onready var _workbench_button: Button = $BuildMenu/Margin/Column/Workbench as Button
@onready var _storage_button: Button = $BuildMenu/Margin/Column/Storage as Button


func _ready() -> void:
	_build_menu.add_theme_stylebox_override("panel", _menu_style())
	UiSkin.apply_card_button(_mode_button)
	UiSkin.apply_tab_button(_wall_button)
	UiSkin.apply_tab_button(_workbench_button)
	UiSkin.apply_tab_button(_storage_button)
	var building_group := ButtonGroup.new()
	_wall_button.button_group = building_group
	_workbench_button.button_group = building_group
	_storage_button.button_group = building_group
	_wall_button.button_pressed = true
	_build_button.tooltip_text = Localized.resolve("ui.construction.palette.start")
	_build_button.pressed.connect(_toggle_menu)
	_mode_button.toggled.connect(_on_mode_toggled)
	_wall_button.pressed.connect(_select_building.bind("core:wood_wall"))
	_workbench_button.pressed.connect(_select_building.bind("core:workbench"))
	_storage_button.pressed.connect(_select_building.bind("core:storage_zone"))
	_refresh_text()
	_build_menu.hide()


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
	_wall_button.text = Localized.resolve("ui.construction.palette.wall")
	_workbench_button.text = Localized.resolve("ui.construction.palette.workbench")
	_storage_button.text = Localized.resolve("ui.storage.zone.designate")


func _menu_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = preload("res://assets/sprites/ui/back_plane.png")
	style.texture_margin_left = 24.0
	style.texture_margin_top = 24.0
	style.texture_margin_right = 24.0
	style.texture_margin_bottom = 24.0
	return style
