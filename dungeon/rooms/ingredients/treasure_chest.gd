class_name TreasureChest
extends Node2D
## Bonus chest (D-109): opened with E, it gives an upgrade choice through the existing dialog (no
## gold while the gold values are OPEN). It opens once the room's fight is won, so the dialog never
## interrupts a fight. Stands in the deepest dead end of a catacomb (A3); the
## combat variants (A7) and trial rooms (A8) can place the same scene. The origin is the base line
## of the chest; it blocks like a crate and glows a little, so the reward is visible before the risk.
## Opening is decided here once (is_open, opened signal); the reward is a separate step that only
## needs the run's DungeonContext (upgrade manager, dialog, dungeon RNG).

signal opened(chest: TreasureChest, player: Player)

const PROMPT := "Truhe öffnen"
const DIALOG_TITLE := "Truhe geöffnet!"
const GLOW_RADIUS := 80.0
const GLOW_INTENSITY := 0.6
const OPEN_FPS := 10.0
const FOOTPRINT := Vector2(44, 20)
const INTERACT_RADIUS := 56.0

## Upgrade choices per opening (TESTWERT). Koop scaling (chests or choices per player) is only a
## parameter for now and gets its values in MP5 (D-109).
@export var upgrade_choices := 1
## false: the chest stays closed for the other players until MP5 decides (D-109).
@export var per_player := false
## Locked until the room around it reports completed (RoomController.completed).
@export var locked_until_cleared := true

var is_open := false
var _sprite: AnimatedSprite2D = null
var _interactable: Interactable = null
var _glow: LightSource = null


func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = SpriteStrip.make_frames(IngredientArt.get_texture("chest_open_4f"), IngredientArt.CHEST_FRAME, OPEN_FPS, false)
	_sprite.offset = SpriteStrip.pivot_offset(IngredientArt.CHEST_FRAME, Vector2(16, 30))
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.frame = 0
	add_child(_sprite)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = FOOTPRINT
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -FOOTPRINT.y * 0.5)
	body.add_child(collision)
	add_child(body)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt = PROMPT
	var area := CircleShape2D.new()
	area.radius = INTERACT_RADIUS
	var area_shape := CollisionShape2D.new()
	area_shape.shape = area
	_interactable.add_child(area_shape)
	_interactable.position = Vector2(0, -16)
	_interactable.interacted.connect(_on_interacted)
	add_child(_interactable)
	_glow = LightSource.new()
	_glow.radius = GLOW_RADIUS
	_glow.intensity = GLOW_INTENSITY
	_glow.flicker = 0.05
	_glow.position = Vector2(0, -24)
	add_child(_glow)
	DropShadow.attach(self, 20.0, -2.0)
	# Sorted by its base line against the characters' feet, like crates.
	SortLift.lift(self)
	var room := find_room()
	if locked_until_cleared and room != null and room.state != RoomController.State.CLEARED:
		_interactable.enabled = false
		room.completed.connect(_on_room_completed, CONNECT_ONE_SHOT)


func is_locked() -> bool:
	return not is_open and not _interactable.enabled


func _on_room_completed(_room: RoomController) -> void:
	if not is_open:
		_interactable.enabled = true
		LightSource.flash(self, global_position + Vector2(0, -24), GLOW_RADIUS * 1.6, 0.6)


func get_interactable() -> Interactable:
	return _interactable


func _on_interacted(player: Player) -> void:
	if is_open:
		return
	is_open = true
	_interactable.enabled = false
	_sprite.play(&"default")
	Sfx.play_at(self, &"door_open", global_position, -4.0)
	Burst.spawn(get_parent(), global_position + Vector2(0, -28), IngredientArt.GOLD, 18, 120.0, 0.5, 3.0)
	_glow.intensity = 1.0
	opened.emit(self, player)
	grant_reward(player)


## The reward of D-109: upgrade_choices upgrade dialogs, rolled with the dungeon RNG.
func grant_reward(_player: Player) -> void:
	var context := find_context()
	if context == null or context.upgrade_manager == null or context.ui == null or context.rng == null:
		return
	for i in upgrade_choices:
		var offer := context.upgrade_manager.roll_offer(context.get_owned_weapons(), context.rng)
		if offer.is_empty():
			return
		var choice: UpgradeData = await context.ui.choose_upgrade(offer, DIALOG_TITLE)
		if choice != null and is_instance_valid(context.upgrade_manager):
			context.upgrade_manager.acquire_upgrade(choice)


## DungeonContext of the room this chest stands in (null outside a dungeon room).
func find_context() -> DungeonContext:
	var room := find_room()
	return room.context if room != null else null


func find_room() -> RoomController:
	var node := get_parent()
	while node != null:
		if node is RoomController:
			return node as RoomController
		node = node.get_parent()
	return null
