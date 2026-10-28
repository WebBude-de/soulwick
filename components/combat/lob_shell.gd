class_name LobShell
extends Node2D
## Picture of a lobbed shot (the ember golem's lava ball, BossPressure): flies in an arc from the
## thrower to the landing point in the given time, with a ground shadow that grows as it comes down.
## Only a picture: the Blast it belongs to deals the damage on landing and frees it with itself.
## Code-drawn in pixel art (PixelDraw, D-218); art/projectiles/lava_ball_4f.png replaces the ball
## when present.

const ART_PATH := "res://art/projectiles/lava_ball_4f.png"
const ART_FRAME := Vector2i(16, 16)
const ART_FPS := 8.0
const ART_SCALE := 3.0
## Peak of the arc: this share of the distance, within the bounds (px).
const HEIGHT_SHARE := 0.4
const MIN_HEIGHT := 80.0
const MAX_HEIGHT := 220.0
const BALL_RADIUS := 9.0
const CRUST_COLOR := Color(0.25, 0.08, 0.04)
const GLOW_COLOR := Color(1.0, 0.42, 0.1)
const CORE_COLOR := Color(1.0, 0.85, 0.35)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
## Darker core of the ground shadow (share of its size).
const SHADOW_CORE := 0.6

var _start := Vector2.ZERO
var _end := Vector2.ZERO
var _duration := 1.0
var _height := MIN_HEIGHT
var _time := 0.0
var _lift := 0.0
var _sprite: AnimatedSprite2D = null


## Starts a shell under parent (it lives as long as the parent does).
static func launch(parent: Node, from: Vector2, to: Vector2, duration: float) -> LobShell:
	var shell := LobShell.new()
	shell._start = from
	shell._end = to
	shell._duration = maxf(0.05, duration)
	shell._height = clampf(from.distance_to(to) * HEIGHT_SHARE, MIN_HEIGHT, MAX_HEIGHT)
	shell.top_level = true
	shell.z_index = 6
	parent.add_child(shell)
	shell.global_position = from
	return shell


func _ready() -> void:
	var glow := LightSource.new()
	glow.radius = 46.0
	glow.intensity = 0.7
	add_child(glow)
	if ResourceLoader.exists(ART_PATH):
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteStrip.make_frames(load(ART_PATH) as Texture2D, ART_FRAME, ART_FPS, true)
		_sprite.scale = Vector2.ONE * ART_SCALE
		_sprite.play(&"default")
		add_child(_sprite)


## Share of the flight already done (0..1).
func get_progress() -> float:
	return clampf(_time / _duration, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var t := get_progress()
	global_position = PixelDraw.snap(_start.lerp(_end, t))
	_lift = sin(t * PI) * _height
	if _sprite != null:
		_sprite.position.y = -_lift
	queue_redraw()


func _draw() -> void:
	# Pixel art (D-218): a stepped ground shadow like DropShadow, a ball of whole art pixels.
	var shadow_scale := lerpf(1.0, 0.45, clampf(_lift / _height, 0.0, 1.0))
	var shadow := Vector2(1.0, 0.5) * BALL_RADIUS * 1.4 * shadow_scale
	PixelDraw.ellipse(self, Vector2.ZERO, shadow, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.6))
	PixelDraw.ellipse(self, Vector2.ZERO, shadow * SHADOW_CORE, SHADOW_COLOR)
	if _sprite != null:
		return
	var ball := Vector2(0.0, -_lift)
	PixelDraw.disc(self, ball, BALL_RADIUS + 3.0, Color(GLOW_COLOR, 0.35))
	PixelDraw.disc(self, ball, BALL_RADIUS, CRUST_COLOR)
	PixelDraw.disc(self, ball, BALL_RADIUS - 2.5, GLOW_COLOR)
	PixelDraw.disc(self, ball + Vector2(-2.0, -2.0), BALL_RADIUS * 0.4, CORE_COLOR)
