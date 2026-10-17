extends GutTest
## Browser loop fix (feedback 17.10.2026, web build: "since the last report the music loops
## again"). Godot 4.7.2 plays music in the browser as Web Audio samples and restarts a looping
## sample at the position it was started from (godot.js SampleNode._restart), so a piece started
## mid-file (champion version on the same bar, scene handoff) repeated only its tail. MusicChannel
## restarts such a player at its loop start at the end of the first pass, keeps gain and fade, and
## reads positions of samples from its clock. Desktop playback (mixer) never gets the fix.
## sample_mode_override = 1 stands in for the web export (headless runs play through the mixer).

const SECOND := 1000000

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_music_web_loop_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	MusicPlayer.clear_handoff()


func before_each() -> void:
	MusicPlayer.clear_handoff()


## A silent mono WAV of seconds length (8 kHz), looping from loop_begin_frames unless loop = false.
func _wav(seconds: float, loop := true, loop_begin_frames := 0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	wav.stereo = false
	var frames := int(seconds * wav.mix_rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = loop_begin_frames
		wav.loop_end = frames
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav


func _channel(sample_mode: int) -> MusicChannel:
	var channel := MusicChannel.new(&"Music")
	channel.sample_mode_override = sample_mode
	add_child_autofree(channel)
	return channel


func _now() -> int:
	return Time.get_ticks_usec()


## Waits in real time (headless frames can be very short).
func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func test_desktop_playback_never_gets_the_fix() -> void:
	var channel := _channel(0)
	channel.play("a", _wav(2.0), 0.0, 1.5)
	assert_false(channel.is_sample_playback())
	assert_false(channel.has_loop_anchor(), "the mixer loops on its own")
	assert_eq(channel.update_loop_anchors(_now() + 10 * SECOND), 0)
	assert_eq(channel.get_loop_anchor_count(), 0)


func test_sample_started_mid_file_restarts_at_the_loop_start() -> void:
	var channel := _channel(1)
	var stream := _wav(2.0)
	channel.play("a", stream, 0.0, 1.5)
	assert_true(channel.is_sample_playback())
	assert_true(channel.has_loop_anchor(), "started mid-file: the browser would loop back to 1.5 s")
	assert_eq(channel.update_loop_anchors(_now()), 0, "not before the end of the first pass")
	assert_eq(channel.update_loop_anchors(_now() + int(0.3 * SECOND)), 0)
	var player: AudioStreamPlayer = channel._players[channel._active]
	assert_eq(channel.update_loop_anchors(_now() + int(0.49 * SECOND)), 1, "restarted within the lead before the end")
	assert_false(channel.has_loop_anchor(), "once: from now on the browser loops the whole piece")
	assert_eq(channel.get_loop_anchor_count(), 1)
	assert_true(player.playing)
	assert_eq(player.stream, stream, "the same piece, no other player")
	assert_eq(channel.get_track(), "a")
	assert_almost_eq(channel.get_timeline_position(), 0.0, 0.1, "the clock starts again at the loop start")
	assert_eq(channel.update_loop_anchors(_now() + 10 * SECOND), 0, "nothing more to fix")


func test_a_piece_with_an_intro_restarts_at_its_loop_begin() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(2.0, true, 4000), 0.0)
	assert_true(channel.has_loop_anchor(), "started at 0, the loop begins at 0.5 s")
	assert_eq(channel.update_loop_anchors(_now() + 2 * SECOND), 1)
	assert_almost_eq(channel.get_timeline_position(), 0.5, 0.1)


func test_start_on_the_loop_start_and_one_shots_need_no_fix() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(2.0), 0.0)
	assert_false(channel.has_loop_anchor(), "from the top the browser loops correctly")
	var stingers := _channel(1)
	stingers.play("s", _wav(2.0, false), 0.0, 1.0)
	assert_false(stingers.has_loop_anchor(), "a stinger does not loop")


func test_too_close_to_the_end_starts_on_the_loop_start_at_once() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(2.0), 0.0, 2.0 - MusicChannel.LOOP_ANCHOR_MAX_LEAD * 0.5)
	assert_false(channel.has_loop_anchor())
	assert_eq(channel.get_loop_anchor_count(), 1)
	assert_almost_eq(channel.get_timeline_position(), 0.0, 0.1)
	channel.play("b", _wav(2.0), 0.0, 5.0)
	assert_almost_eq(channel.get_timeline_position(), 1.0, 0.1, "a position past the end wraps into the piece")


func test_gain_and_fade_survive_the_restart() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(2.0), 0.0)
	channel.play("b", _wav(2.0), 1.0, 1.5, MusicRules.FadeCurve.LINEAR)
	var index: int = channel._active
	var player: AudioStreamPlayer = channel._players[index]
	await _wait_real(0.15)
	var volume := player.volume_db
	assert_eq(channel.update_loop_anchors(_now() + 2 * SECOND), 1)
	assert_eq(player.volume_db, volume, "same gain right after the restart")
	assert_true(channel._tweens[index] != null and channel._tweens[index].is_valid(), "its fade-in goes on")
	assert_eq(channel.get_audible_count(), 2, "the old piece still fades out")


func test_a_stopped_player_drops_its_fix() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(2.0), 0.0, 1.0)
	assert_true(channel.has_loop_anchor())
	channel.stop(0.0)
	assert_eq(channel.update_loop_anchors(_now() + 10 * SECOND), 0, "nothing restarts after a stop")
	assert_false(channel.has_loop_anchor())
	for player: AudioStreamPlayer in channel._players:
		assert_false(player.playing)


func test_sample_positions_come_from_the_clock() -> void:
	var channel := _channel(1)
	channel.play("a", _wav(4.0), 0.0, 1.2)
	assert_almost_eq(channel.get_playback_position(), 1.2, 0.1, "the browser's own value lags about a second")
	channel._clock_usec[channel._active] -= 3 * SECOND
	assert_almost_eq(channel.get_playback_position(), 0.2, 0.1, "wraps at the end like the loop")


func test_wrap_position() -> void:
	assert_almost_eq(MusicChannel.wrap_position(1.5, 2.0), 1.5, 0.0001)
	assert_almost_eq(MusicChannel.wrap_position(2.5, 2.0), 0.5, 0.0001)
	assert_almost_eq(MusicChannel.wrap_position(2.0, 2.0), 0.0, 0.0001)
	assert_almost_eq(MusicChannel.wrap_position(2.5, 2.0, 0.5), 1.0, 0.0001, "loops back to the loop start")
	assert_almost_eq(MusicChannel.wrap_position(7.0, 0.0), 7.0, 0.0001, "no length: unchanged")


func test_champion_version_on_the_web_loops_the_whole_piece() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	music._music.sample_mode_override = 1
	music.play_track("dungeon_crypt", 0.0)
	assert_false(music._music.has_loop_anchor(), "biome track from the top")
	# 30 s into the biome track, then a champion room: same piece, same bar.
	music._music._clock_usec[music._music._active] -= 30 * SECOND
	music.play_track("dungeon_crypt_intense", MusicPlayer.INTENSE_FADE_TIME)
	assert_eq(music.get_current_track(), "dungeon_crypt_intense")
	assert_almost_eq(music._music.get_playback_position(), 30.0, 0.2, "the champion version keeps the bar")
	assert_true(music._music.has_loop_anchor(), "started mid-file")
	var length: float = music._music._players[music._music._active].stream.get_length()
	assert_eq(music._music.update_loop_anchors(_now() + int((length - 30.0 + 0.05) * SECOND)), 1)
	assert_almost_eq(music._music.get_timeline_position(), 0.0, 0.2, "the next pass starts at the top, not at 30 s")
	var diagnostics := music.get_diagnostics()
	assert_eq(diagnostics["track"], "dungeon_crypt_intense")
	assert_true(diagnostics["sample_playback"])
	assert_eq(diagnostics["loop_restarts"], 1)


func test_champion_version_on_the_desktop_is_unchanged() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	music._music.sample_mode_override = 0
	music.play_track("dungeon_crypt", 0.0)
	music.play_track("dungeon_crypt_intense", MusicPlayer.INTENSE_FADE_TIME)
	assert_false(music._music.has_loop_anchor())
	assert_false(music.get_diagnostics()["sample_playback"])
	assert_eq(music.get_diagnostics()["loop_restarts"], 0)


func test_short_stalls_are_counted_for_reports() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	music._last_frame_usec = _now() - int(0.3 * SECOND)
	music._process(0.0)
	music._process(0.0)
	assert_eq(music.get_stall_count(), 1, "a 300 ms gap counts")
	assert_eq(music.get_hitch_count(), 0, "but is not logged (under HITCH_LOG_MS)")
	var stalls: Dictionary = music.get_diagnostics()["stalls"]
	assert_gte(int(stalls["longest_ms"]), 300)
	assert_gte(int(stalls["last_ms"]), 300)
	assert_true(stalls.has("last_ago_s"))
	assert_false(MusicPlayer.diagnostics_of(get_tree()).is_empty(), "found through the group")
