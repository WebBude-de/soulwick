class_name SideCoin
extends Node2D
## A coin on a jump arc of a side segment (M5); the golden coin sits at the hardest spot. Only the
## look lives here: SideSegment decides when a player touches it and pays the reward
## (SideRules.coin_gold, SideRules.golden_coin_gold); take() plays the pickup.

const TEXTURE: Texture2D = preload("res://art/environment/props/gold_coin_4f.png")
const FRAME := Vector2i(16, 16)
const FPS := 8.0
## Delivered later (SPRITES_V9); until then the normal coin, bigger and tinted.
const GOLDEN_ART_PATH := "res://art/environment/props/golden_coin_4f.png"
const GOLDEN_TINT := Color(1.5, 1.2, 0.6)
const PICKUP_RADIUS := 30.0
const GOLDEN_PICKUP_RADIUS := 36.0
const BOB_HEIGHT := 3.0
const COLOR := Color(1.0, 0.85, 0.35)
const GOLDEN_COLOR := Color(1.0, 0.8, 1.0)

var golden := false
var is_taken := false

var _sprite: AnimatedSprite2D = null
var _time := 0.0


func _ready() -> void:
	_time = fmod(position.x * 0.013, TAU)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	var texture := TEXTURE
	if golden and ResourceLoader.exists(GOLDEN_ART_PATH):
		texture = load(GOLDEN_ART_PATH) as Texture2D
	elif golden:
		_sprite.modulate = GOLDEN_TINT
	_sprite.sprite_frames = SpriteStrip.make_frames(texture, FRAME, FPS, true)
	_sprite.scale = Vector2.ONE * (2.5 if golden else 1.5)
	_sprite.play(&"default")
	add_child(_sprite)
	var glow := LightSource.new()
	glow.name = "Glow"
	glow.radius = 90.0 if golden else 46.0
	glow.intensity = 0.8 if golden else 0.55
	glow.flicker = 0.05
	add_child(glow)


func _process(delta: float) -> void:
	_time += delta
	if _sprite != null:
		_sprite.position.y = sin(_time * 3.0) * BOB_HEIGHT


func get_pickup_radius() -> float:
	return GOLDEN_PICKUP_RADIUS if golden else PICKUP_RADIUS


## Pickup look (burst, sound) and gone. false if it was taken already.
func take() -> bool:
	if is_taken:
		return false
	is_taken = true
	if is_inside_tree():
		# A pixel pop (D-218); the plain coin keeps the small light flash its burst had.
		SideDust.spawn(get_parent(), global_position, SideDust.Kind.POP, 1.0 if golden else 0.4, 0.0, GOLDEN_COLOR if golden else COLOR)
		if not golden and Burst.should_flash(8):
			LightSource.flash(get_parent(), global_position, Burst.flash_radius(140.0), 0.24, COLOR, Burst.FLASH_PEAK)
		Sfx.play_at(self, SideRules.SOUND_GOLDEN_COIN if golden else SideRules.SOUND_COIN, global_position, -3.0)
		if golden:
			LightSource.flash(get_parent(), global_position, 160.0, 0.5)
	queue_free()
	return true
