class_name DroppedItem
extends Area2D

signal pickup_requested(drop: DroppedItem)

var drop_id: String = ""
@export var item_id: String = "core:wood"
@export_range(1, 999, 1) var amount: int = 1
@export var icon: Texture2D
@export_range(0.1, 1.0, 0.05) var visual_scale: float = 0.5
@onready var _icon: Sprite2D = $Icon as Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = true

	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh_visual()

	body_entered.connect(_on_body_entered)


func configure(
	new_drop_id: String,
	new_item_id: String,
	new_amount: int,
	new_icon: Texture2D
) -> void:
	drop_id = new_drop_id
	item_id = new_item_id
	amount = maxi(1, new_amount)
	icon = new_icon

	if is_node_ready():
		_refresh_visual()


func _refresh_visual() -> void:
	_icon.texture = icon
	_icon.scale = Vector2.ONE * visual_scale


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		pickup_requested.emit(self)
