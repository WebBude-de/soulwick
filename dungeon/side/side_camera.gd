class_name SideCamera
extends Camera2D
## Camera of a side segment (M5): follows horizontally with a look-ahead in the running direction,
## vertically only when the players change level (the height of the platform they stand on), never
## past the segment's edges. The players it follows come from camera_targets() - today the players
## of this machine; the co-op later puts the group's middle there (SideSegment.camera_targets).
## Knows add_trauma, so CameraShake works in the segment as everywhere else, and kick() for a short
## push (a hard landing, round 2).

## TESTWERTE
const LOOK_AHEAD := 110.0
const LOOK_AHEAD_SPEED := 260.0
const FOLLOW_X := 7.0
const FOLLOW_Y := 3.5
## Where the feet sit on screen when the view must scroll vertically (share of the view height).
const FEET_SCREEN_SHARE := 0.66
const MAX_SHAKE := 16.0
## The view may go this far below the plan (rock drawn there, SideTiles.DEPTH_ROWS), so the lowest
## floor stays above the HUD at the bottom of the screen.
const BOTTOM_MARGIN := 128.0
const SHAKE_DECAY := 1.8
## A kick springs back within about this many seconds (TESTWERT).
const KICK_RETURN_SPEED := 18.0

var segment: SideSegment = null

var _look := 0.0
var _anchor_y := 0.0
var _trauma := 0.0
var _time := 0.0
var _kick := Vector2.ZERO


## The players the camera keeps in view (hook for the co-op group camera).
func camera_targets() -> Array[Player]:
	return segment.camera_targets() if segment != null else ([] as Array[Player])


## Jumps to the target view at once (on entering).
func snap() -> void:
	var targets := camera_targets()
	if targets.is_empty():
		return
	_anchor_y = _mean_feet_y(targets)
	_look = LOOK_AHEAD * _mean_facing(targets)
	global_position = _desired(targets)
	reset_smoothing()


## A short push of the view (px), springing back at once: a hard landing.
func kick(amount: Vector2) -> void:
	_kick += amount


func get_kick() -> Vector2:
	return _kick


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Visible world rectangle around the camera centre.
func get_view_rect() -> Rect2:
	var view := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - view * 0.5, view)


func _process(delta: float) -> void:
	var targets := camera_targets()
	if not targets.is_empty():
		_look = move_toward(_look, LOOK_AHEAD * _mean_facing(targets), LOOK_AHEAD_SPEED * delta)
		if _all_standing(targets):
			_anchor_y = _mean_feet_y(targets)
		var desired := _desired(targets)
		global_position.x = lerpf(global_position.x, desired.x, 1.0 - exp(-FOLLOW_X * delta))
		global_position.y = lerpf(global_position.y, desired.y, 1.0 - exp(-FOLLOW_Y * delta))
	_time += delta
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-KICK_RETURN_SPEED * delta))
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
		var shake := _trauma * _trauma * MAX_SHAKE
		offset = Vector2(sin(_time * 47.0), cos(_time * 39.0)) * shake + _kick
	else:
		offset = _kick


func _desired(targets: Array[Player]) -> Vector2:
	var x := 0.0
	for player in targets:
		x += player.global_position.x
	x /= targets.size()
	var view := get_viewport_rect().size / zoom
	var desired := Vector2(x + _look, _anchor_y - view.y * (FEET_SCREEN_SHARE - 0.5))
	if segment == null:
		return desired
	var bounds := Rect2(segment.global_position, segment.layout.world_size() + Vector2(0, BOTTOM_MARGIN))
	desired.x = _clamp_axis(desired.x, bounds.position.x, bounds.end.x, view.x)
	desired.y = _clamp_axis(desired.y, bounds.position.y, bounds.end.y, view.y)
	# A player above or below the view pulls it along (falling, a tall jump).
	for player in targets:
		var feet := player.get_feet_position().y
		if feet > desired.y + view.y * 0.5 - 24.0 and feet < bounds.end.y:
			desired.y = _clamp_axis(feet - view.y * 0.5 + 24.0, bounds.position.y, bounds.end.y, view.y)
		elif feet - 64.0 < desired.y - view.y * 0.5:
			desired.y = _clamp_axis(feet - 64.0 + view.y * 0.5, bounds.position.y, bounds.end.y, view.y)
	return desired


## Keeps the view inside [low, high]; a view larger than the range sits in its middle.
static func _clamp_axis(value: float, low: float, high: float, view: float) -> float:
	if view >= high - low:
		return (low + high) * 0.5
	return clampf(value, low + view * 0.5, high - view * 0.5)


static func _mean_feet_y(targets: Array[Player]) -> float:
	var y := 0.0
	for player in targets:
		y += player.get_feet_position().y
	return y / targets.size()


static func _mean_facing(targets: Array[Player]) -> float:
	var facing := 0.0
	for player in targets:
		facing += player.side_motion.facing if player.side_motion != null else 0.0
	return clampf(facing / targets.size(), -1.0, 1.0)


static func _all_standing(targets: Array[Player]) -> bool:
	for player in targets:
		var motion := player.side_motion
		if motion == null or not (motion.is_on_floor() or motion.is_climbing()):
			return false
	return true
