extends GutTest
## Music choice per biome and room type (D-092): own tracks per biome and boss, champion and
## phase-two versions, fallbacks for missing files, loop points of the imported streams.

const BIOMES := {
	"res://dungeon/biomes/crypt.tres": ["dungeon_crypt", "boss_bone_king"],
	"res://dungeon/biomes/slime_grotto.tres": ["dungeon_slime_grotto", "boss_slime_queen"],
	"res://dungeon/biomes/shadow_realm.tres": ["dungeon_shadow_realm", "boss_shadow_lord"],
	"res://dungeon/biomes/ember_forge.tres": ["dungeon_ember_forge", "boss_ember_golem"],
}


func _biome(music := "", boss := "", ambient := "") -> BiomeData:
	var biome := BiomeData.new()
	biome.music_track = music
	biome.boss_music_track = boss
	biome.ambient_track = ambient
	return biome


func test_every_biome_names_its_own_tracks_and_files_exist() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		var names: Array = BIOMES[path]
		assert_eq(biome.music_track, names[0], path)
		assert_eq(biome.boss_music_track, names[1], path)
		for track: String in [names[0], names[0] + MusicRules.INTENSE_SUFFIX, names[1], names[1] + MusicRules.PHASE_TWO_SUFFIX]:
			assert_ne(MusicRules.find_file(track, MusicRules.MUSIC_DIR), "", "missing file for " + track)


func test_fallback_tracks_still_exist() -> void:
	for track: String in [MusicRules.DUNGEON_FALLBACK, MusicRules.BOSS_FALLBACK, MusicRules.VILLAGE_TRACK]:
		assert_ne(MusicRules.find_file(track, MusicRules.MUSIC_DIR), "", track)


func test_biome_for_room_follows_room_sequence() -> void:
	var expected := {1: "crypt", 15: "crypt", 16: "slime_grotto", 30: "slime_grotto", 31: "shadow_realm",
		46: "ember_forge", 60: "ember_forge", 61: "crypt", 76: "slime_grotto"}
	for room: int in expected:
		var biome := MusicRules.biome_for_room(room)
		assert_not_null(biome, "room %d" % room)
		assert_eq(String(biome.id), expected[room], "room %d" % room)


func test_normal_and_special_rooms_play_the_biome_track() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		for room_type in [RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, RoomSequence.RoomType.SPECIAL]:
			assert_eq(MusicRules.dungeon_track(biome, room_type), biome.music_track, path)


func test_champion_room_plays_the_intense_version() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.MINIBOSS), biome.music_track + "_intense", path)


func test_boss_room_plays_boss_track_and_phase_two() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.BOSS), biome.boss_music_track, path)
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.BOSS, 2), biome.boss_music_track + "_p2", path)
		assert_eq(MusicRules.boss_track(biome, 2), biome.boss_music_track + "_p2", path)


func test_missing_or_empty_tracks_fall_back_to_dungeon_and_boss() -> void:
	for biome: BiomeData in [_biome("no_such_track", "no_such_boss"), _biome(), null]:
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.COMBAT), "dungeon")
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.MINIBOSS), "dungeon")
		assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.SPECIAL), "dungeon")
		assert_eq(MusicRules.boss_track(biome), "boss")
		assert_eq(MusicRules.boss_track(biome, 2), "boss", "no boss_p2 file: phase-one fallback")


func test_missing_versions_fall_back_to_the_base_track() -> void:
	# boss_bone_king has no "_intense", dungeon_crypt has no "_p2".
	var biome := _biome("boss_bone_king", "dungeon_crypt")
	assert_eq(MusicRules.dungeon_track(biome, RoomSequence.RoomType.MINIBOSS), "boss_bone_king")
	assert_eq(MusicRules.boss_track(biome, 2), "dungeon_crypt")


func test_shares_timeline_only_for_base_and_intense() -> void:
	assert_true(MusicRules.shares_timeline("dungeon_crypt", "dungeon_crypt_intense"))
	assert_true(MusicRules.shares_timeline("dungeon_crypt_intense", "dungeon_crypt"))
	assert_false(MusicRules.shares_timeline("dungeon_crypt", "dungeon_slime_grotto"))
	assert_false(MusicRules.shares_timeline("boss_bone_king", "boss_bone_king_p2"))
	assert_false(MusicRules.shares_timeline("", "_intense"))


func test_streams_loop_over_the_whole_file() -> void:
	# Regression: the loop end was computed from the byte size, which for QOA imports cut the
	# 30 s dungeon loop after about 12 s.
	for track: String in ["dungeon", "boss", "dungeon_crypt", "boss_shadow_lord_p2"]:
		var stream := MusicRules.load_stream(track, MusicRules.MUSIC_DIR) as AudioStreamWAV
		assert_not_null(stream, track)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, track)
		assert_eq(stream.loop_begin, 0, track)
		assert_almost_eq(stream.loop_end / float(stream.mix_rate), stream.get_length(), 0.01, track)
	assert_almost_eq(MusicRules.load_stream("dungeon", MusicRules.MUSIC_DIR).get_length(), 30.0, 0.05)
	assert_null(MusicRules.load_stream("no_such_track", MusicRules.MUSIC_DIR))


func test_biome_tracks_are_60_to_90_seconds_and_versions_match() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		var base := MusicRules.load_stream(biome.music_track, MusicRules.MUSIC_DIR)
		var intense := MusicRules.load_stream(biome.music_track + "_intense", MusicRules.MUSIC_DIR)
		assert_between(base.get_length(), 60.0, 90.0, biome.music_track)
		assert_almost_eq(intense.get_length(), base.get_length(), 0.01, "champion version shares the timeline")
		var boss := MusicRules.load_stream(biome.boss_music_track, MusicRules.MUSIC_DIR)
		var phase_two := MusicRules.load_stream(biome.boss_music_track + "_p2", MusicRules.MUSIC_DIR)
		assert_lt(phase_two.get_length(), boss.get_length(), "phase two is faster")


const STINGERS := {
	"res://dungeon/biomes/crypt.tres": ["transition_crypt", "victory_bone_king"],
	"res://dungeon/biomes/slime_grotto.tres": ["transition_slime_grotto", "victory_slime_queen"],
	"res://dungeon/biomes/shadow_realm.tres": ["transition_shadow_realm", "victory_shadow_lord"],
	"res://dungeon/biomes/ember_forge.tres": ["transition_ember_forge", "victory_ember_golem"],
}


func test_every_biome_has_transition_and_victory_stingers() -> void:
	for path: String in STINGERS:
		var biome: BiomeData = load(path)
		var names: Array = STINGERS[path]
		assert_eq(MusicRules.transition_track(biome), names[0], path)
		assert_eq(MusicRules.victory_track(biome), names[1], path)


func test_missing_stingers_mean_none() -> void:
	var biome := BiomeData.new()
	assert_eq(MusicRules.transition_track(biome), "")
	assert_eq(MusicRules.victory_track(biome), "")
	biome.transition_track = "no_such_stinger"
	assert_eq(MusicRules.transition_track(biome), "")
	assert_eq(MusicRules.transition_track(null), "")
	assert_eq(MusicRules.victory_track(null), "")


func test_stingers_play_once_and_are_short() -> void:
	for names: Array in STINGERS.values():
		for track: String in names:
			var stream := MusicRules.load_stream(track, MusicRules.MUSIC_DIR, false) as AudioStreamWAV
			assert_not_null(stream, track)
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, track)
			assert_between(stream.get_length(), 3.0 + MusicRules.STINGER_TAIL, 8.0, track)


func test_transition_stinger_ends_on_a_bar_of_its_biome_loop() -> void:
	# Musical part = whole 16ths of the loop tempo (crypt 84, grotto 104, shadow 76, forge 120 BPM).
	var bpms := {"transition_crypt": 84, "transition_slime_grotto": 104, "transition_shadow_realm": 76, "transition_ember_forge": 120}
	for track: String in bpms:
		var stream := MusicRules.load_stream(track, MusicRules.MUSIC_DIR, false)
		var entry := MusicRules.stinger_entry_time(stream.get_length())
		var bar := 240.0 / float(bpms[track])
		var bars := entry / bar
		assert_between(bars, 1.4, 2.01, track)
		assert_almost_eq(bars * 2.0, roundf(bars * 2.0), 0.01, track + " ends on a (half) bar line")
	assert_eq(MusicRules.stinger_entry_time(1.0), 0.0, "never negative")


func test_equal_power_crossfade_keeps_the_sum_of_powers() -> void:
	for t: float in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		var rise := MusicRules.fade_gain(0.0, 1.0, t, MusicRules.FadeCurve.EQUAL_POWER)
		var fall := MusicRules.fade_gain(1.0, 0.0, t, MusicRules.FadeCurve.EQUAL_POWER)
		assert_almost_eq(rise * rise + fall * fall, 1.0, 0.001, "t=%s" % t)
		assert_lt(maxf(rise, fall), 1.0 if t > 0.0 and t < 1.0 else 1.01, "never two tracks at full volume")
	assert_almost_eq(MusicRules.fade_gain(0.0, 1.0, 0.5, MusicRules.FadeCurve.EQUAL_POWER), sqrt(0.5), 0.001)


func test_linear_crossfade_for_the_same_piece_keeps_the_sum_of_gains() -> void:
	for t: float in [0.0, 0.3, 0.5, 0.8, 1.0]:
		var rise := MusicRules.fade_gain(0.0, 1.0, t, MusicRules.FadeCurve.LINEAR)
		var fall := MusicRules.fade_gain(1.0, 0.0, t, MusicRules.FadeCurve.LINEAR)
		assert_almost_eq(rise + fall, 1.0, 0.001)
	assert_eq(MusicRules.fade_curve("dungeon_crypt", "dungeon_crypt_intense"), MusicRules.FadeCurve.LINEAR)
	assert_eq(MusicRules.fade_curve("dungeon_crypt", "boss_bone_king"), MusicRules.FadeCurve.EQUAL_POWER)


func test_interrupted_fade_continues_from_the_current_gain() -> void:
	assert_almost_eq(MusicRules.fade_gain(0.4, 0.0, 0.0, MusicRules.FadeCurve.EQUAL_POWER), 0.4, 0.001)
	assert_almost_eq(MusicRules.fade_gain(0.4, 1.0, 0.0, MusicRules.FadeCurve.EQUAL_POWER), 0.4, 0.001)
	assert_almost_eq(MusicRules.fade_gain(0.4, 1.0, 1.0, MusicRules.FadeCurve.EQUAL_POWER), 1.0, 0.001)
	assert_eq(MusicRules.gain_to_db(0.0), -60.0)
	assert_almost_eq(MusicRules.gain_to_db(1.0, -3.0), -3.0, 0.001)
