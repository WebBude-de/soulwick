class_name SideDust
extends Node2D
## A dust effect of the side view (M5 round 2, pixel art since FS1/D-218): a puff at a take-off, a
## cloud at a landing, a ring and sparks at a double jump, crumbs at a wall slide, chips thrown up
## by a hard landing, a pop of pixels all around (a coin taken, an enemy stomped). Delivered strips are played when they exist (art/effects/side_<kind>_<n>f.png,
## SPRITES_V13 D2); until then the effect is drawn here from a few pixel clumps on the art-pixel grid
## (SidePixels: hard edges, stepped fade, sizes in whole art pixels) and frees itself. The clumps
## follow fixed patterns (no random numbers: the same on every machine). Look only, no gameplay.

enum Kind { PUFF, CLOUD, RING, SLIDE, SPARKS, CHIPS, POP }

const ART := {
	Kind.PUFF: ["res://art/effects/side_jump_puff_4f.png", Vector2i(32, 16), Vector2(16, 16)],
	Kind.CLOUD: ["res://art/effects/side_land_dust_5f.png", Vector2i(48, 16), Vector2(24, 16)],
	Kind.RING: ["res://art/effects/side_double_jump_ring_5f.png", Vector2i(32, 16), Vector2(16, 8)],
	Kind.SLIDE: ["res://art/effects/side_wall_dust_3f.png", Vector2i(16, 16), Vector2(8, 8)],
}
## TESTWERTE (look): seconds each effect lives.
const LIFETIME := {Kind.PUFF: 0.3, Kind.CLOUD: 0.42, Kind.RING: 0.3, Kind.SLIDE: 0.25, Kind.SPARKS: 0.34, Kind.CHIPS: 0.45, Kind.POP: 0.38}
const COLOR := Color(0.86, 0.83, 0.92, 0.9)
## Darker pixels in a clump (its lower side) so the dust reads as a shape, not a blob.
const SHADE := 0.72
const SPARK_COLOR := Color(1.0, 0.94, 0.72)
const SPARK_HOT := Color(1.0, 0.68, 0.3)
const CHIP_COLOR := Color(0.5, 0.46, 0.58)
## Ring of the double jump: start and end radius (art px), flattening.
const RING_RADIUS_PX := Vector2(4.0, 15.0)
const RING_SQUASH := 0.35

var kind := Kind.PUFF
## 0..1: how strong (cloud size after a hard landing).
var strength := 0.5
## +1 / -1: which way the body moved (a puff kicks more dust against it; the side of the wall for
## slide crumbs), 0: no side.
var direction := 0.0
var color := COLOR

var _age := 0.0
var _life := 0.3
var _clumps: Array[Clump] = []


## One pixel clump: where it starts, how it flies, how big it is (art px).
class Clump:
	extends RefCounted
	var start := Vector2.ZERO
	var velocity := Vector2.ZERO
	## Velocity loss per second (exponential) and pull down (px/s²).
	var drag := 6.0
	var gravity := 0.0
	var size_px := 1
	## Shrinks to one pixel over its life.
	var shrinks := true
	## Draws a one-pixel tail against its flight (sparks).
	var tail := false
	var color := Color.WHITE

	func _init(at: Vector2, speed: Vector2, pixels: int, tint: Color) -> void:
		start = at
		velocity = speed
		size_px = pixels
		color = tint

	func position_at(age: float) -> Vector2:
		var travel := velocity * (1.0 - exp(-drag * age)) / drag if drag > 0.0 else velocity * age
		return start + travel + Vector2(0.0, 0.5 * gravity * age * age)


## Spawns dust at a global point under parent. Returns the node (tests). tint replaces the dust
## colour of a drawn effect when its alpha is above zero.
static func spawn(parent: Node, at: Vector2, dust_kind: Kind, dust_strength := 0.5, drift := 0.0,
		tint := Color(0, 0, 0, 0)) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var art: Array = ART.get(dust_kind, [])
	if not art.is_empty() and ResourceLoader.exists(art[0]):
		var texture := load(art[0]) as Texture2D
		var frame_size: Vector2i = art[1]
		var frames := maxi(1, texture.get_width() / frame_size.x)
		var fps := frames / float(LIFETIME[dust_kind])
		var effect_scale := Vector2.ONE * SpriteStrip.PIXEL_SCALE * (0.8 + dust_strength * 0.6)
		if drift < 0.0:
			effect_scale.x = -effect_scale.x
		return SpriteStrip.spawn_effect(parent, at, texture, frame_size, fps, art[2], effect_scale)
	var dust := SideDust.new()
	dust.kind = dust_kind
	dust.strength = clampf(dust_strength, 0.0, 1.0)
	dust.direction = signf(drift)
	if tint.a > 0.0:
		dust.color = tint
	parent.add_child(dust)
	dust.global_position = SidePixels.snap(at)
	return dust


func _ready() -> void:
	z_index = 2
	_life = LIFETIME[kind]
	_clumps = _make_clumps()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	queue_redraw()


## The clumps of this effect (tests).
func get_clumps() -> Array[Clump]:
	return _clumps


func _draw() -> void:
	var t := clampf(_age / _life, 0.0, 1.0)
	if kind == Kind.RING:
		_draw_ring(t)
	for clump in _clumps:
		var tint := clump.color
		tint.a = SidePixels.fade(tint.a, t)
		var size := clump.size_px
		if clump.shrinks:
			size = maxi(1, ceili(clump.size_px * (1.0 - t)))
		var at := clump.position_at(_age)
		if size == 1:
			SidePixels.dot(self, at, tint)
		else:
			SidePixels.disc(self, at, size * SidePixels.PIXEL * 0.5, tint)
		if clump.tail and clump.velocity.length() > 1.0:
			var back := clump.position_at(maxf(0.0, _age - 0.03))
			SidePixels.line(self, back, at, Color(tint, tint.a * 0.6))


## The double jump's ring: a flat pixel ellipse growing in whole art pixels.
func _draw_ring(t: float) -> void:
	var grow := 1.0 - pow(1.0 - t, 2.0)
	var radius_px := roundf(lerpf(RING_RADIUS_PX.x, RING_RADIUS_PX.y + 4.0 * strength, grow))
	var tint := color
	tint.a = SidePixels.fade(color.a, t)
	SidePixels.ring(self, Vector2.ZERO, radius_px * SidePixels.PIXEL, tint, 1, RING_SQUASH)


func _make_clumps() -> Array[Clump]:
	var shade := Color(color.darkened(1.0 - SHADE), color.a)
	var clumps: Array[Clump] = []
	match kind:
		Kind.PUFF:
			# Two clumps to each side, the one against the run kicked further; two specks rise.
			for side: float in [-1.0, 1.0]:
				var kick := 1.0 - 0.4 * side * direction
				clumps.append(Clump.new(Vector2(side * 6.0, -2.0), Vector2(side * 120.0 * kick, -30.0), 3, color))
				clumps.append(Clump.new(Vector2(side * 10.0, 0.0), Vector2(side * 70.0 * kick, -10.0), 2, shade))
			clumps.append(Clump.new(Vector2(-4.0, -4.0), Vector2(-20.0, -70.0), 1, color))
			clumps.append(Clump.new(Vector2(4.0, -6.0), Vector2(25.0, -55.0), 1, color))
		Kind.CLOUD:
			var reach := 0.6 + strength
			var big := 2 + roundi(2.0 * strength)
			for side: float in [-1.0, 1.0]:
				clumps.append(Clump.new(Vector2(side * 8.0, -2.0), Vector2(side * 190.0 * reach, -24.0), big, color))
				clumps.append(Clump.new(Vector2(side * 4.0, -4.0), Vector2(side * 110.0 * reach, -46.0), big - 1, color))
				clumps.append(Clump.new(Vector2(side * 12.0, 0.0), Vector2(side * 250.0 * reach, -6.0), 2, shade))
				clumps.append(Clump.new(Vector2(side * 2.0, -6.0), Vector2(side * 50.0 * reach, -90.0 * reach), 1, color))
		Kind.RING:
			# Specks thrown off the ring's edge (the ring itself is drawn in _draw_ring).
			for i in 6:
				var angle := TAU * (i + 0.5) / 6.0
				var out := Vector2(cos(angle), sin(angle) * RING_SQUASH)
				clumps.append(Clump.new(out * 10.0, out * 170.0, 1, color))
		Kind.SPARKS:
			# A fan of sparks under the feet (the second jump pushes off the air), two flying up.
			for i in 7:
				var angle := lerpf(deg_to_rad(20.0), deg_to_rad(160.0), i / 6.0)
				var speed := 150.0 + 60.0 * float(i % 3)
				var spark := Clump.new(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * speed, 1, SPARK_COLOR if i % 2 == 0 else SPARK_HOT)
				spark.gravity = 260.0
				spark.drag = 4.0
				spark.shrinks = false
				spark.tail = true
				clumps.append(spark)
			for side: float in [-1.0, 1.0]:
				var rising := Clump.new(Vector2(side * 6.0, -8.0), Vector2(side * 40.0, -120.0), 1, SPARK_COLOR)
				rising.shrinks = false
				clumps.append(rising)
		Kind.SLIDE:
			for i in 2:
				var crumb := Clump.new(Vector2(0.0, 4.0 * i), Vector2(-direction * (30.0 + 20.0 * i), 10.0), 2 - i, color)
				crumb.gravity = 220.0
				clumps.append(crumb)
		Kind.CHIPS:
			# Rock chips knocked up by a hard landing: thrown out and up, falling back.
			for i in 6:
				var side := -1.0 if i % 2 == 0 else 1.0
				var step := floorf(i / 2.0)
				var chip := Clump.new(Vector2(side * (6.0 + 6.0 * step), -2.0),
						Vector2(side * (60.0 + 45.0 * step), -(200.0 - 30.0 * step) * (0.7 + 0.5 * strength)),
						2 if i < 2 else 1, CHIP_COLOR)
				chip.gravity = 900.0
				chip.drag = 1.5
				chip.shrinks = false
				clumps.append(chip)
		Kind.POP:
			# Pixels flying out all around, a little upwards, falling back.
			for i in 10:
				var angle := TAU * i / 10.0 + 0.3
				var speed := (130.0 + 50.0 * float(i % 3)) * (0.6 + strength * 0.6)
				var bit := Clump.new(Vector2.ZERO, Vector2(cos(angle), sin(angle) - 0.4) * speed, 2 if i % 2 == 0 else 1, color)
				bit.gravity = 320.0
				bit.drag = 5.0
				clumps.append(bit)
	return clumps
