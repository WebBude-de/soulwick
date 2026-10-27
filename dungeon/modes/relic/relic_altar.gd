class_name RelicAltar
extends Node2D
## The empty altar of "Reliquie holen" next to the entrance (RAEUME §3.5, design answer:
## "Altar hat eine leere, dunkle Mulde, die beim Ablegen aufleuchtet"). Pure look: the relic lays
## itself on (Relic.place) and the altar shows it in its hollow and lights up gold.
## Art: relic_altar.png 32x32, pivot (16, 28); the relic is drawn in at (16, 14) (objectives.json).
## The origin is the base line of the altar; it blocks like a crate.

const ART := "res://art/environment/objectives/relic_altar.png"
const FRAME := Vector2i(32, 32)
const PIVOT := Vector2(16, 28)
## Where a relic lies on the altar, in art pixels of the altar (objectives.json), and the step for
## a second one.
const RELIC_SLOT := Vector2(16, 14)
const SECOND_SLOT_STEP := Vector2(-7, 0)
const FOOTPRINT := Vector2(44, 16)
const LIGHT_RADIUS := 110.0
const LIT_LIGHT_RADIUS := 240.0
const COLOR := Color("#f2cf4a")

var relics_on := 0

var _sprite: Sprite2D = null
var _light: LightSource = null
var _relic_sprites: Array[Sprite2D] = []
var _slots_taken := 0


func build() -> void:
	DropShadow.attach(self, 18.0, -2.0)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = _altar_texture()
	_sprite.centered = false
	_sprite.offset = -PIVOT
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	add_child(_sprite)
	_light = LightSource.new()
	_light.name = "Light"
	_light.radius = LIGHT_RADIUS
	_light.intensity = 0.35
	_light.position = Vector2(0.0, -30.0)
	_light.ground_offset = Vector2(0.0, 30.0)
	add_child(_light)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = FOOTPRINT
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -FOOTPRINT.y * 0.5)
	body.add_child(collision)
	add_child(body)


## Global point where the next relic lies on the altar (one slot per relic).
func take_slot() -> Vector2:
	var index := _slots_taken
	_slots_taken += 1
	return to_global(_slot_local(index))


## A relic arrived: drawn in the hollow, the altar lights up.
func add_relic(texture: Texture2D) -> void:
	var index := relics_on
	relics_on += 1
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.name = "Relic%d" % index
		sprite.texture = texture
		sprite.centered = false
		sprite.offset = -Relic.PIVOT
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.position = _slot_local(index)
		add_child(sprite)
		_relic_sprites.append(sprite)
	if _light != null:
		_light.radius = LIT_LIGHT_RADIUS
		_light.intensity = 1.0
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -40.0), COLOR, 22, 150.0)
		LightSource.flash(get_parent(), global_position + Vector2(0.0, -40.0), 260.0, 0.6)


func _slot_local(index: int) -> Vector2:
	var art := RELIC_SLOT + SECOND_SLOT_STEP * index - PIVOT
	return art * SpriteStrip.PIXEL_SCALE


static func _altar_texture() -> Texture2D:
	if ResourceLoader.exists(ART):
		return load(ART) as Texture2D
	var image := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(12, 29):
		for x in range(6, 26):
			image.set_pixel(x, y, Color("#5b5670") if y > 14 else Color("#2a2638"))
	return ImageTexture.create_from_image(image)
