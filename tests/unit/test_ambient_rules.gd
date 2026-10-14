extends GutTest
## Ambient beds under the music: one per biome plus the village, empty field = none, loops.

const BIOMES := {
	"res://dungeon/biomes/crypt.tres": "ambient_crypt",
	"res://dungeon/biomes/slime_grotto.tres": "ambient_slime_grotto",
	"res://dungeon/biomes/shadow_realm.tres": "ambient_shadow_realm",
	"res://dungeon/biomes/ember_forge.tres": "ambient_ember_forge",
}


func test_every_biome_has_an_ambient_bed() -> void:
	for path: String in BIOMES:
		var biome: BiomeData = load(path)
		assert_eq(biome.ambient_track, BIOMES[path], path)
		assert_eq(MusicRules.ambient_track(biome), BIOMES[path], path)


func test_empty_or_missing_ambient_means_none() -> void:
	var biome := BiomeData.new()
	assert_eq(MusicRules.ambient_track(biome), "")
	biome.ambient_track = "no_such_ambient"
	assert_eq(MusicRules.ambient_track(biome), "")
	assert_eq(MusicRules.ambient_track(null), "")


func test_village_ambient_exists() -> void:
	assert_eq(MusicRules.village_ambient(), MusicRules.VILLAGE_AMBIENT)


func test_ambient_streams_loop_over_the_whole_file() -> void:
	for track: String in BIOMES.values() + [MusicRules.VILLAGE_AMBIENT]:
		var stream := MusicRules.load_stream(track, MusicRules.AMBIENT_DIR) as AudioStreamWAV
		assert_not_null(stream, track)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, track)
		assert_almost_eq(stream.loop_end / float(stream.mix_rate), stream.get_length(), 0.01, track)
		assert_between(stream.get_length(), 30.0, 90.0, track)
