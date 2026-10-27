class_name WallBreach
extends Node2D
## Look and sound of one opening in a wall (A5, R2): a gate (enemy_gate_4f, arena gates) or a
## breach (wall_breach_6f, wall rifts). Effects only: SpawnSource (R2, before ArenaWaves) decides
## when, this node shows it. The delivered art (SPRITES_V5 §2, pivots from art/environment/rooms/arena.json) is
## drawn for the north wall face and turned towards the room on the other walls; without the files
## the drawn version (cracks, hole, grate) is the fallback. Dust, stone chips, light and sound come
## on top.
## The node sits on the edge between wall and floor, local +y points into the room.

enum Mode { GATE, BREACH }

const BREACH_ART := "res://art/environment/rooms/wall_breach_6f.png"
## Breach in a cave's rock front (SPRITES_V9 §3, breach_cave_<biome>.json: same frames, pivot and
## speed as wall_breach_6f), fitted to the room rock (SoftPalette). %s = biome.
const BREACH_CAVE_ART := "res://art/environment/rooms/wall_breach_cave_%s_6f.png"
const GATE_ART := "res://art/environment/rooms/enemy_gate_4f.png"
const BREACH_FRAME := Vector2i(32, 48)
const GATE_FRAME := Vector2i(32, 32)
## Pivots and speeds from arena.json.
const BREACH_PIVOT := Vector2(16, 47)
const GATE_PIVOT := Vector2(16, 31)
const BREACH_FPS := 10.0
## Frames of wall_breach_6f: 0-1 cracks (telegraph), from 2 the hole opens, the last one stays.
const BREACH_CRACK_FRAMES := 2
## Light while the wall cracks and the flash when it breaks (px). TESTWERTE
const GLOW_RADIUS := 80.0
const GLOW_INTENSITY := 0.55
const FLASH_RADIUS := 150.0
const FLASH_TIME := 0.4
const GATE_CLOSE_DELAY := 0.6
## Gate warning (rattle): the grate jumps this far up and down every RATTLE_STEP seconds.
const RATTLE_OPENING := 0.2
const RATTLE_STEP := 0.1
const STONE_COLOR := Color("6b6275")
const STONE_LIGHT := Color("8d8498")
const DUST_COLOR := Color("a39a8a")
const HOLE_COLOR := Color("0b0910")
const CRACK_GLOW := Color(1.0, 0.62, 0.32)
const GATE_FRAME_COLOR := Color("2a2433")
const GATE_BAR_COLOR := Color("55525f")
## How far the drawn opening reaches into the wall (px): the north wall shows a 64 px high face,
## the side and south walls only a thin edge, so their openings sit right on that edge.
const NORTH_DEPTH := 58.0
const EDGE_DEPTH := 30.0
const HOLE_RADII := Vector2(22.0, 25.0)
const CRACK_COUNT := 6

var mode := Mode.BREACH
## 0 = intact wall, 1 = fully cracked (breach telegraph).
var crack := 0.0:
	set(value):
		crack = value
		_sync_art()
		queue_redraw()
## 0 = grate down, 1 = grate up (gate).
var opening := 0.0:
	set(value):
		opening = value
		_sync_art()
		queue_redraw()
var is_broken := false

var _sprite: AnimatedSprite2D = null
var _glow: LightSource = null
var _crack_angles: Array[float] = []
var _depth := NORTH_DEPTH
var _hole_centre := Vector2(0.0, -NORTH_DEPTH * 0.5)
var _rubble: Array[Vector2] = []
## Biome of a cave room (rock front instead of masonry), empty in masonry rooms.
var _cave_biome: StringName = &""


## mode_value: Mode; inward: unit direction from the wall into the room; look_seed only varies
## the drawn cracks (optics, not the dungeon RNG).
func setup(mode_value: Mode, inward: Vector2, look_seed: int, cave_biome: StringName = &"") -> void:
	mode = mode_value
	_cave_biome = cave_biome
	rotation = inward.angle() - PI * 0.5
	_depth = NORTH_DEPTH if inward.is_equal_approx(Vector2.DOWN) else EDGE_DEPTH
	_hole_centre = Vector2(0.0, -_depth * 0.5)
	var look := RandomNumberGenerator.new()
	look.seed = look_seed
	_crack_angles.clear()
	for i in CRACK_COUNT:
		_crack_angles.append(TAU * (float(i) + look.randf_range(-0.3, 0.3)) / CRACK_COUNT)
	_rubble.clear()
	for i in 5:
		_rubble.append(Vector2(look.randf_range(-24.0, 24.0), look.randf_range(3.0, 18.0)))
	_build_sprite()


## The wall starts to give way (breach) or the grate rattles up (gate) over duration seconds.
func telegraph(duration: float) -> void:
	_set_glow(true)
	var tween := create_tween()
	if mode == Mode.BREACH:
		tween.tween_property(self, "crack", 1.0, maxf(0.05, duration))
	else:
		Sfx.play_at(self, &"door_open_gate", global_position, -6.0)
		tween.tween_property(self, "opening", 1.0, maxf(0.05, duration))
	Burst.spawn(self, to_global(_hole_centre), DUST_COLOR, 6, 50.0, 0.6, 3.0)


## Gate warning of a spawn source (R2): the grate rattles in place and light shines through it for
## duration seconds; it only goes up with lift(). The source plays the sound.
func rattle(duration: float) -> void:
	_set_glow(true)
	var steps := maxi(2, roundi(duration / RATTLE_STEP))
	var tween := create_tween()
	for i in steps:
		tween.tween_property(self, "opening", RATTLE_OPENING if i % 2 == 0 else 0.0, duration / steps)


## The grate goes up quickly: an enemy steps out (R2).
func lift(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "opening", 1.0, maxf(0.05, duration))


## An enemy comes through. The first one breaks the wall: stones, dust, flash, sound, shake.
func burst(first_of_wave: bool) -> void:
	var centre := to_global(_hole_centre)
	if mode == Mode.BREACH and not is_broken:
		is_broken = true
		crack = 1.0
		Burst.spawn(self, centre, STONE_COLOR, 18, 260.0, 0.6, 5.0)
		Burst.spawn(self, centre, DUST_COLOR, 16, 120.0, 0.9, 6.0)
		LightSource.flash(self, centre, FLASH_RADIUS, FLASH_TIME)
		Sfx.play_at(self, &"crate_break", centre, 2.0)
		if first_of_wave:
			CameraShake.shake(self, 4.0)
		if _sprite != null:
			_sprite.visible = true
			_sprite.play(&"default")
			_sprite.frame = BREACH_CRACK_FRAMES
	else:
		Burst.spawn(self, centre, DUST_COLOR, 8, 90.0, 0.5, 4.0)
	_set_glow(false)


## Gate: the grate goes down again once the wave is out. A breach stays open.
func settle() -> void:
	if mode != Mode.GATE:
		return
	var tween := create_tween()
	tween.tween_interval(GATE_CLOSE_DELAY)
	tween.tween_property(self, "opening", 0.0, 0.3)


## Does the breach use the cave art (a rock front)?
func is_cave_breach() -> bool:
	return mode == Mode.BREACH and _cave_biome != &"" and ResourceLoader.exists(BREACH_CAVE_ART % _cave_biome)


static func has_art(art_mode: Mode) -> bool:
	return ResourceLoader.exists(BREACH_ART if art_mode == Mode.BREACH else GATE_ART)


func _build_sprite() -> void:
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null
	if not has_art(mode):
		queue_redraw()
		return
	var breach := mode == Mode.BREACH
	var frame_size := BREACH_FRAME if breach else GATE_FRAME
	var texture := load(BREACH_ART if breach else GATE_ART) as Texture2D
	if breach and _cave_biome != &"" and ResourceLoader.exists(BREACH_CAVE_ART % _cave_biome):
		var cave := SoftPalette.texture(BREACH_CAVE_ART % _cave_biome, _cave_biome)
		if cave != null:
			texture = cave
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Art"
	_sprite.sprite_frames = SpriteStrip.make_frames(texture, frame_size, BREACH_FPS, false)
	# Pivot on the wall foot: the picture covers the wall face and its upper edge.
	_sprite.offset = SpriteStrip.pivot_offset(frame_size, BREACH_PIVOT if breach else GATE_PIVOT)
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(_sprite)
	_sync_art()


## Delivered art shows the state by frame instead of the drawn placeholder.
func _sync_art() -> void:
	if _sprite == null:
		return
	var count := _sprite.sprite_frames.get_frame_count(&"default")
	if mode == Mode.BREACH:
		if is_broken:
			# burst() plays the rest of the strip, the last frame stays.
			return
		_sprite.visible = crack > 0.0
		_sprite.frame = clampi(floori(crack * BREACH_CRACK_FRAMES), 0, BREACH_CRACK_FRAMES - 1)
	else:
		_sprite.frame = clampi(roundi(opening * (count - 1)), 0, count - 1)


func _set_glow(on: bool) -> void:
	if on and _glow == null:
		_glow = LightSource.new()
		_glow.name = "Glow"
		_glow.radius = GLOW_RADIUS
		_glow.intensity = GLOW_INTENSITY
		_glow.flicker = 0.12
		_glow.position = _hole_centre
		add_child(_glow)
	elif not on and _glow != null:
		var light := _glow
		_glow = null
		var tween := light.create_tween()
		tween.tween_property(light, "intensity", 0.0, 0.3)
		tween.tween_callback(light.queue_free)


func _draw() -> void:
	if _sprite != null:
		return
	if mode == Mode.GATE:
		_draw_gate()
	else:
		_draw_breach()


## Drawn stand-ins in pixel art (D-218, PixelDraw).
func _draw_gate() -> void:
	PixelDraw.rect(self, Rect2(-26.0, -_depth, 52.0, _depth), GATE_FRAME_COLOR)
	var inner := _depth - 7.0
	PixelDraw.rect(self, Rect2(-19.0, -inner, 38.0, inner), HOLE_COLOR)
	# Bars slide up into the wall while the gate opens.
	var bottom := lerpf(0.0, 3.0 - inner, opening)
	for i in 5:
		var x := -16.0 + i * 8.0
		PixelDraw.rect(self, Rect2(x - 2.0, -inner, 4.0, bottom + inner), GATE_BAR_COLOR)
	PixelDraw.rect(self, Rect2(-19.0, bottom - 4.0, 38.0, 4.0), GATE_BAR_COLOR)
	if opening > 0.0:
		PixelDraw.disc(self, _hole_centre + Vector2(0, 10), 10.0 * opening, Color(CRACK_GLOW, 0.25 * opening))


func _draw_breach() -> void:
	if is_broken:
		var radii := Vector2(HOLE_RADII.x, minf(HOLE_RADII.y, _depth * 0.5 + 4.0))
		PixelDraw.ellipse(self, _hole_centre, radii + Vector2(5, 5), STONE_LIGHT)
		PixelDraw.ellipse(self, _hole_centre, radii, HOLE_COLOR)
		for stone in _rubble:
			PixelDraw.rect(self, Rect2(stone, Vector2(6, 4)), STONE_COLOR)
			PixelDraw.rect(self, Rect2(stone + Vector2(2, -2), Vector2(2, 2)), STONE_LIGHT)
		return
	if crack <= 0.0:
		return
	# Cracks run out from the centre, glowing from behind.
	PixelDraw.disc(self, _hole_centre, 6.0 + 8.0 * crack, Color(CRACK_GLOW, 0.35 * crack))
	for angle in _crack_angles:
		var direction := Vector2.from_angle(angle)
		var middle := _hole_centre + direction * 16.0 * crack + direction.orthogonal() * 3.0
		var tip := _hole_centre + direction * 30.0 * crack
		PixelDraw.polyline(self, PackedVector2Array([_hole_centre, middle, tip]), Color(HOLE_COLOR, 0.85))
