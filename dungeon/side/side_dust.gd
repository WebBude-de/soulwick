class_name SideDust
extends Node2D
## A dust effect of the side view (M5 round 2): a puff at a take-off, a cloud at a landing, a ring
## under a double jump, crumbs at a wall slide. Delivered strips are played when they exist
## (art/effects/side_<kind>_<n>f.png, see the round 2 report); until then the dust is drawn here
## (placeholder) and frees itself. Look only, no gameplay.

enum Kind { PUFF, CLOUD, RING, SLIDE }

const ART := {
	Kind.PUFF: ["res://art/effects/side_jump_puff_4f.png", Vector2i(32, 16), Vector2(16, 16)],
	Kind.CLOUD: ["res://art/effects/side_land_dust_5f.png", Vector2i(48, 16), Vector2(24, 16)],
	Kind.RING: ["res://art/effects/side_double_jump_ring_5f.png", Vector2i(32, 16), Vector2(16, 8)],
	Kind.SLIDE: ["res://art/effects/side_wall_dust_3f.png", Vector2i(16, 16), Vector2(8, 8)],
}
const LIFETIME := {Kind.PUFF: 0.28, Kind.CLOUD: 0.4, Kind.RING: 0.32, Kind.SLIDE: 0.25}
const COLOR := Color(0.86, 0.83, 0.92, 0.85)

var kind := Kind.PUFF
## 0..1: how strong (cloud size after a hard landing).
var strength := 0.5
## +1 / -1: which way the dust drifts (puff, slide).
var direction := 1.0
var color := COLOR

var _age := 0.0
var _life := 0.3


## Spawns dust at a global point under parent. Returns the node (tests).
static func spawn(parent: Node, at: Vector2, dust_kind: Kind, dust_strength := 0.5, drift := 1.0) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var art: Array = ART[dust_kind]
	if ResourceLoader.exists(art[0]):
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
	dust.direction = signf(drift) if drift != 0.0 else 1.0
	parent.add_child(dust)
	dust.global_position = at
	return dust


func _ready() -> void:
	z_index = 2
	_life = LIFETIME[kind]


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / _life, 0.0, 1.0)
	var fade := color
	fade.a = color.a * (1.0 - t)
	match kind:
		Kind.PUFF:
			for i in 3:
				var side := -1.0 if i == 0 else 1.0
				var offset := Vector2(side * (6.0 + 22.0 * t) * (1.0 if i < 2 else 0.4), -3.0 - 6.0 * t * float(i))
				draw_circle(offset, 5.0 * (1.0 - t * 0.5), fade)
		Kind.CLOUD:
			var spread := 18.0 + 30.0 * strength
			for i in 6:
				var side := -1.0 if i % 2 == 0 else 1.0
				var step := float(i / 2 + 1) / 3.0
				var offset := Vector2(side * spread * step * (0.4 + t), -4.0 - 10.0 * t * step)
				draw_circle(offset, (4.0 + 5.0 * strength) * (1.0 - t * 0.6), fade)
		Kind.RING:
			var radius := 8.0 + 26.0 * t
			var points := PackedVector2Array()
			for i in 25:
				var angle := TAU * i / 24.0
				points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.35))
			draw_polyline(points, fade, 3.0 * (1.0 - t) + 1.0)
		Kind.SLIDE:
			for i in 2:
				draw_circle(Vector2(-direction * 4.0 * t * float(i + 1), 8.0 * t + 4.0 * i), 2.5 * (1.0 - t), fade)
