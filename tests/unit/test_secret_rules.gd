extends GutTest
## Secret niches (A10, D-109, D-117, R1): the draw (from room 6, normal and chasm rooms,
## fixed RNG draws, content weights), only explosions break a cracked wall, the niche places of every
## template keep the room whole, and a niche in the tree: sealed, tapped by a sword, opened by a
## barrel blast, its content (chest, crystals, wandering merchant with the shop's prices).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_secret_rules_save.cfg"


func after_all() -> void:
	SecretRules.chance_override = -1.0
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	SecretRules.chance_override = -1.0
	HitStop.reset()
	await wait_process_frames(1)


func _damage(tags: Array[StringName], area := false) -> DamageData:
	var damage := DamageData.new()
	damage.amount = 10.0
	damage.tags.assign(tags)
	damage.has_impact_position = area
	return damage


# --- Rules ---

func test_only_explosions_break_a_cracked_wall() -> void:
	assert_true(SecretRules.breaks_wall(_damage([&"explosion"])), "barrel, bomber, explosive hit")
	assert_true(SecretRules.breaks_wall(_damage([&"melee", &"heavy"], true)), "hammer slam / staff impact (area hit)")
	assert_false(SecretRules.breaks_wall(_damage([&"melee"])), "sword")
	assert_false(SecretRules.breaks_wall(_damage([&"projectile"])), "arrow")
	assert_false(SecretRules.breaks_wall(null))


func test_draw_uses_fixed_rng_values_and_eligibility() -> void:
	for kind in [RoomSequence.RoomKind.NORMAL, RoomSequence.RoomKind.ARENA]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		SecretRules.roll(9, RoomSequence.RoomType.COMBAT, kind, rng)
		var reference := RandomNumberGenerator.new()
		reference.seed = 4
		for i in SecretRules.DRAWS:
			reference.randf()
		assert_eq(rng.state, reference.state)
	SecretRules.chance_override = 1.0
	var rng := RandomNumberGenerator.new()
	assert_false(SecretRules.roll(5, RoomSequence.RoomType.COMBAT, RoomSequence.RoomKind.NORMAL, rng).has_secret, "not before room 6")
	assert_false(SecretRules.roll(9, RoomSequence.RoomType.COMBAT, RoomSequence.RoomKind.ARENA, rng).has_secret, "arenas keep their walls")
	assert_true(SecretRules.roll(9, RoomSequence.RoomType.COMBAT, RoomSequence.RoomKind.CHASM, rng).has_secret)
	assert_false(SecretRules.roll(9, RoomSequence.RoomType.SPECIAL, -1, rng).has_secret)


func test_one_in_eight_rooms_and_a_rare_merchant() -> void:
	var secrets := 0
	var contents := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 4000:
		var pick := SecretRules.roll(12, RoomSequence.RoomType.COMBAT, RoomSequence.RoomKind.NORMAL, rng)
		if pick.has_secret:
			secrets += 1
			contents[pick.content] = contents.get(pick.content, 0) + 1
	assert_almost_eq(secrets / 4000.0, SecretRules.CHANCE, 0.02)
	assert_lt(contents.get(SecretRules.Content.MERCHANT, 0), contents.get(SecretRules.Content.CRYSTAL, 0), "the merchant is the rarest")
	assert_gt(contents.get(SecretRules.Content.CHEST, 0), contents.get(SecretRules.Content.CRYSTAL, 0))


func test_niche_geometry() -> void:
	var site := SecretRules.site_at(Vector2i(5, -1))
	assert_true(site.is_in_north_wall())
	assert_eq(site.niche, [Vector2i(4, -3), Vector2i(5, -3), Vector2i(6, -3)] as Array[Vector2i], "behind the north wall")
	assert_eq(site.crack, Vector2i(5, -1), "the north wall's brick front")
	assert_eq(site.opening, [Vector2i(5, -2), Vector2i(5, -1)] as Array[Vector2i], "crown and front open")
	assert_eq(site.approach, Vector2i(5, 0))
	assert_eq(site.get_content_tile(), Vector2i(5, -3))
	assert_eq(site.get_rect(), Rect2i(4, -3, 3, 1))
	var inner := SecretRules.site_at(Vector2i(3, 2))
	assert_false(inner.is_in_north_wall(), "cut into an inner wall")
	assert_eq(inner.get_rect(), Rect2i(2, 0, 3, 1))


## Nearly every plan that may get a niche has a place for it (north wall or a thick inner wall; a
## plan without one simply never gets a niche); the niche is sealed until the wall opens, the floor
## plan stays as it is.
func test_every_template_has_a_sealed_niche_place() -> void:
	var catalog := RoomCatalog.create()
	var without: Array[StringName] = []
	var total := 0
	for entry in catalog.get_entries():
		if entry.room_kind == RoomSequence.RoomKind.ARENA or not entry.is_plain_fight():
			continue
		total += 1
		var room := entry.scene.instantiate() as RoomController
		autofree(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		var forbidden := {}
		for marker in IngredientScatter.get_marker_tiles(room):
			forbidden[marker] = true
		var sites := SecretRules.find_sites(tiles, forbidden)
		if sites.is_empty():
			without.append(entry.id)
			continue
		var before := tiles.get_reachable_tiles()
		for candidate in sites:
			assert_false(SecretRules._beside_fixture(candidate.crack, tiles.front_fixtures), "%s: no crack beside a niche, gate or torch" % entry.id)
			if candidate.is_in_north_wall() and tiles.secret_cracks.is_empty():
				assert_gte(absi(candidate.crack.x - tiles.exit_x), SecretRules.DOOR_CLEARANCE, "%s: away from the exit door" % entry.id)
		var site := sites[sites.size() / 2]
		SecretNiche.carve(room, site)
		assert_true(WallAutotile.is_valid_mass(tiles.get_wall_mass(), tiles.room_size), "%s: walls stay two tiles tall" % entry.id)
		var after := tiles.get_reachable_tiles()
		assert_eq(after.size(), before.size(), "%s: the floor plan stays" % entry.id)
		for tile in site.niche:
			assert_true(tiles.is_walkable(tile), "%s: niche floor %s" % [entry.id, tile])
			assert_false(after.has(tile), "%s: niche sealed" % entry.id)
		assert_true(tiles.is_painted(site.get_content_tile() + Vector2i.UP), "%s: rock above the niche" % entry.id)
		tiles.open_wall_tiles(site.opening)
		assert_true(tiles.get_reachable_tiles().has(site.get_content_tile()), "%s: open after the break" % entry.id)
	gut.p("plans without a niche place: %s" % [without])
	assert_lte(without.size(), total / 4, "most plans can hide a niche (%d of %d without)" % [without.size(), total])


# --- In the tree ---

func _room() -> RoomController:
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 21
	room.setup(9, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	return room


func _niche(room: RoomController, content: SecretRules.Content) -> SecretNiche:
	var tiles := room.get_node("Tiles") as RoomTiles
	var forbidden := {}
	for marker in IngredientScatter.get_marker_tiles(room):
		forbidden[marker] = true
	var site := SecretRules.find_sites(tiles, forbidden)[0]
	SecretNiche.carve(room, site)
	add_child_autofree(room)
	return SecretNiche.attach(room, site, content)


func test_a_sword_taps_and_a_blast_breaks_the_wall() -> void:
	var room := _room()
	var niche := _niche(room, SecretRules.Content.CHEST)
	assert_false(niche.is_open)
	assert_false(room.tiles.get_reachable_tiles().has(niche.site.get_content_tile()), "sealed")
	watch_signals(niche)
	niche.get_hurtbox().receive_hit(_damage([&"melee"]))
	assert_false(niche.is_open, "a sword does not break it")
	await wait_physics_frames(2)
	var blast := BarrelBlast.create(96.0, 0.0, 0.0, 0.0)
	room.add_child(blast)
	blast.global_position = room.to_global(RoomTiles.tile_center(niche.site.approach))
	await wait_physics_frames(3)
	assert_true(niche.is_open, "the barrel blast breaks it")
	assert_signal_emitted(niche, "opened")
	assert_true(room.tiles.get_reachable_tiles().has(niche.site.get_content_tile()), "the way into the niche is free")
	assert_true(niche.content is TreasureChest, "a chest waits behind it")
	assert_false(niche.break_open(), "breaks once")


func test_bomber_blast_on_the_player_layer_breaks_it_too() -> void:
	var room := _room()
	var niche := _niche(room, SecretRules.Content.CRYSTAL)
	await wait_physics_frames(2)
	var blast := Blast.spawn(room, room.to_global(RoomTiles.tile_center(niche.site.approach)), 72.0, 1.0)
	assert_eq(blast.target_mask, PhysicsLayers.PLAYER_HURTBOX)
	await wait_physics_frames(3)
	assert_true(niche.is_open)


func test_crystals_in_the_niche() -> void:
	var room := _room()
	var niche := _niche(room, SecretRules.Content.CRYSTAL)
	niche.break_open()
	var crystal := niche.content as SecretCrystal
	assert_not_null(crystal)
	var before := RunManager.get_run_crystals()
	watch_signals(niche)
	assert_true(crystal.collect(null))
	assert_eq(RunManager.get_run_crystals(), before + SecretRules.CRYSTALS)
	assert_signal_emitted(niche, "content_used")
	assert_false(crystal.collect(null), "taken once")


func test_wandering_merchant_sells_rare_goods_at_shop_prices() -> void:
	var room := _room()
	var upgrades := UpgradeManager.new()
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))
	add_child_autofree(upgrades)
	var economy := EconomySystem.new()
	economy.config = load("res://economy/data/economy_config.tres") as EconomyConfig
	add_child_autofree(economy)
	room.context.upgrade_manager = upgrades
	room.context.economy = economy
	if upgrades.upgrade_pool.is_empty():
		pending("upgrade pool not configured in a bare UpgradeManager")
		return
	var offers := WanderingMerchant.roll_offers(room.context, 9)
	assert_between(offers.size(), 1, WanderingMerchant.OFFER_COUNT)
	var rare := 0
	for offer in offers:
		assert_eq(offer.kind, ShopOffer.Kind.UPGRADE)
		assert_eq(offer.price, economy.get_price(ShopOffer.Kind.UPGRADE, 9), "the shop's price formula (D-109)")
		if WanderingMerchant.RARE_CATEGORIES.has(offer.upgrade.category):
			rare += 1
	assert_gt(rare, 0, "rarer goods than the shop")


func test_merchant_stands_in_the_niche() -> void:
	var room := _room()
	var niche := _niche(room, SecretRules.Content.MERCHANT)
	niche.break_open()
	assert_true(niche.content is WanderingMerchant)
	var interactable: Interactable = null
	for child in niche.content.get_children():
		if child is Interactable:
			interactable = child
	assert_not_null(interactable, "trade with E")
