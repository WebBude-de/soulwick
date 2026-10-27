class_name SideLantern
extends Node2D
## A lantern of the jump trial (Laterne, Rücksetzpunkt, SV2, D-195, plan "L"): it stands on the
## ground before a hard stretch of a long plan and lights up when a player passes. Its cell is
## always a safe return spot (SideLayout.is_safe_spot), while the cells on and next to the elements
## after it are not, so whoever falls into a pit there comes back at the lantern (one heart, D-144)
## and sees where. Lighting is a look only: every machine lights it when it sees a player pass.
## The origin is the floor line in the middle of its cell. Art: checkpoint_lantern_2f.png (2 ×
## 16×32, pivot (8,31): off, on), else a drawn lantern.

## A player lit the lantern (once per segment).
signal lit(lantern: SideLantern, player: Player)

const ART_PATH := "res://art/environment/side/checkpoint_lantern_2f.png"
const ART_FRAME := Vector2i(16, 32)
const ART_PIVOT := Vector2(8, 31)
const SOUND := &"torch_ignite"
const GLOW_OFF := 0.12
const GLOW_ON := 0.7
const GLOW_COLOR := Color(1.0, 0.82, 0.45)
const FRAME_COLOR := Color(0.22, 0.2, 0.26)

var segment: SideSegment = null
var is_lit := false

var _sprite: Sprite2D = null
var _light: LightSource = null


func _ready() -> void:
	z_index = -2
	if ResourceLoader.exists(ART_PATH):
		_sprite = Sprite2D.new()
		_sprite.name = "Art"
		_sprite.texture = load(ART_PATH) as Texture2D
		_sprite.hframes = 2
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.offset = SpriteStrip.pivot_offset(ART_FRAME, ART_PIVOT)
		add_child(_sprite)
	_light = LightSource.new()
	_light.name = "Glow"
	_light.radius = 110.0
	_light.intensity = GLOW_OFF
	_light.flicker = 0.05
	_light.color = GLOW_COLOR
	_light.position = Vector2(0, -40)
	add_child(_light)


func _physics_process(_delta: float) -> void:
	if is_lit or segment == null:
		return
	for player in segment.get_players():
		if player.is_alive() and player.get_feet_position().distance_to(global_position) <= SideElementRules.LANTERN_REACH:
			light(player)
			return


## Lights the lantern (the look: frame, glow, sound).
func light(player: Player = null) -> void:
	if is_lit:
		return
	is_lit = true
	if _sprite != null:
		_sprite.frame = 1
	if _light != null:
		_light.intensity = GLOW_ON
	if is_inside_tree():
		Sfx.play_at(self, SOUND, global_position, -8.0)
	queue_redraw()
	lit.emit(self, player)


## Placeholder until checkpoint_lantern_2f.png: a post with a lantern, glowing when lit.
func _draw() -> void:
	if _sprite != null:
		return
	draw_rect(Rect2(-3.0, -60.0, 6.0, 60.0), FRAME_COLOR)
	draw_rect(Rect2(-12.0, -78.0, 24.0, 22.0), FRAME_COLOR)
	draw_rect(Rect2(-8.0, -74.0, 16.0, 14.0), GLOW_COLOR if is_lit else GLOW_COLOR.darkened(0.7))
