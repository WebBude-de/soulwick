class_name MusicChannel
extends Node
## AudioStreamPlayers on one bus that crossfade (D-068). MusicPlayer owns one channel for the
## music, one for the ambient bed and one for one-shot stingers. Fades ignore pause and
## Engine.time_scale (HitStop).
##
## Every player fades from its current gain, so an interrupted crossfade never jumps. Three
## players: a new track always gets a silent one, the two older ones fade out from wherever
## they are (no cut when tracks change faster than a fade lasts). A track that is still fading
## out is faded back in where it is instead of being started a second time (champion room
## cleared right after entering: no two copies of the same piece slightly out of step).
##
## Debounce: the same wish again never restarts anything (play() of the current track is a no-op,
## of a fading track resumes it in place). Only a fourth piece while all three players still
## play would have to cut one and start from the top; a burst of such wishes (pieces changing
## every frame) is held back for MIN_RESTART_INTERVAL and only the newest is played, so the
## channel never restarts a piece in quick succession (no "stuck record"). A wish back to the
## current track drops the held one.
##
## Browser loop fix (feedback 16. and 17.10.2026, web build: "the music loops again"): in the web
## export the players run as Web Audio samples (default_playback_type.web = Sample), and Godot
## 4.7.2 (godot.js SampleNode._restart) restarts a looping sample at the position it was started
## from, not at the loop start; its reported position also lags about a second. A piece started
## mid-file (champion version on the same bar, scene handoff) would repeat only its tail forever,
## a short tail very fast. Such a player is started again at the loop start just before its first
## pass ends (gain and fade stay); from then on the browser loops the whole piece. Positions of
## sample players come from the channel's clock. Desktop (mixer playback) is unchanged.

const SILENT_DB := -60.0
const PLAYER_COUNT := 3
## Shortest real time between two fresh starts that cut a playing player (TESTWERT).
const MIN_RESTART_INTERVAL := 0.4
## Browser loop fix: a sample player started off its loop start restarts there this long before
## its first pass ends, at least 1.5 frames (checked once a frame: too late and the browser jumps
## back first), at most LOOP_ANCHOR_MAX_LEAD (TESTWERTE).
const LOOP_ANCHOR_LEAD := 0.03
const LOOP_ANCHOR_MAX_LEAD := 0.1

## Volume of the audible player in dB (gain 1).
var level_db := 0.0
## Plays as a browser sample: -1 asks every player after its start (web export), 0 never, 1 always
## (tests).
var sample_mode_override := -1

var _players: Array[AudioStreamPlayer] = []
## Linear gain 0..1 of every player.
var _gains: Array[float] = []
## Track name loaded in every player.
var _player_tracks: Array[String] = []
var _tweens: Array[Tween] = []
var _active := -1
var _track := ""
## Per player: plays as a browser sample, real time (usec) of its start and the position it
## started from (its clock, see get_timeline_position), and the real time at which its first pass
## ends and it has to restart at the loop start (-1: none, see update_loop_anchors).
var _sampled: Array[bool] = []
var _clock_usec: Array[int] = []
var _clock_from: Array[float] = []
var _anchor_usec: Array[int] = []
## Players restarted at the loop start by the browser loop fix (diagnostics).
var _anchor_count := 0
var _last_tick_usec := 0
## Players started from scratch (diagnostics and tests: the same wish never adds one).
var _start_count := 0
## Real time (usec) of the last fresh start that had to cut an audible player.
var _last_steal_usec := -1
## Wish held back by the restart guard (empty when none) and the serial of its timer.
var _queued := {}
var _queue_serial := 0


func _init(bus: StringName = &"Music", level := 0.0) -> void:
	level_db = level
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		player.volume_db = SILENT_DB
		player.finished.connect(_on_player_finished.bind(i))
		add_child(player)
		_players.append(player)
		_gains.append(0.0)
		_player_tracks.append("")
		_tweens.append(null)
		_sampled.append(false)
		_clock_usec.append(0)
		_clock_from.append(0.0)
		_anchor_usec.append(-1)


func _ready() -> void:
	# _process only runs while a browser loop fix waits.
	set_process(has_loop_anchor())


func _process(_delta: float) -> void:
	# Real frame time: delta follows Engine.time_scale (HitStop).
	var now := Time.get_ticks_usec()
	var frame := float(now - _last_tick_usec) / 1000000.0 if _last_tick_usec > 0 else 0.0
	_last_tick_usec = now
	update_loop_anchors(now, frame)


func get_track() -> String:
	return _track


func is_playing() -> bool:
	return not _track.is_empty() and _active >= 0 and _players[_active].playing


## Seconds into the audible track (0 if silent). Browser samples report from the clock (the
## engine's value lags about a second there).
func get_playback_position() -> float:
	if _active < 0 or not _players[_active].playing:
		return 0.0
	if _sampled[_active]:
		return _clock_position(_active)
	return _players[_active].get_playback_position()


## Position of the current track computed from the clock (also valid after the players left the
## tree, for the scene handoff); the music never pauses, so it matches the playback.
func get_timeline_position() -> float:
	if _track.is_empty() or _active < 0:
		return 0.0
	return _clock_position(_active)


## The current track plays as a browser sample (web export).
func is_sample_playback() -> bool:
	return _active >= 0 and _sampled[_active]


## How often the browser loop fix restarted a player at its loop start.
func get_loop_anchor_count() -> int:
	return _anchor_count


## A player waits for the browser loop fix.
func has_loop_anchor() -> bool:
	for usec in _anchor_usec:
		if usec >= 0:
			return true
	return false


## Browser loop fix (see the class notes): every sample player whose first pass ends within the
## lead (frame_time * 1.5, clamped to LOOP_ANCHOR_LEAD..LOOP_ANCHOR_MAX_LEAD) of now_usec is
## started again at its loop start, keeping gain and fade. Returns how many were restarted.
## Called every frame while one waits; tests call it with a time in the future.
func update_loop_anchors(now_usec: int, frame_time := 0.0) -> int:
	var lead_usec := int(clampf(frame_time * 1.5, LOOP_ANCHOR_LEAD, LOOP_ANCHOR_MAX_LEAD) * 1000000.0)
	var restarted := 0
	for i in PLAYER_COUNT:
		if _anchor_usec[i] < 0:
			continue
		var player := _players[i]
		if not player.playing or player.stream == null or not player.is_inside_tree():
			_anchor_usec[i] = -1
			continue
		if now_usec + lead_usec < _anchor_usec[i]:
			continue
		_anchor_usec[i] = -1
		var loop_start := loop_start_of(player.stream)
		player.play(loop_start)
		_clock_usec[i] = Time.get_ticks_usec()
		_clock_from[i] = loop_start
		_anchor_count += 1
		restarted += 1
	if not has_loop_anchor():
		set_process(false)
		_last_tick_usec = 0
	return restarted


## The stream repeats (WAV loop mode, Ogg/MP3 loop flag).
static func loops(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	return false


## Seconds where the stream's loop starts (0 for the generated music, MusicRules.make_loop).
static func loop_start_of(stream: AudioStream) -> float:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		return float(wav.loop_begin) / wav.mix_rate if wav.mix_rate > 0 else 0.0
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop_offset
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop_offset
	return 0.0


## position on a looping timeline of length seconds that jumps back to loop_start at the end.
static func wrap_position(position: float, length: float, loop_start := 0.0) -> float:
	if length <= 0.0 or position < length:
		return maxf(position, 0.0)
	var start := clampf(loop_start, 0.0, length)
	if length - start <= 0.0:
		return start
	return start + fmod(position - start, length - start)


## Linear gain of the current track (0 when nothing plays).
func get_gain() -> float:
	return _gains[_active] if _active >= 0 else 0.0


## How many times a player was started from the top (a resumed or repeated wish does not count).
func get_start_count() -> int:
	return _start_count


## Track held back by the restart guard ("" when none).
func get_queued_track() -> String:
	return String(_queued.get("track", ""))


## Drops a held-back wish (the caller wants the current track after all).
func drop_queued() -> void:
	_queued = {}
	_queue_serial += 1


## Number of players that are still audible (current track plus tracks fading out).
func get_audible_count() -> int:
	var count := 0
	for i in PLAYER_COUNT:
		if _players[i].playing and _gains[i] > MusicRules.SILENT_GAIN:
			count += 1
	return count


## Fades stream in and everything else out. from_position keeps the beat when both tracks share
## a timeline (use FadeCurve.LINEAR then); fade = 0 starts at full volume; start_gain > 0 makes
## the first beat audible (a loop entering after a stinger).
func play(track: String, stream: AudioStream, fade: float, from_position := 0.0,
		curve := MusicRules.FadeCurve.EQUAL_POWER, start_gain := 0.0) -> void:
	if stream == null:
		return
	if track == _track:
		# The same wish again (or back to the current one): nothing restarts, a held-back
		# different wish is dropped.
		drop_queued()
		return
	var index := _fading_player(track, stream)
	if index >= 0:
		# Resumed in place: its own clock (and a pending browser loop fix) stays.
		drop_queued()
	else:
		index = _free_player()
		# Any player that still plays counts: a piece started this frame is still at gain 0 but
		# would be heard if it were not cut again and again.
		var steals := _players[index].playing
		if steals and _hold_back(track, stream, fade, from_position, curve, start_gain):
			return
		drop_queued()
		if steals:
			_last_steal_usec = Time.get_ticks_usec()
		var player := _players[index]
		_kill_tween(index)
		player.stop()
		player.stream = stream
		_player_tracks[index] = track
		_set_gain(index, clampf(start_gain, 0.0, 1.0))
		_start(index, from_position)
		_start_count += 1
	for i in PLAYER_COUNT:
		if i != index and _players[i].playing:
			_fade(i, 0.0, fade, curve)
	_active = index
	_track = track
	_fade(index, 1.0, fade, curve)


## Fades everything out (the channel stays usable).
func stop(fade: float, curve := MusicRules.FadeCurve.EQUAL_POWER) -> void:
	drop_queued()
	_track = ""
	_active = -1
	for i in PLAYER_COUNT:
		if _players[i].playing:
			_fade(i, 0.0, fade, curve)


func _exit_tree() -> void:
	drop_queued()
	for i in PLAYER_COUNT:
		_kill_tween(i)
		_players[i].stop()
		_anchor_usec[i] = -1


## Starts player index at from (inside the piece), starts its clock and, for a browser sample that
## does not start on its loop start, arms the loop fix at the end of the first pass.
func _start(index: int, from: float) -> void:
	var player := _players[index]
	var length := player.stream.get_length() if player.stream != null else 0.0
	if length > 0.0 and loops(player.stream):
		# Never at or past the end (a browser sample would end at once and restart there).
		from = wrap_position(from, length, loop_start_of(player.stream))
	else:
		from = clampf(from, 0.0, length) if length > 0.0 else maxf(from, 0.0)
	player.play(from)
	_clock_usec[index] = Time.get_ticks_usec()
	_clock_from[index] = from
	_sampled[index] = _plays_as_sample(player)
	_anchor_usec[index] = -1
	if not _sampled[index] or length <= 0.0 or not loops(player.stream):
		return
	var loop_start := loop_start_of(player.stream)
	if is_equal_approx(from, loop_start):
		return
	if length - from <= LOOP_ANCHOR_MAX_LEAD:
		# Too close to the end for the fix to come in time: start on the loop start right away.
		player.play(loop_start)
		_clock_from[index] = loop_start
		_anchor_count += 1
		return
	_anchor_usec[index] = _clock_usec[index] + int((length - from) * 1000000.0)
	set_process(true)


## The player runs as a Web Audio sample (web export) instead of through the mixer.
func _plays_as_sample(player: AudioStreamPlayer) -> bool:
	if sample_mode_override >= 0:
		return sample_mode_override == 1
	if not player.has_stream_playback():
		return false
	var playback := player.get_stream_playback()
	return playback != null and playback.get_sample_playback() != null


## Position of player index from its clock (wraps at the end like the loop).
func _clock_position(index: int) -> float:
	var stream := _players[index].stream
	if stream == null:
		return 0.0
	var elapsed := float(Time.get_ticks_usec() - _clock_usec[index]) / 1000000.0
	return wrap_position(_clock_from[index] + elapsed, stream.get_length(), loop_start_of(stream))


## Restart guard: a fresh start that would cut an audible player shortly after the last such cut
## waits (newest wish wins). Returns true when the wish was held back.
func _hold_back(track: String, stream: AudioStream, fade: float, from_position: float,
		curve: MusicRules.FadeCurve, start_gain: float) -> bool:
	if _last_steal_usec < 0 or not is_inside_tree():
		return false
	var since := float(Time.get_ticks_usec() - _last_steal_usec) / 1000000.0
	if since < 0.0 or since >= MIN_RESTART_INTERVAL:
		return false
	var armed := not _queued.is_empty()
	_queued = {
		"track": track, "stream": stream, "fade": fade, "from_position": from_position,
		"curve": curve, "start_gain": start_gain,
	}
	if not armed:
		_queue_serial += 1
		# Real time, also while paused (the music keeps playing under menus).
		get_tree().create_timer(MIN_RESTART_INTERVAL - since + 0.01, true, false, true).timeout.connect(
				_on_queue_timer.bind(_queue_serial))
	return true


func _on_queue_timer(serial: int) -> void:
	if serial != _queue_serial or _queued.is_empty():
		return
	var wish := _queued
	_queued = {}
	_queue_serial += 1
	var curve: MusicRules.FadeCurve = wish["curve"]
	play(String(wish["track"]), wish["stream"] as AudioStream, float(wish["fade"]), float(wish["from_position"]),
			curve, float(wish["start_gain"]))


## A player that still plays track (fading out), -1 if none.
func _fading_player(track: String, stream: AudioStream) -> int:
	for i in PLAYER_COUNT:
		if i != _active and _players[i].playing and _player_tracks[i] == track and _players[i].stream == stream:
			return i
	return -1


## A silent, stopped player; otherwise the quietest one that is not the current track.
func _free_player() -> int:
	var best := -1
	for i in PLAYER_COUNT:
		if i == _active:
			continue
		if not _players[i].playing:
			return i
		if best < 0 or _gains[i] < _gains[best]:
			best = i
	return best if best >= 0 else 0


func _fade(index: int, target: float, time: float, curve: MusicRules.FadeCurve) -> void:
	_kill_tween(index)
	if time <= 0.0 or not is_inside_tree():
		_set_gain(index, target)
		if target <= 0.0:
			_players[index].stop()
		return
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_method(_apply_fade.bind(index, _gains[index], target, curve), 0.0, 1.0, time)
	if target <= 0.0:
		tween.tween_callback(_players[index].stop)
	_tweens[index] = tween


func _apply_fade(t: float, index: int, start: float, target: float, curve: MusicRules.FadeCurve) -> void:
	_set_gain(index, MusicRules.fade_gain(start, target, t, curve))


func _set_gain(index: int, gain: float) -> void:
	_gains[index] = gain
	_players[index].volume_db = MusicRules.gain_to_db(gain, level_db, SILENT_DB)


func _kill_tween(index: int) -> void:
	var tween := _tweens[index]
	if tween != null and tween.is_valid():
		tween.kill()
	_tweens[index] = null


## A one-shot stream (stinger) ended: the channel is silent again.
func _on_player_finished(index: int) -> void:
	_kill_tween(index)
	_set_gain(index, 0.0)
	_anchor_usec[index] = -1
	if index == _active:
		_active = -1
		_track = ""
