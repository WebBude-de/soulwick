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

var space: StringName = &""
var door: Interactable = null


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
