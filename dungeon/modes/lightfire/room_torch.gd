class_name RoomTorch
extends Node2D
## Torch stand of "Lichtfeuer" (RAEUME §3.9; before the variant "Fackelraum", A9): starts
## unlit (torch_stand_unlit, SPRITES_V5 §3); any hit by a player (sword, arrow, blast) or E lights it
## for good (torch_stand_4f, SPRITES_V5 §1). A burning torch is a light for LightQuery (it holds the
## stone guardians). The origin is the base line of the stand; it blocks like a crate.
## Decision: ignite(); the look follows it.

signal ignited(torch: RoomTorch, by: Node)

const FLAME_HEIGHT := 64.0
const INTERACT_RADIUS := 44.0
const HURT_SIZE := Vector2(28, 64)
const FOOTPRINT := Vector2(26, 14)
const FLAME_COLOR := Color("#ffb347")

var lit := false
var light: LightSource = null

var _lit_sprite: AnimatedProp = null
var _unlit_sprite: Sprite2D = null
var _interactable: Interactable = null
var _hurtbox: RoomTorchHurtbox = null


func build(tint: Color = Color.WHITE, light_radius := LightfireRules.TORCH_LIGHT_RADIUS) -> void:
	DropShadow.attach(self, 10.0, -2.0)
	_unlit_sprite = VariantArt.make_sprite(VariantArt.TORCH_UNLIT)
	_unlit_sprite.name = "Unlit"
	add_child(_unlit_sprite)
	_lit_sprite = AnimatedProp.new()
	_lit_sprite.name = "Lit"
	_lit_sprite.frame_size = IngredientArt.TORCH_STAND_FRAME
	_lit_sprite.pivot = Vector2(8, 39)
	_lit_sprite.fps = 8.0
	_lit_sprite.strip = IngredientArt.get_texture("torch_stand_4f")
	_lit_sprite.modulate = Color.WHITE.lerp(tint, 0.35)
	_lit_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_lit_sprite.visible = false
	add_child(_lit_sprite)
	light = LightSource.new()
	light.name = "Light"
	light.radius = light_radius
	light.intensity = 0.95
	light.flicker = 0.08
	light.position = Vector2(0.0, -FLAME_HEIGHT)
	light.ground_offset = Vector2(0.0, FLAME_HEIGHT)
	light.visible = false
	add_child(light)
	var body := StaticBody2D.new()
	body.name = "Blocker"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var block_shape := RectangleShape2D.new()
	block_shape.size = FOOTPRINT
	var block := CollisionShape2D.new()
	block.shape = block_shape
	block.position = Vector2(0.0, -FOOTPRINT.y * 0.5)
	body.add_child(block)
	add_child(body)
	_hurtbox = RoomTorchHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.torch = self
	var hurt_shape := RectangleShape2D.new()
	hurt_shape.size = HURT_SIZE
	var hurt := CollisionShape2D.new()
	hurt.shape = hurt_shape
	hurt.position = Vector2(0.0, -HURT_SIZE.y * 0.5)
	_hurtbox.add_child(hurt)
	add_child(_hurtbox)
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt = DungeonTexts.t(&"VARIANT_TORCH_PROMPT")
	var shape := CircleShape2D.new()
	shape.radius = INTERACT_RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -16.0)
	_interactable.add_child(collision)
	add_child(_interactable)
	_interactable.interacted.connect(func(player: Player) -> void: ignite(player))


func get_interactable() -> Interactable:
	return _interactable


func get_hurtbox() -> Hurtbox:
	return _hurtbox


## Circle of a burning torch for LightQuery (z = 0 while unlit).
func get_light_circle() -> Vector3:
	if not lit or light == null:
		return LightQuery.circle(global_position if is_inside_tree() else position, 0.0)
	return LightQuery.circle(light.get_lit_center() if is_inside_tree() else position, light.get_lit_radius())


## Decision: the torch burns from now on (by = the player or the attack's source).
func ignite(by: Node = null) -> bool:
	if lit:
		return false
	lit = true
	if _unlit_sprite != null:
		_unlit_sprite.visible = false
		_lit_sprite.visible = true
		light.visible = true
		light.counts_as_light = true
		_interactable.enabled = false
		_hurtbox.set_deferred("monitorable", false)
	ignited.emit(self, by)
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0.0, -FLAME_HEIGHT), FLAME_COLOR, 14, 110.0)
		LightSource.flash(get_parent(), global_position + Vector2(0.0, -FLAME_HEIGHT), 220.0, 0.4)
		Sfx.play_at(self, &"fuse", global_position, -6.0)
	return true
