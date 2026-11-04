class_name DecorStation
extends Node2D
## Where decorating starts (WK5, WK7): in the village the decoration board beside the home ("Dorf
## schmücken"), in the home the catalog stand by the door ("Zuhause einrichten"). E (X, a tap) opens
## the DecorEditor for the player who used it; the first time Flint explains it in two sentences
## (FlintExplanation hint "flint_decor_village" / "flint_decor_home", once per account).
## Art: ART_VILLAGE / ART_HOME as soon as they exist (SPRITES_V13 Teil C); until then the village
## shows the delivered signpost of the decoration and the home a drawn stand with an open book.
## Koop-Check: only alone (a solo session); in a group the station is switched off, guests see the
## host's arrangement only (Village.apply_host_decor).
## KE8b (playtest 04.11.2026 "man kann die Wohnung nicht einrichten"): the stand always twinkles a
## little (two gold pixels over the book), and while set_attention(true) a gold pixel arrow bounces
## over it (the home: until the decorating mode was opened once). Pixel art (D-218), hard steps.

signal used(player: Player)

const ART_VILLAGE := "res://art/environment/village/decor_board.png"
const ART_HOME := "res://art/environment/home/decor_catalog.png"
const FALLBACK_VILLAGE := "res://art/environment/village/deco/fun/signpost.png"
## Interaction radius (world px).
const RADIUS := 30.0
const WOOD := Color("#8a5a34")
const WOOD_DARK := Color("#5c3a24")
const PAGE := Color("#e9e4d2")
const PAGE_LINE := Color("#b9b3c9")
const OUTLINE := Color("#1c1a2b")

## TESTWERT: the arrow bounces in two hard steps (s per step, art px up), the sparkle blinks.
const BOUNCE_STEP := 0.35
const BOUNCE_PX := 2
const SPARKLE_STEP := 0.5
const ARROW := Color("#f2cf4a")
const ARROW_LIGHT := Color("#fff1a8")
const ARROW_EDGE := Color("#1c1a2b")
## Size of a drawn art pixel (world px, like the sprite's scale).
const ART_PIXEL := 2.0

var space: StringName = &""
var door: Interactable = null
## A bouncing arrow over the stand (it has not been used yet).
var attention := false
var _time := 0.0
var _sprite: Sprite2D = null


static func create(station_space: StringName) -> DecorStation:
	var station := DecorStation.new()
	station.space = station_space
	station.name = "DecorStation"
	return station


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = station_texture(space)
	sprite.centered = false
	sprite.scale = Vector2.ONE * 2.0
	sprite.offset = Vector2(-sprite.texture.get_width() * 0.5, -sprite.texture.get_height())
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_sprite = sprite
	# The arrow and the sparkle (this node's _draw) go over the picture.
	sprite.show_behind_parent = true
	door = Interactable.new()
	door.name = "Door"
	door.prompt = prompt_text()
	door.enabled = can_decorate(self)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	door.add_child(shape)
	door.position = Vector2(0, -8)
	add_child(door)
	door.interacted.connect(func(player: Player) -> void: used.emit(player))


func set_attention(on: bool) -> void:
	attention = on
	queue_redraw()


func _process(delta: float) -> void:
	var before := _phase()
	_time += delta
	if _phase() != before:
		queue_redraw()


## Hard animation step (bounce and sparkle change only on it).
func _phase() -> int:
	return int(_time / BOUNCE_STEP) * 7 + int(_time / SPARKLE_STEP)


## Arrow (while attention) and the sparkle over the book, in art pixels.
func _draw() -> void:
	var top := picture_top()
	var sparkle := int(_time / SPARKLE_STEP) % 3
	var spark_at := Vector2(-8 + sparkle * 6, top + 4 * ART_PIXEL)
	_pixel(spark_at, ARROW_LIGHT)
	if sparkle != 1:
		_pixel(spark_at + Vector2(ART_PIXEL * 3, -ART_PIXEL * 2), ARROW_LIGHT)
	if not attention:
		return
	var lift := BOUNCE_PX * ART_PIXEL if int(_time / BOUNCE_STEP) % 2 == 0 else 0.0
	# A down arrow of 7×8 art px with a dark edge, its tip 2 art px over the picture.
	var tip := Vector2(-ART_PIXEL * 0.5, top - 2 * ART_PIXEL - lift)
	var shape: Array[Vector2i] = []
	for row in 4:
		for x in range(-row, row + 1):
			shape.append(Vector2i(x, -row))
	for y in range(4, 8):
		for x in [-1, 0, 1]:
			shape.append(Vector2i(x, -y))
	for cell in shape:
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not shape.has(cell + step):
				_pixel(tip + Vector2(cell + step) * ART_PIXEL, ARROW_EDGE)
	for cell in shape:
		_pixel(tip + Vector2(cell) * ART_PIXEL, ARROW_LIGHT if cell.x < 0 and cell.y > -4 else ARROW)


## Upper edge of the stand's picture (local px).
func picture_top() -> float:
	if _sprite == null:
		return -28.0 * ART_PIXEL
	return _sprite.position.y + _sprite.offset.y * _sprite.scale.y


func _pixel(at: Vector2, colour: Color) -> void:
	draw_rect(Rect2(at.round(), Vector2.ONE * ART_PIXEL), colour)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and door != null:
		door.prompt = prompt_text()


func prompt_text() -> String:
	return Loc.t(&"DECOR_PROMPT_VILLAGE" if space == DecorCatalog.VILLAGE else &"DECOR_PROMPT_HOME")


## Decorating is for a solo session only (Koop-Check WK5/WK7).
static func can_decorate(node: Node) -> bool:
	return not GameMode.of(node).is_multiplayer()


## The first-time explanation of the space (FlintGuide hint, once per account).
static func explanation(station_space: StringName) -> FlintExplanation:
	if station_space == DecorCatalog.VILLAGE:
		return FlintExplanation.hint(&"flint_decor_village", [
			FlintGuideStep.say(&"FLINT_DECOR_VILLAGE", FlintGuideStep.Mood.HAPPY),
			FlintGuideStep.say(&"FLINT_DECOR_CONTROLS"),
		])
	return FlintExplanation.hint(&"flint_decor_home", [
		FlintGuideStep.say(&"FLINT_DECOR_HOME", FlintGuideStep.Mood.HAPPY),
		FlintGuideStep.say(&"FLINT_DECOR_CONTROLS"),
	])


## Opens the editor of layer for player in world (Flint explains it the first time). Null when it
## may not open (group session, an editor already open).
static func start(world: Node2D, layer: DecorLayer, player: Player) -> DecorEditor:
	if world == null or player == null or not can_decorate(world):
		return null
	if world.get_node_or_null(^"DecorEditor") != null:
		return null
	var editor := DecorEditor.open_for(world, layer, player)
	if editor != null:
		Sfx.play_ui(world, &"ui_open")
		FlintGuide.explain(player, explanation(layer.space))
	return editor


static func station_texture(station_space: StringName) -> Texture2D:
	var path := ART_VILLAGE if station_space == DecorCatalog.VILLAGE else ART_HOME
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if station_space == DecorCatalog.VILLAGE and ResourceLoader.exists(FALLBACK_VILLAGE):
		return load(FALLBACK_VILLAGE) as Texture2D
	return placeholder_texture()


## 24×28 stand with an open book: wooden post and foot, slanted top, two pages with lines.
static func placeholder_texture() -> Texture2D:
	var image := Image.create(24, 28, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(12, 26):
		for x in range(10, 14):
			image.set_pixel(x, y, OUTLINE if x == 10 or x == 13 else WOOD)
	for x in range(5, 19):
		for y in range(25, 28):
			image.set_pixel(x, y, OUTLINE if y == 27 or x == 5 or x == 18 else WOOD_DARK)
	for y in range(3, 13):
		for x in range(1, 23):
			var edge := y == 3 or y == 12 or x == 1 or x == 22
			var spine := x == 11 or x == 12
			var color := OUTLINE if edge else (WOOD_DARK if spine else PAGE)
			if not edge and not spine and y % 3 == 0 and x > 2 and x < 21:
				color = PAGE_LINE
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
