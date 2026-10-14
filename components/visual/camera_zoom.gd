class_name CameraZoom
extends RefCounted
## How close the player camera is (M4, Makeover 3 §9): 1.25× while exploring (the figure looks
## bigger, rooms never fit the view completely), a short pull-out to 1.0× when a new room is entered
## (overview: where does it go?), 1.0× in boss rooms. Pure state: CameraRig asks for the value every
## frame and applies it. Zoom 1.0 = the old view (1280×720 world px); the HUD never scales with it.

## Exploring the dungeon. TESTWERT.
const DUNGEON := 1.25
## The short overview when a room is entered.
const OVERVIEW := 1.0
## Boss rooms: the whole fight in view. TESTWERT.
const BOSS := 1.0
## Campfire: the whole rest place in view (fire, portal, way on), like the boss room before it.
## TESTWERT (screenshot check M4: at 1.25 the way on is cut off).
const CAMPFIRE := 1.0
## Village: built for the 1280×720 view (several buildings per view). TESTWERT.
const VILLAGE := 1.0
## Pull-out timeline (s): out, overview held, back in. Sine in-out, never a jump. TESTWERTE.
const PULL_OUT_TIME := 0.35
const PULL_OUT_HOLD := 1.0
const PULL_IN_TIME := 0.8
## The overview waits for a running room intro (camera swing), but never longer than this (s).
const PULL_OUT_MAX := 4.0
## Other changes of the base zoom (into or out of a boss room).
const CHANGE_TIME := 0.6

## Zoom the view rests at (room type, village).
var base := DUNGEON
## Zoom right now.
var value := DUNGEON

var _pulled := false
var _pull_time := 0.0
var _from := DUNGEON
var _to := DUNGEON
var _time := 0.0
var _duration := 0.0


## Zoom a room rests at, by RoomSequence.RoomType.
static func for_room_type(room_type: int) -> float:
	match room_type:
		RoomSequence.RoomType.BOSS:
			return BOSS
		RoomSequence.RoomType.CAMPFIRE:
			return CAMPFIRE
	return DUNGEON


## New resting zoom; glides there unless instant (a running pull-out comes back to it).
func set_base(zoom_value: float, instant := false) -> void:
	base = zoom_value
	if instant:
		_pulled = false
		_snap(zoom_value)


## The overview on entering a room: out to 1.0×, hold, back to the base. Nothing where the base
## already shows as much (boss rooms).
func pull_out() -> void:
	if base <= OVERVIEW:
		return
	_pulled = true
	_pull_time = 0.0


func is_pulled_out() -> bool:
	return _pulled


## How far the view is out towards the overview right now: 0 at the base, 1 at OVERVIEW.
func get_pull_weight() -> float:
	if base <= OVERVIEW:
		return 0.0
	return clampf((base - value) / (base - OVERVIEW), 0.0, 1.0)


## Advances one frame and returns the zoom. hold: something still needs the overview (the room
## intro swings the camera to the goal), the way back waits for it (at most PULL_OUT_MAX).
func step(delta: float, hold := false) -> float:
	if _pulled:
		_pull_time += delta
		var held_enough := _pull_time >= PULL_OUT_TIME + PULL_OUT_HOLD
		if held_enough and (not hold or _pull_time >= PULL_OUT_MAX):
			_pulled = false
	var target := OVERVIEW if _pulled else base
	if not is_equal_approx(target, _to):
		_begin(target, _transition_time(target))
	if _duration > 0.0 and _time < _duration:
		_time = minf(_time + delta, _duration)
		var t := _time / _duration
		value = lerpf(_from, _to, 0.5 - 0.5 * cos(PI * t))
	else:
		value = _to
	return value


func _transition_time(target: float) -> float:
	if _pulled:
		return PULL_OUT_TIME
	if is_equal_approx(_to, OVERVIEW) and target > OVERVIEW:
		return PULL_IN_TIME
	return CHANGE_TIME


func _begin(target: float, duration: float) -> void:
	_from = value
	_to = target
	_time = 0.0
	_duration = duration


func _snap(zoom_value: float) -> void:
	value = zoom_value
	_from = zoom_value
	_to = zoom_value
	_time = 0.0
	_duration = 0.0
