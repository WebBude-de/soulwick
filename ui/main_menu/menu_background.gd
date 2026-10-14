class_name MenuBackground
extends Control
## Night scene behind the main menu (layout from art/ui/menu/menu.json): sky and ground as two
## parallax layers that follow the mouse a little, the lantern, the save's character in front of the
## dungeon entrance, drifting mist and flickering torch/lantern light. Purely decorative.
##
## Scene coordinates are art pixels of the 480×270 layout. The stage is scaled by a whole number
## (3 at 1280×720) so pixels stay even, and centred: on 16:9 a few art pixels are cropped at the edges.

const ART_SIZE := Vector2(480, 270)
const FAR_TEXTURE: Texture2D = preload("res://art/ui/menu/menu_bg_far.png")
const NEAR_TEXTURE: Texture2D = preload("res://art/ui/menu/menu_bg_near.png")
const LAMP_TEXTURE: Texture2D = preload("res://art/environment/buildings/lamp_post_4f.png")
const MIST_TEXTURE: Texture2D = preload("res://art/environment/props/abyss_mist_4f.png")

const LAMP_POSITION := Vector2(214, 106)
const LAMP_FRAMES := 4
const LAMP_FPS := 5.0
const HERO_POSITION := Vector2(236, 128)
## Weapon grip relative to the character frame (art/characters/player/player.json "weapon_hand").
const HERO_WEAPON_HAND := Vector2(19, 19)
## Resting weapon angle in radians (blade up and to the right).
const HERO_WEAPON_ANGLE := -0.9
const MIST_POSITIONS: Array[Vector2] = [Vector2(40, 236), Vector2(150, 214), Vector2(330, 236), Vector2(420, 200)]
const MIST_FRAMES := 4
const MIST_FPS := 3.0
const MIST_ALPHA := 0.6
## Mist drift to the right in art pixels per second; wraps around.
const MIST_DRIFT := 4.0
## Lights: centre (art px), colour, radius (art px), torch = strong flicker.
const LIGHTS: Array[Dictionary] = [
	{"position": Vector2(291, 134), "color": Color("#ff8a3c"), "radius": 16.0, "torch": true},
	{"position": Vector2(317, 134), "color": Color("#ff8a3c"), "radius": 16.0, "torch": true},
	{"position": Vector2(222, 114), "color": Color("#ffd166"), "radius": 30.0, "torch": false},
]
const LIGHT_ALPHA := 0.32
## Mouse parallax in art pixels at the screen edge: sky moves more than the ground.
const PARALLAX_FAR := 4.0
const PARALLAX_NEAR := 1.5
const PARALLAX_SMOOTHING := 4.0

var _stage: Node2D = null
var _far: Sprite2D = null
var _near_group: Node2D = null
var _lamp: Sprite2D = null
var _hero: AnimatedSprite2D = null
var _weapon: Sprite2D = null
var _mists: Array[Sprite2D] = []
var _lights: Array[Sprite2D] = []
var _time := 0.0
var _parallax := Vector2.ZERO
var _art_scale := 1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var sky := ColorRect.new()
	sky.color = UiKit.COLOR_BG
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	_stage = Node2D.new()
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_stage)
	_far = _sprite(FAR_TEXTURE)
	_stage.add_child(_far)
	_near_group = Node2D.new()
	_stage.add_child(_near_group)
	_near_group.add_child(_sprite(NEAR_TEXTURE))

	_lamp = _sprite(LAMP_TEXTURE, LAMP_FRAMES)
	_lamp.position = LAMP_POSITION
	_near_group.add_child(_lamp)

	_hero = AnimatedSprite2D.new()
	_hero.centered = false
	_hero.position = HERO_POSITION
	_near_group.add_child(_hero)
	_weapon = Sprite2D.new()
	_weapon.centered = false
	_weapon.position = HERO_POSITION + HERO_WEAPON_HAND
	_weapon.rotation = HERO_WEAPON_ANGLE
	_near_group.add_child(_weapon)

	for spot in MIST_POSITIONS:
		var mist := _sprite(MIST_TEXTURE, MIST_FRAMES)
		mist.position = spot
		mist.modulate.a = MIST_ALPHA
		_near_group.add_child(mist)
		_mists.append(mist)

	var glow := _glow_texture()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for light in LIGHTS:
		var sprite := Sprite2D.new()
		sprite.texture = glow
		sprite.material = additive
		sprite.position = light["position"]
		sprite.modulate = Color(light["color"], LIGHT_ALPHA)
		sprite.scale = Vector2.ONE * float(light["radius"]) * 2.0 / float(glow.get_width())
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_near_group.add_child(sprite)
		_lights.append(sprite)

	resized.connect(_layout)
	_layout()
	set_character(CharacterCatalog.get_character(CharacterCatalog.DEFAULT_ID), Color(0, 0, 0, 0))


## Shows data in front of the entrance; a transparent colour means the character's default.
func set_character(data: CharacterData, color: Color) -> void:
	if data == null:
		return
	data.apply_to(_hero, color if color.a > 0.0 else data.default_color)
	_hero.play(&"idle")
	_weapon.texture = data.menu_weapon
	_weapon.offset = -data.menu_weapon_pivot


func set_character_color(color: Color) -> void:
	CharacterData.set_tint_color(_hero, color)


func get_hero() -> AnimatedSprite2D:
	return _hero


func get_art_scale() -> int:
	return _art_scale


func _process(delta: float) -> void:
	_time += delta
	_lamp.frame = int(_time * LAMP_FPS) % LAMP_FRAMES
	for i in _mists.size():
		var mist := _mists[i]
		mist.frame = (int(_time * MIST_FPS) + i) % MIST_FRAMES
		mist.position.x += MIST_DRIFT * delta
		if mist.position.x > ART_SIZE.x + 8.0:
			mist.position.x = -40.0
	for i in _lights.size():
		var torch: bool = LIGHTS[i]["torch"]
		# Two detuned waves per light: torches flicker, the lantern only breathes.
		var wave := sin(_time * (9.0 + i * 1.7) + i * 2.1) * 0.5 + sin(_time * (14.3 + i) + i) * 0.5
		var strength := 0.12 if torch else 0.05
		var base_scale := float(LIGHTS[i]["radius"]) * 2.0 / float(_lights[i].texture.get_width())
		_lights[i].modulate.a = LIGHT_ALPHA * (1.0 + wave * strength * 2.0)
		_lights[i].scale = Vector2.ONE * base_scale * (1.0 + wave * strength * 0.5)
	_update_parallax(delta)


func _update_parallax(delta: float) -> void:
	var target := Vector2.ZERO
	if size.x > 0.0 and size.y > 0.0 and get_viewport() != null:
		var mouse := get_local_mouse_position()
		target = ((mouse / size) - Vector2(0.5, 0.5)) * 2.0
		target = target.clamp(Vector2(-1, -1), Vector2(1, 1))
	_parallax = _parallax.lerp(target, 1.0 - exp(-PARALLAX_SMOOTHING * delta))
	_far.position = _snap(-_parallax * PARALLAX_FAR)
	_near_group.position = _snap(-_parallax * PARALLAX_NEAR)


## Rounds to whole screen pixels so the art does not shimmer.
func _snap(offset: Vector2) -> Vector2:
	return (offset * _art_scale).round() / float(_art_scale)


func _layout() -> void:
	_art_scale = maxi(1, ceili(maxf(size.x / ART_SIZE.x, size.y / ART_SIZE.y) - 0.001))
	_stage.scale = Vector2.ONE * _art_scale
	_stage.position = ((size - ART_SIZE * _art_scale) * 0.5).floor()


func _sprite(texture: Texture2D, frames := 1) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.hframes = frames
	return sprite


## Soft round light: white centre fading to transparent.
static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.35))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
