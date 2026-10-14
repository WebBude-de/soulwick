class_name FountainSound
extends AudioStreamPlayer2D
## The fountain on the village square babbles (R7, 06_dorf.md): a quiet positional loop, heard only
## near the fountain. Uses audio/ambient/fountain.(ogg|wav) once that file exists; until then a
## short loop is synthesised once per session (soft filtered noise and small droplets, fixed seed).
## Ambient bed: bus Music like the other ambience (D-097). Pure optics/audio.

const FILES: Array[String] = ["res://audio/ambient/fountain.ogg", "res://audio/ambient/fountain.wav"]
const BUS: StringName = &"Music"
## TESTWERT: loudness and how far it carries (world px).
const VOLUME_DB := -12.0
const DISTANCE := 560.0
## Synthesised loop: sample rate, length (s), droplets per loop.
const MIX_RATE := 22050
const LOOP_SECONDS := 3.0
const DROPLETS := 26
const SEED := 9013

static var _synth: AudioStreamWAV = null


func _ready() -> void:
	stream = load_stream()
	bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
	volume_db = VOLUME_DB
	max_distance = DISTANCE
	attenuation = 1.6
	if stream != null and not DisplayServer.get_name() == "headless":
		play()


## The delivered file if there is one, else the synthesised loop.
static func load_stream() -> AudioStream:
	for path in FILES:
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return synthesize()


## Babbling water: low-passed noise with a slow swell and short rising "plinks". Loops seamlessly
## (noise has no phase; droplets end before the loop point).
static func synthesize() -> AudioStreamWAV:
	if _synth != null:
		return _synth
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var count := int(MIX_RATE * LOOP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var band := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var white := rng.randf_range(-1.0, 1.0)
		low += 0.18 * (white - low)
		band += 0.5 * (low - band)
		var swell := 0.75 + 0.25 * sin(TAU * t / LOOP_SECONDS) * sin(TAU * 3.0 * t / LOOP_SECONDS)
		samples[i] = (low - band * 0.6) * 0.55 * swell
	for d in DROPLETS:
		var start := rng.randi_range(0, count - int(MIX_RATE * 0.06) - 1)
		var pitch := rng.randf_range(700.0, 1900.0)
		var loud := rng.randf_range(0.06, 0.16)
		var length := int(MIX_RATE * rng.randf_range(0.025, 0.05))
		var phase := 0.0
		for k in length:
			var progress := float(k) / length
			phase += TAU * pitch * (1.0 + progress * 0.8) / MIX_RATE
			samples[start + k] += sin(phase) * loud * (1.0 - progress) * (1.0 - progress)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	_synth = wav
	return wav
