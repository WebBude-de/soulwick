class_name VillageRavens
extends Node2D
## Two ravens on the lintel of the dungeon ruin (R7, 06_dorf.md): they sit and peck now and then,
## fly up when any player comes near and come back once nobody has been close for a while.
## Art: art/environment/village/ravens_4f.png (4 × 32×16: sitting, pecking, wings up, wings down),
## drawn by VillagePlaceholders until it exists. Optional sound audio/sfx/ravens_fly.wav.
## Coop: every player in the "player" group counts. Pure optics, no gameplay.

enum State { SITTING, LEAVING, AWAY, RETURNING }

const ART := "ravens_4f"
const FRAMES := 4
const FRAME_SIZE := Vector2(32, 16)
## TESTWERT: a player this close (world px) scares them, they return when all are further away.
const SCARE_DISTANCE := 260.0
const RETURN_DISTANCE := 420.0
## TESTWERT: seconds away before they try to return, flight time, flight path (world px) and flap speed.
const AWAY_TIME := 7.0
const FLIGHT_TIME := 1.6
const FLIGHT := Vector2(300, -380)
const FLAP_FPS := 10.0
## A short peck every this many seconds while sitting.
const PECK_EVERY := 3.4
const PECK_TIME := 0.35
const SOUND: StringName = &"ravens_fly"

var state := State.SITTING

var _sprite: Sprite2D = null
var _home := Vector2.ZERO
## The perch is taken on the first frame: the village lifts its props (SortLift) after _ready.
var _home_known := false
var _time := 0.0
var _away_left := 0.0
var _tween: Tween = null


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = VillageArt.get_texture(ART)
	_sprite.hframes = FRAMES
	_sprite.scale = Vector2.ONE * VillageArt.SCALE
	# Feet (bottom row of the frame) on the node origin.
	_sprite.offset = Vector2(0, -FRAME_SIZE.y * 0.5)
	add_child(_sprite)


func _process(delta: float) -> void:
	_remember_home()
	_time += delta
	match state:
		State.SITTING:
			_sprite.frame = 1 if fmod(_time, PECK_EVERY) > PECK_EVERY - PECK_TIME else 0
			if is_player_near(SCARE_DISTANCE):
				take_off()
		State.LEAVING, State.RETURNING:
			_sprite.frame = 2 + int(_time * FLAP_FPS) % 2
		State.AWAY:
			_away_left -= delta
			if _away_left <= 0.0 and not is_player_near(RETURN_DISTANCE):
				land()


## True while any player is within distance of the perch.
func is_player_near(distance: float) -> bool:
	if not is_inside_tree():
		return false
	var perch := _perch_global()
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node2D
		if player != null and player.global_position.distance_to(perch) <= distance:
			return true
	return false


## Fly up and away (flapping, fading out).
func take_off() -> void:
	if state != State.SITTING:
		return
	_remember_home()
	state = State.LEAVING
	if ResourceLoader.exists(Sfx.SFX_DIR + String(SOUND) + ".wav"):
		Sfx.play_at(self, SOUND, global_position, -6.0)
	_restart_tween()
	_tween.tween_property(self, "position", _home + FLIGHT, FLIGHT_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, FLIGHT_TIME).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		state = State.AWAY
		_away_left = AWAY_TIME)


## Fly back in and land on the perch.
func land() -> void:
	if state != State.AWAY:
		return
	state = State.RETURNING
	position = _home + Vector2(-FLIGHT.x, FLIGHT.y)
	_restart_tween()
	_tween.tween_property(self, "position", _home, FLIGHT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, FLIGHT_TIME * 0.5)
	_tween.tween_callback(func() -> void: state = State.SITTING)


func _restart_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()


func _remember_home() -> void:
	if not _home_known:
		_home = position
		_home_known = true


## The perch in world coordinates (the node moves while flying).
func _perch_global() -> Vector2:
	_remember_home()
	var parent := get_parent() as Node2D
	return parent.to_global(_home) if parent != null else _home
