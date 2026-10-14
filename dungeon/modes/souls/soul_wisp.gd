class_name SoulWisp
extends Node2D
## One soul light of "Seelen sammeln" (R4a, design answer 06: "jede Seele ist eine kleine türkise
## Lichtinsel"): floats over its fixed place, a thin ring around it shows the time it has left, the
## last second it flickers. Look only: SoulsMode advances its age, decides when it is taken or gone
## and calls take() / fade(). A preview wisp (intro) is fainter and never taken.
## The origin is the floor point of its place, so it sorts against the feet of the characters.

const ART_PATH := "res://art/environment/objectives/soul_wisp_4f.png"
const FADE_PATH := "res://art/environment/objectives/soul_wisp_fade_4f.png"
const FRAME := Vector2i(16, 16)
const PIVOT := Vector2(8, 14)
const FPS := 6.0
const COLOR := Color("#5ff2d0")
## Small teal light island (TESTWERT).
const LIGHT_RADIUS := 115.0
const PREVIEW_ALPHA := 0.45
## Floats this high over its place and bobs a little (px).
const HOVER := Vector2(0, -14)
const BOB := 3.0
const RING_RADIUS := 20.0
const FLICKER_TIME := 1.0

## Tile of its place (room-local).
var tile := Vector2i.ZERO
var lifetime := SoulsRules.SOUL_LIFETIME
var age := 0.0
var preview := false
var taken := false
var gone := false

var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _time := 0.0


func build(place: Vector2i, is_preview := false) -> void:
	tile = place
	preview = is_preview
	position = RoomTiles.tile_center(place) + Vector2(0, RoomTiles.TILE_WORLD * 0.25)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	var texture: Texture2D = load(ART_PATH) as Texture2D if ResourceLoader.exists(ART_PATH) else null
	if texture != null:
		_sprite.sprite_frames = SpriteStrip.make_frames(texture, FRAME, FPS, true, &"float")
		var fade_texture: Texture2D = load(FADE_PATH) as Texture2D if ResourceLoader.exists(FADE_PATH) else null
		if fade_texture != null:
			SpriteStrip.add_strip(_sprite.sprite_frames, &"fade", fade_texture, FRAME, FPS, false)
		_sprite.play(&"float")
	_sprite.offset = SpriteStrip.pivot_offset(FRAME, PIVOT)
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.position = HOVER
	add_child(_sprite)
	_light = LightSource.new()
	_light.name = "SoulLight"
	_light.radius = LIGHT_RADIUS * (0.6 if preview else 1.0)
	_light.intensity = 0.85
	_light.flicker = 0.05
	_light.color = COLOR
	_light.position = HOVER + Vector2(0, -10)
	_light.ground_offset = -_light.position
	add_child(_light)
	modulate.a = PREVIEW_ALPHA if preview else 1.0


func get_time_left() -> float:
	return maxf(0.0, lifetime - age)


func is_visible_soul() -> bool:
	return not taken and not gone and not preview


## Taken by a player: burst, sound, gone.
func take() -> void:
	if taken or gone:
		return
	taken = true
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + HOVER, COLOR, 18, 150.0, 0.5)
		LightSource.flash(get_parent(), global_position + HOVER, 150.0, 0.35)
		Sfx.play_at(self, &"soul_collect", global_position, -3.0)
	queue_free()


## Time is up for it: the fade strip, a soft sound, gone.
func fade() -> void:
	if taken or gone:
		return
	gone = true
	if not is_inside_tree():
		queue_free()
		return
	if not preview:
		Sfx.play_at(self, &"soul_fade", global_position, -8.0)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"fade"):
		_sprite.play(&"fade")
	var tween := create_tween().set_parallel()
	tween.tween_property(_light, "intensity", 0.0, 0.6)
	tween.tween_property(self, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(queue_free)


func _appear() -> void:
	if not is_inside_tree():
		return
	var scale_from := _sprite.scale * 0.3
	var scale_to := _sprite.scale
	_sprite.scale = scale_from
	create_tween().tween_property(_sprite, "scale", scale_to, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not preview:
		Burst.spawn(get_parent(), global_position + HOVER, COLOR, 8, 70.0, 0.4, 3.0)


func _enter_tree() -> void:
	if _sprite != null and age <= 0.0:
		_appear.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	if _sprite == null or gone:
		return
	_sprite.position = HOVER + Vector2(0, sin(_time * 3.0) * BOB)
	if not preview:
		var left := get_time_left()
		_sprite.visible = left > FLICKER_TIME or fmod(_time, 0.16) < 0.1
		queue_redraw()


## Ring of the time it has left.
func _draw() -> void:
	if preview or gone or taken:
		return
	var share := clampf(get_time_left() / lifetime, 0.0, 1.0)
	var center := HOVER + Vector2(0, -8)
	draw_arc(center, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * share, 32, Color(COLOR, 0.65), 2.0, true)
