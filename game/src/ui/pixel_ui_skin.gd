class_name PixelUiSkin
extends RefCounted

const PANEL_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/panel_9patch.png"
)
const TAB_REGULAR_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/tab_regular.png"
)
const TAB_HOVER_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/tab_hover.png"
)
const TAB_ACTIVE_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/tab_active.png"
)
const CLOSE_REGULAR_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/x_mark_regular.png"
)
const CLOSE_HOVER_TEXTURE: Texture2D = preload(
	"res://assets/sprites/ui/x_mark_hover.png"
)

const TEXT_PRIMARY := Color8(239, 226, 207)
const TEXT_MUTED := Color8(202, 178, 151)
const TEXT_ACCENT := Color8(235, 207, 115)
const CARD_NORMAL := Color8(82, 58, 52, 245)
const CARD_HOVER := Color8(111, 75, 57, 250)
const CARD_PRESSED := Color8(61, 47, 57, 255)
const BORDER_NORMAL := Color8(70, 48, 57)
const BORDER_HOVER := Color8(211, 174, 105)


static func panel_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL_TEXTURE
	style.texture_margin_left = 20.0
	style.texture_margin_top = 20.0
	style.texture_margin_right = 20.0
	style.texture_margin_bottom = 20.0
	return style


static func card_style(
	background: Color,
	border: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8.0
	style.content_margin_top = 5.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 5.0
	return style


static func apply_card_button(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal", card_style(CARD_NORMAL, BORDER_NORMAL)
	)
	button.add_theme_stylebox_override(
		"hover", card_style(CARD_HOVER, BORDER_HOVER)
	)
	button.add_theme_stylebox_override(
		"pressed", card_style(CARD_PRESSED, TEXT_ACCENT)
	)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", TEXT_ACCENT)


static func apply_tab_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", texture_style(TAB_REGULAR_TEXTURE))
	button.add_theme_stylebox_override("hover", texture_style(TAB_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", texture_style(TAB_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", Color8(54, 42, 50))


static func apply_close_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", texture_style(CLOSE_REGULAR_TEXTURE))
	button.add_theme_stylebox_override("hover", texture_style(CLOSE_HOVER_TEXTURE))
	button.add_theme_stylebox_override("pressed", texture_style(CLOSE_HOVER_TEXTURE))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style
