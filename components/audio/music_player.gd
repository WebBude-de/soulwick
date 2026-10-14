class_name MusicPlayer
extends Node
## Looping background music with crossfades plus a quiet ambient bed per biome (D-068, D-092,
## D-097). Lives in main.tscn and game.tscn. In the game it follows the phase (village/dungeon),
## the biome of each room, champion and boss rooms and boss phase two; MusicRules picks the
## files. It only reacts to signals: rooms and bosses never play music themselves.
##
## Transitions (all times TESTWERTE below):
## - New biome (also village -> dungeon): the ambient bed crosses first, old music fades out,
##   then the biome's transition stinger plays and the loop fades in from bar one where the
##   stinger's last bar ends. Never a crossfade between two different running loops.
## - Boss defeated: boss music fades, a victory stinger plays, then only the ambient bed until
##   the next room (normally the next biome) is entered.
## - Champion room <-> biome track: same piece and position, linear gains (level sum stays 1).
## - Run over: music fades under the summary, the ambient bed stays; in the village the ambient
##   comes first, the village theme fades in a little later.
## - Scene change (main menu <-> game): the outgoing player hands its track and position to the
##   next one, which continues instead of cutting (static handoff, no autoload).
##
## Hooks (call directly or with get_tree().call_group(MusicPlayer.GROUP, &"...")):
## hold_boss_music()/release_boss_music() around a boss intro, on_boss_phase_changed(phase),
## on_run_ended(), begin_interlude(next_biome) for a room between two biomes (campfire, A6). With follow_game they are also picked up automatically: Enemy.phase_changed
## of a boss, a BossIntro node entering the tree (held until its "ending"/"finished" signal) and
## EventBus.run_ended.

const GROUP := &"music_player"
const FADE_TIME := 1.2
## Biome track <-> champion version, same position in the bar (TESTWERT).
const INTENSE_FADE_TIME := 1.5
## Boss phase two cuts in with the roar (TESTWERT).
const PHASE_TWO_FADE_TIME := 0.6
const AMBIENT_FADE_TIME := 3.0
## Ambient bed relative to the music; the files are already ~15 dB quieter (TESTWERT).
const AMBIENT_VOLUME_DB := 0.0
## Stingers relative to the music; the files are loudness-matched (TESTWERT).
const STINGER_VOLUME_DB := 0.0

## Entering a biome (TESTWERTE): ambient crossfade, old music out, then the stinger, then the
## loop fades in. Without a stinger file the loop starts after ENTRY_LOOP_DELAY.
const ENTRY_AMBIENT_FADE_TIME := 4.0
const ENTRY_MUSIC_OUT_TIME := 1.8
const ENTRY_STINGER_DELAY := 1.8
const ENTRY_LOOP_DELAY := 2.5
const ENTRY_LOOP_FADE_TIME := 3.5
## After a stinger the loop's first bar is already audible at this gain (-6 dB) and swells up.
const ENTRY_LOOP_START_GAIN := 0.5

## Boss room (TESTWERTE): the biome track fades while the intro speaks, the boss track comes in
## quickly with the roar.
const INTRO_FADE_OUT_TIME := 2.0
const BOSS_START_FADE_TIME := 0.5
## A held boss track waits for the intro's "ending"/"finished" signals. Only if none comes it
## starts after this time (pausable, the intro freezes with menus too). While the followed intro
## is still running at that point it checks again every BOSS_HOLD_RECHECK_TIME, at most until
## BOSS_HOLD_ABSOLUTE_MAX (TESTWERTE), so a long first intro is never overrun.
const BOSS_HOLD_MAX_TIME := 30.0
const BOSS_HOLD_RECHECK_TIME := 5.0
const BOSS_HOLD_ABSOLUTE_MAX := 120.0

## Boss defeated (TESTWERTE): boss music out, victory stinger after the room-clear jingle.
const VICTORY_FADE_OUT_TIME := 1.5
const VICTORY_STINGER_DELAY := 1.0

## Run over and back in the village (TESTWERTE).
const RUN_END_FADE_TIME := 3.0
const VILLAGE_LOOP_DELAY := 1.5
const VILLAGE_LOOP_FADE_TIME := 4.0

## Scene change handoff (TESTWERTE): accepted for this long (loading the game scene takes about
## half a second), resumed where it stopped with a tiny fade (a short pause, no skipped notes);
## a different start track then crossfades in over MENU_FADE_TIME.
const HANDOFF_MAX_AGE := 3.0
const HANDOFF_RESUME_FADE := 0.08
const MENU_FADE_TIME := 2.5

const PAUSE_DUCK_DB := -9.0
## Global class name of the boss intro node that holds the boss track (see _on_node_added).
const BOSS_INTRO_CLASS := &"BossIntro"

## Track and position of the last scene-level player that left the tree (see _exit_tree).
static var _handoff := {}

## Track played on start ("" = none).
@export var start_track := ""
## React to game phase, rooms, biomes and boss phases (game.tscn only).
@export var follow_game := false

var _music: MusicChannel
var _ambient: MusicChannel
var _stinger: MusicChannel
var _room_index := 0
var _room_type := RoomSequence.RoomType.COMBAT
var _biome: BiomeData
var _boss_phase := 1
## The current room was completed (champion back to normal, boss beaten).
var _room_cleared := false
## Boss room entered, boss track not started yet (deferred one frame, or held by an intro).
var _boss_pending := false
var _boss_hold := false
var _hold_serial := 0
var _hold_waited := 0.0
## Boss intro node that holds the boss track (null for a manual hold).
var _hold_source: Node = null
## Interlude: boss beaten (or begin_interlude), only the ambient bed (and a victory stinger)
## plays until the next room starts with a full biome entry.
var _calm := false
## A biome or village entry is running; its last step starts the right loop.
var _entry_pending := false
## Next step of a running transition (entry or victory) and the serial of its timer.
var _pending_step := Callable()
var _sequence_serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	_music = MusicChannel.new(&"Music")
	add_child(_music)
	_ambient = MusicChannel.new(&"Music", AMBIENT_VOLUME_DB)
	add_child(_ambient)
	_stinger = MusicChannel.new(&"Music", STINGER_VOLUME_DB)
	add_child(_stinger)
	var resumed := _resume_handoff() if _is_scene_player() else ""
	if follow_game:
		GameManager.phase_changed.connect(_on_phase_changed)
		GameManager.pause_changed.connect(_on_pause_changed)
		EventBus.room_entered.connect(_on_room_entered)
		EventBus.room_completed.connect(_on_room_completed)
		EventBus.run_ended.connect(_on_run_ended)
		get_tree().node_added.connect(_on_node_added)
	if start_track.is_empty():
		return
	if resumed.is_empty() or resumed == start_track:
		_play_start_track()
	else:
		# Let the handed-over track come back to full volume first, then cross over.
		get_tree().create_timer(HANDOFF_RESUME_FADE, true, false, true).timeout.connect(_play_start_track)


## Start track of a scene player (main menu); a handed-over ambient bed fades away.
func _play_start_track() -> void:
	play_track(start_track, MENU_FADE_TIME if _music.is_playing() else FADE_TIME)
	if not _ambient.get_track().is_empty():
		_ambient.stop(MENU_FADE_TIME)


func _exit_tree() -> void:
	# Children leave the tree first, so the players are already stopped here: the channels
	# report their position from the clock.
	if _is_scene_player() and _music != null:
		_handoff = {
			"music": _music.get_track(),
			"music_position": _music.get_timeline_position(),
			"ambient": _ambient.get_track(),
			"ambient_position": _ambient.get_timeline_position(),
			"usec": Time.get_ticks_usec(),
		}


## Crossfades to track. Equal power between different pieces, linear (keeping the position)
## between a biome track and its champion version. start_gain: see MusicChannel.play.
func play_track(track: String, fade := FADE_TIME, start_gain := 0.0) -> void:
	if track.is_empty() or track == _music.get_track():
		return
	var stream := MusicRules.load_stream(track, MusicRules.MUSIC_DIR)
	if stream == null:
		return
	var current := _music.get_track()
	var position := 0.0
	if MusicRules.shares_timeline(current, track) and stream.get_length() > 0.0:
		position = fmod(_music.get_playback_position(), stream.get_length())
	_music.play(track, stream, fade, position, MusicRules.fade_curve(current, track), start_gain)


func stop_music(fade := FADE_TIME) -> void:
	_music.stop(fade)


## Crossfades the ambient bed ("" = fade out).
func play_ambient(track: String, fade := AMBIENT_FADE_TIME) -> void:
	if track == _ambient.get_track():
		return
	var stream := MusicRules.load_stream(track, MusicRules.AMBIENT_DIR)
	if stream == null:
		_ambient.stop(fade)
		return
	_ambient.play(track, stream, fade)


## Plays a one-shot stinger on top (returns its length, 0 if there is no such file).
func play_stinger(track: String, fade := 0.02) -> float:
	var stream := MusicRules.load_stream(track, MusicRules.MUSIC_DIR, false)
	if stream == null:
		return 0.0
	_stinger.play(track, stream, fade)
	return stream.get_length()


func get_current_track() -> String:
	return _music.get_track()


func get_current_ambient() -> String:
	return _ambient.get_track()


## Stinger that is playing right now ("" when none).
func get_current_stinger() -> String:
	return _stinger.get_track()


## Players of the music channel that are still audible (2 during a crossfade).
func get_audible_music_count() -> int:
	return _music.get_audible_count()


## True while an entry or a victory sequence still has a step to come.
func is_transition_pending() -> bool:
	return _pending_step.is_valid()


## Runs the remaining steps of a transition right now (tests, debugging).
func complete_transition() -> void:
	while _pending_step.is_valid():
		_run_pending_step()


## Music and ambient of a dungeon room (EventBus.room_entered). A boss track starts one frame
## later, so a boss intro started in the same frame can still hold it.
func enter_room(room_index: int) -> void:
	var previous_biome := _biome
	_room_index = room_index
	_room_type = RoomSequence.get_room_type(room_index)
	_biome = MusicRules.biome_for_room(room_index)
	_boss_phase = 1
	_room_cleared = false
	if _room_type == RoomSequence.RoomType.BOSS:
		_cancel_sequence()
		_calm = false
		_stinger.stop(FADE_TIME)
		play_ambient(MusicRules.ambient_track(_biome))
		_boss_pending = true
		_start_boss_music.call_deferred()
		return
	_boss_pending = false
	_boss_hold = false
	var biome_changed := previous_biome != null and previous_biome != _biome
	if biome_changed or _calm:
		_enter_biome()
		return
	play_ambient(MusicRules.ambient_track(_biome))
	if _entry_pending:
		# The running entry starts the loop of this room when its stinger ends.
		return
	var track := _room_track()
	play_track(track, INTENSE_FADE_TIME if MusicRules.shares_timeline(_music.get_track(), track) else FADE_TIME)


## A cleared champion room falls back to the biome track, a beaten boss leaves only a victory
## stinger and the ambient bed.
func complete_room(room_index: int) -> void:
	if room_index != _room_index or _room_cleared:
		return
	_room_cleared = true
	match _room_type:
		RoomSequence.RoomType.BOSS:
			_boss_pending = false
			_boss_hold = false
			_hold_serial += 1
			_hold_source = null
			_win_boss()
		RoomSequence.RoomType.MINIBOSS:
			if not _entry_pending:
				play_track(_room_track(), INTENSE_FADE_TIME)


## Interlude hook ("a transition is running"), e.g. the campfire between two biomes (A6, D-103):
## the music fades out (a victory stinger may ring on), the ambient bed already crosses to the
## next biome's (null = keep the current one) and the next room starts with a full biome entry
## (stinger, then the loop). Works on state, not on room numbers; call it any time after a boss.
func begin_interlude(next_biome: BiomeData = null) -> void:
	if _entry_pending:
		_cancel_sequence()
	_calm = true
	_boss_pending = false
	_boss_hold = false
	_hold_serial += 1
	_hold_source = null
	_music.stop(ENTRY_MUSIC_OUT_TIME)
	if next_biome != null:
		play_ambient(MusicRules.ambient_track(next_biome), ENTRY_AMBIENT_FADE_TIME)


## True between a boss victory (or begin_interlude) and the entry of the next room.
func is_in_interlude() -> bool:
	return _calm


## Run over (EventBus.run_ended): the music fades under the summary, the ambient bed stays.
func on_run_ended() -> void:
	_cancel_sequence()
	_reset_room_state()
	_calm = false
	_music.stop(RUN_END_FADE_TIME)
	_stinger.stop(RUN_END_FADE_TIME)


## Boss intro hook: keep the boss track back (music fades out, the ambient bed stays) until
## release_boss_music(). May be called before or after entering the room, and again to renew
## the hold (the followed intro stays the source). The safety release after max_time is
## pausable and waits longer while a followed intro is still running.
func hold_boss_music(max_time := BOSS_HOLD_MAX_TIME) -> void:
	_boss_hold = true
	_hold_serial += 1
	_hold_waited = 0.0
	if _room_type == RoomSequence.RoomType.BOSS and not _room_cleared:
		_boss_pending = true
		stop_music(INTRO_FADE_OUT_TIME)
	_arm_hold_timer(_hold_serial, max_time)


## Boss intro hook: the intro is over, the boss track (or phase two) starts now.
func release_boss_music() -> void:
	_boss_hold = false
	_hold_serial += 1
	_hold_source = null
	_start_boss_music()


## Boss phase hook; also called automatically for every Enemy.phase_changed of a boss.
func on_boss_phase_changed(phase: int) -> void:
	if _room_type != RoomSequence.RoomType.BOSS or _room_cleared or phase <= _boss_phase:
		return
	_boss_phase = phase
	if not _boss_pending:
		play_track(MusicRules.boss_track(_biome, _boss_phase), PHASE_TWO_FADE_TIME)


func _start_boss_music() -> void:
	if not _boss_pending or _room_type != RoomSequence.RoomType.BOSS or _room_cleared:
		return
	if _boss_hold:
		stop_music(INTRO_FADE_OUT_TIME)
		return
	_boss_pending = false
	# Without an intro the biome track still plays: crossfade. After an intro: in with the roar.
	play_track(MusicRules.boss_track(_biome, _boss_phase), FADE_TIME if _music.is_playing() else BOSS_START_FADE_TIME)


## Loop of the current room: the champion version until the champion room is cleared.
func _room_track() -> String:
	var room_type := _room_type
	if _room_cleared and room_type == RoomSequence.RoomType.MINIBOSS:
		room_type = RoomSequence.RoomType.COMBAT
	return MusicRules.dungeon_track(_biome, room_type)


# --- Transitions ---

## Ambient first, old music out, then the biome's transition stinger and the loop on its bar.
func _enter_biome() -> void:
	_cancel_sequence()
	_calm = false
	_entry_pending = true
	play_ambient(MusicRules.ambient_track(_biome), ENTRY_AMBIENT_FADE_TIME)
	_music.stop(ENTRY_MUSIC_OUT_TIME)
	_stinger.stop(ENTRY_MUSIC_OUT_TIME)
	var transition := MusicRules.transition_track(_biome)
	if transition.is_empty():
		_schedule(ENTRY_LOOP_DELAY, _start_entry_loop.bind(0.0))
	else:
		_schedule(ENTRY_STINGER_DELAY, _play_entry_stinger.bind(transition))


func _play_entry_stinger(track: String) -> void:
	var length := play_stinger(track)
	if length <= 0.0:
		_start_entry_loop(0.0)
		return
	# Starts on the bar line after the stinger's last bar; its reverb tail overlaps the fade-in.
	_schedule(MusicRules.stinger_entry_time(length), _start_entry_loop.bind(ENTRY_LOOP_START_GAIN))


func _start_entry_loop(start_gain: float) -> void:
	_entry_pending = false
	if _room_type != RoomSequence.RoomType.BOSS:
		play_track(_room_track(), ENTRY_LOOP_FADE_TIME, start_gain)


## Village: ambient first, the village theme fades in a little later (unless it already plays,
## e.g. handed over from the main menu).
func _enter_village() -> void:
	_cancel_sequence()
	play_ambient(MusicRules.village_ambient(), ENTRY_AMBIENT_FADE_TIME)
	_stinger.stop(ENTRY_MUSIC_OUT_TIME)
	if _music.get_track() == MusicRules.VILLAGE_TRACK:
		return
	_music.stop(ENTRY_MUSIC_OUT_TIME)
	_entry_pending = true
	_schedule(VILLAGE_LOOP_DELAY, _start_village_loop)


func _start_village_loop() -> void:
	_entry_pending = false
	play_track(MusicRules.VILLAGE_TRACK, VILLAGE_LOOP_FADE_TIME)


## Boss beaten: boss music out, victory stinger after the room-clear jingle, then calm.
func _win_boss() -> void:
	_cancel_sequence()
	_calm = true
	_music.stop(VICTORY_FADE_OUT_TIME)
	var victory := MusicRules.victory_track(_biome)
	if not victory.is_empty():
		_schedule(VICTORY_STINGER_DELAY, _play_victory_stinger.bind(victory))


func _play_victory_stinger(track: String) -> void:
	play_stinger(track)


func _schedule(delay: float, step: Callable) -> void:
	_sequence_serial += 1
	_pending_step = step
	if delay <= 0.0 or not is_inside_tree():
		if delay <= 0.0:
			_run_pending_step()
		return
	# Runs during pause too: the audio keeps playing (ducked) while a menu is open.
	get_tree().create_timer(delay, true, false, true).timeout.connect(_on_sequence_timer.bind(_sequence_serial))


func _run_pending_step() -> void:
	var step := _pending_step
	_pending_step = Callable()
	_sequence_serial += 1
	if step.is_valid():
		step.call()


func _cancel_sequence() -> void:
	_sequence_serial += 1
	_pending_step = Callable()
	_entry_pending = false


func _on_sequence_timer(serial: int) -> void:
	if serial == _sequence_serial:
		_run_pending_step()


func _reset_room_state() -> void:
	_room_index = 0
	_room_type = RoomSequence.RoomType.COMBAT
	_boss_phase = 1
	_room_cleared = false
	_boss_pending = false
	_boss_hold = false
	_hold_serial += 1
	_hold_source = null


# --- Boss hold safety ---

func _arm_hold_timer(serial: int, time: float) -> void:
	if not is_inside_tree():
		return
	# Pausable (process_always = false): an intro frozen by a menu does not run out.
	get_tree().create_timer(time, false, false, true).timeout.connect(_on_hold_timeout.bind(serial, time))


func _on_hold_timeout(serial: int, waited: float) -> void:
	if serial != _hold_serial or not _boss_hold:
		return
	_hold_waited += waited
	if _hold_source_running() and _hold_waited < BOSS_HOLD_ABSOLUTE_MAX:
		_arm_hold_timer(serial, BOSS_HOLD_RECHECK_TIME)
		return
	release_boss_music()


## The followed intro still exists and has not finished (a long first intro keeps the hold).
func _hold_source_running() -> bool:
	if _hold_source == null or not is_instance_valid(_hold_source) or not _hold_source.is_inside_tree():
		return false
	return not (_hold_source.has_method(&"is_finished") and _hold_source.call(&"is_finished"))


# --- Scene handoff ---

## Players placed in a scene (main menu, game) hand their music over; test instances do not.
func _is_scene_player() -> bool:
	return follow_game or not start_track.is_empty()


## Continues the music (and ambient) of the scene that just closed, so a scene change never
## cuts. Returns the resumed music track ("" if there was nothing recent to take over).
func _resume_handoff() -> String:
	var handoff := _handoff
	_handoff = {}
	if handoff.is_empty():
		return ""
	var elapsed := float(Time.get_ticks_usec() - int(handoff.get("usec", 0))) / 1000000.0
	if elapsed < 0.0 or elapsed > HANDOFF_MAX_AGE:
		return ""
	_resume_channel(_ambient, String(handoff.get("ambient", "")), float(handoff.get("ambient_position", 0.0)), MusicRules.AMBIENT_DIR)
	var track := String(handoff.get("music", ""))
	return track if _resume_channel(_music, track, float(handoff.get("music_position", 0.0)), MusicRules.MUSIC_DIR) else ""


func _resume_channel(channel: MusicChannel, track: String, position: float, dir: String) -> bool:
	var stream := MusicRules.load_stream(track, dir)
	if stream == null or stream.get_length() <= 0.0:
		return false
	channel.play(track, stream, HANDOFF_RESUME_FADE, fmod(position, stream.get_length()))
	return true


static func clear_handoff() -> void:
	_handoff = {}


# --- Signals ---

func _on_phase_changed(phase: GameManager.Phase) -> void:
	_cancel_sequence()
	_reset_room_state()
	_calm = false
	match phase:
		GameManager.Phase.VILLAGE:
			_biome = null
			_enter_village()
		GameManager.Phase.DUNGEON:
			# The first room_entered comes later; the entry of the run's first biome starts now.
			_biome = MusicRules.biome_for_room(RunManager.get_current_room())
			_room_type = RoomSequence.get_room_type(maxi(1, RunManager.get_current_room()))
			_enter_biome()


func _on_room_entered(room_index: int) -> void:
	enter_room(room_index)


func _on_room_completed(room_index: int) -> void:
	complete_room(room_index)


func _on_run_ended(_reason: int, _remaining_run_gold: int, _payout: int) -> void:
	on_run_ended()


func _on_node_added(node: Node) -> void:
	var enemy := node as Enemy
	if enemy != null:
		if not enemy.phase_changed.is_connected(_on_enemy_phase_changed):
			enemy.phase_changed.connect(_on_enemy_phase_changed)
		return
	if _is_boss_intro(node):
		_follow_boss_intro(node)


## The boss intro (BossIntro, ui/boss_intro) holds the boss track; it starts with the roar
## ("ending") or at the latest when the intro is "finished". Matched by name and signals only,
## so the music keeps working if the intro changes.
static func _is_boss_intro(node: Node) -> bool:
	var script := node.get_script() as Script
	return script != null and script.get_global_name() == BOSS_INTRO_CLASS and node.has_signal(&"finished")


func _follow_boss_intro(intro: Node) -> void:
	hold_boss_music()
	_hold_source = intro
	if intro.has_signal(&"ending"):
		intro.connect(&"ending", _on_intro_ending.bind(intro), CONNECT_ONE_SHOT)
	intro.connect(&"finished", _on_intro_finished.bind(intro), CONNECT_ONE_SHOT)


func _on_intro_ending(_skipped: bool, intro: Node) -> void:
	_on_intro_finished(intro)


## Only the intro that holds the music may release it (an older one finishing late does not).
func _on_intro_finished(intro: Node) -> void:
	if _boss_hold and (_hold_source == null or _hold_source == intro):
		release_boss_music()


func _on_enemy_phase_changed(enemy: Enemy, phase: int) -> void:
	if is_instance_valid(enemy) and enemy.data != null and enemy.data.is_boss:
		on_boss_phase_changed(phase)


func _on_pause_changed(is_paused: bool) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), SaveManager.get_bus_volume_db(&"Music") + (PAUSE_DUCK_DB if is_paused else 0.0))
