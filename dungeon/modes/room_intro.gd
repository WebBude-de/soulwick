class_name RoomIntro
extends Node
## The same introduction for every room mode (KONZEPT_RAEUME_V2 §1.3, 07_ui.md, R3):
## door shuts (0.3 s) → the camera swings to the goal (1.5 s, players' input locked, no global
## pause) → goal banner (symbol in the mode colour, big sentence, small rule line) → big 3-2-1
## with a tick → go. The first time per save (seen id "room_intro_<genre>") the full version with the
## camera swing and the explanation card; later the short one (banner + countdown, about 2 s).
## Skippable with the interact key (or Enter while the players are locked).
##
## Logic only: it holds the fight back (after_intro), locks and frees the players and moves their
## cameras. Everything visible or audible (banner, countdown, card, sounds) is DungeonUI's: it finds
## the intro through node_added and follows the signals. Child of its room, so it dies with it and
## always frees players and cameras on the way out.
##
## Use (R4): var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
##           RoomIntro.start(room, goal, flame.global_position)
## RoomController.activate() starts the fight through RoomIntro.after_intro(self, start_encounter).

## Phase reached (DOOR, PAN, BANNER, COUNTDOWN, DONE).
signal phase_changed(phase: Phase)
## 3, 2, 1, then 0 = go.
signal countdown_tick(number: int)
## The fight may begin (after "go", a skip, or at once when it was already running).
signal released
## The intro is over. skipped: cut short by a key, or the fight was already running.
signal finished(skipped: bool)

enum Phase { DOOR, PAN, BANNER, COUNTDOWN, DONE }
enum Style { AUTO, FULL, SHORT }

const META_KEY: StringName = &"room_intro"
## Player.set_input_locked reason (per player, D-088).
const INPUT_LOCK: StringName = &"room_intro"
const COUNTDOWN_FROM := 3
## Timings in seconds (07_ui.md; TESTWERTE).
const DOOR_TIME := 0.3
const PAN_TIME := 1.5
const PAN_MOVE_TIME := 0.55
const CAMERA_RETURN_TIME := 0.4
const BANNER_LEAD := 0.6
const COUNTDOWN_STEP := 0.9
## Short version: banner + countdown in about 2 s.
const SHORT_BANNER_LEAD := 0.35
const SHORT_COUNTDOWN_STEP := 0.5
## The camera swings at most this far from the player (world px), so it never leaves the room.
const MAX_PAN_DISTANCE := 260.0

var room: Node2D = null
var objective: RoomObjective = null
## Global point the camera swings to (Vector2.INF: no swing).
var focus := Vector2.INF
## Full version (first time per save): camera swing, input lock, explanation card.
var full := false
var phase: Phase = Phase.DOOR
var skipped := false
## The fight was already running when the intro wanted to hold it (RoomController hook missing).
var fight_was_running := false

var _phase_time := 0.0
var _count := COUNTDOWN_FROM
var _released := false
var _locked: Array[Player] = []
## Camera2D -> its position before the swing.
var _cameras: Dictionary = {}


## Starts the intro of target_room for objective. focus_global: what the camera shows (INF = none).
## style AUTO: full the first time per save, short afterwards. Returns the running intro (one per
## room: a second call returns the first).
static func start(target_room: Node2D, goal: RoomObjective, focus_global := Vector2.INF, style := Style.AUTO) -> RoomIntro:
	var running := get_intro(target_room)
	if running != null:
		return running
	var intro := RoomIntro.new()
	intro.name = "RoomIntro"
	intro.room = target_room
	intro.objective = goal
	intro.focus = focus_global
	intro.full = is_first_time(goal) if style == Style.AUTO else style == Style.FULL
	target_room.set_meta(META_KEY, intro)
	target_room.add_child(intro)
	return intro


## The running intro of a room (null if none or already over).
static func get_intro(target_room: Node) -> RoomIntro:
	if target_room == null or not is_instance_valid(target_room) or not target_room.has_meta(META_KEY):
		return null
	var intro := target_room.get_meta(META_KEY) as RoomIntro
	return intro if is_instance_valid(intro) and not intro.is_queued_for_deletion() else null


## Hook for RoomController: true while an intro holds the fight back.
static func holds_encounter(target_room: Node) -> bool:
	var intro := get_intro(target_room)
	return intro != null and not intro.is_released()


## Hook for RoomController.activate(): calls callback once the intro of target_room lets the fight
## begin, at once when there is no intro.
static func after_intro(target_room: Node, callback: Callable) -> void:
	var intro := get_intro(target_room)
	if intro == null or intro.is_released():
		callback.call()
		return
	intro.released.connect(callback, CONNECT_ONE_SHOT)


## First time per save for this goal: the explanation card has not been seen yet.
static func is_first_time(goal: RoomObjective) -> bool:
	if goal == null:
		return false
	if RoomGenre.has_genre(goal.genre):
		return RoomGenre.should_explain(goal.genre)
	return not SaveManager.has_seen(RoomGenre.get_seen_id(goal.genre))


## Seconds from start to "go" (tests, tools).
static func get_total_time(is_full: bool) -> float:
	if is_full:
		return DOOR_TIME + PAN_TIME + BANNER_LEAD + COUNTDOWN_FROM * COUNTDOWN_STEP
	return DOOR_TIME + SHORT_BANNER_LEAD + COUNTDOWN_FROM * SHORT_COUNTDOWN_STEP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if full:
		_lock_players(true)
	phase_changed.emit(phase)


func is_released() -> bool:
	return _released


## Players locked right now (tests).
func get_locked_players() -> Array[Player]:
	return _locked.duplicate()


## Cuts the intro short: the banner stays a moment, the fight starts now.
func skip() -> void:
	if _released:
		return
	skipped = true
	if phase < Phase.BANNER:
		_enter(Phase.BANNER)
	_go()


func _process(delta: float) -> void:
	if _released:
		return
	if _fight_running():
		# RoomController started the fight without waiting (hook not wired): never lock or count
		# down over a running fight, just name the goal.
		fight_was_running = true
		skipped = true
		if phase < Phase.BANNER:
			_enter(Phase.BANNER)
		_finish_now()
		return
	_phase_time += delta
	match phase:
		Phase.DOOR:
			if _phase_time >= DOOR_TIME:
				_enter(Phase.PAN if full and focus.is_finite() else Phase.BANNER)
		Phase.PAN:
			if _phase_time >= PAN_TIME:
				_enter(Phase.BANNER)
		Phase.BANNER:
			if _phase_time >= (BANNER_LEAD if full else SHORT_BANNER_LEAD):
				_enter(Phase.COUNTDOWN)
		Phase.COUNTDOWN:
			if _phase_time >= _countdown_step():
				_phase_time -= _countdown_step()
				_count -= 1
				if _count <= 0:
					_go()
				else:
					countdown_tick.emit(_count)


func _unhandled_input(event: InputEvent) -> void:
	if _released or event.is_echo():
		return
	var wants_skip := event.is_action_pressed(&"interact")
	if not wants_skip and not _locked.is_empty():
		wants_skip = event.is_action_pressed(&"ui_accept")
	if wants_skip:
		get_viewport().set_input_as_handled()
		skip()


func _enter(next: Phase) -> void:
	phase = next
	_phase_time = 0.0
	match next:
		Phase.PAN:
			_swing_cameras()
		Phase.COUNTDOWN:
			# Players may move again while the numbers run; the camera comes home.
			_lock_players(false)
			_return_cameras()
			_count = COUNTDOWN_FROM
	phase_changed.emit(next)
	if next == Phase.COUNTDOWN:
		countdown_tick.emit(_count)


func _go() -> void:
	countdown_tick.emit(0)
	_finish_now()


func _finish_now() -> void:
	if _released:
		return
	_released = true
	_lock_players(false)
	_return_cameras()
	phase = Phase.DONE
	phase_changed.emit(Phase.DONE)
	released.emit()
	finished.emit(skipped)
	_clear_meta()
	queue_free()


func _countdown_step() -> float:
	return COUNTDOWN_STEP if full else SHORT_COUNTDOWN_STEP


func _fight_running() -> bool:
	return room != null and is_instance_valid(room) and room.has_method(&"is_encounter_started") and bool(room.call(&"is_encounter_started"))


# --- Players and cameras ---

## Living players of the run (coop: all of them, D-088).
func _players() -> Array[Player]:
	var players: Array[Player] = []
	if not is_inside_tree():
		return players
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_alive():
			players.append(player)
	return players


func _lock_players(locked: bool) -> void:
	if locked:
		for player in _players():
			player.set_input_locked(INPUT_LOCK, true)
			_locked.append(player)
		return
	for player in _locked:
		if is_instance_valid(player):
			player.set_input_locked(INPUT_LOCK, false)
	_locked.clear()


func _swing_cameras() -> void:
	for player in _players():
		var camera := player.get_node_or_null(^"Camera2D") as Camera2D
		if camera == null or _cameras.has(camera):
			continue
		_cameras[camera] = camera.position
		var target := player.to_local(focus).limit_length(MAX_PAN_DISTANCE)
		var tween := camera.create_tween()
		tween.tween_property(camera, "position", target, PAN_MOVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _return_cameras() -> void:
	for key in _cameras:
		if not is_instance_valid(key):
			continue
		var camera := key as Camera2D
		var home: Vector2 = _cameras[key]
		if camera.is_inside_tree():
			var tween := camera.create_tween()
			tween.tween_property(camera, "position", home, CAMERA_RETURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			camera.position = home
	_cameras.clear()


func _clear_meta() -> void:
	if room != null and is_instance_valid(room) and room.has_meta(META_KEY) and room.get_meta(META_KEY) == self:
		room.remove_meta(META_KEY)


## Freed with its room (unloaded early): never leave a player locked or a camera off to the side.
func _exit_tree() -> void:
	_lock_players(false)
	for key in _cameras:
		if is_instance_valid(key):
			(key as Camera2D).position = _cameras[key]
	_cameras.clear()
	_clear_meta()
	if not _released:
		# A waiting fight must never stay held.
		_released = true
		released.emit()
