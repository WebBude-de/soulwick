class_name MusicRules
extends RefCounted
## Pure choice of music and ambient beds (D-068, D-092): which file plays for a room type, biome
## and boss phase, with fallbacks when a file is missing. No nodes, unit-testable; MusicPlayer
## applies the result.
##
## Naming: audio/music/<BiomeData.music_track>[_intense], <BiomeData.boss_music_track>[_p2],
## audio/ambient/<BiomeData.ambient_track>. Own .ogg/.mp3 files win over the generated .wav.
## One-shot stingers (not looped): audio/music/<BiomeData.transition_track> when a biome is
## entered, <BiomeData.victory_track> when its boss falls.

## How a crossfade shapes the two gains.
enum FadeCurve {
	## sin/cos: constant power for two different pieces, never both at full volume.
	EQUAL_POWER,
	## Gains add up to 1: for two versions of the same piece at the same position.
	LINEAR,
}

const MUSIC_DIR := "res://audio/music/"
const AMBIENT_DIR := "res://audio/ambient/"
const EXTENSIONS: Array[String] = [".ogg", ".mp3", ".wav"]
const DUNGEON_FALLBACK := "dungeon"
const BOSS_FALLBACK := "boss"
const VILLAGE_TRACK := "village"
const VILLAGE_AMBIENT := "ambient_village"
## Champion rooms: same tempo and bars as the biome track, plus drums.
const INTENSE_SUFFIX := "_intense"
## Boss phase two: faster, extra percussion.
const PHASE_TWO_SUFFIX := "_p2"
## The last seconds of a transition stinger are only its reverb tail: the biome loop starts
## there, on the bar line after the stinger's last bar (generate_music.py renders it so).
const STINGER_TAIL := 1.5
## Gains below this count as silent (-60 dB).
const SILENT_GAIN := 0.001
## In RoomSequence.Biome order, like the spawner's biome list in room_base.tscn.
const BIOME_PATHS: Array[String] = [
	"res://dungeon/biomes/crypt.tres",
	"res://dungeon/biomes/slime_grotto.tres",
	"res://dungeon/biomes/shadow_realm.tres",
	"res://dungeon/biomes/ember_forge.tres",
]


static func biome_for_room(room_index: int) -> BiomeData:
	var index := int(RoomSequence.get_biome(maxi(1, room_index)))
	if index < 0 or index >= BIOME_PATHS.size() or not ResourceLoader.exists(BIOME_PATHS[index]):
		return null
	return load(BIOME_PATHS[index]) as BiomeData


## Path of a track in dir ("" if no file exists).
static func find_file(track: String, dir: String) -> String:
	if track.is_empty():
		return ""
	for extension in EXTENSIONS:
		var path := dir + track + extension
		if ResourceLoader.exists(path):
			return path
	return ""


## First candidate with a file in dir, "" if none exists.
static func first_existing(candidates: Array[String], dir: String) -> String:
	for track in candidates:
		if not find_file(track, dir).is_empty():
			return track
	return ""


## Music for a dungeon room. boss_phase only matters in boss rooms.
static func dungeon_track(biome: BiomeData, room_type: RoomSequence.RoomType, boss_phase := 1) -> String:
	if room_type == RoomSequence.RoomType.BOSS:
		return boss_track(biome, boss_phase)
	var base := biome.music_track if biome != null else ""
	var candidates: Array[String] = []
	if not base.is_empty():
		if room_type == RoomSequence.RoomType.MINIBOSS:
			candidates.append(base + INTENSE_SUFFIX)
		candidates.append(base)
	candidates.append(DUNGEON_FALLBACK)
	return first_existing(candidates, MUSIC_DIR)


## Boss music of a biome; phase two prefers "<track>_p2" and falls back to the phase-one track.
static func boss_track(biome: BiomeData, phase := 1) -> String:
	var base := biome.boss_music_track if biome != null else ""
	var candidates: Array[String] = []
	if not base.is_empty():
		if phase >= 2:
			candidates.append(base + PHASE_TWO_SUFFIX)
		candidates.append(base)
	if phase >= 2:
		candidates.append(BOSS_FALLBACK + PHASE_TWO_SUFFIX)
	candidates.append(BOSS_FALLBACK)
	return first_existing(candidates, MUSIC_DIR)


## Ambient bed of a biome, "" for none (empty field or missing file).
static func ambient_track(biome: BiomeData) -> String:
	if biome == null or find_file(biome.ambient_track, AMBIENT_DIR).is_empty():
		return ""
	return biome.ambient_track


static func village_ambient() -> String:
	return VILLAGE_AMBIENT if not find_file(VILLAGE_AMBIENT, AMBIENT_DIR).is_empty() else ""


## Stinger played when the biome is entered, "" for none (empty field or missing file).
static func transition_track(biome: BiomeData) -> String:
	if biome == null or find_file(biome.transition_track, MUSIC_DIR).is_empty():
		return ""
	return biome.transition_track


## Stinger played when the biome's boss is defeated, "" for none.
static func victory_track(biome: BiomeData) -> String:
	if biome == null or find_file(biome.victory_track, MUSIC_DIR).is_empty():
		return ""
	return biome.victory_track


## Seconds after a transition stinger starts at which the loop comes in (end of its last bar).
static func stinger_entry_time(stinger_length: float) -> float:
	return maxf(0.0, stinger_length - STINGER_TAIL)


## True for a biome track and its champion version: same tempo and bars, so a crossfade can
## keep the playback position.
static func shares_timeline(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return a + INTENSE_SUFFIX == b or b + INTENSE_SUFFIX == a


## Crossfade shape between two tracks: linear for the same piece (champion version, so the sum
## stays level), equal power otherwise (no dip, no two tracks at full volume).
static func fade_curve(from_track: String, to_track: String) -> FadeCurve:
	return FadeCurve.LINEAR if shares_timeline(from_track, to_track) else FadeCurve.EQUAL_POWER


## Gain at progress t (0..1) of a fade from start_gain to target_gain (linear gains 0..1).
## Equal power rises with sin and falls with cos, so a crossfade keeps sin^2 + cos^2 = 1.
static func fade_gain(start_gain: float, target_gain: float, t: float, curve: FadeCurve) -> float:
	var x := clampf(t, 0.0, 1.0)
	if target_gain >= start_gain:
		var rise := sin(x * PI * 0.5) if curve == FadeCurve.EQUAL_POWER else x
		return start_gain + (target_gain - start_gain) * rise
	var fall := cos(x * PI * 0.5) if curve == FadeCurve.EQUAL_POWER else 1.0 - x
	return target_gain + (start_gain - target_gain) * fall


## Volume in dB for a linear gain on top of level_db (silent below SILENT_GAIN).
static func gain_to_db(gain: float, level_db := 0.0, silent_db := -60.0) -> float:
	if gain <= SILENT_GAIN:
		return silent_db
	return maxf(silent_db, level_db + linear_to_db(gain))


## Loads a track as a looping stream (null if no file exists); loop = false for stingers.
static func load_stream(track: String, dir: String, loop := true) -> AudioStream:
	var path := find_file(track, dir)
	if path.is_empty():
		return null
	var stream := load(path) as AudioStream
	if loop:
		make_loop(stream)
	else:
		make_one_shot(stream)
	return stream


## Plays the file once (stingers), whatever the import says.
static func make_one_shot(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false


## Loops the whole file unless the import already defines a loop.
static func make_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# Frames from the length: data.size() counts bytes, which for compressed imports
		# (QOA, the default) is far less than the frame count and cut the loop short.
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
