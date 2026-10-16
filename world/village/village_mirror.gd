class_name VillageMirror
extends Node2D
## The standing mirror next to the player's home (D-152): E opens the profile editor (name and look,
## VillageUI.open_mirror). Art: art/environment/village/mirror.png (16×28 art px, bottom centre,
## SPRITES_V10 §7) as soon as it exists; until then a drawn placeholder (wooden frame, glass with a
## glint). Placed by Village next to Zuhause (MIRROR_OFFSET), sorted like the other props.

signal used(player: Player)

const ART_PATH := "res://art/environment/village/mirror.png"
const SIZE := Vector2i(16, 28)
## Interaction radius in world px.
const RADIUS := 30.0
const WOOD := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const WOOD_LIGHT := Color("#a8703f")
const GLASS := Color("#6f8fb0")
const GLASS_LIGHT := Color("#b7d3ea")
const GLASS_DARK := Color("#4c6684")
const OUTLINE := Color("#1c1a2b")

var door: Interactable = null


static func create() -> VillageMirror:
	var mirror := VillageMirror.new()
	mirror.name = "Mirror"
	return mirror


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load(ART_PATH) as Texture2D if ResourceLoader.exists(ART_PATH) else placeholder_texture()
	sprite.centered = false
	sprite.scale = Vector2.ONE * VillageArt.SCALE
	sprite.offset = Vector2(-sprite.texture.get_width() * 0.5, -sprite.texture.get_height())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	door = Interactable.new()
	door.name = "Door"
	door.prompt = Loc.t(&"MIRROR_PROMPT")
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	door.add_child(shape)
	door.position = Vector2(0, -8)
	add_child(door)
	door.interacted.connect(func(player: Player) -> void: used.emit(player))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and door != null:
		door.prompt = Loc.t(&"MIRROR_PROMPT")


## 16×28 standing mirror: dark outline, wooden frame on two feet, blue-grey glass with a glint.
static func placeholder_texture() -> Texture2D:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Frame (rows 0..23), outline around it.
	for y in range(0, 24):
		for x in range(1, 15):
			var edge := y == 0 or y == 23 or x == 1 or x == 14
			image.set_pixel(x, y, OUTLINE if edge else WOOD)
	for y in range(1, 23):
		image.set_pixel(2, y, WOOD_LIGHT)
		image.set_pixel(13, y, WOOD_DARK)
	# Glass with a diagonal glint.
	for y in range(3, 21):
		for x in range(4, 12):
			var color := GLASS
			if x + y >= 21 and x + y <= 23:
				color = GLASS_LIGHT
			elif x == 11 or y == 20:
				color = GLASS_DARK
			image.set_pixel(x, y, color)
	# Feet.
	for x in [3, 4, 11, 12]:
		for y in range(24, 28):
			image.set_pixel(x, y, OUTLINE if y == 27 or x == 3 or x == 12 else WOOD_DARK)
	return ImageTexture.create_from_image(image)
