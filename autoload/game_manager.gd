extends Node
## Owns the game phase, the set of active pause reasons and top-level scene changes.
## Several pause reasons may be active at once; the tree stays paused until all are released (D-043).
## A pause reason means "a menu holds this player". Whether that pauses the tree is the session's
## call (GameMode.pauses_for_menus): single player yes (D-043), group games no (D-085, D-123), there
## the WorldController protects the local player instead. pause_changed follows the menu state.

enum Phase { MENU, VILLAGE, DUNGEON }

signal pause_changed(is_paused: bool)
signal phase_changed(phase: Phase)

const PAUSE_SHOP: StringName = &"shop"
const PAUSE_WEAPON_CHOICE: StringName = &"weapon_choice"
const PAUSE_UPGRADE_CHOICE: StringName = &"upgrade_choice"
const PAUSE_UPGRADE_OVERVIEW: StringName = &"upgrade_overview"
const PAUSE_MENU: StringName = &"pause_menu"
const PAUSE_CONFIRM: StringName = &"confirm"
const PAUSE_RUN_END: StringName = &"run_end"

var _pause_reasons: Dictionary[StringName, bool] = {}
var _phase: Phase = Phase.MENU
## Menu state last reported through pause_changed.
var _menus_open := false


func _ready() -> void:
	# Must keep running while the tree is paused so pause reasons can be released.
	process_mode = Node.PROCESS_MODE_ALWAYS


func request_pause(reason: StringName) -> void:
	_pause_reasons[reason] = true
	_apply_pause_state()


func release_pause(reason: StringName) -> void:
	_pause_reasons.erase(reason)
	_apply_pause_state()


func has_pause_reason(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


func is_game_paused() -> bool:
	return not _pause_reasons.is_empty()


func clear_pause_reasons() -> void:
	_pause_reasons.clear()
	_apply_pause_state()


func get_phase() -> Phase:
	return _phase


func set_phase(phase: Phase) -> void:
	if phase == _phase:
		return
	_phase = phase
	phase_changed.emit(_phase)


## Switches the top-level scene (main menu <-> game). Stale pause reasons are dropped first.
func change_scene(path: String) -> Error:
	clear_pause_reasons()
	return get_tree().change_scene_to_file(path)


func _apply_pause_state() -> void:
	var menus_open := is_game_paused()
	var should_pause := menus_open and GameMode.of_tree(get_tree()).pauses_for_menus()
	var tree_changed := get_tree().paused != should_pause
	if tree_changed:
		get_tree().paused = should_pause
	if tree_changed or menus_open != _menus_open:
		_menus_open = menus_open
		pause_changed.emit(menus_open)
