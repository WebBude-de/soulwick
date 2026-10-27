class_name RoomIntro
extends Node
## The same introduction for every room mode (RAEUME §1.3, 07_ui.md, R3):
## door shuts (0.3 s) → Flint explains the room type to whoever does not know it yet (Phase.FLINT,
## WK11) → goal banner (symbol in the mode colour, big sentence, small rule line) → big 3-2-1 with
## a tick → go. The first time per account (RoomFlint, seen id "flint_room_<genre>") Flint flies the
## learner's camera over the task (way, goal, danger) and says it in short sentences; this replaces
## the old camera swing and explanation card (D-211). A known room type gets the short version
## (banner + countdown, about 2 s). Skippable with the interact key (not while Flint talks: his
## "Weiter" and "Überspringen" are his own).
## Co-op (playtest 23.10.2026 #88465571, #2b1a5a87): the intro waits behind the shut door until
## every living player stands in the room (at most GATHER_MAX_WAIT, then the stragglers are brought
## in anyway, CoopRules.WAIT_COUNTDOWN). Every machine computes the same learners (RoomFlint.knows)
## and holds the countdown for the same estimated time of the tour; the host's countdown decides
## when the fight starts. As soon as one player does not know the room type, every player sees the
## tour at the same time and is protected - nobody plays on while a mate listens. Online the tour
## goes through NetGuide (online/net_guide.gd): every machine registers the room tour as the builder
## of the "flint_room_" ids and asks for it with its local player; the host shows it to everybody
## (learners page, the others watch it go on), and Phase.FLINT holds until the group hint is over.
## Local co-op (one machine) shows the tour to every local player itself. Nothing pauses.
## Without Flint (scripts, RoomFlint.is_enabled) the old full version stays for the first time per
## save: camera swing to the goal (players' input locked) instead of the tour.
##
## Logic only: it holds the fight back (after_intro), locks and frees the players, moves their
## cameras and asks FlintGuide for the tours. Banner, countdown and sounds are DungeonUI's: it finds
## the intro through node_added and follows the signals; the co-op line goes to the room's DungeonUI
## status line like a mode's banner (CombatVariant.show_banner). Child of its room, so it dies with
## it and always frees players and cameras on the way out.
##
## Use (R4): var goal := RoomObjective.attach(room, RoomObjective.create(RoomObjective.FLAME))
##           RoomIntro.start(room, goal, flame.global_position)
## A mode node (the room's CombatVariant) or the goal may answer get_flint_steps() ->
## Array[FlintGuideStep] (RoomFlint.steps with its camera goals); else Flint looks at focus.
## RoomController.activate() starts the fight through RoomIntro.after_intro(self, start_encounter).

## Phase reached (DOOR, PAN, BANNER, COUNTDOWN, DONE).
signal phase_changed(phase: Phase)
## 3, 2, 1, then 0 = go.
signal countdown_tick(number: int)
## The fight may begin (after "go", a skip, or at once when it was already running).
signal released
## The intro is over. skipped: cut short by a key, or the fight was already running.
signal finished(skipped: bool)

enum Phase { DOOR, PAN, FLINT, BANNER, COUNTDOWN, DONE }
## AUTO: Flint for learners (first time per account), else short. FULL: the old full version with
## the camera swing (no Flint). SHORT: banner and countdown only.
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
## Co-op: the intro waits at most this long (s) for every living player to stand in the room; by
## then the room start has brought the stragglers in (CoopRules.WAIT_COUNTDOWN 10 s). TESTWERT
const GATHER_MAX_WAIT := 11.0
## Online: the group hint must have started this long (s) after Phase.FLINT began, else Flint is
## skipped (a mate's request never reached the host); it ends at the host's time limit at the latest.
## TESTWERTE
const GROUP_START_WAIT := 3.0
const GROUP_END_MARGIN := 2.0

## Online group tours of the running intros by genre (NetGuide builder, build_group_tour).
static var _group_tours: Dictionary[StringName, FlintExplanation] = {}
## The room's mode node (CombatVariant.NODE_NAME), asked for Flint's camera goals.
const MODE_NODE := ^"CombatVariant"

var room: Node2D = null
var objective: RoomObjective = null
## Global point the camera swings to (Vector2.INF: no swing).
var focus := Vector2.INF
var style: Style = Style.AUTO
## Full version: Flint explains (or, without Flint, the camera swing with input lock); slower
## banner and countdown.
var full := false
## Room type of the goal (RoomGenre id; Flint's tour and seen id).
var genre: StringName = &""
var phase: Phase = Phase.DOOR
var skipped := false
## Co-op: still waiting behind the shut door for players outside the room (Phase.DOOR holds).
var gathering := false
## The fight was already running when the intro wanted to hold it (RoomController hook missing).
var fight_was_running := false
## Players who do not know this room type yet (the same on every machine, RoomFlint.knows).
var learners: Array[Player] = []
## Seconds Phase.FLINT holds the countdown in co-op (RoomFlint.estimated_duration, the same on
## every machine); 0 in single player: until the local tour ends.
var flint_time := 0.0
## The tour of this room (null without learners).
var flint_tour: FlintExplanation = null

var _phase_time := 0.0
var _count := COUNTDOWN_FROM
var _released := false
var _locked: Array[Player] = []
## Camera2D -> its position before the swing.
var _cameras: Dictionary = {}
## Guides of local players that play flint_tour.
var _guides: Array[FlintGuide] = []
## Online: the run's NetGuide that shows flint_tour to the group (null: this machine shows it).
var _group: NetGuide = null
## Online: the group hint of flint_tour has been shown on this machine.
var _group_seen := false


## Starts the intro of target_room for objective. focus_global: what the camera shows (INF = none).
## style AUTO: Flint the first time per account, short afterwards (without Flint: full the first
## time per save). Returns the running intro (one per room: a second call returns the first).
static func start(target_room: Node2D, goal: RoomObjective, focus_global := Vector2.INF, intro_style := Style.AUTO) -> RoomIntro:
	var running := get_intro(target_room)
	if running != null:
		return running
	var intro := RoomIntro.new()
	intro.name = "RoomIntro"
	intro.room = target_room
	intro.objective = goal
	intro.focus = focus_global
	intro.style = intro_style
	intro.genre = goal.genre if goal != null else &""
	intro.full = is_first_time(goal) if intro_style == Style.AUTO else intro_style == Style.FULL
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


## First time per save for this goal (the full version without Flint, scripts and tools).
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
	gathering = GameMode.of(self).is_multiplayer() and not are_all_players_inside()
	if not gathering:
		_begin()
	phase_changed.emit(phase)


## Everybody is here (or never waited for): who learns the room type, the tour, the lock.
func _begin() -> void:
	gathering = false
	if style == Style.AUTO and RoomFlint.is_enabled():
		_plan_flint()
		full = has_flint()
	if full and not has_flint():
		_lock_players(true)


## Are all living players inside the room (its arena rect)? A room without one counts everybody in.
func are_all_players_inside() -> bool:
	if room == null or not is_instance_valid(room) or not room.has_method(&"get_arena"):
		return true
	var rect: Rect2 = room.call(&"get_arena")
	for player in _players():
		if not rect.has_point(player.global_position):
			return false
	return true


## Co-op hook (net layer): the room start brought every player in - stop waiting now.
func end_gather() -> void:
	if gathering:
		_begin()
		_phase_time = 0.0


func is_released() -> bool:
	return _released


## True if Flint explains this room to somebody (Phase.FLINT comes after the door).
func has_flint() -> bool:
	return flint_tour != null


## The guides of this machine's players that play the tour (tests).
func get_flint_guides() -> Array[FlintGuide]:
	return _guides.duplicate()


## Players locked right now (tests).
func get_locked_players() -> Array[Player]:
	return _locked.duplicate()


## Cuts the intro short: the banner stays a moment, the fight starts now (a tour of this room on
## this machine ends too: Flint flies back, the room type counts as seen).
func skip() -> void:
	if _released:
		return
	skipped = true
	for guide in _guides:
		if is_instance_valid(guide) and guide.current == flint_tour:
			guide.skip()
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
			if gathering:
				if are_all_players_inside() or _phase_time >= GATHER_MAX_WAIT:
					end_gather()
				return
			if _phase_time >= DOOR_TIME:
				if has_flint():
					_enter(Phase.FLINT)
				else:
					_enter(Phase.PAN if full and focus.is_finite() else Phase.BANNER)
		Phase.PAN:
			if _phase_time >= PAN_TIME:
				_enter(Phase.BANNER)
		Phase.FLINT:
			if _flint_done():
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
	# While Flint explains, his keys are his ("Weiter", "Überspringen"); the countdown waits for him.
	if _released or event.is_echo() or gathering or (has_flint() and phase <= Phase.FLINT):
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
		Phase.BANNER:
			_mark_known()
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
	_mark_known()
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


# --- Flint (WK11) ---

## Who learns the room type here, the tour, its time in co-op; the tours start at once (Flint grows
## and flies to his corner while the door shuts): for the local learners, in co-op for every local
## player as soon as anybody learns (force: also for those who know it).
func _plan_flint() -> void:
	if not RoomFlint.has_tour(genre):
		return
	var players := _players()
	learners = RoomFlint.learners(players, genre)
	if learners.is_empty():
		return
	var coop := GameMode.of(self).is_multiplayer()
	var tour_steps := _flint_steps()
	flint_tour = RoomFlint.tour(genre, tour_steps, coop)
	flint_time = RoomFlint.estimated_duration(tour_steps) if coop else 0.0
	_group = NetGuide.of(get_tree()) if coop else null
	if _group != null:
		_ask_group(players)
		return
	var audience: Array[Player] = players if coop else learners
	for player in audience:
		if player.is_local and FlintGuide.explain(player, flint_tour, coop):
			var guide := FlintGuide.of(player)
			if guide != null and not _guides.has(guide):
				_guides.append(guide)


## Online: the tour as the group hint of its seen id; every local player asks (the host starts it
## for everybody once one of them has not seen it).
func _ask_group(players: Array[Player]) -> void:
	_group_tours[genre] = flint_tour
	_group.register_builder(RoomFlint.SEEN_PREFIX, RoomIntro.build_group_tour)
	for player in players:
		if player.is_local:
			_group.request_hint(player, flint_tour.id)


## NetGuide builder of the "flint_room_" ids: the tour of a running intro of that genre (camera
## goals from its mode), else FlintControls' explanation (rooms without an intro).
static func build_group_tour(id: StringName) -> FlintExplanation:
	var genre_id := StringName(String(id).trim_prefix(RoomFlint.SEEN_PREFIX))
	var tour: FlintExplanation = _group_tours.get(genre_id)
	if tour != null:
		return tour
	return FlintControls.explanation_for(id)


## The tour's sentences with camera goals: from the goal (arena) or the room's mode node, else the
## intro's focus for the first sentence.
func _flint_steps() -> Array[FlintGuideStep]:
	var result: Array[FlintGuideStep] = []
	var source: Object = null
	if objective != null and is_instance_valid(objective) and objective.has_method(&"get_flint_steps"):
		source = objective
	elif room != null and is_instance_valid(room):
		var mode := room.get_node_or_null(MODE_NODE)
		if mode != null and mode.has_method(&"get_flint_steps"):
			source = mode
	if source != null:
		result.assign(source.call(&"get_flint_steps"))
	if result.is_empty():
		result = RoomFlint.steps(genre, [focus])
	return result


## Co-op: the countdown waits flint_time on every machine. Single player: until the local tour is
## over (or SOLO_MAX_WAIT, or at once when no local tour runs).
func _flint_done() -> bool:
	if _group != null:
		return _group_done()
	if flint_time > 0.0:
		return _phase_time >= flint_time
	if _phase_time >= RoomFlint.SOLO_MAX_WAIT:
		return true
	for guide in _guides:
		if is_instance_valid(guide) and not guide.is_queued_for_deletion() and guide.is_known(flint_tour.id):
			return false
	return true


## Online: over once the group hint of the tour has been shown here and ended; never started within
## GROUP_START_WAIT, or longer than the host's limit (NetGuide.time_limit), it counts as over too.
func _group_done() -> bool:
	if not is_instance_valid(_group):
		return true
	if _group.get_showing() == flint_tour.id:
		_group_seen = true
		return _phase_time >= NetGuide.time_limit(flint_tour) + GROUP_END_MARGIN
	if _group_seen:
		return true
	return _phase_time >= GROUP_START_WAIT


## Everybody of the session has been through this room type now (the same on every machine).
func _mark_known() -> void:
	if has_flint():
		RoomFlint.mark_known(_players(), genre)


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
	if flint_tour != null and _group_tours.get(genre) == flint_tour:
		_group_tours.erase(genre)
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
