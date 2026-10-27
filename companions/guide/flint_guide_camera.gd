class_name FlintGuideCamera
extends RefCounted
## Camera hook of "Flint erklärt" (KONZEPT §7.2, D-184): flies only the explained player's own camera
## (the player's child "Camera2D", a CameraRig) to the goals of a tour and home again. It works like
## the room intro's swing (RoomIntro._swing_cameras): it tweens the camera node's position relative
## to the player; CameraRig sees an aimed camera and lets go of its follow lead, offset, zoom and
## shake stay the rig's. Nobody else's camera moves, nothing pauses.
## A player without an enabled camera (a remote player, a headless host) gets no camera ride.

const CAMERA_NODE := ^"Camera2D"

var camera: Camera2D = null
## The camera's position before the ride (normally Vector2.ZERO: centred on the player).
var home := Vector2.ZERO
var _tween: Tween = null
var _active := false
var _last_target := Vector2.ZERO


## The camera ride of player, or null when the player has no enabled camera of his own.
static func for_player(player: Node2D) -> FlintGuideCamera:
	if player == null or not is_instance_valid(player):
		return null
	var found := player.get_node_or_null(CAMERA_NODE) as Camera2D
	if found == null or not found.enabled:
		return null
	var ride := FlintGuideCamera.new()
	ride.camera = found
	# Home is where the camera rests before the tour; a later goal never moves it (a ride can start
	# while the camera is still on its way back from the previous goal).
	ride.home = found.position
	return ride


## Flies the camera so it shows the global point goal (at most max_distance px from the player,
## 0 = no limit) in time seconds.
func look_at(goal: Vector2, max_distance := 0.0, time := FlintGuideRules.CAMERA_PAN_TIME) -> void:
	if not _usable() or goal == Vector2.INF:
		return
	_active = true
	var carrier := camera.get_parent() as Node2D
	var target := goal - carrier.global_position
	if max_distance > 0.0:
		target = target.limit_length(max_distance)
	_move_to(target, time)


## Brings the camera back to the player (end of a tour, a step without a goal).
func return_home(time := FlintGuideRules.CAMERA_RETURN_TIME) -> void:
	if not _active:
		return
	_active = false
	if _usable():
		_move_to(home, time)


## Puts the camera home at once (the guide is freed mid-ride).
func release_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _active and _usable():
		camera.position = home
	_active = false


## True while the camera is away from the player (or on its way).
func is_away() -> bool:
	return _active


## Where the camera is headed relative to the player (tests).
func get_target() -> Vector2:
	return _last_target


func _move_to(target: Vector2, time: float) -> void:
	_last_target = target
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if time <= 0.0 or not camera.is_inside_tree():
		camera.position = target
		_tween = null
		return
	_tween = camera.create_tween()
	_tween.tween_property(camera, "position", target, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _usable() -> bool:
	return camera != null and is_instance_valid(camera) and camera.get_parent() is Node2D
