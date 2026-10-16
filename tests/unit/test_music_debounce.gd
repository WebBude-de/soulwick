extends GutTest
## Debounce of the MusicPlayer (feedback 16.10.2026: "music stutters, loops very fast"): many
## quick music wishes in a row never restart a running piece, duplicate room entries keep boss
## phase and victory, a burst of different pieces is held back (newest wins), the pause duck
## fades, and Engine.time_scale (HitStop) never reaches the music.

var _old_save_path: String
var _old_time_scale := 1.0


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_music_debounce_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	MusicPlayer.clear_handoff()


func before_each() -> void:
	MusicPlayer.clear_handoff()
	_old_time_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _old_time_scale
	var bus := AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, SaveManager.get_bus_volume_db(&"Music"))


func _make() -> MusicPlayer:
	var player := MusicPlayer.new()
	add_child_autofree(player)
	return player


func _playing_players(music: MusicPlayer) -> int:
	var playing := 0
	for player: AudioStreamPlayer in music._music._players:
		playing += 1 if player.playing else 0
	return playing


## Waits in real time (GUT's waits follow Engine.time_scale).
func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func test_the_same_wish_many_times_never_restarts_the_piece() -> void:
	var music := _make()
	music.enter_room(1)
	assert_eq(music.get_current_track(), "dungeon_crypt")
	var starts := music.get_music_start_count()
	for i in 300:
		music.play_track("dungeon_crypt")
		music.play_track("dungeon_crypt", 0.0)
		music.enter_room(1)
		music.play_ambient("ambient_crypt")
	assert_eq(music.get_music_start_count(), starts, "no restart from repeated wishes")
	assert_eq(music.get_current_track(), "dungeon_crypt")
	assert_eq(_playing_players(music), 1, "no second copy of the piece")


func test_stop_and_the_same_wish_again_resumes_in_place() -> void:
	var music := _make()
	music.play_track("dungeon_crypt", 0.0)
	var starts := music.get_music_start_count()
	for i in 100:
		music.stop_music(1.0)
		music.play_track("dungeon_crypt", 1.0)
	assert_eq(music.get_music_start_count(), starts, "the fading piece comes back where it is")
	assert_eq(music.get_current_track(), "dungeon_crypt")
	assert_eq(_playing_players(music), 1)


func test_duplicate_room_entries_keep_boss_phase_and_victory() -> void:
	var music := _make()
	music.enter_room(14)
	music.enter_room(15)
	await wait_process_frames(2)
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "boss_bone_king_p2")
	var starts := music.get_music_start_count()
	for i in 50:
		music.enter_room(15)
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "boss_bone_king_p2", "a re-sent room entry does not reset phase two")
	assert_eq(music.get_music_start_count(), starts)
	music.complete_room(15)
	music.complete_transition()
	for i in 20:
		music.enter_room(15)
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "", "the beaten boss does not come back")
	assert_true(music.is_in_interlude())
	music.enter_room(16)
	music.complete_transition()
	assert_eq(music.get_current_track(), "dungeon_slime_grotto", "the next room still enters normally")


func test_rapid_back_and_forth_between_champion_and_biome_track() -> void:
	var music := _make()
	music.enter_room(1)
	music.enter_room(5)
	assert_eq(music.get_current_track(), "dungeon_crypt_intense")
	var starts := music.get_music_start_count()
	for i in 200:
		music.play_track("dungeon_crypt", MusicPlayer.INTENSE_FADE_TIME)
		music.play_track("dungeon_crypt_intense", MusicPlayer.INTENSE_FADE_TIME)
	assert_eq(music.get_music_start_count(), starts, "both versions keep running, none restarts")
	assert_eq(music.get_current_track(), "dungeon_crypt_intense")
	assert_lte(_playing_players(music), 2)


func test_a_burst_of_different_pieces_is_held_back_and_the_newest_wins() -> void:
	var music := _make()
	music.play_track("dungeon_crypt", 0.0)
	var tracks: Array[String] = ["dungeon_slime_grotto", "dungeon_shadow_realm", "dungeon_ember_forge",
		"boss_bone_king", "boss_slime_queen", "dungeon_crypt"]
	for round_index in 30:
		for track in tracks:
			music.play_track(track, 1.0)
	assert_lte(music.get_music_start_count(), MusicChannel.PLAYER_COUNT + 1,
		"at most one audible player is cut in the burst, nothing restarts every call")
	music.play_track("village", 1.0)
	var held := music._music.get_queued_track() == "village"
	await _wait_real(MusicChannel.MIN_RESTART_INTERVAL + 0.15)
	assert_eq(music.get_current_track(), "village", "the newest wish plays once the guard is over")
	assert_lte(music.get_music_start_count(), MusicChannel.PLAYER_COUNT + 2)
	if held:
		music.play_track("boss_bone_king", 1.0)
		music.play_track("village", 1.0)
		assert_eq(music._music.get_queued_track(), "", "a wish back to the current piece drops the held one")


func test_pause_duck_fades_and_ignores_repeats() -> void:
	var music := _make()
	var base := SaveManager.get_bus_volume_db(&"Music")
	var bus := AudioServer.get_bus_index(&"Music")
	music.set_pause_duck(true)
	assert_gt(music.get_pause_duck_db(), MusicPlayer.PAUSE_DUCK_DB + 1.0, "no jump to the full duck")
	for i in 100:
		music.set_pause_duck(i % 2 == 0)
		assert_between(music.get_pause_duck_db(), MusicPlayer.PAUSE_DUCK_DB, 0.0)
	music.set_pause_duck(true)
	await _wait_real(MusicPlayer.PAUSE_DUCK_FADE_TIME + 0.15)
	assert_almost_eq(music.get_pause_duck_db(), MusicPlayer.PAUSE_DUCK_DB, 0.01)
	if bus >= 0:
		assert_almost_eq(AudioServer.get_bus_volume_db(bus), base + MusicPlayer.PAUSE_DUCK_DB, 0.05)
	music.set_pause_duck(false, 0.0)
	assert_almost_eq(music.get_pause_duck_db(), 0.0, 0.001)
	if bus >= 0:
		assert_almost_eq(AudioServer.get_bus_volume_db(bus), base, 0.05)


func test_hit_stop_time_scale_never_slows_the_music() -> void:
	var music := _make()
	music.play_track("dungeon_crypt", 0.0)
	music.play_track("dungeon_slime_grotto", 0.3)
	Engine.time_scale = HitStop.FREEZE_SCALE
	await _wait_real(0.5)
	assert_almost_eq(music._music.get_gain(), 1.0, 0.001, "the crossfade runs in real time")
	assert_eq(music.get_audible_music_count(), 1)
	for player: AudioStreamPlayer in music._music._players:
		assert_eq(player.pitch_scale, 1.0, "no pitch change on the music")
	Engine.time_scale = _old_time_scale


func test_a_long_main_thread_stall_is_logged_once() -> void:
	var music := _make()
	music.play_track("dungeon_crypt", 0.0)
	var starts := music.get_music_start_count()
	music._last_frame_usec = Time.get_ticks_usec() - 1500000
	music._process(0.0)
	music._process(0.0)
	assert_eq(music.get_hitch_count(), 1)
	assert_gte(music.get_longest_hitch_ms(), 1500)
	assert_eq(music.get_music_start_count(), starts, "a stall restarts nothing")
	assert_eq(music.get_current_track(), "dungeon_crypt")
