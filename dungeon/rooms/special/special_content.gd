class_name SpecialContent
extends Node2D
## Base for the content of special rooms (D-005): shop, weapon choice, fountain, upgrade altar, portal.
## All offers are optional; nothing blocks the exit. Children are built in code from art/ sprites.
## Two steps (playtest 15.10.2026 #9, "nothing pops up", R5): prepare() builds what is seen when the
## room is prepared, so the merchant, altar or fountain already stands there under the room's veil;
## setup() makes it usable when the room is entered (shop offers depend on what the players own by
## then). Interactables wait until setup(). Captions show only near a player anyway (WorldCaption).

var context: DungeonContext = null
var room: RoomController = null
var _prepared := false
var _is_set_up := false
## Interactables built by prepare(): disabled until the room is entered.
var _waiting: Array[Interactable] = []


## Builds the visible part (sprites, lights, blockers, captions, interactables) while the room is
## prepared. Rolls that decide what is shown (which weapons, pact or plain altar) happen here with
## the dungeon RNG, inside the slot's captured RNG range (identical on every machine).
func prepare(dungeon_context: DungeonContext, owner_room: RoomController) -> void:
	if _prepared:
		return
	_prepared = true
	context = dungeon_context
	room = owner_room
	# Each sprite sorts by its own base line against the player (not the whole content at once).
	y_sort_enabled = true
	_on_prepare()


## Makes the content usable when the room is entered (prepares it first if that has not happened).
func setup(dungeon_context: DungeonContext, owner_room: RoomController) -> void:
	if _is_set_up:
		return
	prepare(dungeon_context, owner_room)
	context = dungeon_context
	room = owner_room
	_is_set_up = true
	for interactable in _waiting:
		if is_instance_valid(interactable):
			interactable.enabled = true
	_waiting.clear()
	_on_setup()


func is_prepared() -> bool:
	return _prepared


func is_set_up() -> bool:
	return _is_set_up


## Override: build what is seen (no player state that may change before the room is entered).
func _on_prepare() -> void:
	pass


## Override: the part that needs the room to be entered (offers, prompts with player state).
func _on_setup() -> void:
	pass


## All players of the run. Single player today; per-player offers and states iterate this list,
## so the multiplayer change (MP1) only has to fill it (no player group lookups, D-088).
func get_players() -> Array[Player]:
	var players: Array[Player] = []
	if context != null and context.player != null and is_instance_valid(context.player):
		players.append(context.player)
	return players


func add_sprite(texture: Texture2D, pivot: Vector2, offset_position := Vector2.ZERO) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.offset = SpriteStrip.pivot_offset(Vector2i(texture.get_size()), pivot)
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_add_sorted(sprite, offset_position)
	return sprite


func add_animated(texture: Texture2D, frame_size: Vector2i, fps: float, pivot: Vector2, offset_position := Vector2.ZERO) -> AnimatedProp:
	var prop := AnimatedProp.new()
	prop.frame_size = frame_size
	prop.fps = fps
	prop.pivot = pivot
	prop.strip = texture
	prop.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_add_sorted(prop, offset_position)
	return prop


## Adds item with its base (pivot) at base_position, sorted against the characters' feet: a holder
## lifted by SortLift carries the item, so the picture stays where it is.
func _add_sorted(item: Node2D, base_position: Vector2) -> void:
	var holder := Node2D.new()
	holder.name = "%sHolder" % item.name if not String(item.name).is_empty() else "PropHolder"
	holder.position = base_position
	holder.add_child(item)
	add_child(holder)
	SortLift.lift(holder)


## Solid footprint so the player cannot walk through the object.
func add_blocker(size: Vector2, center := Vector2.ZERO) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	add_child(body)
	return body


func add_interactable(prompt: String, radius := 40.0, center := Vector2.ZERO) -> Interactable:
	var interactable := Interactable.new()
	interactable.prompt = prompt
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	interactable.add_child(collision)
	interactable.position = center
	add_child(interactable)
	if _prepared and not _is_set_up:
		interactable.enabled = false
		_waiting.append(interactable)
	return interactable


func add_light(radius: float, offset_position := Vector2.ZERO) -> LightSource:
	var light := LightSource.new()
	light.radius = radius
	light.flicker = 0.04
	light.position = offset_position
	add_child(light)
	return light


func add_caption(text: String, offset_position: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(220, 24)
	label.position = offset_position - Vector2(110, 12)
	label.z_index = 30
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
