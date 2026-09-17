class_name InventoryPanel
extends PanelContainer

signal close_requested

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

func _ready() -> void:
	_close_button.pressed.connect(_on_close_button_pressed)


func present(
	title_text: String,
	weight_text: String,
	placements: Array[Dictionary]
) -> void:
	_title_label.text = title_text
	_weight_label.text = weight_text
	_inventory_grid.present(placements)


func _on_close_button_pressed() -> void:
	close_requested.emit()
