extends GutTest
## Preloading of the music (MusicPreloader): the files of the coming biome load ahead of time,
## threaded or (web build without threads) one per idle interval, and are found in the resource
## cache when they play; missing files are skipped, unready ones load the normal way.

const MusicPreloader := MusicPlayer.MusicPreloader
const CRYPT_FILES: Array[String] = [
	"res://audio/music/transition_crypt.wav",
	"res://audio/ambient/ambient_crypt.wav",
	"res://audio/music/dungeon_crypt.wav",
	"res://audio/music/dungeon_crypt_intense.wav",
	"res://audio/music/boss_bone_king.wav",
	"res://audio/music/boss_bone_king_p2.wav",
	"res://audio/music/victory_bone_king.wav",
]


func before_each() -> void:
	MusicPlayer.clear_handoff()


func after_all() -> void:
	MusicPlayer.clear_handoff()


func _make_preloader() -> MusicPreloader:
	var preloader := MusicPreloader.new()
	add_child_autofree(preloader)
	return preloader


func test_biome_files_list_the_entry_first_and_skip_missing() -> void:
	var crypt := MusicRules.biome_for_room(1)
	var files := MusicRules.biome_files(crypt)
	for path in files:
		assert_true(ResourceLoader.exists(path), path)
	for path in CRYPT_FILES:
		if ResourceLoader.exists(path):
			assert_has(files, path)
	assert_eq(files[0], MusicRules.find_file("transition_crypt", MusicRules.MUSIC_DIR), "the entry stinger first")
	var entry := MusicRules.biome_files(crypt, false)
	assert_eq(entry.size(), 3, "entry: stinger, ambient, loop")
	assert_false(entry.has(MusicRules.find_file("boss_bone_king", MusicRules.MUSIC_DIR)))
	assert_eq(MusicRules.biome_files(null, false), ["res://audio/music/dungeon.wav"] as Array[String],
		"no biome: only the fallback loop")


func test_next_biome_after_a_room() -> void:
	assert_eq(MusicRules.next_biome_after(1).music_track, "dungeon_slime_grotto")
	assert_eq(MusicRules.next_biome_after(15).music_track, "dungeon_slime_grotto")
	assert_eq(MusicRules.next_biome_after(16).music_track, "dungeon_shadow_realm")
	assert_eq(MusicRules.next_biome_after(46).music_track, "dungeon_crypt", "the biomes cycle")


func test_threaded_preload_fills_the_cache() -> void:
	var preloader := _make_preloader()
	preloader.set_threaded(true)
	var path := MusicRules.find_file("dungeon_shadow_realm", MusicRules.MUSIC_DIR)
	preloader.request([path] as Array[String])
	var frames := 0
	while not preloader.is_idle() and frames < 600:
		await wait_process_frames(1)
		frames += 1
	assert_true(preloader.is_loaded(path), "loaded in the background (%d frames)" % frames)
	assert_same(MusicRules.load_stream("dungeon_shadow_realm", MusicRules.MUSIC_DIR), preloader._held[path],
		"playing it later is a cache hit")


func test_without_threads_one_file_per_idle_interval() -> void:
	var preloader := _make_preloader()
	preloader.set_threaded(false)
	var files := MusicRules.biome_files(MusicRules.biome_for_room(31), false)
	preloader.request(files)
	preloader._process(0.0)
	preloader._process(0.0)
	assert_eq(preloader.get_loaded_paths().size(), 1, "the second load waits for the next idle interval")
	preloader.finish_now()
	assert_eq(preloader.get_loaded_paths().size(), files.size())
	preloader.request(files)
	assert_true(preloader.is_idle(), "loaded files are not queued again")


func test_missing_files_are_skipped() -> void:
	var preloader := _make_preloader()
	preloader.request(["res://audio/music/no_such_track.wav", ""] as Array[String])
	assert_true(preloader.is_idle())


func test_rooms_preload_the_biome_and_near_the_change_the_next_entry() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	var preloader := music.get_preloader()
	var slime_entry := MusicRules.find_file("transition_slime_grotto", MusicRules.MUSIC_DIR)
	music.enter_room(2)
	preloader.finish_now()
	assert_true(preloader.is_loaded(MusicRules.find_file("boss_bone_king", MusicRules.MUSIC_DIR)), "own biome, boss included")
	assert_false(preloader.is_loaded(slime_entry), "the next biome is still far away")
	music.enter_room(13)
	preloader.finish_now()
	assert_true(preloader.is_loaded(slime_entry), "three rooms before the change its entry is ready")
	assert_true(preloader.is_loaded(MusicRules.find_file("dungeon_slime_grotto", MusicRules.MUSIC_DIR)))
	music.enter_room(16)
	preloader.finish_now()
	assert_false(preloader.is_loaded(MusicRules.find_file("boss_bone_king", MusicRules.MUSIC_DIR)), "the old biome is let go")
	assert_true(preloader.is_loaded(MusicRules.find_file("boss_slime_queen", MusicRules.MUSIC_DIR)))


func test_interlude_and_village_preload_the_coming_entry() -> void:
	var music := MusicPlayer.new()
	add_child_autofree(music)
	var preloader := music.get_preloader()
	music.begin_interlude(MusicRules.biome_for_room(31))
	preloader.finish_now()
	assert_true(preloader.is_loaded(MusicRules.find_file("transition_shadow_realm", MusicRules.MUSIC_DIR)))
	music._on_phase_changed(GameManager.Phase.VILLAGE)
	preloader.finish_now()
	assert_true(preloader.is_loaded(MusicRules.find_file("transition_crypt", MusicRules.MUSIC_DIR)), "the first biome waits in the village")
	assert_false(preloader.is_loaded(MusicRules.find_file("transition_shadow_realm", MusicRules.MUSIC_DIR)))


func test_leaving_the_tree_with_a_request_in_flight_is_clean() -> void:
	var preloader := MusicPreloader.new()
	add_child(preloader)
	preloader.set_threaded(true)
	preloader.request(MusicRules.biome_files(MusicRules.biome_for_room(46), false))
	await wait_process_frames(1)
	remove_child(preloader)
	assert_true(preloader._in_flight.is_empty(), "the running request was collected")
	preloader.free()
