class_name InventoryPanel
extends PanelContainer

signal close_requested

const Localized := preload(
	"res://src/localization/localized_text.gd"
)
const PANEL_TEXTURE := preload(
	"res://assets/sprites/ui/panel_9patch.png"
)
const TAB_REGULAR_TEXTURE := preload(
	"res://assets/sprites/ui/tab_regular.png"
)
const TAB_HOVER_TEXTURE := preload(
	"res://assets/sprites/ui/tab_hover.png"
)
const TAB_ACTIVE_TEXTURE := preload(
	"res://assets/sprites/ui/tab_active.png"
)
const CLOSE_REGULAR_TEXTURE := preload(
	"res://assets/sprites/ui/x_mark_regular.png"
)
const CLOSE_HOVER_TEXTURE := preload(
	"res://assets/sprites/ui/x_mark_hover.png"
)

@onready var _title_label: Label = (
	$ContentMargin/ContentColumn/HeaderRow/TitleLabel as Label
)
@onready var _close_button: Button = (
	$ContentMargin/ContentColumn/HeaderRow/CloseButton as Button
)
@onready var _weight_label: Label = (
	$ContentMargin/ContentColumn/WeightLabel as Label
)
@onready var _inventory_grid: InventoryGrid = (
	$ContentMargin/ContentColumn/GridCenter/InventoryGrid
	as InventoryGrid
)
@onready var _details_label: Label = (
	$ContentMargin/ContentColumn/DetailsPanel/DetailsMargin/DetailsLabel
	as Label
)
@onready var _tab_buttons: Array[Button] = [
	$ContentMargin/ContentColumn/TabCenter/TabRow/Tab1 as Button,
	$ContentMargin/ContentColumn/TabCenter/TabRow/Tab2 as Button,
	$ContentMargin/ContentColumn/TabCenter/TabRow/Tab3 as Button,
	$ContentMargin/ContentColumn/TabCenter/TabRow/Tab4 as Button,
]


func _ready() -> void:
	_apply_panel_style()
	_apply_close_button_style()
	_apply_tab_styles()
	_close_button.pressed.connect(_on_close_button_pressed)
	_inventory_grid.selection_changed.connect(
		_on_inventory_selection_changed
	)
	_details_label.text = Localized.resolve(
		"ui.inventory.details.empty"
	)


func present(
	title_text: String,
	weight_text: String,
	placements: Array[Dictionary]
) -> void:
	_title_label.text = title_text
	_weight_label.text = weight_text
	_inventory_grid.present(placements)


func get_details_text() -> String:
	return _details_label.text


func _apply_panel_style() -> void:
	var panel_style := StyleBoxTexture.new()
	panel_style.texture = PANEL_TEXTURE
	panel_style.texture_margin_left = 20.0
	panel_style.texture_margin_top = 20.0
	panel_style.texture_margin_right = 20.0
	panel_style.texture_margin_bottom = 20.0
	add_theme_stylebox_override("panel", panel_style)


func _apply_close_button_style() -> void:
	var regular_style := _texture_style(CLOSE_REGULAR_TEXTURE)
	var hover_style := _texture_style(CLOSE_HOVER_TEXTURE)
	_close_button.add_theme_stylebox_override("normal", regular_style)
	_close_button.add_theme_stylebox_override("hover", hover_style)
	_close_button.add_theme_stylebox_override("pressed", hover_style)
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _apply_tab_styles() -> void:
	var regular_style := _texture_style(TAB_REGULAR_TEXTURE)
	var hover_style := _texture_style(TAB_HOVER_TEXTURE)
	var active_style := _texture_style(TAB_ACTIVE_TEXTURE)

	for index: int in range(_tab_buttons.size()):
		var button := _tab_buttons[index]
		button.add_theme_stylebox_override("normal", regular_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", active_style)
		button.add_theme_stylebox_override("disabled", regular_style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.tooltip_text = Localized.resolve(
			"ui.inventory.tab.items"
			if index == 0
			else "ui.inventory.tab.future"
		)

	_tab_buttons[0].button_pressed = true
	for index: int in range(1, _tab_buttons.size()):
		_tab_buttons[index].disabled = true


func _texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style


func _on_inventory_selection_changed(
	placement: Dictionary
) -> void:
	if placement.is_empty():
		_details_label.text = Localized.resolve(
			"ui.inventory.details.empty"
		)
		return

	_details_label.text = Localized.resolve(
		"ui.inventory.details.item",
		{
			"item": String(placement.get("label", "")),
			"amount": int(placement.get("amount", 1)),
			"weight": String.num(
				float(placement.get("total_weight", 0.0)),
				1
			),
		}
	)


func _on_close_button_pressed() -> void:
	close_requested.emit()
