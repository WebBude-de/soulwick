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

const SILENT_DB := -60.0
const PLAYER_COUNT := 3

## Volume of the audible player in dB (gain 1).
var level_db := 0.0

var _players: Array[AudioStreamPlayer] = []
## Linear gain 0..1 of every player.
var _gains: Array[float] = []
## Track name loaded in every player.
var _player_tracks: Array[String] = []
var _tweens: Array[Tween] = []
var _active := -1
var _track := ""
## Clock reference of the current track (see get_timeline_position).
var _started_usec := 0
var _started_from := 0.0
var _length := 0.0


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


func get_track() -> String:
	return _track


func is_playing() -> bool:
	return not _track.is_empty() and _active >= 0 and _players[_active].playing


## Seconds into the audible track (0 if silent).
func get_playback_position() -> float:
	if _active < 0 or not _players[_active].playing:
		return 0.0
	return _players[_active].get_playback_position()


## Position of the current track computed from the clock (also valid after the players left the
## tree, for the scene handoff); the music never pauses, so it matches the playback.
func get_timeline_position() -> float:
	if _track.is_empty() or _length <= 0.0:
		return 0.0
	var elapsed := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	return fmod(_started_from + elapsed, _length)


## Linear gain of the current track (0 when nothing plays).
func get_gain() -> float:
	return _gains[_active] if _active >= 0 else 0.0


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
	if track == _track or stream == null:
		return
	var index := _fading_player(track, stream)
	var player: AudioStreamPlayer
	if index >= 0:
		player = _players[index]
		from_position = player.get_playback_position()
	else:
		index = _free_player()
		player = _players[index]
		_kill_tween(index)
		player.stop()
		player.stream = stream
		_player_tracks[index] = track
		_set_gain(index, clampf(start_gain, 0.0, 1.0))
		player.play(from_position)
	for i in PLAYER_COUNT:
		if i != index and _players[i].playing:
			_fade(i, 0.0, fade, curve)
	_active = index
	_track = track
	_started_usec = Time.get_ticks_usec()
	_started_from = from_position
	_length = stream.get_length()
	_fade(index, 1.0, fade, curve)


## Fades everything out (the channel stays usable).
func stop(fade: float, curve := MusicRules.FadeCurve.EQUAL_POWER) -> void:
	_track = ""
	_active = -1
	for i in PLAYER_COUNT:
		if _players[i].playing:
			_fade(i, 0.0, fade, curve)


func _exit_tree() -> void:
	for i in PLAYER_COUNT:
		_kill_tween(i)
		_players[i].stop()


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
	if index == _active:
		_active = -1
		_track = ""
