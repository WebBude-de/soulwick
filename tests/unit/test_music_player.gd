extends GutTest
## MusicPlayer reacting to rooms, biomes, champion and boss rooms, boss phase two and a boss
## intro (D-092), plus the transitions of D-097: biome entry (ambient, stinger, loop), boss
## victory, run end, village and the scene handoff. follow_game stays off: the tests call the
## same handlers the signals use; complete_transition() skips the waiting of a transition.

const BOSS_DATA := "res://enemies/data/boss_bone_king.tres"
const SKELETON_DATA := "res://enemies/data/skeleton.tres"


func before_each() -> void:
	MusicPlayer.clear_handoff()


func after_all() -> void:
	MusicPlayer.clear_handoff()


func _make() -> MusicPlayer:
	var player := MusicPlayer.new()
	add_child_autofree(player)
	return player


func test_rooms_play_biome_track_and_ambient() -> void:
	var music := _make()
	music.enter_room(1)
	assert_eq(music.get_current_track(), "dungeon_crypt")
	assert_eq(music.get_current_ambient(), "ambient_crypt")
	music.enter_room(4)
	assert_eq(music.get_current_track(), "dungeon_crypt", "special rooms keep the biome track")
	for room: int in [16, 31, 46]:
		music.enter_room(room)
		music.complete_transition()
	assert_eq(music.get_current_track(), "dungeon_ember_forge")
	assert_eq(music.get_current_ambient(), "ambient_ember_forge")


func test_new_biome_crosses_ambient_first_then_stinger_then_loop() -> void:
	var music := _make()
	music.enter_room(14)
	music.enter_room(16)
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto", "the ambient bed crosses right away")
	assert_eq(music.get_current_track(), "", "the old loop fades out, no crossfade between two loops")
	assert_true(music.is_transition_pending())
	music.enter_room(17)
	assert_eq(music.get_current_track(), "", "a room inside the running entry waits for it")
	music._run_pending_step()
	assert_eq(music.get_current_stinger(), "transition_slime_grotto")
	assert_eq(music.get_current_track(), "", "the loop waits for the end of the stinger's last bar")
	music._run_pending_step()
	assert_eq(music.get_current_track(), "dungeon_slime_grotto")
	assert_false(music.is_transition_pending())


func test_champion_room_switches_to_intense_and_back() -> void:
	var music := _make()
	music.enter_room(1)
	music.enter_room(5)
	assert_eq(music.get_current_track(), "dungeon_crypt_intense")
	music.complete_room(5)
	assert_eq(music.get_current_track(), "dungeon_crypt")
	music.complete_room(5)
	assert_eq(music.get_current_track(), "dungeon_crypt", "a second completion changes nothing")
	var playing := 0
	for player: AudioStreamPlayer in music._music._players:
		playing += 1 if player.playing else 0
	assert_eq(playing, 2, "the fading biome track came back, no second copy of it")


func test_boss_track_starts_a_frame_later_and_phase_two_switches() -> void:
	var music := _make()
	music.enter_room(14)
	music.enter_room(15)
	assert_eq(music.get_current_track(), "dungeon_crypt", "deferred so an intro can hold it")
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "boss_bone_king")
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "boss_bone_king_p2")
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "boss_bone_king_p2")


func test_boss_victory_leaves_stinger_and_ambient_until_the_next_biome() -> void:
	var music := _make()
	music.enter_room(14)
	music.enter_room(15)
	await wait_process_frames(2)
	music.complete_room(15)
	assert_eq(music.get_current_track(), "", "no jump back to the crypt track")
	assert_eq(music.get_current_ambient(), "ambient_crypt", "only the ambient bed stays")
	music.complete_transition()
	assert_eq(music.get_current_stinger(), "victory_bone_king")
	assert_eq(music.get_current_track(), "")
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "", "a late phase change after the victory is ignored")
	music.enter_room(16)
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto")
	assert_eq(music.get_current_stinger(), "", "the victory stinger fades for the new biome")
	music.complete_transition()
	assert_eq(music.get_current_track(), "dungeon_slime_grotto")


func test_victory_without_a_followup_biome_still_starts_with_an_entry() -> void:
	# Calm after the boss: even a room of the same biome (custom sequences) enters properly.
	var music := _make()
	music.enter_room(15)
	await wait_process_frames(2)
	music.complete_room(15)
	music.complete_transition()
	music.enter_room(14)
	assert_eq(music.get_current_track(), "")
	music.complete_transition()
	assert_eq(music.get_current_track(), "dungeon_crypt")


func test_interlude_hook_crosses_the_ambient_before_the_next_biome() -> void:
	# The future campfire (A6) between two biomes: music out, new ambient, then the full entry.
	var music := _make()
	music.enter_room(15)
	await wait_process_frames(2)
	music.complete_room(15)
	assert_true(music.is_in_interlude(), "after the boss a transition is running")
	music.begin_interlude(MusicRules.biome_for_room(16))
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto", "the new ambient sets in at the fire")
	assert_eq(music.get_current_track(), "")
	music.complete_transition()
	assert_eq(music.get_current_stinger(), "victory_bone_king", "the victory stinger still rings out")
	music.enter_room(16)
	assert_false(music.is_in_interlude())
	music.complete_transition()
	assert_eq(music.get_current_stinger(), "transition_slime_grotto")
	assert_eq(music.get_current_track(), "dungeon_slime_grotto")


func test_phase_two_outside_a_boss_room_is_ignored() -> void:
	var music := _make()
	music.enter_room(5)
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "dungeon_crypt_intense")


func test_boss_intro_holds_the_boss_track_until_released() -> void:
	var music := _make()
	music.enter_room(29)
	music.enter_room(30)
	music.hold_boss_music()
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "", "silent while the intro runs, ambient stays")
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto")
	music.release_boss_music()
	assert_eq(music.get_current_track(), "boss_slime_queen")


func test_hold_before_entering_and_phase_two_during_hold() -> void:
	var music := _make()
	music.enter_room(44)
	music.hold_boss_music()
	assert_eq(music.get_current_track(), "dungeon_shadow_realm", "hold outside a boss room keeps the music")
	music.enter_room(45)
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "")
	music.on_boss_phase_changed(2)
	assert_eq(music.get_current_track(), "")
	music.release_boss_music()
	assert_eq(music.get_current_track(), "boss_shadow_lord_p2")


func test_long_intro_is_not_overrun_by_the_safety_time() -> void:
	var music := _make()
	music.enter_room(15)
	var intro := BossIntro.create(null)
	add_child_autofree(intro)
	music._follow_boss_intro(intro)
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "")
	# The safety time runs out while the intro is still speaking: keep waiting.
	music._on_hold_timeout(music._hold_serial, MusicPlayer.BOSS_HOLD_MAX_TIME)
	assert_eq(music.get_current_track(), "", "a running intro keeps the hold")
	intro.ending.emit(false)
	assert_eq(music.get_current_track(), "boss_bone_king", "the roar starts the boss track")


func test_hold_safety_releases_without_intro_or_after_the_absolute_maximum() -> void:
	var music := _make()
	music.enter_room(15)
	music.hold_boss_music()
	await wait_process_frames(2)
	music._on_hold_timeout(music._hold_serial, MusicPlayer.BOSS_HOLD_MAX_TIME)
	assert_eq(music.get_current_track(), "boss_bone_king", "manual hold: released after the safety time")

	var stuck := _make()
	stuck.enter_room(30)
	var intro := BossIntro.create(null)
	add_child_autofree(intro)
	stuck._follow_boss_intro(intro)
	await wait_process_frames(2)
	stuck._on_hold_timeout(stuck._hold_serial, MusicPlayer.BOSS_HOLD_ABSOLUTE_MAX)
	assert_eq(stuck.get_current_track(), "boss_slime_queen", "a stuck intro cannot hold forever")


func test_finished_of_an_old_intro_does_not_release_a_new_hold() -> void:
	var music := _make()
	music.enter_room(15)
	var old_intro := BossIntro.create(null)
	var new_intro := BossIntro.create(null)
	add_child_autofree(old_intro)
	add_child_autofree(new_intro)
	music._follow_boss_intro(old_intro)
	music._follow_boss_intro(new_intro)
	await wait_process_frames(2)
	old_intro.finished.emit()
	assert_eq(music.get_current_track(), "")
	new_intro.finished.emit()
	assert_eq(music.get_current_track(), "boss_bone_king")


func test_boss_phase_signal_of_a_boss_enemy_is_followed() -> void:
	var music := _make()
	music.enter_room(60)
	await wait_process_frames(2)
	assert_eq(music.get_current_track(), "boss_ember_golem")
	var champion := Enemy.new()
	champion.data = load(SKELETON_DATA)
	music._on_node_added(champion)
	champion.phase_changed.emit(champion, 2)
	assert_eq(music.get_current_track(), "boss_ember_golem", "champions do not switch the boss music")
	var boss := Enemy.new()
	boss.data = load(BOSS_DATA)
	music._on_node_added(boss)
	boss.phase_changed.emit(boss, 2)
	assert_eq(music.get_current_track(), "boss_ember_golem_p2")
	champion.free()
	boss.free()


func test_village_phase_crosses_ambient_first_then_the_theme() -> void:
	var music := _make()
	music.enter_room(20)
	music._on_phase_changed(GameManager.Phase.VILLAGE)
	assert_eq(music.get_current_ambient(), "ambient_village")
	assert_eq(music.get_current_track(), "", "the dungeon track fades, the theme follows")
	music.complete_transition()
	assert_eq(music.get_current_track(), "village")


func test_dungeon_phase_starts_with_the_entry_of_the_first_biome() -> void:
	var music := _make()
	music.play_track("village", 0.0)
	music._on_phase_changed(GameManager.Phase.DUNGEON)
	music.enter_room(1)
	assert_eq(music.get_current_ambient(), "ambient_crypt")
	assert_eq(music.get_current_track(), "", "village fades out, no crossfade into the crypt loop")
	music.complete_transition()
	assert_eq(music.get_current_stinger(), "transition_crypt")
	assert_eq(music.get_current_track(), "dungeon_crypt")


func test_run_end_fades_the_music_and_keeps_the_ambient() -> void:
	var music := _make()
	music.enter_room(5)
	music.on_run_ended()
	assert_eq(music.get_current_track(), "")
	assert_eq(music.get_current_ambient(), "ambient_crypt")
	music.complete_room(5)
	assert_eq(music.get_current_track(), "", "a late room completion after the run does nothing")


func test_run_end_during_a_held_boss_intro_never_starts_the_boss_track() -> void:
	var music := _make()
	music.enter_room(15)
	music.hold_boss_music()
	await wait_process_frames(2)
	music.on_run_ended()
	music.release_boss_music()
	assert_eq(music.get_current_track(), "")


func test_crossfade_never_has_more_than_two_loud_tracks_and_does_not_cut() -> void:
	var music := _make()
	music.play_track("dungeon_crypt", 0.0)
	music.play_track("dungeon_slime_grotto", 1.0)
	music.play_track("dungeon_shadow_realm", 1.0)
	assert_eq(music.get_current_track(), "dungeon_shadow_realm")
	assert_eq(music.get_audible_music_count(), 1, "the first track still fades out instead of being cut")
	await wait_seconds(0.3)
	assert_between(music.get_audible_music_count(), 1, 2, "old one out, new one in, the cut one silent")


func test_scene_handoff_continues_the_track_instead_of_cutting() -> void:
	var menu := MusicPlayer.new()
	menu.start_track = "village"
	add_child(menu)
	await wait_seconds(0.2)
	menu.play_track("dungeon_crypt", 0.0)
	remove_child(menu)
	menu.free()
	var next := MusicPlayer.new()
	next.start_track = "village"
	add_child_autofree(next)
	assert_eq(next.get_current_track(), "dungeon_crypt", "the handed-over track continues first")
	await wait_seconds(0.3)
	assert_eq(next.get_current_track(), "village", "then the start track crosses over")
	assert_eq(next.get_audible_music_count(), 2, "both audible during the crossfade")


func test_handoff_is_ignored_by_test_instances_and_when_stale() -> void:
	var music := _make()
	assert_eq(music.get_current_track(), "")
	MusicPlayer._handoff = {"music": "dungeon_crypt", "music_position": 1.0, "ambient": "", "ambient_position": 0.0,
		"usec": Time.get_ticks_usec() - 5000000}
	var late := MusicPlayer.new()
	late.start_track = "village"
	add_child_autofree(late)
	assert_eq(late.get_current_track(), "village", "a handoff older than HANDOFF_MAX_AGE is dropped")


func test_unknown_track_keeps_the_current_music() -> void:
	var music := _make()
	music.play_track("village")
	music.play_track("no_such_track")
	assert_eq(music.get_current_track(), "village")
	music.play_ambient("no_such_ambient")
	assert_eq(music.get_current_ambient(), "")
	assert_eq(music.play_stinger("no_such_stinger"), 0.0)
