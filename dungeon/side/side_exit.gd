class_name SideExit
extends Node2D
## The door at the end of a side segment (M5): frame and leaf of the biome's door, a warm light, the
## leaf swings open when a player comes close. The origin is the floor line under the door.
## SideSegment decides when a player walks in (is_entered_by).
## Round 3 ("Ausgang klar erkennbar"): a beam of light over the doorway, golden motes rising in it
## and a slow pulse of the door light, so the way out reads from afar; it brightens once open. Beam
## and motes are pixel art (D-218): the beam fades upwards in hard bands, the motes are squares of
## one art pixel fading in steps; the door light itself is the light system's (soft).

const DOORS_DIR := "res://art/environment/doors/"
const FALLBACK_BIOME := &"crypt"
const FRAME_PIVOT := Vector2(24, 48)
const LEAF_FRAME := Vector2i(32, 32)
const LEAF_PIVOT := Vector2(16, 32)
const OPEN_DISTANCE := 190.0
const ENTER_DISTANCE := 26.0
const ENTER_HEIGHT := 40.0
## Beacon (TESTWERTE, look): beam size, colour, pulse.
const BEAM_SIZE := Vector2(72.0, 260.0)
const BEAM_COLOR := Color(1.0, 0.85, 0.5)
const BEAM_ALPHA := 0.16
const PULSE_SPEED := 2.2
const PULSE_DEPTH := 0.2
## Hard bands of the beam from the floor upwards (TESTWERT).
const BEAM_BANDS := 5

var biome_id: StringName = FALLBACK_BIOME
var is_open := false

var _leaf: AnimatedSprite2D = null
var _glow: LightSource = null
var _time := 0.0


func _ready() -> void:
	z_index = -2
	_build_door()
	_glow = LightSource.new()
	_glow.name = "Glow"
	_glow.radius = 170.0
	_glow.intensity = 0.8
	_glow.flicker = 0.04
	_glow.position = Vector2(0, -48)
	add_child(_glow)
	var motes := CPUParticles2D.new()
	motes.name = "Motes"
	motes.amount = 10
	motes.lifetime = 2.2
	motes.preprocess = 2.2
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(BEAM_SIZE.x * 0.35, 6.0)
	motes.position = Vector2(0, -8)
	motes.direction = Vector2(0, -1)
	motes.spread = 8.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 30.0
	motes.initial_velocity_max = 60.0
	motes.scale_amount_min = SidePixels.PIXEL
	motes.scale_amount_max = SidePixels.PIXEL
	var ramp := Gradient.new()
	ramp.set_color(0, Color(BEAM_COLOR, 0.0))
	ramp.set_color(1, Color(BEAM_COLOR, 0.0))
	ramp.add_point(0.25, Color(BEAM_COLOR, 0.9))
	ramp.add_point(0.7, Color(BEAM_COLOR, 0.45))
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	motes.color_ramp = ramp
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = additive
	add_child(motes)


func _build_door() -> void:
	var frame_texture := _texture("door_frame_%s.png")
	if frame_texture != null:
		var frame := Sprite2D.new()
		frame.name = "Frame"
		frame.texture = frame_texture
		frame.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		frame.offset = SpriteStrip.pivot_offset(Vector2i(frame_texture.get_size()), FRAME_PIVOT)
		add_child(frame)
	var leaf_texture := _texture("door_%s_open_4f.png")
	if leaf_texture != null:
		_leaf = AnimatedSprite2D.new()
		_leaf.name = "Leaf"
		_leaf.sprite_frames = SpriteStrip.make_frames(leaf_texture, LEAF_FRAME, 8.0, false)
		_leaf.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_leaf.offset = SpriteStrip.pivot_offset(LEAF_FRAME, LEAF_PIVOT)
		_leaf.frame = 0
		add_child(_leaf)


func _process(delta: float) -> void:
	_time += delta
	if _glow != null:
		_glow.intensity = (1.0 if is_open else 0.8) * (1.0 - PULSE_DEPTH * 0.5 + PULSE_DEPTH * 0.5 * sin(_time * PULSE_SPEED))
	queue_redraw()


## The beam: brightest at the floor, fading upwards in hard bands, a little stronger once open (the
## pulse moves in steps too).
func _draw() -> void:
	var half := BEAM_SIZE.x * 0.5
	var pulse := roundf(sin(_time * PULSE_SPEED) * 2.0) * 0.5
	var alpha := BEAM_ALPHA * (1.6 if is_open else 1.0) * (1.0 + 0.25 * pulse)
	var band_height := BEAM_SIZE.y / BEAM_BANDS
	for band in BEAM_BANDS:
		var bottom := -band * band_height
		var top := bottom - band_height
		var wide := lerpf(half, half * 0.6, float(band) / BEAM_BANDS)
		var narrow := lerpf(half, half * 0.6, float(band + 1) / BEAM_BANDS)
		var color := Color(BEAM_COLOR, alpha * (1.0 - float(band) / BEAM_BANDS))
		SidePixels.polygon(self, PackedVector2Array([Vector2(-wide, bottom), Vector2(wide, bottom), Vector2(narrow, top), Vector2(-narrow, top)]), color)


## Opens once (look and sound).
func open() -> void:
	if is_open:
		return
	is_open = true
	if _leaf != null:
		_leaf.play(&"default")
	if is_inside_tree():
		Sfx.play_at(self, SideRules.SOUND_DOOR, global_position, -4.0)


func is_near(feet: Vector2) -> bool:
	return feet.distance_to(global_position) <= OPEN_DISTANCE


## A player whose feet stand in the doorway walks through.
func is_entered_by(feet: Vector2) -> bool:
	return absf(feet.x - global_position.x) <= ENTER_DISTANCE and absf(feet.y - global_position.y) <= ENTER_HEIGHT


func _texture(pattern: String) -> Texture2D:
	for biome in [biome_id, FALLBACK_BIOME]:
		var path := DOORS_DIR + pattern % biome
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null
