class_name SideBot
extends RefCounted
## Autopilot for a side segment (check tool, tests, screenshots): plays a player through the
## segment like a person would - it follows the layout's jump graph (SideLayout.find_path) from the
## stand cell it is on to the door, walks, jumps from platform edges, climbs ladders, steers in the
## air - and only talks to the player through PlayerSideMotion.input_source, the same door a network
## peer uses. Replans whenever it lands somewhere unexpected.

const EDGE_INSET := 14.0
const ARRIVE_DISTANCE := 8.0
const STUCK_TIME := 1.2
const LADDER_ALIGN := 6.0

var segment: SideSegment = null
var player: Player = null
## Steps taken (jumps started) and replans (tools).
var jumps := 0
var replans := 0

var _path: Array[Vector2i] = []
var _current := Vector2i(-1, -1)
var _target := Vector2i(-1, -1)
var _airborne_target := Vector2i(-1, -1)
var _jump_was_pressed := false
var _hold_jump := false
var _stuck_time := 0.0
var _last_x := INF


static func drive(owner_segment: SideSegment, driven: Player) -> SideBot:
	var bot := SideBot.new()
	bot.segment = owner_segment
	bot.player = driven
	driven.side_motion.input_source = bot.next_input
	return bot


## Input for this physics frame (PlayerSideMotion.input_source).
func next_input() -> PlayerSideMotion.SideInput:
	var input := PlayerSideMotion.SideInput.new()
	if segment == null or not is_instance_valid(player) or player.side_motion == null:
		return input
	var motion := player.side_motion
	var layout := segment.layout
	var feet := segment.to_local(player.get_feet_position())
	var want_jump := false
	if motion.is_climbing():
		_climb(input, feet)
		return _finish(input, false)
	if motion.is_on_floor():
		var cell := SideLayout.cell_at(feet + Vector2(0, -4))
		if layout.is_standable(cell) and cell != _current:
			_current = cell
			_replan()
		_airborne_target = Vector2i(-1, -1)
		_hold_jump = false
		want_jump = _ground_step(input, feet)
	else:
		_air_step(input, feet)
	return _finish(input, want_jump)


func _finish(input: PlayerSideMotion.SideInput, want_jump: bool) -> PlayerSideMotion.SideInput:
	input.jump_just_pressed = want_jump and not _jump_was_pressed
	input.jump_pressed = want_jump or _hold_jump
	if input.jump_just_pressed:
		jumps += 1
		_hold_jump = true
	_jump_was_pressed = input.jump_pressed
	return input


func _replan() -> void:
	replans += 1
	_path = segment.layout.find_path(_current, segment.layout.door)
	_target = _path[1] if _path.size() > 1 else _current


## On the ground: walk, start a jump at the edge, or step onto a ladder. Returns "jump now".
func _ground_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> bool:
	if _target == _current or _path.size() < 2:
		return false
	var layout := segment.layout
	var target_x := SideLayout.feet_of(_target).x
	# Ladder between the two cells: walk to it and climb.
	if _target.x == _current.x and layout.ladders.has(_current.x):
		var center := SideLayout.cell_center(Vector2i(_current.x, 0)).x
		if absf(feet.x - center) > LADDER_ALIGN:
			input.axis.x = signf(center - feet.x) * 0.5
			return false
		input.axis.y = -1.0 if _target.y < _current.y else 1.0
		return false
	var direction := signi(_target.x - _current.x)
	var edge_cell := _run_end(_current, _target)
	var gap := edge_cell.x != _target.x
	var rising := _target.y < _current.y
	var needs_jump := rising or (gap and (_target.y == _current.y or absi(_target.x - _current.x) >= 3))
	_update_stuck(feet)
	if _stuck_time > STUCK_TIME:
		_stuck_time = 0.0
		_airborne_target = _target
		return true
	if not needs_jump:
		input.axis.x = signf(target_x - feet.x) if absf(target_x - feet.x) > ARRIVE_DISTANCE else 0.0
		return false
	var takeoff := SideLayout.feet_of(edge_cell).x
	if direction != 0 and gap:
		takeoff += direction * (SideRules.TILE * 0.5 - EDGE_INSET)
	elif direction != 0 and edge_cell.x != _current.x:
		# A step up in the same run: jump from the cell in front of the wall.
		takeoff = SideLayout.feet_of(edge_cell).x
	var to_takeoff := takeoff - feet.x
	if direction == 0 or absf(to_takeoff) <= ARRIVE_DISTANCE or signf(to_takeoff) != float(direction):
		input.axis.x = float(direction)
		_airborne_target = _target
		return true
	input.axis.x = signf(to_takeoff)
	return false


## In the air: steer to the target cell, keep the jump pressed while rising.
func _air_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> void:
	var target := _airborne_target if _airborne_target.x >= 0 else _target
	if target.x < 0:
		return
	var target_x := SideLayout.feet_of(target).x
	var dx := target_x - feet.x
	input.axis.x = signf(dx) if absf(dx) > ARRIVE_DISTANCE else 0.0
	if player.velocity.y >= 0.0:
		_hold_jump = false


func _climb(input: PlayerSideMotion.SideInput, feet: Vector2) -> void:
	var target := _target
	if target.x < 0:
		input.axis.y = -1.0
		return
	var target_feet := SideLayout.feet_of(target)
	input.axis.y = -1.0 if target_feet.y < feet.y else 1.0


## The last stand cell walking from cell towards target on cell's row (the edge before a gap or a
## wall); the target column itself when the row reaches it.
func _run_end(cell: Vector2i, target: Vector2i) -> Vector2i:
	var direction := signi(target.x - cell.x)
	var end := cell
	while end.x != target.x:
		var next := Vector2i(end.x + direction, cell.y)
		if not segment.layout.is_standable(next):
			break
		end = next
	return end


func _update_stuck(feet: Vector2) -> void:
	if absf(feet.x - _last_x) < 0.5:
		_stuck_time += 1.0 / Engine.physics_ticks_per_second
	else:
		_stuck_time = 0.0
	_last_x = feet.x
