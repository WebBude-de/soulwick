class_name SecretNiche
extends Node2D
## The secret niche of one combat room (A10, KONZEPT_RAEUME §7.3), behind its north wall: the cracked wall with its dust,
## the hurtbox that waits for an explosion, the break and the content behind it (chest, soul
## crystals or the wandering merchant). No room of its own: no room number, no encounter.
## Decision and effects are separate (D-088): break_open() decides once, opens the room's tiles and
## emits opened; the break animation and the content follow. carve() runs before the room enters
## the tree (walls into the floor plan, tiles kept free of ingredients), attach() after it.
## Look (R1): the cracked front sits flush in the brick front, the niche behind it is drawn as rock
## until the wall breaks (RoomTiles), and the break animation (crypt colours) is recoloured into the
## biome's wall colours (WallArt), so no purple crypt edge shows up in the ember forge.

signal opened(niche: SecretNiche)
## A hit that was no explosion (a sword on the wall): dust and, once per save, a hint.
signal tapped(niche: SecretNiche)
## The content was taken: chest opened, crystals picked up, something bought (D-109).
signal content_used(niche: SecretNiche)

const NODE_NAME := &"SecretNiche"
const CRACK_ART := "res://art/environment/rooms/wall_cracked_%s.png"
const BREAK_ART: Texture2D = preload("res://art/environment/rooms/wall_break_6f.png")
const BREAK_FRAME := Vector2i(32, 48)
const BREAK_PIVOT := Vector2(16, 47)
const BREAK_FPS := 10.0
const CHEST_SCENE: PackedScene = preload("res://dungeon/rooms/ingredients/treasure_chest.tscn")
## The break art is drawn in crypt colours and tinted per biome (SPRITES_V5 §6).
const BIOME_TINTS := {
	&"crypt": Color.WHITE,
	&"slime_grotto": Color(0.72, 0.95, 0.76),
	&"shadow_realm": Color(0.78, 0.68, 0.98),
	&"ember_forge": Color(1.0, 0.78, 0.62),
}
const DUST_COLOR := Color(0.74, 0.7, 0.62, 0.55)
## Over the room's tiles (z -10), under props and characters.
const WALL_Z := -9

var site: SecretRules.Site = null
var content_kind := SecretRules.Content.CHEST
var room: RoomController = null
var is_open := false
## Chest, SecretCrystal or WanderingMerchant once the wall broke.
var content: Node2D = null

var _crack: Sprite2D = null
var _hurtbox: SecretWallHurtbox = null
var _dust: CPUParticles2D = null


## Before the room enters the tree: the niche goes into the rock ring behind the north wall, and the
## scatter keeps the floor in front of the crack free.
static func carve(room_node: Node, niche_site: SecretRules.Site) -> void:
	var tiles := room_node.get_node("Tiles") as RoomTiles
	tiles.niche_rect = niche_site.get_rect()
	var scatter := room_node.get_node_or_null("Ingredients") as IngredientScatter
	if scatter != null:
		var reserved: Array[Vector2i] = scatter.reserved_tiles.duplicate()
		reserved.append(niche_site.approach)
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1, 1), Vector2i(1, 1)]:
			reserved.append(niche_site.approach + offset)
		scatter.reserved_tiles = reserved


## After the room is ready: the niche node with the cracked wall.
static func attach(target: RoomController, niche_site: SecretRules.Site, kind: SecretRules.Content) -> SecretNiche:
	var niche := SecretNiche.new()
	niche.name = NODE_NAME
	niche.site = niche_site
	niche.content_kind = kind
	niche.room = target
	niche.y_sort_enabled = true
	target.add_child(niche)
	return niche


static func of(target: Node) -> SecretNiche:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null(NodePath(NODE_NAME)) as SecretNiche


func _ready() -> void:
	var biome_id: StringName = &"crypt"
	var biome := room.spawner.get_biome(room.room_index) if room != null else null
	if biome != null:
		biome_id = biome.id
	var crack_path := CRACK_ART % biome_id
	if not ResourceLoader.exists(crack_path):
		crack_path = CRACK_ART % "crypt"
	_crack = Sprite2D.new()
	_crack.name = "CrackedWall"
	_crack.texture = load(crack_path) as Texture2D
	_crack.centered = false
	_crack.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_crack.position = RoomTiles.tile_to_local(site.crack)
	_crack.z_index = WALL_Z
	add_child(_crack)
	_build_dust()
	_hurtbox = SecretWallHurtbox.new()
	_hurtbox.name = "Hurtbox"
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * RoomTiles.TILE_WORLD
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_hurtbox.add_child(collision)
	_hurtbox.position = RoomTiles.tile_center(site.crack)
	add_child(_hurtbox)
	_hurtbox.struck.connect(_on_struck)
	_hurtbox.tapped.connect(_on_tapped)


func get_crack_position() -> Vector2:
	return to_global(RoomTiles.tile_center(site.crack))


func get_hurtbox() -> SecretWallHurtbox:
	return _hurtbox


## Decision: the wall breaks (once). Opens the room's tiles, then the effects and the content.
func break_open() -> bool:
	if is_open:
		return false
	is_open = true
	if room != null and is_instance_valid(room) and room.tiles != null:
		room.tiles.open_wall_tiles(site.opening)
	_hurtbox.set_deferred("monitorable", false)
	_play_break()
	_spawn_content()
	opened.emit(self)
	return true


func _on_struck(_damage: DamageData) -> void:
	break_open()


func _on_tapped(_damage: DamageData) -> void:
	if is_open:
		return
	Burst.spawn(self, get_crack_position(), DUST_COLOR, 6, 70.0, 0.4, 3.0)
	tapped.emit(self)


func _build_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.name = "Dust"
	_dust.amount = 4
	_dust.lifetime = 2.2
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(18, 10)
	_dust.direction = Vector2.DOWN
	_dust.spread = 25.0
	_dust.gravity = Vector2(0, 14)
	_dust.initial_velocity_min = 4.0
	_dust.initial_velocity_max = 12.0
	_dust.scale_amount_min = 1.5
	_dust.scale_amount_max = 2.5
	_dust.color = DUST_COLOR
	_dust.position = RoomTiles.tile_center(site.crack) + Vector2(0, -8)
	_dust.z_index = WALL_Z + 1
	add_child(_dust)


## The break animation in the biome's wall colours (R1, "Bruchkante in Biomfarbe").
static func get_break_art(biome_id: StringName) -> Texture2D:
	return WallArt.recolor_texture(BREAK_ART, biome_id)


func _play_break() -> void:
	if _crack != null:
		_crack.visible = false
	if _dust != null:
		_dust.emitting = false
	if not is_inside_tree():
		return
	var base := RoomTiles.tile_to_local(site.crack) + Vector2(RoomTiles.TILE_WORLD * 0.5, RoomTiles.TILE_WORLD)
	var biome := room.spawner.get_biome(room.room_index) if room != null else null
	var biome_id: StringName = biome.id if biome != null else &"crypt"
	var sprite := SpriteStrip.spawn_effect(self, to_global(base), get_break_art(biome_id), BREAK_FRAME, BREAK_FPS, BREAK_PIVOT, Vector2.ONE * SpriteStrip.PIXEL_SCALE)
	sprite.z_index = WALL_Z
	if not WallArt.has_biome_colors(biome_id):
		sprite.modulate = BIOME_TINTS.get(biome_id, Color.WHITE)
	var centre := get_crack_position()
	Burst.spawn(self, centre, DUST_COLOR, 24, 180.0, 0.6, 5.0)
	LightSource.flash(self, centre, 200.0, 0.5)
	CameraShake.shake(self, 5.0)
	Sfx.play_at(self, &"crate_break", centre)


## The content stands in the middle of the niche, made only now (no light shines through the wall).
func _spawn_content() -> void:
	var spot := RoomTiles.tile_center(site.get_content_tile())
	match content_kind:
		SecretRules.Content.CRYSTAL:
			var crystal := SecretCrystal.new()
			crystal.name = "SecretCrystal"
			crystal.position = spot + Vector2(0, 18)
			add_child(crystal)
			crystal.collected.connect(func(_c: SecretCrystal, _p: Player) -> void: content_used.emit(self))
			content = crystal
		SecretRules.Content.MERCHANT:
			var merchant := WanderingMerchant.new()
			merchant.name = "WanderingMerchant"
			merchant.position = spot + Vector2(0, 20)
			add_child(merchant)
			merchant.setup(room.context if room != null else null, room)
			merchant.traded.connect(func(_m: WanderingMerchant) -> void: content_used.emit(self))
			content = merchant
		_:
			var chest := CHEST_SCENE.instantiate() as TreasureChest
			chest.name = "SecretChest"
			chest.upgrade_choices = VariantRules.CHEST_UPGRADE_CHOICES
			chest.per_player = VariantRules.CHESTS_PER_PLAYER
			chest.position = spot + Vector2(0, 22)
			add_child(chest)
			chest.opened.connect(func(_c: TreasureChest, _p: Player) -> void: content_used.emit(self))
			content = chest
