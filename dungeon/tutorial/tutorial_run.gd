class_name TutorialRun
extends Node2D
## The practice run (Übungsgang, WK10, KONZEPT §7.2): a short hall before room 1 with four stations -
## 1 walk and attack (straw dummies), 2 dash (over an abyss), 3 jump (a stretch in side view with the
## double jump and momentum), 4 right click / special (a dummy with a wooden shield: normal hits
## bounce off, the special breaks it). Flint is the one who explains (WK10b): one-sentence hints in
## his corner while the player already plays (no tour, no stop, nobody waits); the key symbols stand
## on the station signs, the TutorialHud is only a slim progress strip at the top edge and hides in
## the side-view stretch. A station's flag flies when it is done and the next door opens. At the end
## Flint says "Los geht's!", the gate "Dungeon" leads into room 1, where the normal run begins and
## Flint says "geschafft" (no banner). "Kenne ich schon" (sign at the start, strip) skips it. The
## first completion gives TutorialRules.XP_FIRST_COMPLETION XP (AccountProgress hook); done or
## skipped, the account never gets it again (AccountSeen TutorialRules.SEEN_ID).
## Only alone: in a group game begin() adds TutorialCoopTips instead (tip bubbles in the first rooms)
## and the practice run waits for the next solo start.
##
## Hook (DungeonManager, integrator): at the end of _ready(), after the first two slots are prepared,
##     TutorialRun.begin(self)
## It builds the hall far south of the rooms (TutorialRules.ORIGIN), moves PlayerSpawn there (the
## WorldController spawns the players after the dungeon's _ready) and holds Flint's first-run key
## hints (FlintControls, D-211) back until the end. Room 1 is prepared as always and starts
## when the player is placed inside it; nothing draws from the dungeon RNG, so the room stream is the
## same with and without it.
##
## Decisions here (station order, done, skip, finish), effects through the parts (TutorialArea,
## TutorialHud, TutorialJump, FlintGuide) and the signals. The state is the run's own: it serves the
## one local player of a solo run (no group lookup, D-088).

signal station_started(station: int)
signal station_completed(station: int)
## The run ended: completed through the gate, or skipped. xp: what was credited (0 without).
signal finished(completed: bool, xp: int)

const NODE_NAME := &"TutorialRun"
## Zones: -1 the welcome, 0..3 the stations, FINISH the way to the gate.
const WELCOME := -1
const FINISH := 4
const WELCOME_ID: StringName = &"flint_tutorial_welcome"
const FINISH_ID: StringName = &"flint_tutorial_finish"
const DONE_ID: StringName = &"flint_tutorial_done"
const FALL_ID: StringName = &"flint_tutorial_fall"
const BLOCKED_ID: StringName = &"flint_tutorial_blocked"
const INPUT_LOCK: StringName = &"tutorial"
const FADE_LAYER := 95
## Flint repeats the "Klonk!" tip after this many more blocked hits. TESTWERT
const BLOCK_TIP_EVERY := 4
const CRYPT_BIOME_PATH := "res://dungeon/biomes/crypt.tres"

## Tools and tests: offer it on the next dungeon start even when the account has seen it.
static var force_next := false

var manager: Node2D = null
var area: TutorialArea = null
var hud: TutorialHud = null
var player: Player = null
var zone := WELCOME
var done: Array[bool] = [false, false, false, false]
var is_finished := false
var was_completed := false
## The account had seen it before (a forced replay gives no XP).
var was_seen := false
var credited_xp := 0
var blocked_hits := 0
## Marks the seen flag of the account (tests swap it).
var mark_seen := func(id: StringName) -> void: AccountSeen.mark_seen(id)
## Whether the account has met Flint in the village tour (tests swap it).
var village_tour_seen := func() -> bool: return AccountSeen.has_seen(VillageTour.TOUR_ID)
## The XP hook's target (tests swap it): AccountProgress.current().
var progress_source := func() -> Object: return AccountProgress.current()

var _announced: Dictionary[int, bool] = {}
var _jump: TutorialJump = null
var _fade: CanvasLayer = null
var _black: ColorRect = null


## Starts the practice run in dungeon when it is due (alone, not seen, or forced; force_next for
## tools). In a group game it adds the co-op tips instead and returns null. Idempotent.
static func begin(dungeon: Node2D, force := false) -> TutorialRun:
	if dungeon == null or not is_instance_valid(dungeon):
		return null
	var existing := of(dungeon)
	if existing != null:
		return existing
	var group_game := GameMode.of(dungeon).is_multiplayer()
	if group_game:
		TutorialCoopTips.attach(dungeon)
		return null
	var seen := AccountSeen.has_seen(TutorialRules.SEEN_ID)
	if not TutorialRules.should_offer(seen, group_game, force or force_next):
		return null
	force_next = false
	var run := TutorialRun.new()
	run.manager = dungeon
	run.was_seen = seen
	dungeon.add_child(run)
	run.move_spawn()
	run.hold_first_room(true)
	run.hold_controls_card(true)
	return run


## The practice run of a dungeon (null without one).
static func of(dungeon: Node) -> TutorialRun:
	if dungeon == null or not is_instance_valid(dungeon):
		return null
	var run := dungeon.get_node_or_null(NodePath(NODE_NAME)) as TutorialRun
	return run if run != null and not run.is_queued_for_deletion() else null


func _ready() -> void:
	name = NODE_NAME
	y_sort_enabled = true
	position = TutorialRules.ORIGIN
	area = TutorialArea.new()
	add_child(area)
	for dummy in area.dummies:
		dummy.broken.connect(_on_dummy_broken)
	area.shield_dummy.hit.connect(_on_shield_hit)
	area.shield_dummy.broken.connect(func(_dummy: TutorialDummy) -> void: complete(TutorialRules.Station.SPECIAL))
	area.shortcut_used.connect(func(_player: Player) -> void: skip())
	area.gate_passed.connect(func(_player: Player) -> void: finish(true))
	area.jump_door_entered.connect(_start_jump)
	_build_fade()


## PlayerSpawn of the dungeon to the hall's start (the WorldController spawns there).
func move_spawn() -> void:
	var spawn := manager.get_node_or_null(^"PlayerSpawn") as Node2D if manager != null else null
	if spawn != null and area != null:
		spawn.global_position = area.get_start_feet() - Player.FEET_OFFSET


## Room 1 must not see the player before the end: a body entering the tree touches the world origin
## (where room 1 lies) for one physics step, which would start room 1 behind the player's back. Its
## enter trigger stops watching until the player stands inside (place_in_first_room).
func hold_first_room(hold: bool) -> void:
	var room := _first_room()
	var trigger := room.get_node_or_null(^"EnterTrigger") as Area2D if room != null else null
	if trigger == null:
		return
	if hold:
		trigger.monitoring = false
	else:
		trigger.set_deferred(&"monitoring", true)


func _first_room() -> RoomController:
	if manager == null or not manager.has_method(&"get_room"):
		return null
	return manager.call(&"get_room", 1) as RoomController


## Flint's first-run key hints (FlintControls) wait while the practice run teaches the same keys
## (DungeonUI hook show_controls_hint switches the coach off); afterwards they may come. A coach that
## started first (the room catalog's threaded load runs deferred calls inside the dungeon's _ready,
## before begin()) just waits; an older UI's visible hint node is hidden meanwhile, so nothing but
## the strip and Flint lies over the hall.
func hold_controls_card(hold: bool) -> void:
	var ui: Object = manager.get(&"ui") if manager != null and &"ui" in manager else null
	if ui == null or not &"show_controls_hint" in ui:
		return
	ui.set(&"show_controls_hint", not hold)
	var card := ui.call(&"get_controls_hint") as CanvasItem if ui.has_method(&"get_controls_hint") else null
	if card != null:
		card.visible = not hold
	elif not hold and ui.has_method(&"start_controls_hint"):
		ui.call(&"start_controls_hint")


func _physics_process(_delta: float) -> void:
	if is_finished:
		return
	if player == null:
		var found := _find_player()
		if found != null:
			adopt(found)
		return
	if not is_instance_valid(player):
		return
	_update_zone(player.get_feet_position())


## The local player of this solo run from the dungeon (its session players), null before the spawn.
func _find_player() -> Player:
	if manager == null or not manager.has_method(&"get_session_players"):
		return null
	for candidate: Player in manager.call(&"get_session_players"):
		if candidate.is_local:
			return candidate
	return null


## Takes the player: light of the hall, the strip, Flint's welcome (a hint while the first door
## opens at once: nobody waits for Flint).
func adopt(target: Player) -> void:
	player = target
	if not player.fall.fall_started.is_connected(_on_fall_started):
		player.fall.fall_started.connect(_on_fall_started)
	player.fall.remember_safe_spot(player.get_feet_position())
	_light_hall()
	hud = TutorialHud.new()
	hud.name = "TutorialHud"
	hud.skip_pressed.connect(skip)
	add_child(hud)
	hud.show_zone(WELCOME)
	say(WELCOME_ID, [TutorialRules.welcome_key(bool(village_tour_seen.call()))], FlintGuideStep.Mood.HAPPY)
	begin_stations()


## After the welcome: the first door opens and station 1 waits behind it.
func begin_stations() -> void:
	if zone != WELCOME or is_finished:
		return
	zone = 0
	area.doors[0].open()
	if hud != null:
		hud.show_zone(zone)


## A station is done (once, in order): its flag flies, the way on opens, Flint is pleased.
func complete(station: TutorialRules.Station) -> void:
	if is_finished or done[station] or zone != int(station):
		return
	done[station] = true
	var flag := area.get_flag(station)
	if flag != null:
		flag.raise()
	match station:
		TutorialRules.Station.ATTACK:
			area.doors[1].open()
		TutorialRules.Station.DASH:
			area.jump_door.open()
			area.arm_jump_door(true)
		TutorialRules.Station.JUMP:
			area.jump_door.close()
		TutorialRules.Station.SPECIAL:
			area.doors[area.doors.size() - 1].open()
	var next := TutorialRules.next_station(station)
	zone = next if next >= 0 else FINISH
	if hud != null:
		hud.set_done(station)
		hud.show_zone(zone)
	say(StringName(String(TutorialRules.explanation_id(station)) + "_done"), [TutorialRules.DONE_KEYS[station]], FlintGuideStep.Mood.HAPPY)
	station_completed.emit(station)


## "Kenne ich schon": straight into room 1, no XP. Not while the side-view stretch runs.
func skip() -> void:
	if _jump != null and is_instance_valid(_jump) and _jump.is_running:
		return
	finish(false)


## Ends the practice run: seen for the account, XP on the first completion, then the fade into
## room 1 and away with the hall.
func finish(completed: bool) -> void:
	if is_finished:
		return
	is_finished = true
	was_completed = completed
	mark_seen.call(TutorialRules.SEEN_ID)
	var amount := TutorialRules.xp_for(completed, was_seen)
	if amount > 0 and TutorialRules.credit_xp(progress_source.call(), amount):
		credited_xp = amount
	if completed:
		Sfx.play_ui(self, &"countdown_go", -4.0)
	_leave()


func _leave() -> void:
	_lock(true)
	await _fade_to(1.0)
	if not is_inside_tree():
		return
	var guide := FlintGuide.of(player) if player != null and is_instance_valid(player) else null
	if guide != null:
		guide.cancel_all()
	place_in_first_room()
	if hud != null:
		hud.queue_free()
		hud = null
	area.queue_free()
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_lock(false)
	hold_controls_card(false)
	if was_completed:
		_say_done()
	await _fade_to(0.0)
	finished.emit(was_completed, credited_xp)
	queue_free()


## The player just inside room 1 (its enter trigger starts the room as if he had walked in).
func place_in_first_room() -> void:
	var room := _first_room()
	if room == null or player == null or not is_instance_valid(player):
		return
	player.global_position = room.get_player_start()
	player.velocity = Vector2.ZERO
	player.fall.remember_safe_spot(player.get_feet_position())
	var own := player.get_node_or_null("Camera2D") as Camera2D
	if own != null:
		own.reset_smoothing()
	hold_first_room(false)
	var spawn := manager.get_node_or_null(^"PlayerSpawn") as Node2D
	if spawn != null:
		spawn.global_position = room.get_player_start()


## In room 1: Flint says it is done (with the XP of the first completion) instead of a banner over
## the room that is just starting.
func _say_done() -> void:
	if player == null or not is_instance_valid(player):
		return
	var step := FlintGuideStep.say(&"FLINT_TUTORIAL_DONE", FlintGuideStep.Mood.PROUD)
	if credited_xp > 0:
		step = FlintGuideStep.say(&"FLINT_TUTORIAL_DONE_XP", FlintGuideStep.Mood.PROUD, [credited_xp])
	var hint := FlintExplanation.hint(DONE_ID, [step] as Array[FlintGuideStep])
	hint.once = false
	FlintGuide.explain(player, hint)


# --- Stations ---

## Announces stations as the player reaches their part of the hall, and checks the dash.
func _update_zone(feet: Vector2) -> void:
	if zone == WELCOME:
		return
	if not _announced.has(zone) and feet.x >= area.get_zone_start_x(zone):
		_announce(zone)
	if zone == TutorialRules.Station.DASH and TutorialRules.is_dash_done(feet.x, area.get_pit_east_x(), player.is_falling(), player.is_dashing()):
		complete(TutorialRules.Station.DASH)


func _announce(value: int) -> void:
	_announced[value] = true
	if value == FINISH:
		say(FINISH_ID, [&"FLINT_TUTORIAL_FINISH"], FlintGuideStep.Mood.PROUD)
		return
	var station: TutorialRules.Station = TutorialRules.STATIONS[value]
	var keys: Array[StringName] = []
	keys.assign(TutorialRules.EXPLANATIONS[station])
	say(TutorialRules.explanation_id(station), keys, FlintGuideStep.Mood.POINT)
	station_started.emit(station)


func _on_dummy_broken(_dummy: TutorialDummy) -> void:
	for dummy in area.dummies:
		if not dummy.is_broken:
			return
	complete(TutorialRules.Station.ATTACK)


func _on_shield_hit(_dummy: TutorialDummy, result: TutorialRules.Hit) -> void:
	if result != TutorialRules.Hit.BLOCKED:
		return
	blocked_hits += 1
	if blocked_hits == 1 or blocked_hits % BLOCK_TIP_EVERY == 0:
		say(BLOCKED_ID, [&"FLINT_TUTORIAL_SPECIAL_BLOCKED"], FlintGuideStep.Mood.WORRIED)


## Station 2: a fall into the abyss costs nothing here (PlayerFall lands at the last safe spot).
func _on_fall_started(fallen: Player) -> void:
	if is_finished or fallen != player:
		return
	fallen.fall.set_landing(fallen.get_last_safe_position(), 0.0)
	say(FALL_ID, [&"FLINT_TUTORIAL_DASH_FALL"], FlintGuideStep.Mood.WORRIED)


func _start_jump(entered: Player) -> void:
	if is_finished or zone != TutorialRules.Station.JUMP or entered != player:
		return
	if not _announced.has(zone):
		_announce(zone)
	var context: DungeonContext = manager.get(&"context") if &"context" in manager else null
	var group: Array[Player] = [player]
	_jump = TutorialJump.start(manager, group, context, _place_after_jump)
	_jump.hint_due.connect(func(key: StringName) -> void:
		say(StringName(String(key).to_lower()), [key], FlintGuideStep.Mood.POINT))
	# Nothing over the side view but Flint's corner: the strip waits in the hall.
	if hud != null:
		hud.visible = false
	_jump.left.connect(func(_jump_node: TutorialJump) -> void:
		if hud != null:
			hud.visible = true
		complete(TutorialRules.Station.JUMP))


func _place_after_jump(players: Array) -> void:
	for node: Variant in players:
		var placed := node as Player
		if placed != null and is_instance_valid(placed):
			placed.global_position = area.get_jump_exit_feet() - Player.FEET_OFFSET
			placed.velocity = Vector2.ZERO


## The side-view stretch running now (tools), null otherwise.
func get_jump() -> TutorialJump:
	return _jump if _jump != null and is_instance_valid(_jump) else null


# --- Flint ---

## Flint says these sentences as a hint (corner, no stop; repeats allowed, the run is the seen flag).
func say(id: StringName, keys: Array[StringName], mood: FlintGuideStep.Mood) -> bool:
	if player == null or not is_instance_valid(player) or keys.is_empty():
		return false
	var steps: Array[FlintGuideStep] = []
	for key in keys:
		steps.append(FlintGuideStep.say(key, mood))
	var hint := FlintExplanation.hint(id, steps)
	hint.once = false
	return FlintGuide.explain(player, hint)



# --- Light and fades ---

func _light_hall() -> void:
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay == null:
		return
	var biome := load(CRYPT_BIOME_PATH) as BiomeData if ResourceLoader.exists(CRYPT_BIOME_PATH) else null
	if biome != null:
		overlay.set_biome(biome, true)
	overlay.set_vision(TutorialRules.DARKNESS, TutorialRules.VISION_RADIUS, true)
	overlay.set_lighting(LightingProfile.create(TutorialRules.AMBIENT), true)


func _build_fade() -> void:
	_fade = CanvasLayer.new()
	_fade.name = "Fade"
	_fade.layer = FADE_LAYER
	add_child(_fade)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.modulate.a = 0.0
	_fade.add_child(_black)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_black, ^"modulate:a", alpha, TutorialRules.FADE_TIME)
	await tween.finished


func _lock(locked: bool) -> void:
	if player != null and is_instance_valid(player):
		player.set_input_locked(INPUT_LOCK, locked)


func _exit_tree() -> void:
	# Freed with the dungeon mid-way: never leave the player locked.
	_lock(false)
