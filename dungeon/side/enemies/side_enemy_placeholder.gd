class_name SideEnemyPlaceholder
extends Node2D
## Drawn stand-in for a newer side enemy until its art from SPRITES_V13 §B10 lies in art/ (SV4): a
## bat with flapping wings, a spike hedgehog whose spikes always point up (bristling when a stomp is
## refused), the shield of a shield bearer in front of its skeleton body. Drawn in 32-px frame
## pixels, scaled like the sprites; the origin is the feet. Every shape is filled on whole frame
## pixels (SidePixels on the world grid, D-218). Telegraph rule: the spikes and the shield
## are the readable reasons why a stomp or a run into it does not work.

enum Look { BAT, SPIKE_HEDGEHOG, SHIELD }

const OUTLINE := Color("1c1a2b")
const BAT_BODY := Color("4b3b6e")
const BAT_WING := Color("6a55a0")
const HEDGEHOG_BODY := Color("8a5a3c")
const HEDGEHOG_BELLY := Color("d9b48a")
const SPIKE := Color("e9e4d2")
const SHIELD_FACE := Color("6f86a8")
const SHIELD_RIM := Color("c9cfdb")
const EYE := Color("f2cf4a")
const FLAP_SPEED := 14.0
const BRISTLE_TIME := 0.35

var look := Look.BAT
var facing := 1.0

var _time := 0.0
var _bristle_left := 0.0


func _ready() -> void:
	scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE


## The hedgehog's spikes stand out longer for a moment (refused stomp).
func bristle() -> void:
	_bristle_left = BRISTLE_TIME
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_bristle_left = maxf(0.0, _bristle_left - delta)
	if look == Look.BAT or _bristle_left > 0.0:
		queue_redraw()


func _draw() -> void:
	# The node is scaled like the sprites; SidePixels works in world px, so draw at half scale and
	# hand it world coordinates (W).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / SpriteStrip.PIXEL_SCALE)
	match look:
		Look.BAT:
			_draw_bat()
		Look.SPIKE_HEDGEHOG:
			_draw_hedgehog()
		Look.SHIELD:
			_draw_shield()


## Frame pixels -> world px of the unscaled drawing.
const W := Transform2D(0.0, Vector2.ONE * SpriteStrip.PIXEL_SCALE, 0.0, Vector2.ZERO)


func _draw_bat() -> void:
	var flap := roundf(sin(_time * FLAP_SPEED) * 2.0) * 0.5
	var center := Vector2(0, -5)
	for side in [-1.0, 1.0]:
		var tip := center + Vector2(side * 11.0, -4.0 - flap * 5.0)
		var wing := PackedVector2Array([center + Vector2(side * 2.0, -2.0), tip, center + Vector2(side * 9.0, 2.0 + flap * 2.0), center + Vector2(side * 3.0, 2.0)])
		SidePixels.polygon(self, W * wing, BAT_WING)
		SidePixels.polyline(self, W * (wing + PackedVector2Array([wing[0]])), OUTLINE)
	SidePixels.disc(self, W * center, 9.0, OUTLINE)
	SidePixels.disc(self, W * center, 7.0, BAT_BODY)
	SidePixels.dot(self, W * (center + Vector2(facing * 1.5, -0.5)), EYE)
	SidePixels.line(self, W * (center + Vector2(-2, -3)), W * (center + Vector2(-3, -6)), OUTLINE)
	SidePixels.line(self, W * (center + Vector2(2, -3)), W * (center + Vector2(3, -6)), OUTLINE)


func _draw_hedgehog() -> void:
	var length := 6.0 if _bristle_left > 0.0 else 4.0
	for i in 7:
		var angle := lerpf(-PI * 0.85, -PI * 0.15, i / 6.0)
		var base := Vector2(cos(angle) * 10.0, -5.0 + sin(angle) * 7.0)
		var tip := base + Vector2(cos(angle), sin(angle)) * length
		var side := Vector2(-sin(angle), cos(angle)) * 1.6
		SidePixels.polygon(self, W * PackedVector2Array([base - side, tip, base + side]), SPIKE)
	var body := PackedVector2Array()
	for i in 13:
		var angle := lerpf(PI, TAU, i / 12.0)
		body.append(Vector2(cos(angle) * 11.0, -1.0 + sin(angle) * 9.0))
	SidePixels.polygon(self, W * body, HEDGEHOG_BODY)
	SidePixels.polyline(self, W * body, OUTLINE)
	SidePixels.line(self, W * Vector2(-11, -1), W * Vector2(11, -1), OUTLINE)
	var snout := Vector2(facing * 10.0, -4.0)
	SidePixels.disc(self, W * snout, 5.0, HEDGEHOG_BELLY)
	SidePixels.dot(self, W * (snout + Vector2(facing * 2.0, 0)), OUTLINE)
	SidePixels.dot(self, W * Vector2(facing * 6.0, -6.0), OUTLINE)


func _draw_shield() -> void:
	var rect := Rect2(Vector2(facing * 7.0 - 4.0, -20.0), Vector2(8, 15))
	var world := Rect2(W * rect.position, rect.size * SpriteStrip.PIXEL_SCALE)
	SidePixels.rect(self, world.grow(SidePixels.PIXEL), OUTLINE)
	SidePixels.rect(self, world, SHIELD_FACE)
	SidePixels.frame(self, world, SHIELD_RIM)
	var middle := world.get_center()
	SidePixels.line(self, middle + Vector2(0, -10), middle + Vector2(0, 10), SHIELD_RIM)
