class_name CampfireContent
extends SpecialContent
## The campfire between two biomes (D-103): fire with warm light in the
## middle, a seat and a bedroll, no enemies. At the fire (E) every player makes ONE choice: heal
## (+HEAL_AMOUNT up to max HP) or strengthen an upgrade they already have by one stack.
## While the player walks from the entrance (old biome) to the exit (new biome) the darkness colour
## and the ambient particles follow the floor blend of the room (RoomTiles.get_blend_progress).
##
## Decision and effect are separate (D-088): take_rest() checks and decides, rest_taken carries
## the result to the effects (heal, stack, sound, particles).

signal rest_taken(player: Player, upgrade: UpgradeData)

## TESTWERTE (D-103): heal amount and light of the fire.
const HEAL_AMOUNT := 4.0
const FIRE_LIGHT_RADIUS := 250.0
const FIRE_FLICKER := 0.1
const FIRE_FPS := 8.0
## Warm glow on the floor around the fire and the coloured glows of the two biomes.
const FIRE_GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.5)
const FIRE_GLOW_SIZE := 460.0
const BIOME_GLOW_ALPHA := 0.15
const BIOME_GLOW_SIZE := 300.0
## Glow colour per biome (light of the old biome at the entrance, of the new one at the exit).
const BIOME_GLOW_COLORS := {
	&"crypt": Color(0.55, 0.5, 1.0),
	&"slime_grotto": Color(0.35, 1.0, 0.45),
	&"shadow_realm": Color(0.7, 0.35, 1.0),
	&"ember_forge": Color(1.0, 0.45, 0.15),
}
## Floor overlays of the next biome over the old floor (SPRITES_V4 §5, TESTWERTE): chance per floor
## tile = OVERLAY_DENSITY * blend progress, so they get denser towards the new biome; none where
## the floor is still fully old or already fully new. Never two side by side (R1: patches, no
## raster of decals in the smaller campfire plan).
const OVERLAY_DENSITY := 0.5
const OVERLAY_BAND := Vector2(0.05, 0.95)
## Ambient particles switch to the next biome from this blend progress on.
const PARTICLE_SWITCH_AT := 0.5
const SEAT_OFFSET := Vector2(-92, 14)
const BEDROLL_OFFSET := Vector2(96, 26)
const PACK_OFFSET := Vector2(70, -34)
## Pivots in art pixels (art/environment/campfire/campfire.json).
const FIRE_PIVOT := Vector2(16, 30)
const SEAT_PIVOT := Vector2(16, 16)
const BEDROLL_PIVOT := Vector2(16, 16)
const PACK_PIVOT := Vector2(8, 16)

var _rested: Dictionary[int, bool] = {}
var _choosing := false
var _interactable: Interactable = null
var _fire: AnimatedProp = null
var _old_biome: BiomeData = null
var _new_biome: BiomeData = null
var _particle_biome := &""


## Upgrades the player already has and that can take one more stack (stackable, not at the limit).
static func get_stackable_upgrades(manager: UpgradeManager) -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	if manager == null:
		return result
	for upgrade in manager.get_active_upgrades():
		if not manager.is_maxed(upgrade):
			result.append(upgrade)
	return result


static func can_heal(player: Player) -> bool:
	return player != null and player.is_alive() and player.health.get_health() < player.health.get_max_health()


func _on_setup() -> void:
	_old_biome = room.spawner.get_biome(room.room_index) if room != null else null
	_new_biome = room.get_next_biome() if room != null else null
	_fire = add_animated(CampfireArt.get_texture(CampfireArt.FIRE), CampfireArt.FIRE_FRAME_SIZE, FIRE_FPS, FIRE_PIVOT)
	var light := add_light(FIRE_LIGHT_RADIUS, Vector2(0, -24))
	light.flicker = FIRE_FLICKER
	_add_glow(Vector2(0, -12), FIRE_GLOW_COLOR, FIRE_GLOW_SIZE)
	_add_embers()
	add_blocker(Vector2(48, 22), Vector2(0, -8))
	add_sprite(CampfireArt.get_texture(CampfireArt.LOG_SEAT), SEAT_PIVOT, SEAT_OFFSET)
	add_blocker(Vector2(56, 14), SEAT_OFFSET + Vector2(0, -8))
	add_sprite(CampfireArt.get_texture(CampfireArt.BEDROLL), BEDROLL_PIVOT, BEDROLL_OFFSET)
	add_blocker(Vector2(56, 14), BEDROLL_OFFSET + Vector2(0, -8))
	add_sprite(CampfireArt.get_texture(CampfireArt.PACK), PACK_PIVOT, PACK_OFFSET)
	add_blocker(Vector2(24, 12), PACK_OFFSET + Vector2(0, -6))
	_interactable = add_interactable(DungeonTexts.t(&"CAMPFIRE_PROMPT"), 72.0, Vector2(0, 8))
	_interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"ROOM_CAMPFIRE_TITLE"), Vector2(0, -92))
	_add_biome_glows()
	_add_transition_overlays()
	rest_taken.connect(_on_rest_taken)


func has_rested(player: Player) -> bool:
	return player != null and _rested.has(player.get_instance_id())


## The one choice of a player (null = heal). Returns false if it is not allowed: already rested,
## nothing to heal, or the upgrade is not one of the player's stackable upgrades.
func take_rest(player: Player, upgrade: UpgradeData) -> bool:
	if player == null or not player.is_alive() or has_rested(player):
		return false
	if upgrade == null and not can_heal(player):
		return false
	if upgrade != null and not get_stackable_upgrades(context.upgrade_manager).has(upgrade):
		return false
	_rested[player.get_instance_id()] = true
	rest_taken.emit(player, upgrade)
	_update_interactable()
	return true


func _on_interacted(player: Player) -> void:
	if _choosing or has_rested(player):
		return
	var upgrades := get_stackable_upgrades(context.upgrade_manager)
	var heal_possible := can_heal(player)
	if upgrades.is_empty() and not heal_possible:
		context.ui.show_banner(DungeonTexts.t(&"CAMPFIRE_RESTED_TITLE"), DungeonTexts.t(&"CAMPFIRE_RESTED_SUB"), UiKit.COLOR_GOLD)
		return
	_choosing = true
	var pick: int = await context.ui.choose_campfire_rest(HEAL_AMOUNT, heal_possible, upgrades, player)
	_choosing = false
	if pick < 0 or not is_instance_valid(player):
		# Esc: the fire stays, the player may come back.
		return
	take_rest(player, null if pick == 0 else upgrades[pick - 1])


## Effects of a choice.
func _on_rest_taken(player: Player, upgrade: UpgradeData) -> void:
	if upgrade == null:
		player.health.heal(HEAL_AMOUNT)
		Sfx.play_at(self, &"heal", global_position)
		Burst.spawn(get_parent(), player.global_position + Vector2(0, -24), Color(1.0, 0.45, 0.4), 16, 120.0)
	else:
		context.upgrade_manager.acquire_upgrade(upgrade)
		Burst.spawn(get_parent(), player.global_position + Vector2(0, -24), UiKit.COLOR_GOLD, 16, 120.0)
	Burst.spawn(get_parent(), global_position + Vector2(0, -26), FIRE_GLOW_COLOR, 24, 150.0)


## The fire stays usable until every player has made their choice.
func _update_interactable() -> void:
	for player in _players():
		if not has_rested(player):
			return
	_interactable.enabled = false
	_interactable.prompt = DungeonTexts.t(&"CAMPFIRE_RESTED_PROMPT")


## All players of the run. Single player today; the list keeps the per-player logic ready (MP1).
func _players() -> Array[Player]:
	var players: Array[Player] = []
	if context != null and context.player != null:
		players.append(context.player)
	return players


# --- Atmosphere: the darkness colour and the particles follow the floor blend ---

func _process(_delta: float) -> void:
	if room == null or context == null or context.manager == null or _old_biome == null or _new_biome == null:
		return
	if context.manager.get_active_slot() != room.slot_index:
		return
	var player := context.player
	if player == null or not is_instance_valid(player):
		return
	var progress := room.tiles.get_blend_progress(room.to_local(player.global_position).y)
	var overlay := get_tree().get_first_node_in_group(VisionOverlay.GROUP) as VisionOverlay
	if overlay != null:
		overlay.set_dark_color(get_dark_color(progress))
	var particles := _new_biome.id if progress >= PARTICLE_SWITCH_AT else _old_biome.id
	if particles != _particle_biome:
		_particle_biome = particles
		AmbientParticles.set_biome_for(self, particles)


## Darkness colour at a blend progress (0 = old biome, 1 = new biome).
func get_dark_color(progress: float) -> Color:
	return _old_biome.darkness_color.lerp(_new_biome.darkness_color, clampf(progress, 0.0, 1.0))


# --- Look ---

func _add_glow(offset_position: Vector2, color: Color, size: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _glow_texture()
	sprite.modulate = color
	sprite.scale = Vector2.ONE * size / 64.0
	sprite.position = offset_position
	# On the floor, under props and characters; adds light instead of painting over it.
	sprite.z_index = -8
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = additive
	add_child(sprite)
	return sprite


static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## Sparks rising from the fire (optics only).
func _add_embers() -> void:
	var embers := CPUParticles2D.new()
	embers.amount = 14
	embers.lifetime = 1.6
	embers.position = Vector2(0, -26)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(10, 3)
	embers.direction = Vector2.UP
	embers.spread = 20.0
	embers.gravity = Vector2(0, -30)
	embers.initial_velocity_min = 18.0
	embers.initial_velocity_max = 46.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.15, 0.0))
	embers.color_ramp = ramp
	embers.z_index = 4
	add_child(embers)


## Coloured light of the old biome near the entrance, of the new one near the exit.
func _add_biome_glows() -> void:
	if room == null or _old_biome == null or _new_biome == null:
		return
	var size := room.tiles.room_size
	var corners := {
		_old_biome.id: [Vector2(1.5, size.y - 1.5), Vector2(size.x - 1.5, size.y - 1.5)],
		_new_biome.id: [Vector2(1.5, 1.2), Vector2(size.x - 1.5, 1.2)],
	}
	for biome_id: StringName in corners:
		var base: Color = BIOME_GLOW_COLORS.get(biome_id, Color(0.6, 0.6, 0.8))
		for tile: Vector2 in corners[biome_id]:
			_add_glow(tile * RoomTiles.TILE_WORLD - position, Color(base, BIOME_GLOW_ALPHA), BIOME_GLOW_SIZE)


## Patches of the next biome on the old floor, tile-aligned, denser towards the exit (seeded by
## the room, not the dungeon RNG: optics only).
func _add_transition_overlays() -> void:
	if room == null or _new_biome == null:
		return
	var texture := CampfireArt.get_texture(CampfireArt.get_overlay_name(_new_biome.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = room.room_index * 7919 + room.tiles.floor_seed
	for tile in get_overlay_tiles(room.tiles, rng):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.hframes = CampfireArt.OVERLAY_TILES
		sprite.frame = rng.randi_range(0, CampfireArt.OVERLAY_TILES - 1)
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.position = RoomTiles.tile_to_local(tile) - position
		sprite.z_index = -9
		add_child(sprite)


## Floor tiles that get an overlay: inside the blend band, chance rising with the blend progress.
## Never the tiles of the door corridors.
static func get_overlay_tiles(tiles: RoomTiles, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in tiles.room_size.y:
		var progress := tiles.get_blend_progress(tiles.position.y + (y + 0.5) * RoomTiles.TILE_WORLD)
		for x in tiles.room_size.x:
			# One draw per tile keeps the pattern stable whatever the band is.
			var roll := rng.randf()
			if progress >= OVERLAY_BAND.x and progress <= OVERLAY_BAND.y and roll < OVERLAY_DENSITY * progress 					and not _has_neighbour(result, Vector2i(x, y)):
				result.append(Vector2i(x, y))
	return result


static func _has_neighbour(tiles: Array[Vector2i], tile: Vector2i) -> bool:
	for other in tiles:
		if absi(other.x - tile.x) <= 1 and absi(other.y - tile.y) <= 1:
			return true
	return false
