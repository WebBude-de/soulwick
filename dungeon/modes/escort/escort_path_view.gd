class_name EscortPathView
extends Node2D
## The visible way of the escort mode (design answer 03: "sein Pfad ist als Leuchtmarken auf dem
## Boden sichtbar"): glowing marks (escort_path_4f) on every tile of the villager's path, a floor
## overlay below all characters. Faint while the room waits behind its door, they light up one after
## the other when the room is entered (reveal), pulse gently and fade behind the villager as he walks
## (set_progress). Look only.

const ART_PATH := "res://art/environment/objectives/escort_path_4f.png"
const FRAME := Vector2i(32, 32)
const FRAMES := 4
const FPS := 4.0
## Floor overlay: above the floor tiles, below every character (like the crumbling plates).
const Z_INDEX := -9
## Seconds between two marks lighting up on reveal. TESTWERT
const REVEAL_STEP := 0.045
const PULSE_SPEED := 2.4
const WALKED_ALPHA := 0.18
## Before the room is entered: faintly visible through the open door.
const WAITING_ALPHA := 0.3
const FALLBACK_COLOR := Color(1.0, 0.82, 0.4, 0.8)

var tiles: Array[Vector2i] = []

var _marks: Array[CanvasItem] = []
## Marks done with their reveal fade (only those pulse).
var _lit: Array[bool] = []
## Index of the first mark still ahead of the villager.
var _ahead_from := 0
var _time := 0.0
var _revealed := false


## Builds one mark per path tile (room-local tiles; the node sits at the room origin).
func build(path_tiles: Array[Vector2i]) -> void:
	tiles = path_tiles.duplicate()
	z_index = Z_INDEX
	var texture: Texture2D = load(ART_PATH) as Texture2D if ResourceLoader.exists(ART_PATH) else null
	for i in tiles.size():
		var mark: CanvasItem = null
		if texture != null:
			var sprite := AnimatedSprite2D.new()
			sprite.sprite_frames = SpriteStrip.make_frames(texture, FRAME, FPS, true)
			sprite.centered = false
			sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
			sprite.position = RoomTiles.tile_to_local(tiles[i])
			sprite.frame = i % FRAMES
			sprite.play()
			mark = sprite
		else:
			var dot := Polygon2D.new()
			# A pixel diamond (D-218), not a smooth one.
			dot.polygon = PixelDraw.diamond_points(2)
			dot.color = FALLBACK_COLOR
			dot.position = RoomTiles.tile_center(tiles[i])
			mark = dot
		mark.name = "Mark%d" % i
		mark.modulate.a = WAITING_ALPHA
		add_child(mark)
		_marks.append(mark)
		_lit.append(false)


## The marks light up from the start to the exit (room entered, intro).
func reveal() -> void:
	if _revealed:
		return
	_revealed = true
	for i in _marks.size():
		var mark := _marks[i]
		if not is_inside_tree():
			mark.modulate.a = 1.0
			_lit[i] = true
			continue
		var tween := mark.create_tween()
		tween.tween_interval(i * REVEAL_STEP)
		tween.tween_property(mark, "modulate:a", 1.0, 0.25)
		tween.tween_callback(_set_lit.bind(i))


func is_revealed() -> bool:
	return _revealed


## The villager has passed this share of the way: marks behind him fade.
func set_progress(ratio: float) -> void:
	_ahead_from = clampi(floori(ratio * _marks.size()), 0, _marks.size())


func get_mark_count() -> int:
	return _marks.size()


## Visible marks ahead of the villager (tests).
func get_marks_ahead() -> int:
	return _marks.size() - _ahead_from


## All marks fade out (the villager is home or fell).
func fade_all(duration := 0.6) -> void:
	_ahead_from = _marks.size()
	for i in _marks.size():
		var mark := _marks[i]
		_lit[i] = false
		if is_inside_tree():
			mark.create_tween().tween_property(mark, "modulate:a", 0.0, duration)
		else:
			mark.modulate.a = 0.0


func _process(delta: float) -> void:
	if not _revealed:
		return
	_time += delta
	for i in range(_ahead_from, _marks.size()):
		if _lit[i]:
			_marks[i].modulate.a = 0.72 + 0.28 * sin(_time * PULSE_SPEED - i * 0.35)
	var walked_alpha := WALKED_ALPHA if _ahead_from < _marks.size() else 0.0
	for i in mini(_ahead_from, _marks.size()):
		_marks[i].modulate.a = move_toward(_marks[i].modulate.a, walked_alpha, delta * 1.5)


func _set_lit(index: int) -> void:
	if index >= 0 and index < _lit.size():
		_lit[index] = true
