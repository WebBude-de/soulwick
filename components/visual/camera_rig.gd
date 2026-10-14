class_name CameraRig
extends Camera2D
## Player camera (child "Camera2D" of the player).
##
## Follow and zoom (M4, Makeover 3 §9): the view follows camera_targets() closely with a small dead
## zone and a small, slowly changing lead in the walking direction (CameraFollow), 1.25× close in the dungeon with a short pull-out to
## 1.0× on entering a room and 1.0× in boss rooms (CameraZoom). The rig only reacts: the dungeon
## announces rooms (room_activated), RoomIntro may swing the node's position to a goal, both stay
## untouched. Everything is applied through offset and zoom, never through position (that belongs to
## RoomIntro) and never to the HUD (CanvasLayers do not scale).
##
## Trauma-based screen shake: trauma decays over time, the offset grows with trauma² and follows
## smooth noise, so small hits jiggle and big explosions really rumble. While stunned the view tilts
## to one side and sways ("the screen goes crooked"). Shake is sized for zoom 1.0 and divided by the
## zoom, so it looks the same on screen at every zoom.
##
## Coop (M4 hook): camera_targets() is the single place that says what the camera keeps in view.
## Today the player carrying this camera; the multiplayer session hands in a provider
## (set_targets_provider: group middle, catch-up) without touching the follow or zoom logic.

const MAX_OFFSET := 18.0
const MAX_ROLL := 0.035
const DECAY_PER_SECOND := 1.8
## Stun sway: constant tilt plus a slow swing, in radians, and a drifting offset in px.
const STUN_TILT := 0.11
const STUN_SWING := 0.05
const STUN_DRIFT := 10.0
const STUN_FADE_IN := 0.15
const STUN_FADE_OUT := 0.3
## A node position longer than this (world px) means someone aims the camera (RoomIntro swing).
const AIMED_THRESHOLD := 0.5
## During the entry overview the view leans this far (world px) towards the middle of the room, so
## the overview shows where it goes, not the corridor behind. TESTWERT.
const OVERVIEW_LEAN := 240.0
const OVERVIEW_LEAN_SPEED := 5.0

var _trauma := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _sway_left := 0.0
var _sway_total := 0.0
var _sway_time := 0.0
var _sway_side := 1.0

var _follow := CameraFollow.new()
var _zoom := CameraZoom.new()
var _targets_provider := Callable()
## Room the dungeon activated last (zoom hold during its intro).
var _room: Node = null
## Offset that puts the view on the follow centre, without shake (also moves AmbientParticles).
var _view_offset := Vector2.ZERO
## Current lean of the entry overview (world px).
var _lean := Vector2.ZERO


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 0.9
	ignore_rotation = false
	# The rig smooths itself (CameraFollow); the built-in smoothing would lag behind the offset.
	position_smoothing_enabled = false
	# Before the overlays that read the canvas transform (vision circle, post-process) this frame.
	process_priority = -10
	_connect_world()
	_zoom.set_base(_resting_zoom(), true)
	zoom = Vector2.ONE * _zoom.value


# --- Coop hook: what the camera keeps in view ---

## The nodes the camera keeps in view (M4 coop hook). Default: the player carrying this camera.
func camera_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if _targets_provider.is_valid():
		for node: Variant in _targets_provider.call():
			if not is_instance_valid(node):
				continue
			var target := node as Node2D
			if target != null and target.is_inside_tree():
				result.append(target)
		return result
	var carrier := get_parent() as Node2D
	if carrier != null:
		result.append(carrier)
	return result


## Replaces camera_targets() (multiplayer: the group). provider returns an Array of Node2D; an
## empty Callable goes back to the carrier.
func set_targets_provider(provider: Callable) -> void:
	_targets_provider = provider


# --- Zoom ---

## The room the dungeon just activated (room_activated): resting zoom by room type plus the
## overview pull-out. Public for tools and tests.
func enter_room(room_type: int, room: Node = null) -> void:
	_room = room
	_zoom.set_base(CameraZoom.for_room_type(room_type))
	_zoom.pull_out()


func get_zoom_state() -> CameraZoom:
	return _zoom


func get_follow() -> CameraFollow:
	return _follow


## Puts the view on the targets at once (after a teleport; big jumps snap by themselves).
func snap_to_targets() -> void:
	_follow.reset(_follow_point(camera_targets()))


# --- Shake ---

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Tilts and sways the view for duration seconds (player stun).
func stun_sway(duration: float) -> void:
	if duration <= 0.0:
		return
	if _sway_left <= 0.0:
		_sway_side = -1.0 if randf() < 0.5 else 1.0
		_sway_time = 0.0
	_sway_left = maxf(_sway_left, duration)
	_sway_total = maxf(_sway_left, 0.001)


func get_sway_amount() -> float:
	if _sway_left <= 0.0:
		return 0.0
	var fade_in := clampf((_sway_total - _sway_left) / STUN_FADE_IN, 0.0, 1.0)
	var fade_out := clampf(_sway_left / STUN_FADE_OUT, 0.0, 1.0)
	var amount := minf(fade_in, fade_out)
	return amount * amount * (3.0 - 2.0 * amount)


func _process(delta: float) -> void:
	var shake_offset := Vector2.ZERO
	var roll := 0.0
	if _trauma > 0.0:
		_time += delta * 60.0
		_trauma = maxf(0.0, _trauma - DECAY_PER_SECOND * delta)
		var shake := _trauma * _trauma
		shake_offset = Vector2(_noise.get_noise_2d(_time, 0.0), _noise.get_noise_2d(0.0, _time)) * MAX_OFFSET * shake
		roll = _noise.get_noise_2d(_time, _time) * MAX_ROLL * shake
	if _sway_left > 0.0:
		_sway_left = maxf(0.0, _sway_left - delta)
		_sway_time += delta
		var sway := get_sway_amount() if _sway_left > 0.0 else 0.0
		roll += (STUN_TILT * _sway_side + STUN_SWING * sin(_sway_time * 5.0)) * sway
		shake_offset += Vector2(sin(_sway_time * 3.7), sin(_sway_time * 2.9) * 0.6) * STUN_DRIFT * sway
	zoom = Vector2.ONE * _zoom.step(delta, _intro_holds_overview())
	_update_view(delta)
	# Shake is sized for zoom 1.0: the same on screen at every zoom.
	offset = _view_offset + shake_offset / zoom.x
	rotation = roll


# --- Follow ---

## Moves the view onto the follow centre. Camera2D clamps its own position to the limits and adds
## offset afterwards, so the offset is measured from that clamped centre.
func _update_view(delta: float) -> void:
	var targets := camera_targets()
	var aimed := position.length() > AIMED_THRESHOLD
	var point := _follow_point(targets)
	var center := _follow.step(point, delta, _targets_velocity(targets), aimed)
	# An intro swing shows its own goal: the lean lets go (softly, the swing is a tween too).
	var lean_target := Vector2.ZERO if aimed else _room_lean(point) * _zoom.get_pull_weight()
	_lean = _lean.lerp(lean_target, 1.0 - exp(-OVERVIEW_LEAN_SPEED * delta))
	var engine_center := clamp_to_limits(global_position)
	_view_offset = clamp_to_limits(center + _lean + position) - engine_center
	for child in get_children():
		if child is AmbientParticles:
			# Ambient particles rain around what is seen, not around the player.
			(child as Node2D).position = _view_offset


func _follow_point(targets: Array[Node2D]) -> Vector2:
	if targets.is_empty():
		return global_position - position
	var sum := Vector2.ZERO
	for target in targets:
		sum += target.global_position
	return sum / float(targets.size())


## Direction to the middle of the activated room (its floor, RoomController.get_arena), at most
## OVERVIEW_LEAN long.
func _room_lean(point: Vector2) -> Vector2:
	if _room == null or not is_instance_valid(_room) or not _room.has_method(&"get_arena"):
		return Vector2.ZERO
	var floor_rect: Rect2 = _room.call(&"get_arena")
	return (floor_rect.get_center() - point).limit_length(OVERVIEW_LEAN)


## Mean walking velocity of the targets (INF: let CameraFollow derive it from the positions).
func _targets_velocity(targets: Array[Node2D]) -> Vector2:
	if targets.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for target in targets:
		var body := target as CharacterBody2D
		if body == null:
			return Vector2.INF
		sum += body.velocity
	return sum / float(targets.size())


## Where Camera2D puts a view centred on point with the current limits and zoom (same order as
## the engine: left, right, bottom, top).
func clamp_to_limits(point: Vector2) -> Vector2:
	if not limit_enabled:
		return point
	var size := get_viewport_rect().size / zoom
	var corner := point - size * 0.5
	if corner.x < limit_left:
		corner.x = limit_left
	if corner.x + size.x > limit_right:
		corner.x = limit_right - size.x
	if corner.y + size.y > limit_bottom:
		corner.y = limit_bottom - size.y
	if corner.y < limit_top:
		corner.y = limit_top
	return corner + size * 0.5


# --- World ---

## The dungeon announces every room it activates (room_activated); the camera only listens.
func _connect_world() -> void:
	var world := _world()
	if world != null and world.has_signal(&"room_activated") and not world.is_connected(&"room_activated", _on_room_activated):
		world.connect(&"room_activated", _on_room_activated)


func _world() -> Node:
	var carrier := get_parent()
	return carrier.get_parent() if carrier != null else null


## Village and other worlds without rooms rest at VILLAGE, the dungeon at DUNGEON until its first
## room says otherwise.
func _resting_zoom() -> float:
	var world := _world()
	if world != null and world.has_signal(&"room_activated"):
		return CameraZoom.DUNGEON
	return CameraZoom.VILLAGE


func _on_room_activated(room: Node) -> void:
	if room == null or not is_instance_valid(room):
		return
	var room_type: Variant = room.get(&"room_type")
	enter_room(int(room_type) if room_type is int else RoomSequence.RoomType.COMBAT, room)


## A room intro still swings the camera to its goal (or holds the players before it): keep the
## overview until the countdown starts.
func _intro_holds_overview() -> bool:
	if _room == null or not is_instance_valid(_room):
		return false
	var intro := RoomIntro.get_intro(_room)
	return intro != null and intro.phase < RoomIntro.Phase.COUNTDOWN
