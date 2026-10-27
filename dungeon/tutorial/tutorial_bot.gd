class_name TutorialBot
extends Node
## Autopilot through the practice run (smoke test, tools): plays it like a person would - plays on
## while Flint talks (a tour would be skipped with "Überspringen"), walks through the doors in the
## middle row, aims at the straw dummies and hits them, dashes over the abyss from its edge, walks
## into the jump door and plays the side-view stretch with SideBot, hits the shield dummy once (it
## bounces off) and breaks it with the special, then walks into the gate. It only talks to the player through a RemoteInput (swapped in
## while it drives, the old input back when it is freed), the same door a network peer uses.

## Close enough to a goal (px), reach for a hit (feet to dummy), stuck time before a nudge (s).
const ARRIVE := 6.0
const HIT_REACH := 52.0
const STUCK_TIME := 1.0
## Feet this far before the abyss's west edge: dash now (a dash flies 90 px, the abyss is 64).
const DASH_BEFORE_EDGE := 4.0

var run: TutorialRun = null
var player: Player = null
var input := RemoteInput.new()
var side_bot: SideBot = null
## What it is doing (tools print it when a run hangs).
var stage := ""
## Frames the special was held at the shield dummy, dashes started.
var special_frames := 0
var dashes := 0

var _old_input: PlayerInput = null
var _stuck := 0.0
var _last_feet := Vector2.INF


## Drives the player of run until the run ends (the bot frees itself with it).
static func drive(practice: TutorialRun) -> TutorialBot:
	var bot := TutorialBot.new()
	bot.name = "TutorialBot"
	bot.run = practice
	practice.add_child(bot)
	return bot


func _physics_process(delta: float) -> void:
	if run == null or not is_instance_valid(run) or run.is_finished:
		return
	if player == null:
		player = run.player
		if player == null:
			return
		_old_input = player.input
		player.input = input
	input.clear()
	var guide := FlintGuide.of(player)
	if guide != null and guide.current != null and guide.current.locks_player():
		stage = "welcome"
		guide.skip()
		return
	var jump := run.get_jump()
	if jump != null and jump.is_running:
		stage = "jump (side view)"
		if player.is_side_view() and jump.segment != null and side_bot == null:
			side_bot = SideBot.drive(jump.segment, player)
			side_bot.fetch_golden = false
		return
	side_bot = null
	if player.is_input_locked():
		return
	match run.zone:
		TutorialRun.WELCOME:
			stage = "waiting for the welcome"
		0:
			_attack_dummies()
		1:
			_dash_over()
		2:
			stage = "to the jump door"
			_walk_to(run.area.get_door_front_feet(run.area.jump_door) + Vector2(40, 0))
		3:
			_break_shield()
		TutorialRun.FINISH:
			stage = "to the gate"
			_walk_to(run.area.get_gate_feet())
	_watch_stuck(delta)


func _attack_dummies() -> void:
	var target: TutorialDummy = null
	var best := INF
	for dummy in run.area.dummies:
		var distance := dummy.global_position.distance_to(player.get_feet_position())
		if not dummy.is_broken and distance < best:
			best = distance
			target = dummy
	if target == null:
		return
	stage = "hitting %s" % target.name
	_hit(target, PlayerInput.ATTACK)


func _break_shield() -> void:
	var dummy := run.area.shield_dummy
	if dummy.is_broken:
		return
	# First a plain hit (it bounces off), then the special.
	var action := PlayerInput.ATTACK if run.blocked_hits == 0 else PlayerInput.SPECIAL
	stage = "shield dummy (%s)" % action
	if _hit(dummy, action) and action == PlayerInput.SPECIAL:
		special_frames += 1


## Walks next to the dummy (west of it) and holds the action aimed at it. True while hitting.
func _hit(dummy: TutorialDummy, action: StringName) -> bool:
	var spot := dummy.global_position + Vector2(-HIT_REACH + 8.0, -4.0)
	var feet := player.get_feet_position()
	if feet.distance_to(spot) > ARRIVE * 3.0:
		_walk_to(spot)
		return false
	input.set_aim_point(dummy.get_aim_point())
	input.press(action)
	return true


func _dash_over() -> void:
	var lane := run.area.get_pit_run_up_feet()
	var feet := player.get_feet_position()
	var edge := run.area.get_pit_west_x()
	if feet.x < lane.x - ARRIVE * 4.0 or absf(feet.y - lane.y) > ARRIVE * 2.0:
		stage = "to the abyss"
		_walk_to(lane)
		return
	stage = "dash over the abyss"
	input.set_move(Vector2.RIGHT)
	if feet.x >= edge - DASH_BEFORE_EDGE and player.can_dash():
		input.tap(PlayerInput.DASH)
		dashes += 1


## Steps towards goal (global feet), through the door in the middle row when a wall lies between.
func _walk_to(goal: Vector2) -> void:
	var feet := player.get_feet_position()
	var lane_y := run.area.to_global(RoomTiles.tile_center(TutorialPlans.door_cells()[0])).y
	var wall := _wall_between(feet.x, goal.x)
	var target := goal
	if wall != INF:
		if absf(feet.y - lane_y) > ARRIVE * 2.0:
			target = Vector2(feet.x, lane_y)
		else:
			target = Vector2(wall + signf(goal.x - feet.x) * RoomTiles.TILE_WORLD, lane_y)
	var to_target := target - feet
	input.set_move(to_target.normalized() if to_target.length() > ARRIVE else Vector2.ZERO)


## Global x of the middle of the first wall column between two x, INF if none.
func _wall_between(from_x: float, to_x: float) -> float:
	var best := INF
	for rect in TutorialPlans.wall_rects():
		var x := run.area.to_global(RoomTiles.tile_center(rect.position)).x
		if (x - from_x) * (x - to_x) < 0.0 and absf(x - from_x) < absf(best - from_x):
			best = x
	return best


func _watch_stuck(delta: float) -> void:
	var feet := player.get_feet_position()
	if _last_feet != Vector2.INF and feet.distance_to(_last_feet) < 0.5 and input.move != Vector2.ZERO:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_feet = feet
	if _stuck >= STUCK_TIME:
		# A nudge sideways (a dummy or a door frame in the way).
		input.set_move((input.move + Vector2(0, 1 if fmod(Time.get_ticks_msec() / 1000.0, 2.0) < 1.0 else -1)).normalized())
		_stuck = 0.0


func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and _old_input != null and player.input == input:
		player.input = _old_input
