class_name SideCamera
extends Camera2D
## Camera of a side segment (M5): follows horizontally with a look-ahead in the running direction,
## vertically only when the players change level (the height of the platform they stand on), never
## past the segment's edges. The players it follows come from camera_targets() - today the players
## of this machine; the co-op later puts the group's middle there (SideSegment.camera_targets).
## Knows add_trauma, so CameraShake works in the segment as everywhere else, and kick() for a short
## push (a hard landing, round 2).
## Jump trial (SV2, D-195: no blind jump): plans up to 22 rows scroll vertically, and while the
## players stand the view leans towards the way ahead (the next cells of the layout's way from the
## start to the door), up a climb or down a drop, so the target of the next jump is in the picture.
## The walking way (the players' feet) never sits lower than MAX_FEET_SCREEN_SHARE of the view, so
## the weapon bar and Flint's bubble at the bottom never cover it (D-211 round).
## Momentum (SV1, D-216): the faster the group runs, the further the view looks ahead (up to
## FAST_LOOK_AHEAD at the top speed), so what comes is on screen in time.

## TESTWERTE
const LOOK_AHEAD := 110.0
const LOOK_AHEAD_SPEED := 260.0
const FOLLOW_X := 7.0
const FOLLOW_Y := 3.5
## Where the feet sit on screen when the view must scroll vertically (share of the view height).
const FEET_SCREEN_SHARE := 0.66
## The feet never sit lower on screen than this share of the view height (TESTWERT): the weapon bar
## and Flint's bubble at the bottom stay off the way.
const MAX_FEET_SCREEN_SHARE := 0.75
const MAX_SHAKE := 16.0
## The view may go this far below the plan (rock drawn there, SideTiles.DEPTH_ROWS), so the lowest
## floor stays above the HUD at the bottom of the screen.
const BOTTOM_MARGIN := 128.0
const SHAKE_DECAY := 1.8
## A kick springs back within about this many seconds (TESTWERT).
const KICK_RETURN_SPEED := 18.0
## Vertical look-ahead along the way (TESTWERTE, SV2): the next WAY_LOOK_STEPS cells of the way, a
## share WAY_LOOK_SHARE of their height difference, at most WAY_LOOK_MAX of the view height, moving
## WAY_LOOK_SPEED px/s.
const WAY_LOOK_STEPS := 2
const WAY_LOOK_SHARE := 0.6
const WAY_LOOK_MAX := 0.3
const WAY_LOOK_SPEED := 320.0
## Look-ahead at the top speed (SideMomentum.MAX_FACTOR) and how fast it follows (TESTWERTE).
const FAST_LOOK_AHEAD := 240.0
const FAST_LOOK_AHEAD_SPEED := 420.0

var segment: SideSegment = null

var _look := 0.0
var _anchor_y := 0.0
var _trauma := 0.0
var _time := 0.0
var _kick := Vector2.ZERO
var _look_y := 0.0
var _way: Array[Vector2i] = []
var _way_built := false


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
		var ahead := look_ahead_for(targets)
		var look_speed := FAST_LOOK_AHEAD_SPEED if ahead > LOOK_AHEAD else LOOK_AHEAD_SPEED
		_look = move_toward(_look, ahead * _mean_facing(targets), look_speed * delta)
		if _all_standing(targets):
			_anchor_y = _mean_feet_y(targets)
			_look_y = move_toward(_look_y, way_look(targets), WAY_LOOK_SPEED * delta)
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
	var desired := Vector2(x + _look, _anchor_y - view.y * (FEET_SCREEN_SHARE - 0.5) + _look_y)
	if segment == null:
		return desired
	# Room below the plan, so the lowest floor can sit at MAX_FEET_SCREEN_SHARE too.
	var bottom := maxf(BOTTOM_MARGIN, view.y * (1.0 - MAX_FEET_SCREEN_SHARE))
	var bounds := Rect2(segment.global_position, segment.layout.world_size() + Vector2(0, bottom))
	desired.x = _clamp_axis(desired.x, bounds.position.x, bounds.end.x, view.x)
	desired.y = _clamp_axis(desired.y, bounds.position.y, bounds.end.y, view.y)
	# A player too low on screen (a climb ahead leans the view up, falling) or above the view (a tall
	# jump) pulls it along.
	for player in targets:
		var feet := player.get_feet_position().y
		if feet > lowest_feet_y(desired.y, view.y) and feet < bounds.end.y:
			desired.y = _clamp_axis(feet - view.y * (MAX_FEET_SCREEN_SHARE - 0.5), bounds.position.y, bounds.end.y, view.y)
		elif feet - 64.0 < desired.y - view.y * 0.5:
			desired.y = _clamp_axis(feet - 64.0 + view.y * 0.5, bounds.position.y, bounds.end.y, view.y)
	return desired


## The lowest the feet may stand (world y) with the view centred at center_y and view_height high.
static func lowest_feet_y(center_y: float, view_height: float) -> float:
	return center_y + view_height * (MAX_FEET_SCREEN_SHARE - 0.5)


## Vertical shift (px) towards the way ahead of the players: the largest height difference to the
## next WAY_LOOK_STEPS cells of the way after the way cell closest to them, scaled and capped.
func way_look(targets: Array[Player]) -> float:
	if segment == null or segment.layout == null or targets.is_empty():
		return 0.0
	if not _way_built:
		_way_built = true
		_way = segment.layout.find_path(segment.layout.start, segment.layout.door)
	if _way.size() < 2:
		return 0.0
	var feet := Vector2.ZERO
	for player in targets:
		feet += segment.to_local(player.get_feet_position())
	feet /= targets.size()
	var here := SideLayout.cell_at(feet + Vector2(0, -4))
	var nearest := 0
	var best := INF
	for i in _way.size():
		var distance := absf(_way[i].x - here.x) + absf(_way[i].y - here.y) * 2.0
		if distance < best:
			best = distance
			nearest = i
	var shift := 0.0
	for i in range(nearest + 1, mini(_way.size(), nearest + 1 + WAY_LOOK_STEPS)):
		var dy := SideLayout.feet_of(_way[i]).y - feet.y
		if absf(dy) > absf(shift):
			shift = dy
	var view := get_viewport_rect().size.y / zoom.y
	return clampf(shift * WAY_LOOK_SHARE, -view * WAY_LOOK_MAX, view * WAY_LOOK_MAX)


## How far the view looks ahead for the targets: LOOK_AHEAD, growing with the group's mean speed
## factor up to FAST_LOOK_AHEAD.
func look_ahead_for(targets: Array[Player]) -> float:
	if targets.is_empty():
		return LOOK_AHEAD
	var factor := 0.0
	for player in targets:
		factor += player.side_motion.get_speed_factor() if player.side_motion != null else SideMomentum.BASE_FACTOR
	factor /= targets.size()
	var share := clampf((factor - SideMomentum.BASE_FACTOR) / (SideMomentum.MAX_FACTOR - SideMomentum.BASE_FACTOR), 0.0, 1.0)
	return lerpf(LOOK_AHEAD, FAST_LOOK_AHEAD, share)


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
