extends Node2D

@onready var _player: PlayerController = $Player as PlayerController
@onready var _world: FirstNightWorld = $World as FirstNightWorld
@onready var _hud: FirstNightHud = $Hud/HudRoot as FirstNightHud
@onready var _dusk_overlay: ColorRect = $DuskOverlay/ColorRect as ColorRect


func _ready() -> void:
	_world.selection_changed.connect(_hud.set_selection)
	Session.state_reloaded.connect(_player.apply_loaded_position)
	Session.time_changed.connect(_update_dusk_overlay)
	_update_dusk_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_time"):
		Session.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_save"):
		Session.save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_load"):
		Session.load_game()
		get_viewport().set_input_as_handled()


func _update_dusk_overlay() -> void:
	var minute: int = Session.get_minute_of_day()
	var alpha: float = 0.0
	if minute >= 17 * 60:
		alpha = remap(clampf(float(minute), 17.0 * 60.0, 22.0 * 60.0), 17.0 * 60.0, 22.0 * 60.0, 0.0, 0.42)
	_dusk_overlay.color = Color(0.10, 0.13, 0.28, alpha)
