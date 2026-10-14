class_name Sfx
extends RefCounted
## Fire-and-forget sound effects from audio/sfx/<name>.wav (D-068). No autoload: every call creates
## a short-lived player next to the caller. World sounds pause with the game, UI sounds do not.

const SFX_DIR := "res://audio/sfx/"
## The same sound is not restarted more often than this (e.g. many coins at once).
const MIN_INTERVAL_MS := 40
const MAX_DISTANCE := 1500.0

static var _cache: Dictionary = {}
static var _last_played: Dictionary = {}


## Positional sound at a world position.
static func play_at(context: Node, sound: StringName, world_position: Vector2, volume_db := 0.0, pitch_variance := 0.08) -> void:
	var stream := _prepare(context, sound)
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.max_distance = MAX_DISTANCE
	player.attenuation = 1.2
	_start(context, player, stream, volume_db, pitch_variance)
	player.global_position = world_position


## Non-positional sound (UI, global events). Keeps playing while the game is paused.
static func play_ui(context: Node, sound: StringName, volume_db := 0.0) -> void:
	var stream := _prepare(context, sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	_start(context, player, stream, volume_db, 0.0)


static func _prepare(context: Node, sound: StringName) -> AudioStream:
	if context == null or not context.is_inside_tree():
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -100000)) < MIN_INTERVAL_MS:
		return null
	_last_played[sound] = now
	if not _cache.has(sound):
		var path := SFX_DIR + String(sound) + ".wav"
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	return _cache[sound]


static func _start(context: Node, player: Node, stream: AudioStream, volume_db: float, pitch_variance: float) -> void:
	player.set(&"stream", stream)
	player.set(&"bus", &"SFX")
	player.set(&"volume_db", volume_db)
	player.set(&"pitch_scale", 1.0 + randf_range(-pitch_variance, pitch_variance))
	var parent := context.get_tree().current_scene
	if parent == null:
		parent = context.get_tree().root
	parent.add_child(player)
	player.connect(&"finished", player.queue_free)
	player.call(&"play")
