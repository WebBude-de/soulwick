class_name SideBot
extends RefCounted
## Autopilot for a side segment (check tool, tests, screenshots): plays a player through the
## segment like a person would - it follows the layout's jump graph (SideLayout.find_path) from the
## stand cell it is on to the door, walks, jumps from platform edges, climbs ladders, steers in the
## air, takes the double jump where the graph asks for it (and as a rescue when a jump falls short),
## fetches the golden coin with a double jump on the way, on request walks up to the niche chest (it
## never opens it; the chest box blocks, so its cell ends a run) - and only talks to the player
## through PlayerSideMotion.input_source, the same door a network peer uses. Replans whenever it
## lands somewhere unexpected.
## Jump trial (SV2, D-195): it waits at the edge for a moving platform and jumps on when the jump
## lands on it, rides it (standing in its middle) until the next jump of the way reaches, walks onto
## springs and steers to the cell after them, climbs a wall-jump shaft from wall to wall, waits for a saw to pass, and hops over a spike
## hedgehog and onto a shield bearer like every other enemy (the jump graph's way over them).
## Slopes (two-way pieces of the obstacle run, D-216): it walks up and down them without a jump
## (SideLayout.walk_connects). It never dashes: there is no side dash (D-216).

const EDGE_INSET := 14.0
const ARRIVE_DISTANCE := 8.0
const STUCK_TIME := 1.2
const LADDER_ALIGN := 6.0
## The second jump is pressed once the first has slowed down to this (near the apex).
const DOUBLE_JUMP_AT_SPEED := -120.0
## The niche chest counts as visited with the feet this close to its base (px): well inside the
## interaction range (player area 44 px + chest area 56 px).
const CHEST_REACH := 72.0
## A jump onto a moving platform is aimed at where it is this many seconds later (about the time
## of a short jump), and the platform must be in reach now and then.
const MOVER_LEAD := 0.35
## Faster upwards than any own jump: a spring threw the bot.
const SPRING_LAUNCH_SPEED := -1000.0
## In a shaft: the jump is let go near the apex, so the next press is a new one (a wall jump).
const SHAFT_RELEASE_SPEED := -140.0
## A shaft climb that takes longer than this is given up and planned again.
const SHAFT_GIVE_UP := 8.0
## Saw look-ahead: seconds and step of the samples.
const SAW_LOOK_AHEAD := 0.9
const SAW_LOOK_STEP := 0.1
## How high a jump's way bends up in the middle (px) for the saw look-ahead.
const SAW_JUMP_ARC := 110.0

var segment: SideSegment = null
var player: Player = null
## Steps taken (jumps started), double jumps pressed and replans (tools).
var jumps := 0
var double_jumps := 0
var replans := 0
## Go for the golden coin before the door (check tool: proves every golden coin is reachable).
var fetch_golden := true
## Walk up to the niche chest before the door (check tool: proves every chest is in easy reach).
## Off by default, so the other tools cross as fast as before.
var fetch_chest := false
## The bot stood next to the chest (fetch_chest).
var chest_visited := false
## Wall jumps pressed in shafts, frames spent waiting for a saw or a moving platform (tools).
var wall_jump_presses := 0
var saw_wait_frames := 0
var mover_wait_frames := 0

var _path: Array[Vector2i] = []
var _current := Vector2i(-1, -1)
var _target := Vector2i(-1, -1)
var _airborne_target := Vector2i(-1, -1)
var _jump_was_pressed := false
var _hold_jump := false
var _stuck_time := 0.0
var _last_x := INF
var _need_double := false
var _golden_launch := Vector2i(-1, -1)
var _golden_try := false
var _golden_done := false
var _spring_next := Vector2i(-1, -1)
var _ride: SideMover = null
var _shaft := Rect2i()
var _shaft_exit := Vector2i(-1, -1)
var _shaft_time := 0.0
var _shaft_wall := 1


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
	if _shaft.has_area():
		return _finish(input, _shaft_step(input, feet))
	if motion.is_on_floor():
		if _chest_pending() and _near_chest(feet):
			chest_visited = true
			_current = Vector2i(-1, -1)
		if _golden_try:
			# Back on the ground after the golden coin jump: on to the door.
			_golden_try = false
			_golden_done = true
			_current = Vector2i(-1, -1)
		var cell := SideLayout.cell_at(feet + Vector2(0, -4))
		if _is_stand_cell(cell, feet) and cell != _current:
			_current = cell
			_replan()
		_airborne_target = Vector2i(-1, -1)
		_ride = null
		_hold_jump = false
		_need_double = false
		want_jump = _golden_step(input, feet) if _at_golden_launch() else _ground_step(input, feet)
	else:
		want_jump = _air_step(input, feet)
	return _finish(input, want_jump)


## A cell the bot stands in: firm ground, or a moving platform's cell with the platform under it.
func _is_stand_cell(cell: Vector2i, feet: Vector2) -> bool:
	if segment.layout.is_standable(cell):
		return true
	return segment.layout.mover_stand_cells().has(cell) and segment.mover_under(segment.to_global(feet)) != null


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
	var layout := segment.layout
	var goal := layout.door
	var golden := false
	var chest := false
	if fetch_golden and not _golden_done and segment.has_golden_coin():
		if _golden_launch.x < 0:
			_golden_launch = layout.launch_cell_for(layout.golden_coin, layout.reachable_from(layout.start))
		if _golden_launch.x >= 0:
			goal = _golden_launch
			golden = true
	if _chest_pending():
		# The chest first when it lies before the golden coin's launch cell on the way.
		var direction := layout.run_direction()
		if not golden or layout.chest.x * direction < _golden_launch.x * direction:
			goal = _chest_visit_cell()
			chest = true
	_path = layout.find_path(_current, goal)
	if _path.is_empty() and chest:
		# Out of the graph's reach (never in a checked plan): on to the door, the tool reports it.
		chest_visited = true
		_path = layout.find_path(_current, layout.door)
	_target = _path[1] if _path.size() > 1 else _current
	_spring_next = _path[2] if _path.size() > 2 and layout.is_spring(_target) else Vector2i(-1, -1)
	_shaft = Rect2i()


func _chest_pending() -> bool:
	return fetch_chest and not chest_visited and segment.get_chest() != null and segment.layout.chest.x >= 0


## Where the bot stands to visit the chest: the open stand cell beside it on its row (a niche has
## one; the jump graph's straight drops into a niche under rock are not real).
func _chest_visit_cell() -> Vector2i:
	var layout := segment.layout
	var best := layout.chest
	var best_distance := 1000000
	for side in [-1, 1]:
		var cell := layout.chest + Vector2i(side, 0)
		var distance := absi(cell.x - _current.x) + absi(cell.y - _current.y)
		if layout.is_standable(cell) and distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _near_chest(feet: Vector2) -> bool:
	return feet.distance_to(SideLayout.feet_of(segment.layout.chest)) <= CHEST_REACH


func _at_golden_launch() -> bool:
	return fetch_golden and not _golden_done and _golden_launch.x >= 0 and _current == _golden_launch and segment.has_golden_coin()


## At the launch cell under the golden coin: line up, jump, double jump at the apex (air step).
func _golden_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> bool:
	var coin_x := SideLayout.cell_center(segment.layout.golden_coin).x
	var launch_x := clampf(coin_x, SideLayout.cell_origin(_current).x + 12.0, SideLayout.cell_origin(_current).x + SideRules.TILE - 12.0)
	if absf(launch_x - feet.x) > ARRIVE_DISTANCE:
		input.axis.x = signf(launch_x - feet.x)
		return false
	_golden_try = true
	_need_double = true
	_airborne_target = Vector2i(-1, -1)
	return true


## On the ground: walk, start a jump at the edge, or step onto a ladder. Returns "jump now".
func _ground_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> bool:
	if _target == _current or _path.size() < 2:
		if _chest_pending() and _current == _chest_visit_cell():
			# Beside the chest but still out of reach: the last steps up to it.
			input.axis.x = signf(SideLayout.feet_of(segment.layout.chest).x - feet.x)
		return false
	var layout := segment.layout
	if layout.is_spring(_current):
		# On a spring it throws the bot anyway: steer to the next cell, no own jump.
		_airborne_target = _target
		_need_double = not layout.neighbours(_current, false).has(_target)
		input.axis.x = signf(SideLayout.feet_of(_target).x - feet.x)
		return false
	var target_x := SideLayout.feet_of(_target).x
	if (layout.is_slope(_current) or layout.is_slope(_target)) and layout.walk_connects(_current, _target):
		# Onto, along or off a slope: walk on.
		_update_stuck(feet)
		if _stuck_time > STUCK_TIME:
			_stuck_time = 0.0
			_airborne_target = _target
			input.axis.x = signf(target_x - feet.x)
			return true
		input.axis.x = signf(target_x - feet.x) if absf(target_x - feet.x) > ARRIVE_DISTANCE else 0.0
		return false
	var shaft := layout.shaft_climb(_current, _target)
	if shaft.has_area():
		_shaft = shaft
		_shaft_exit = _target
		_shaft_time = 0.0
		return _shaft_step(input, feet)
	var riding := layout.mover_stand_cells()
	var on_mover := riding.has(_current) and not layout.is_standable(_current)
	if on_mover and riding.has(_target) and riding[_target] == riding[_current]:
		# Riding: stay in the middle of the platform until the next jump of the way reaches.
		var platform := segment.mover_under(segment.to_global(feet))
		if platform != null:
			var middle := segment.to_local(platform.top_center_at(platform.clock)).x
			input.axis.x = signf(middle - feet.x) * 0.5 if absf(middle - feet.x) > ARRIVE_DISTANCE else 0.0
		mover_wait_frames += 1
		return false
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
	_need_double = layout.needs_double_jump(_current, _target)
	var target_mover: int = riding.get(_target, -1) if not layout.is_standable(_target) and not on_mover else -1
	var gap := edge_cell.x != _target.x
	var rising := _target.y < _current.y
	var needs_jump := rising or (gap and (_target.y == _current.y or absi(_target.x - _current.x) >= 3)) \
			or target_mover >= 0
	if _saw_blocks(feet, SideLayout.feet_of(_target), SAW_JUMP_ARC if needs_jump else 0.0) and _waits_safely():
		# A saw crosses the way just now: let it pass.
		saw_wait_frames += 1
		input.axis.x = 0.0
		_stuck_time = 0.0
		return false
	_update_stuck(feet)
	if _stuck_time > STUCK_TIME and target_mover < 0:
		_stuck_time = 0.0
		_airborne_target = _target
		return true
	if not needs_jump:
		input.axis.x = signf(target_x - feet.x) if absf(target_x - feet.x) > ARRIVE_DISTANCE else 0.0
		return false
	var takeoff := SideLayout.feet_of(edge_cell).x
	if on_mover:
		# Off a moving platform: from its real edge, wherever it is right now.
		var platform := segment.mover_under(segment.to_global(feet))
		if platform != null and direction != 0:
			var rect := platform.get_top_rect()
			var edge := rect.end.x if direction > 0 else rect.position.x
			takeoff = segment.to_local(Vector2(edge, 0)).x - direction * EDGE_INSET
	elif direction != 0 and gap:
		takeoff += direction * (SideRules.TILE * 0.5 - EDGE_INSET)
	elif direction != 0 and edge_cell.x != _current.x:
		# A step up in the same run: jump from the cell in front of the wall.
		takeoff = SideLayout.feet_of(edge_cell).x
	var to_takeoff := takeoff - feet.x
	if direction == 0 or absf(to_takeoff) <= ARRIVE_DISTANCE or signf(to_takeoff) != float(direction):
		if target_mover >= 0:
			var platform := segment.get_movers()[target_mover]
			if not _mover_in_reach(platform, edge_cell):
				# Wait at the edge until the platform will be under the jump.
				mover_wait_frames += 1
				input.axis.x = 0.0
				return false
			_ride = platform
		input.axis.x = float(direction)
		_airborne_target = _target
		return true
	input.axis.x = signf(to_takeoff)
	return false


## Whether a jump from cell lands on the moving platform: one of its stand cells is a neighbour of
## cell in the jump graph now and MOVER_LEAD seconds later.
func _mover_in_reach(platform: SideMover, cell: Vector2i) -> bool:
	var reach := segment.layout.neighbours(cell, true)
	var now_ok := false
	for stand in platform.stand_cells_at(platform.clock):
		if reach.has(stand):
			now_ok = true
	if not now_ok:
		return false
	for stand in platform.stand_cells_at(platform.clock + MOVER_LEAD):
		if reach.has(stand):
			return true
	return false


## Whether a saw's blade comes near the way from from_feet to to_feet (segment-local; a jump bends
## up by arc px in the middle) in the next SAW_LOOK_AHEAD seconds, the bot running at its speed.
func _saw_blocks(from_feet: Vector2, to_feet: Vector2, arc := 0.0) -> bool:
	var saws := segment.get_saws()
	if saws.is_empty():
		return false
	var speed := maxf(1.0, player.move_speed * player.side_motion.get_speed_factor())
	var distance := from_feet.distance_to(to_feet)
	var t := 0.0
	while t <= SAW_LOOK_AHEAD:
		var share := minf(1.0, t * speed / maxf(distance, 1.0))
		var body := from_feet.lerp(to_feet, share) + Vector2(0, -24.0 - arc * sin(PI * share))
		for saw in saws:
			if not is_instance_valid(saw):
				continue
			var blade := segment.to_local(saw.center_at(saw.clock + t))
			if blade.distance_to(body) < SideElementRules.SAW_RADIUS + SideElementRules.SAW_BOT_MARGIN:
				return true
		t += SAW_LOOK_STEP
	return false


## Waiting is safe on firm ground only (never on a tilting platform, a bridge or a platform).
func _waits_safely() -> bool:
	var layout := segment.layout
	return layout.is_standable(_current) and not layout.is_element_ground(_current + Vector2i.DOWN)


## Wall-jump shaft: from the floor jump at a wall, from every wall jump to the other one, let the
## jump go near the apex so the next press is a new one; once above the exit floor steer onto it
## (the double jump if it falls short). Returns "press jump".
func _shaft_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> bool:
	var motion := player.side_motion
	_shaft_time += 1.0 / Engine.physics_ticks_per_second
	var exit_feet := SideLayout.feet_of(_shaft_exit)
	var on_exit := motion.is_on_floor() and SideLayout.cell_at(feet + Vector2(0, -4)) == _shaft_exit
	if on_exit or _shaft_time > SHAFT_GIVE_UP:
		_shaft = Rect2i()
		_current = Vector2i(-1, -1)
		return false
	if feet.y <= exit_feet.y + 4.0:
		# Above the exit floor: over to it.
		input.axis.x = signf(exit_feet.x - feet.x) if absf(exit_feet.x - feet.x) > ARRIVE_DISTANCE else 0.0
		if player.velocity.y >= 0.0:
			_hold_jump = false
		return false
	if motion.is_on_floor():
		if SideLayout.cell_at(feet + Vector2(0, -4)).y < _shaft.end.y - 1:
			# Landed somewhere else on the way up: plan again from there.
			_shaft = Rect2i()
			_current = Vector2i(-1, -1)
			return false
		if _jump_was_pressed:
			# Let go first, so the next jump is a new press.
			_hold_jump = false
			return false
		_shaft_wall = 1 if feet.x < (_shaft.position.x + _shaft.size.x * 0.5) * SideRules.TILE else -1
		input.axis.x = float(_shaft_wall)
		return true
	if player.velocity.y >= SHAFT_RELEASE_SPEED:
		_hold_jump = false
	var wall := motion.wall_side
	if wall != 0 and wall == _shaft_wall and not _jump_was_pressed:
		# At the wall: jump off it towards the other one.
		wall_jump_presses += 1
		_shaft_wall = -wall
		input.axis.x = float(_shaft_wall)
		return true
	input.axis.x = float(_shaft_wall)
	# Near the top and falling short: the double jump.
	if player.velocity.y > 0.0 and feet.y - exit_feet.y < SideRules.TILE * 2.0 and motion.air_jumps_left > 0 and not _jump_was_pressed:
		return true
	return false


## In the air: steer to the target cell, keep the jump pressed while rising, press the second jump
## near the apex when the edge needs it, or as a rescue when the jump falls short. Returns "press".
func _air_step(input: PlayerSideMotion.SideInput, feet: Vector2) -> bool:
	var motion := player.side_motion
	if _golden_try:
		var coin := SideLayout.cell_center(segment.layout.golden_coin)
		input.axis.x = signf(coin.x - feet.x) if absf(coin.x - feet.x) > ARRIVE_DISTANCE else 0.0
		return _second_jump(motion)
	if _spring_next.x >= 0 and player.velocity.y < SPRING_LAUNCH_SPEED and _airborne_target != _spring_next:
		# A spring threw the bot: on to the cell after it.
		_airborne_target = _spring_next
		_need_double = not segment.layout.neighbours(_target, false).has(_spring_next)
	var target := _airborne_target if _airborne_target.x >= 0 else _target
	if target.x < 0:
		return false
	var target_feet := SideLayout.feet_of(target)
	if _ride != null and is_instance_valid(_ride):
		# Onto a moving platform: aim at its middle as it moves.
		target_feet.x = segment.to_local(_ride.top_center_at(_ride.clock)).x
	var dx := target_feet.x - feet.x
	input.axis.x = signf(dx) if absf(dx) > ARRIVE_DISTANCE else 0.0
	if _need_double:
		return _second_jump(motion)
	# Rescue: falling below the target's floor while still short of it.
	if player.velocity.y > 0.0 and feet.y > target_feet.y - 4.0 and absf(dx) > SideRules.TILE * 0.5 and motion.air_jumps_left > 0:
		_need_double = true
		return _second_jump(motion)
	if player.velocity.y >= 0.0:
		_hold_jump = false
	return false


## Releases the first jump near the apex, then presses the double jump (one press per air time).
func _second_jump(motion: PlayerSideMotion) -> bool:
	if motion.has_double_jumped or motion.air_jumps_left <= 0:
		if player.velocity.y >= 0.0:
			_hold_jump = false
		return false
	if player.velocity.y < DOUBLE_JUMP_AT_SPEED:
		return false
	if _jump_was_pressed:
		_hold_jump = false
		return false
	double_jumps += 1
	return true


func _climb(input: PlayerSideMotion.SideInput, feet: Vector2) -> void:
	var target := _target
	if target.x < 0:
		input.axis.y = -1.0
		return
	var target_feet := SideLayout.feet_of(target)
	input.axis.y = -1.0 if target_feet.y < feet.y else 1.0


## The last stand cell walking from cell towards target on cell's row (the edge before a gap, a
## wall or the chest box); the target column itself when the row reaches it.
func _run_end(cell: Vector2i, target: Vector2i) -> Vector2i:
	var direction := signi(target.x - cell.x)
	var end := cell
	var chest := segment.layout.chest if segment.get_chest() != null else Vector2i(-1, -1)
	while end.x != target.x:
		var next := Vector2i(end.x + direction, cell.y)
		if not segment.layout.is_standable(next) or next == chest:
			break
		end = next
	return end


func _update_stuck(feet: Vector2) -> void:
	if absf(feet.x - _last_x) < 0.5:
		_stuck_time += 1.0 / Engine.physics_ticks_per_second
	else:
		_stuck_time = 0.0
	_last_x = feet.x
