class_name TouchState
extends RefCounted
## What the on-screen touch controls of this device report (CP2): both stick vectors and held buttons.
## The TouchOverlay writes it from InputEventScreenTouch/Drag, the TouchInput of the local player
## reads it once per physics frame. One device has one touch screen, so there is one shared state
## (shared()); tests create their own.

## The overlay hides when no TouchInput was polled for this long (pause menu, no player, loading).
const POLL_TIMEOUT_MSEC := 250
## Command-line switch that forces the touch controls on a desktop (screenshots, testing): -- touch=1
const FORCE_ARG := "touch=1"

static var _shared: TouchState = null

## Touch controls forced on (command line or tests): never switched off by keyboard or mouse.
var forced := false
## A finger touched the screen since the last keyboard or mouse use.
var touched := false
## Stick movement, length 0..1.
var move := Vector2.ZERO
## Aim stick (right), length 0..1 after its dead zone; Vector2.ZERO = not aiming.
var aim := Vector2.ZERO
## Written by TouchInput for the overlay: the local player is in a side-view segment (jump button).
var side_view := false
## Written by TouchInput: the local player can act (alive, not locked by a menu or an intro).
var can_play := false
## Written by TouchInput for the overlay's icons: WeaponData.WeaponType of the active weapon (-1 = none).
var weapon_type := -1
## Written by TouchInput: share of a button's cooldown that is left (0 = ready, 1 = just used).
var cooldowns: Dictionary[StringName, float] = {}

var _held: Dictionary[StringName, bool] = {}
var _went_down: Dictionary[StringName, bool] = {}
var _last_poll_msec := -POLL_TIMEOUT_MSEC - 1


## The state of this device's touch screen.
static func shared() -> TouchState:
	if _shared == null:
		_shared = TouchState.new()
		_shared.forced = is_forced_by_command_line()
	return _shared


## True on a device with a touch screen or when forced with -- touch=1.
static func is_touch_possible() -> bool:
	return shared().forced or DisplayServer.is_touchscreen_available()


static func is_forced_by_command_line() -> bool:
	return OS.get_cmdline_user_args().has(FORCE_ARG)


## Touch controls in use: forced, or the last input came from a finger.
func is_active() -> bool:
	return forced or touched


func press(action: StringName) -> void:
	if not _held.get(action, false):
		_went_down[action] = true
	_held[action] = true


func release(action: StringName) -> void:
	_held.erase(action)


func is_held(action: StringName) -> bool:
	return _held.get(action, false)


## The button went down since the last consume_presses() (a tap shorter than a frame counts too).
func went_down(action: StringName) -> bool:
	return _went_down.get(action, false)


func consume_presses() -> void:
	_went_down.clear()


## Nothing held, sticks centred (overlay hidden, fingers lost).
func release_all() -> void:
	_held.clear()
	_went_down.clear()
	move = Vector2.ZERO
	aim = Vector2.ZERO


## Share of the cooldown of action that is left (0 = ready).
func cooldown_share(action: StringName) -> float:
	return cooldowns.get(action, 0.0)


## Called by the polling TouchInput every physics frame.
func mark_polled(is_side_view: bool, player_can_play: bool) -> void:
	side_view = is_side_view
	can_play = player_can_play
	_last_poll_msec = Time.get_ticks_msec()


## The overlay should be visible: touch in use and a local player that can act was polled just now.
func wants_overlay() -> bool:
	return is_active() and can_play and Time.get_ticks_msec() - _last_poll_msec <= POLL_TIMEOUT_MSEC
