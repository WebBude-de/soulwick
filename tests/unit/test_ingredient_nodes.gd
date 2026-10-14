extends GutTest
## Ingredient nodes (A3): dark zone decision, light island, explosive barrel (fuse, chain reaction),
## treasure chest (locked until the room is cleared, opens once, D-109), placeholder art.

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_ingredient_nodes_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_dark_zone_factor_for_any_point() -> void:
	var zone := DarkZone.new()
	zone.radius = 100.0
	zone.vision_factor = 0.5
	add_child_autofree(zone)
	zone.global_position = Vector2(500, 500)
	assert_eq(DarkZone.get_vision_factor_at(get_tree(), Vector2(500, 500)), 0.5, "full factor in the middle")
	assert_eq(DarkZone.get_vision_factor_at(get_tree(), Vector2(500, 640)), 1.0, "no effect outside")
	var edge := DarkZone.get_vision_factor_at(get_tree(), Vector2(500, 575))
	assert_between(edge, 0.5, 1.0, "smooth edge")
	# A second zone: the darker one wins, per point (every player gets their own factor).
	var deep := DarkZone.new()
	deep.radius = 100.0
	deep.vision_factor = 0.3
	add_child_autofree(deep)
	deep.global_position = Vector2(520, 500)
	assert_almost_eq(DarkZone.get_vision_factor_at(get_tree(), Vector2(520, 500)), 0.3, 0.001)


func test_light_island_lights_and_blocks() -> void:
	for style in [IngredientSet.LightStyle.CRYSTAL, IngredientSet.LightStyle.TORCH_STAND]:
		var island := LightIsland.create(style, Color(0.6, 1.0, 0.7))
		add_child_autofree(island)
		assert_not_null(island.light)
		assert_true(island.light.is_in_group(LightSource.GROUP), "VisionOverlay sees it")
		assert_gt(island.light.radius, 100.0)
		assert_not_null(island.get_node_or_null("Blocker"), "pedestal blocks")


func test_placeholder_art_has_the_briefing_sizes() -> void:
	var sizes := {
		"light_crystal_4f": Vector2i(128, 32),
		"torch_stand_4f": Vector2i(64, 40),
		"explosive_barrel": Vector2i(32, 32),
		"explosive_barrel_fuse_4f": Vector2i(128, 32),
		"chest_closed": Vector2i(32, 32),
		"chest_open_4f": Vector2i(128, 32),
	}
	for file_name: String in sizes:
		var texture := IngredientArt.get_texture(file_name)
		assert_not_null(texture, file_name)
		if not IngredientArt.has_file(file_name):
			assert_eq(Vector2i(texture.get_size()), sizes[file_name], "%s placeholder size" % file_name)


func _hit(target: Node, amount: float) -> void:
	var damage := DamageData.new()
	damage.amount = amount
	damage.hit_id = DamageData.next_hit_id()
	(target.get_node("Hurtbox") as Hurtbox).receive_hit(damage)


func test_explosive_barrel_lights_its_fuse_and_explodes() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var barrel := load("res://dungeon/rooms/ingredients/explosive_barrel.tscn").instantiate() as ExplosiveBarrel
	holder.add_child(barrel)
	barrel.global_position = Vector2(300, 300)
	_hit(barrel, 999.0)
	assert_true(barrel.is_lit(), "fuse burns")
	var blasts := holder.get_children().filter(func(n: Node) -> bool: return n is BarrelBlast)
	assert_eq(blasts.size(), 1, "one blast with a warning circle")
	var blast := blasts[0] as BarrelBlast
	assert_eq(blast.delay, ExplosiveBarrel.FUSE_TIME)
	assert_eq(blast.damage, ExplosiveBarrel.PLAYER_DAMAGE)
	assert_eq(blast.enemy_damage, ExplosiveBarrel.ENEMY_DAMAGE)
	assert_true(blast.target_mask & PhysicsLayers.PLAYER_HURTBOX != 0)
	# A second hit during the fuse changes nothing.
	_hit(barrel, 999.0)
	assert_eq(holder.get_children().filter(func(n: Node) -> bool: return n is BarrelBlast).size(), 1)


func test_chain_reaction_breaks_the_neighbour() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var first := load("res://dungeon/rooms/ingredients/explosive_barrel.tscn").instantiate() as ExplosiveBarrel
	var second := load("res://dungeon/rooms/ingredients/explosive_barrel.tscn").instantiate() as ExplosiveBarrel
	holder.add_child(first)
	holder.add_child(second)
	first.global_position = Vector2(300, 300)
	second.global_position = Vector2(360, 300)
	await wait_physics_frames(2)
	_hit(first, 999.0)
	await wait_seconds(ExplosiveBarrel.FUSE_TIME + 0.3)
	assert_true(not is_instance_valid(second) or second.is_lit(), "the blast set off the barrel next to it")


func test_chest_opens_once_after_the_fight() -> void:
	# A plan with a chest guarded by traps (R1, katakombengang).
	var room := preload("res://dungeon/rooms/combat/katakombengang_crypt.tscn").instantiate() as RoomController
	add_child_autofree(room)
	var chest: TreasureChest = null
	for prop in room.get_node("Props").get_children():
		if prop is TreasureChest:
			chest = prop
	assert_not_null(chest, "the catacomb passage has its chest")
	assert_true(chest.is_locked(), "locked while the room is not cleared")
	watch_signals(chest)
	chest.get_interactable().interact(null)
	assert_signal_not_emitted(chest, "opened", "a locked chest does not open")
	room._complete()
	assert_false(chest.is_locked(), "open after the room is completed")
	chest._on_interacted(null)
	assert_signal_emit_count(chest, "opened", 1)
	assert_true(chest.is_open)
	chest._on_interacted(null)
	assert_signal_emit_count(chest, "opened", 1, "only once")
	assert_eq(chest.upgrade_choices, 1, "one upgrade choice (D-109, TESTWERT)")
