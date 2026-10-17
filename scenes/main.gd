extends Control
## Main scene: hosts the main menu (ui/main_menu/main_menu.gd, MM1) and switches to the game once a
## save slot is loaded or created. Applies the global options (window mode, screen shake) at start.

const GAME_SCENE_PATH := "res://scenes/game.tscn"
## Phone held upright: game screen on top, controller field below (D-180), from the main menu on.
const PortraitMode := preload("res://ui/touch/portrait_mode.gd")

var menu: MainMenu = null


func _ready() -> void:
	GameManager.set_phase(GameManager.Phase.MENU)
	GameOptions.apply_all()
	GameCursor.use_pointer()
	PortraitMode.ensure(get_tree())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu = MainMenu.new()
	add_child(menu)
	# Behind the music player node of main.tscn (it draws nothing, order only keeps the tree tidy).
	move_child(menu, 0)
	menu.play_requested.connect(_on_play_requested)
	menu.quit_requested.connect(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if GameOptions.handle_shortcut(event):
		get_viewport().set_input_as_handled()


func _on_play_requested() -> void:
	GameManager.change_scene(GAME_SCENE_PATH)
