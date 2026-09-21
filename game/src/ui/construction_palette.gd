class_name ConstructionPalette
extends PanelContainer

signal build_mode_toggled(active: bool)
signal building_selected(building_id: String)

const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")

var _selected_building_id: String = "core:wood_wall"

@onready var _mode_button: Button = $Margin/Column/ModeButton as Button
@onready var _building_row: HBoxContainer = $Margin/Column/BuildingRow as HBoxContainer
@onready var _wall_button: Button = $Margin/Column/BuildingRow/Wall as Button
@onready var _workbench_button: Button = $Margin/Column/BuildingRow/Workbench as Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UiSkin.panel_style())
	UiSkin.apply_card_button(_mode_button)
	UiSkin.apply_tab_button(_wall_button)
	UiSkin.apply_tab_button(_workbench_button)
	var group := ButtonGroup.new()
	_wall_button.button_group = group
	_workbench_button.button_group = group
	_wall_button.button_pressed = true
	_mode_button.toggled.connect(_on_mode_toggled)
	_wall_button.pressed.connect(_select_building.bind("core:wood_wall"))
	_workbench_button.pressed.connect(_select_building.bind("core:workbench"))
	_refresh_text()
	_building_row.hide()


func _on_mode_toggled(active: bool) -> void:
	_building_row.visible = active
	_refresh_text()
	build_mode_toggled.emit(active)


func _select_building(building_id: String) -> void:
	_selected_building_id = building_id
	building_selected.emit(building_id)


func _refresh_text() -> void:
	_mode_button.text = Localized.resolve(
		"ui.construction.palette.finish"
		if _mode_button.button_pressed
		else "ui.construction.palette.start"
	)
	_wall_button.text = Localized.resolve("ui.construction.palette.wall")
	_workbench_button.text = Localized.resolve("ui.construction.palette.workbench")
