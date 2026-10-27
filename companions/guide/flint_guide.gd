class_name FlintGuide
extends Node
## "Flint erklärt" for one player (KONZEPT §7.2, D-194): plays FlintExplanations one after another.
## Flint grows beside his player, flies into the corner at the bottom right (FlintExcursion, optics
## only: his light stays with the player), says the steps letter by letter with babble (D-098),
## optionally flies the player's own camera to goals (FlintGuideCamera, D-184), goes on with "Weiter"
## (click, key, tap, gamepad), ends with "Überspringen" at any time, then flies back and shrinks.
## Seen flags per account (AccountSeen, ids "flint_*").
##
## Co-op and decisions (D-085, D-088, D-123): nothing pauses. A TOUR protects only the explained
## player like an open menu (Player.set_protected: input locked, no damage, enemies ignore him); a
## HINT neither locks nor protects. Only local players are explained (their machine shows the corner);
## protection_changed tells the network layer (integrator hook: a client reports it to the host like
## its open menus). State lives here, at the player; the view (FlintGuideView) only follows signals.
##
## Usage (WK9, WK10, WK11 and the "first time" hooks):
##   FlintGuide.explain(player, FlintExplanations.named(&"entrance_danger"))
##   FlintGuide.explain(player, FlintExplanation.tour(&"flint_village_forge", [
##       FlintGuideStep.say(&"FLINT_VILLAGE_FORGE", FlintGuideStep.Mood.POINT).at_node(forge)]))
## explain() queues and returns false when it will not show (seen, invalid, remote player, not
## allowed now).
## Queue order (FS5, finding P1-1 of the newcomer run: hints came 30 s late, after the moment):
## - Higher FlintExplanation.priority first (URGENT danger, then PLACE: about where the player is,
##   then GENERAL), equal ones in order of arrival. A waiting explanation of higher priority cuts a
##   running HINT (never a tour): the hint goes back into the queue unseen and comes afterwards.
## - The same channel replaces: the newest practice station's hint ends the running one of its
##   channel and drops the waiting ones.
## - Explanations whose still_due says false are dropped unseen while they wait (room left, soul gate
##   used, key already pressed): dropped, and they come on the next fitting occasion.
## - No tour starts while the player is in the side view (it holds him mid-jump); it waits.
## Online (feedback #ce7cde79 23.10.2026 "Im Online-Game soll Flint ausgeschaltet sein"): while this
## machine is in an online lobby or a networked session and not in the dungeon (the village of a
## relay room, the lobby dialog), Flint explains nothing (allowed_now); a running explanation ends
## without being marked seen, so it comes on the next solo start. In the dungeon of a shared run the
## "first time" hints go through the host to everybody at once (NetGuide, FlintControls).

signal started(explanation: FlintExplanation)
signal phase_changed(phase: Phase)
## A sentence begins (text in the current language).
signal step_started(index: int, text: String, mood: FlintGuideStep.Mood)
signal characters_revealed(count: int)
## A babbled syllable starts at char_index (view: sound and portrait pulse).
signal syllable_spoken(char_index: int, syllable: String)
## Holding "Weiter" skips: 0..1 while held, 0 when let go.
signal hold_progress(ratio: float)
signal finished(explanation: FlintExplanation, skipped: bool)
## The explained player became protected or free again (network hook).
signal protection_changed(protected: bool)
## An explanation was taken back unseen (no longer due, replaced, drop()); it may come again later.
signal dropped(explanation: FlintExplanation)

enum Phase { IDLE, FLY_OUT, TALK, FLY_BACK }

const NODE_NAME := &"FlintGuide"
## Player.set_protected reason (per player).
const PROTECTION: StringName = &"flint_guide"
## "Weiter" on keyboard, mouse and gamepad (E, Space, click, Enter; X and A on the pad).
const NEXT_ACTIONS: Array[StringName] = [&"interact", &"dash", &"attack", &"ui_accept"]
## "Überspringen" on the gamepad (B). Esc stays the pause menu.
const SKIP_PAD_ACTION: StringName = &"ui_cancel"
## Group of the LobbyClient (LobbyClient.GROUP; by name, so this file never waits for the online code).
const LOBBY_GROUP: StringName = &"lobby_client"
const FlintGuideViewScript := preload("res://ui/flint_guide/flint_guide_view.gd")

## The player this guide explains things to.
var player: Player = null
## The explanation running now (null when idle).
var current: FlintExplanation = null
var phase := Phase.IDLE
var step_index := -1
var was_skipped := false
## Local players get the corner view (tests switch it off).
var shows_view := true
## Seen flags (tests swap them): has_seen(id: StringName) -> bool, mark_seen(id: StringName).
var has_seen := func(id: StringName) -> bool: return AccountSeen.has_seen(id)
var mark_seen := func(id: StringName) -> void: AccountSeen.mark_seen(id)

var _queue: Array[FlintExplanation] = []
## Explanations queued with force (shown even if seen meanwhile).
var _forced: Array[FlintExplanation] = []
var _phase_time := 0.0
var _step_time := 0.0
var _text := ""
var _times := PackedFloat32Array()
var _syllables := PackedInt32Array()
var _revealed := 0
var _hold_action: StringName = &""
var _held_time := 0.0
## Guide time (s, advance()) and the time of the last accepted press (debounce).
var _clock := 0.0
var _last_press_at := -1000.0
var _protected := false
## The running explanation was queued with force (kept when it is cut and comes back).
var _current_forced := false
var _camera: FlintGuideCamera = null
var _excursion: FlintExcursion = null
var _view: CanvasLayer = null


## The guide of player, created on first use (idempotent).
static func for_player(target: Player) -> FlintGuide:
	if target == null or not is_instance_valid(target):
		return null
	var existing := of(target)
	if existing != null:
		return existing
	var guide := FlintGuide.new()
	guide.name = NODE_NAME
	guide.player = target
	target.add_child(guide)
	return guide


## The guide of a player, or null.
static func of(target: Node) -> FlintGuide:
	if target == null or not is_instance_valid(target):
		return null
	var guide := target.get_node_or_null(NodePath(NODE_NAME)) as FlintGuide
	if guide == null or guide.is_queued_for_deletion():
		return null
	return guide


## Explains explanation to player (queued behind a running one). False when it will not show: seen
## already (once), invalid, or not a local player. force shows it even when seen.
static func explain(target: Player, explanation: FlintExplanation, force := false) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_local:
		return false
	if not allowed_now(target.get_tree() if target.is_inside_tree() else null):
		return false
	var guide := for_player(target)
	return guide != null and guide.queue(explanation, force)


func _ready() -> void:
	if player == null:
		player = get_parent() as Player


## May Flint explain anything on this machine right now? Not in an online lobby or networked session
## outside the dungeon (village of a relay room, the lobby dialog; feedback #ce7cde79). Solo, local
## co-op and the dungeon of a shared run: yes. Hook for VillageTour.may_explain (village-dev).
static func allowed_now(tree: SceneTree) -> bool:
	if tree == null or not is_online(tree):
		return true
	return GameManager.get_phase() == GameManager.Phase.DUNGEON


## This machine takes part in an online session: a networked GameMode, or a LobbyClient that is
## joining or in a relay room. Group lookup only (never creates a lobby node).
static func is_online(tree: SceneTree) -> bool:
	if tree == null:
		return false
	if GameMode.of_tree(tree).is_networked():
		return true
	var lobby := tree.get_first_node_in_group(LOBBY_GROUP)
	if lobby == null:
		return false
	var in_room := lobby.has_method(&"is_in_room") and bool(lobby.call(&"is_in_room"))
	var busy := lobby.has_method(&"is_busy") and bool(lobby.call(&"is_busy"))
	return in_room or busy


## Queues explanation. False when it is seen (and once), invalid, or already queued or running.
func queue(explanation: FlintExplanation, force := false) -> bool:
	if explanation == null:
		return false
	if not explanation.is_valid():
		push_warning("FlintGuide: %s" % "; ".join(explanation.problems()))
		return false
	if not FlintGuideRules.should_explain(explanation, _seen(explanation.id), force):
		return false
	if is_inside_tree() and not allowed_now(get_tree()):
		return false
	if is_known(explanation.id):
		return false
	var replaced := _replace_channel(explanation.channel)
	_insert(explanation)
	if force:
		_forced.append(explanation)
	if replaced or phase == Phase.IDLE:
		_start_next()
	else:
		_give_way()
	return true


## True while the explanation id runs or waits in the queue.
func is_known(id: StringName) -> bool:
	if current != null and current.id == id:
		return true
	for waiting in _queue:
		if waiting.id == id:
			return true
	return false


func is_running() -> bool:
	return phase != Phase.IDLE


## Explanations still waiting behind the current one.
func get_queue_size() -> int:
	return _queue.size()


## The sentence shown now (current language) and how many letters are visible.
func get_text() -> String:
	return _text


func get_revealed() -> int:
	return _revealed


func get_step() -> FlintGuideStep:
	if current == null or step_index < 0 or step_index >= current.steps.size():
		return null
	return current.steps[step_index]


## The camera ride of the running tour (null without one).
func get_camera() -> FlintGuideCamera:
	return _camera


## The corner view (null for remote players and in tests without a view).
func get_view() -> CanvasLayer:
	return _view if _view != null and is_instance_valid(_view) else null


## "Weiter": shows the whole sentence while it is typed, else goes on. False when ignored (grace
## time, a double tap, not talking).
func press() -> bool:
	if phase != Phase.TALK:
		return false
	if _clock - _last_press_at < FlintGuideRules.PRESS_DEBOUNCE:
		return false
	match FlintGuideRules.press(_revealed, _times.size(), _step_time):
		FlintGuideRules.Press.REVEAL_ALL:
			_last_press_at = _clock
			_set_revealed(_times.size(), false)
			return true
		FlintGuideRules.Press.NEXT:
			_last_press_at = _clock
			_next_step()
			return true
	return false


## "Überspringen": ends the whole explanation (Flint flies back). False when nothing runs.
func skip() -> bool:
	if phase != Phase.FLY_OUT and phase != Phase.TALK:
		return false
	_end(true)
	return true


## Takes the explanation id back: skipped (and marked seen like a skip) while it runs, dropped while
## it waits. NetGuide ends a group explanation on every machine with it. False if it is unknown.
func withdraw(id: StringName) -> bool:
	if current != null and current.id == id:
		return skip()
	for waiting in _queue:
		if waiting.id == id:
			_queue.erase(waiting)
			_forced.erase(waiting)
			return true
	return false


## Takes the explanation id back unseen (FS5; NetGuide when the host drops a group hint): dropped
## while it waits, ended without the seen mark while it runs. False if it is unknown.
func drop(id: StringName) -> bool:
	if current != null and current.id == id:
		if phase == Phase.FLY_OUT or phase == Phase.TALK:
			var ended := current
			_end(true, false)
			dropped.emit(ended)
		return true
	for waiting in _queue:
		if waiting.id == id:
			_queue.erase(waiting)
			_forced.erase(waiting)
			dropped.emit(waiting)
			return true
	return false


## Ends everything at once without the flight back (world change, the player leaves). Nothing is
## marked seen.
func cancel_all() -> void:
	_queue.clear()
	_forced.clear()
	_current_forced = false
	if phase == Phase.IDLE:
		return
	_release()
	var ended := current
	current = null
	step_index = -1
	_set_phase(Phase.IDLE)
	if _view != null and is_instance_valid(_view):
		_view.queue_free()
	_view = null
	finished.emit(ended, true)


## A key or button: "Weiter" actions page (and skip when held), B on the pad skips, a tap pages.
## Only tours take game input; hints close with their buttons or by themselves. True if used.
func handle_input(event: InputEvent) -> bool:
	if current == null or not current.locks_player() or (phase != Phase.TALK and phase != Phase.FLY_OUT):
		return false
	if event.is_echo():
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			press()
		return true
	if event is InputEventJoypadButton and InputMap.has_action(SKIP_PAD_ACTION) and event.is_action_pressed(SKIP_PAD_ACTION):
		skip()
		return true
	for action in NEXT_ACTIONS:
		if not InputMap.has_action(action):
			continue
		if event.is_action_released(action):
			var was_held := action == _hold_action
			if was_held:
				end_hold()
			return was_held
		if event.is_action_pressed(action):
			press()
			begin_hold(action)
			return true
	return false


## A "Weiter" key went down; held HOLD_TO_SKIP_TIME it skips everything.
func begin_hold(action: StringName) -> void:
	_hold_action = action
	_held_time = 0.0
	hold_progress.emit(0.0)


func end_hold() -> void:
	if _hold_action == &"":
		return
	_hold_action = &""
	_held_time = 0.0
	hold_progress.emit(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if phase != Phase.IDLE and not allowed_now(get_tree()):
		# Went online meanwhile (joined a lobby in the village): stop, nothing is marked seen.
		cancel_all()
		return
	# Releases can get lost (focus change, a menu took them): check the key itself.
	if _hold_action != &"" and InputMap.has_action(_hold_action) and not Input.is_action_pressed(_hold_action):
		end_hold()
	advance(delta)


## Steps the guide by delta seconds (every frame; tests call it directly).
func advance(delta: float) -> void:
	_clock += delta
	if not _queue.is_empty():
		if phase == Phase.IDLE:
			_start_next()
		else:
			_prune()
			_give_way()
	match phase:
		Phase.FLY_OUT:
			_phase_time += delta
			var progress := _phase_time / (FlintGuideRules.GROW_TIME + FlintGuideRules.FLY_OUT_TIME)
			if _excursion != null:
				_excursion.out(progress)
			if progress >= 1.0:
				if _excursion != null:
					_excursion.hide_in_corner()
				_set_phase(Phase.TALK)
				_begin_step(0)
		Phase.TALK:
			_talk(delta)
		Phase.FLY_BACK:
			_phase_time += delta
			var progress := _phase_time / FlintGuideRules.FLY_BACK_TIME
			if _excursion != null:
				_excursion.back(progress)
			if progress >= 1.0:
				_finish()


func _talk(delta: float) -> void:
	if _excursion != null:
		_excursion.hide_in_corner()
	_step_time += delta
	_set_revealed(FlintGuideRules.revealed_count(_times, _step_time), true)
	if _hold_action != &"":
		_held_time += delta
		hold_progress.emit(clampf(_held_time / FlintGuideRules.HOLD_TO_SKIP_TIME, 0.0, 1.0))
		if _held_time >= FlintGuideRules.HOLD_TO_SKIP_TIME:
			skip()
			return
	if current.advances_by_itself() and _revealed >= _times.size():
		if _step_time >= FlintGuideRules.typing_time(_text) + FlintGuideRules.read_time(_text):
			_next_step()


## Starts the first waiting explanation that may start now (a tour waits out the side view). After
## a cut (Flint still out or in his corner) the next one goes on from there; with nothing left he
## lands at once.
func _start_next() -> void:
	_prune()
	for i in _queue.size():
		var next: FlintExplanation = _queue[i]
		if not _may_start(next):
			continue
		_queue.remove_at(i)
		_current_forced = _forced.has(next)
		_forced.erase(next)
		_begin(next)
		return
	if current == null and (phase == Phase.FLY_OUT or phase == Phase.TALK):
		if _excursion != null:
			_excursion.land()
		_excursion = null
		_set_phase(Phase.IDLE)


## Puts explanation into the queue by priority: behind its equals, or in front of them when it was
## cut and comes back.
func _insert(explanation: FlintExplanation, before_equals := false) -> void:
	var priorities: Array[int] = []
	for waiting in _queue:
		priorities.append(waiting.priority)
	_queue.insert(FlintGuideRules.queue_index(priorities, explanation.priority, before_equals), explanation)


## Drops the waiting explanations that are seen meanwhile (silently, as always) or no longer due
## (dropped: unseen, they come on the next occasion).
func _prune() -> void:
	for waiting in _queue.duplicate():
		if waiting.once and _seen(waiting.id) and not _forced.has(waiting):
			_queue.erase(waiting)
		elif not waiting.is_still_due():
			_queue.erase(waiting)
			_forced.erase(waiting)
			dropped.emit(waiting)


## A tour holds its player: never in the side view (he would hang mid-jump), it waits for the floor.
func _may_start(explanation: FlintExplanation) -> bool:
	if not explanation.locks_player():
		return true
	return player == null or not is_instance_valid(player) or not player.is_side_view()


## The first startable waiting explanation outranks the running hint: cut it (back into the queue).
func _give_way() -> void:
	var talking := phase == Phase.FLY_OUT or phase == Phase.TALK
	for waiting in _queue:
		if not _may_start(waiting):
			continue
		if FlintGuideRules.gives_way(current, talking, waiting):
			_cut(true)
			_start_next()
		return


## Same channel: drops the waiting explanations of channel and cuts the running hint of it. True if
## the running one was cut.
func _replace_channel(channel: StringName) -> bool:
	if channel == &"":
		return false
	for waiting in _queue.duplicate():
		if waiting.channel == channel:
			_queue.erase(waiting)
			_forced.erase(waiting)
			dropped.emit(waiting)
	var talking := phase == Phase.FLY_OUT or phase == Phase.TALK
	if current != null and current.channel == channel and talking and not current.locks_player():
		_cut(false)
		return true
	return false


## Ends the running hint unseen at once, without the flight back (Flint stays out for the next one):
## back into the queue (in front of its equals) or gone.
func _cut(requeue: bool) -> void:
	var ended := current
	end_hold()
	_set_protected(false)
	current = null
	step_index = -1
	_text = ""
	if _view != null and is_instance_valid(_view):
		_view.queue_free()
	_view = null
	if requeue:
		_insert(ended, true)
		if _current_forced:
			_forced.append(ended)
	else:
		dropped.emit(ended)
	_current_forced = false
	finished.emit(ended, true)


func _begin(explanation: FlintExplanation) -> void:
	# After a cut Flint is out already: the new one goes on from where the flight is.
	var in_flight := phase == Phase.FLY_OUT or phase == Phase.TALK
	current = explanation
	was_skipped = false
	step_index = -1
	_text = ""
	_times = PackedFloat32Array()
	_revealed = 0
	if not in_flight:
		_phase_time = 0.0
	_last_press_at = -1000.0
	if explanation.locks_player():
		_set_protected(true)
	_camera = FlintGuideCamera.for_player(player) if explanation.uses_camera() else null
	if shows_view and player != null and player.is_local and is_inside_tree():
		_view = FlintGuideViewScript.new(self)
		add_child(_view)
	if _excursion == null:
		_excursion = FlintExcursion.new(FlintCompanion.of(player), _corner_point)
	if not in_flight:
		_set_phase(Phase.FLY_OUT)
	started.emit(explanation)
	if phase == Phase.TALK:
		_begin_step(0)


func _begin_step(index: int) -> void:
	step_index = index
	var step := current.steps[index]
	_text = step.get_text()
	_times = FlintGuideRules.reveal_times(_text)
	_syllables = BossIntroRules.syllable_starts(_text)
	_revealed = 0
	_step_time = 0.0
	if _camera != null:
		var goal := step.resolve_focus(player.get_parent() if player != null else null)
		if goal != Vector2.INF:
			_camera.look_at(goal, current.max_pan_distance)
		else:
			_camera.return_home()
	step_started.emit(index, _text, step.mood)
	characters_revealed.emit(0)
	# The first letter is there at once (reveal time 0).
	_set_revealed(FlintGuideRules.revealed_count(_times, 0.0), true)


func _next_step() -> void:
	if current != null and step_index + 1 < current.steps.size():
		_begin_step(step_index + 1)
	else:
		_end(false)


## Talking is over (finished or skipped): seen (unless dropped), camera home, Flint flies back.
func _end(skipped: bool, mark := true) -> void:
	was_skipped = skipped
	end_hold()
	if current.once and mark:
		mark_seen.call(current.id)
	if _camera != null:
		_camera.return_home()
	_phase_time = 0.0
	_set_phase(Phase.FLY_BACK)


func _finish() -> void:
	var ended := current
	_release()
	var flint := FlintCompanion.of(player)
	if flint != null and not was_skipped and ended.locks_player():
		flint.react(FlintMood.Mood.JOY)
	current = null
	_current_forced = false
	step_index = -1
	_set_phase(Phase.IDLE)
	if _view != null and is_instance_valid(_view):
		_view.queue_free()
	_view = null
	finished.emit(ended, was_skipped)
	_start_next()


## Flint lands, the camera is home, the player is free.
func _release() -> void:
	end_hold()
	if _excursion != null:
		_excursion.land()
	_excursion = null
	if _camera != null:
		if phase != Phase.FLY_BACK:
			_camera.release_now()
	_camera = null
	_set_protected(false)


func _set_revealed(count: int, speak: bool) -> void:
	if count <= _revealed:
		return
	if speak:
		for start in _syllables:
			if start >= _revealed and start < count:
				syllable_spoken.emit(start, BossIntroRules.syllable_at(_text, start))
	_revealed = count
	characters_revealed.emit(count)


func _set_phase(value: Phase) -> void:
	if phase == value:
		return
	phase = value
	phase_changed.emit(value)


func _set_protected(value: bool) -> void:
	if _protected == value:
		return
	_protected = value
	if player != null and is_instance_valid(player):
		player.set_protected(PROTECTION, value)
	protection_changed.emit(value)


func _seen(id: StringName) -> bool:
	return bool(has_seen.call(id))


## The corner portrait's spot in the world (FlintExcursion flies there), INF without a view.
func _corner_point() -> Vector2:
	var view := get_view()
	if view == null or not view.has_method(&"get_corner_world_point"):
		return Vector2.INF
	return view.call(&"get_corner_world_point")


func _exit_tree() -> void:
	# Freed with the player or its world: never leave a player protected or a camera off to the side.
	if phase != Phase.IDLE:
		if _camera != null:
			_camera.release_now()
		_camera = null
		if _excursion != null:
			_excursion.land()
		_set_protected(false)
