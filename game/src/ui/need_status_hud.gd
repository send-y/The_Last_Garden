extends Control

signal details_requested
const Localized := preload("res://src/localization/localized_text.gd")
const UiSkin := preload("res://src/ui/pixel_ui_skin.gd")
const KEYS: Array[String] = ["hunger", "energy", "restedness"]
const COLORS: Dictionary = {"hunger": Color("87a867"), "energy": Color("c99d48"), "restedness": Color("859dc2")}
var fills: Dictionary = {}
var labels: Dictionary = {}
var buttons: Dictionary = {}

func _ready() -> void:
	name = "PhysicalNeeds"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index: int in range(KEYS.size()):
		var key := KEYS[index]
		var button := Button.new()
		button.name = key.capitalize()
		button.position = Vector2(0, index * 20)
		button.size = Vector2(174, 18)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", UiSkin.card_style(Color("44353d"), UiSkin.BORDER_NORMAL))
		button.add_theme_stylebox_override("hover", UiSkin.card_style(Color("59424a"), UiSkin.BORDER_HOVER))
		button.pressed.connect(func() -> void: details_requested.emit())
		add_child(button)
		buttons[key] = button
		var title := Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.position = Vector2(5, 2)
		title.add_theme_font_size_override("font_size", 9)
		title.text = Localized.resolve("needs." + key)
		button.add_child(title)
		var background := ColorRect.new()
		background.position = Vector2(87, 4)
		background.size = Vector2(82, 10)
		background.color = Color("30272e")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(background)
		var fill := ColorRect.new()
		fill.position = background.position
		fill.size = background.size
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(fill)
		fills[key] = fill
		var number := Label.new()
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.position = Vector2(87, 2)
		number.add_theme_font_size_override("font_size", 9)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(number)
		number.size = Vector2(82, 14)
		labels[key] = number

func refresh(needs: Dictionary) -> void:
	for key: String in KEYS:
		var current := float(needs[key])
		var fill: ColorRect = fills[key]
		fill.size.x = 82 * current / 100
		fill.visible = current > 0
		fill.color = COLORS[key] if current >= 25 else Color("b35f52")
		labels[key].text = "%d/100" % roundi(current)
		labels[key].size = Vector2(82, 14)
		buttons[key].tooltip_text = Localized.resolve("needs.hint." + key) + "\n" + Localized.resolve("needs.details_hint")
