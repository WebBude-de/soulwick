extends GutTest
## Stone guardians (A9, KONZEPT_RAEUME §4.3): frozen and vulnerable in any light circle, stone and
## advancing in the dark, a wind-up is cut off by the light, a started leap goes on; the variant
## places dormant statues away from the entrance, wakes them with the fight, counts them for the
## room and lets the wall torches hold them too. Draw: crypt and shadow realm only.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://enemies/variants/stone_guardian.tscn")
const GUARDIAN_DATA: EnemyData = preload("res://enemies/data/stone_guardian.tres")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_stone_guardian_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _guardian(at: Vector2) -> StoneGuardian:
	var guardian := GUARDIAN_SCENE.instantiate() as StoneGuardian
	guardian.data = GUARDIAN_DATA
	guardian.apply_scaling(8, false)
	add_child_autofree(guardian)
	guardian.global_position = at
	guardian.set_physics_process(false)
	return guardian


func _player(at: Vector2, drawn_radius := 300.0) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	player.set_physics_process(false)
	LightQuery.set_player_radius(player, drawn_radius)
	return player


func _hit(source: Node, amount := 5.0) -> DamageData:
	var hit := DamageData.new()
	hit.amount = amount
	hit.source = source
	hit.hit_id = DamageData.next_hit_id()
	return hit


func _room(room_index := 8) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(4, 4)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _attach(room: RoomController, seed_value := 5) -> StoneGuardianVariant:
	var pick := VariantTable.Pick.new()
	pick.variant_id = VariantRules.STONE_GUARDIAN
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	assert_eq(RoomVariants.attach(room, pick, rng), VariantRules.STONE_GUARDIAN)
	return CombatVariant.of(room) as StoneGuardianVariant


# --- Rules ---

func test_guardian_numbers() -> void:
	assert_eq(LightVariantRules.guardian_count(0.0, 1), 2)
	assert_eq(LightVariantRules.guardian_count(0.99, 1), 4)
	assert_eq(LightVariantRules.guardian_count(0.0, 3), 4, "+1 per extra player (MP5 parameter)")
	assert_true(LightVariantRules.guardian_frozen(true, false, 0.0), "light freezes at once")
	assert_true(LightVariantRules.guardian_frozen(false, true, LightVariantRules.GUARDIAN_THAW_DELAY * 0.5), "short dark: still frozen")
	assert_false(LightVariantRules.guardian_frozen(false, true, LightVariantRules.GUARDIAN_THAW_DELAY), "then it moves")
	assert_false(LightVariantRules.guardian_frozen(false, false, 0.0))
	assert_true(LightVariantRules.guardian_vulnerable(true))
	assert_false(LightVariantRules.guardian_vulnerable(false))


func test_draw_crypt_and_shadow_realm_only() -> void:
	var table := VariantTable.load_default()
	for biome in RoomSequence.Biome.values():
		var allowed := table.get_allowed(biome)
		var expected: bool = biome == RoomSequence.Biome.CRYPT or biome == RoomSequence.Biome.SHADOW_REALM
		assert_eq(allowed.has(VariantRules.STONE_GUARDIAN), expected, "biome %d" % biome)
	assert_eq(table.get_weight(VariantRules.STONE_GUARDIAN), table.get_weight(VariantRules.SOUL_FLAME), "same weight as the A7 variants")
	var crypt_and_shadow: Array[int] = [RoomSequence.Biome.CRYPT, RoomSequence.Biome.SHADOW_REALM]
	assert_eq(VariantTable.biome_mask(crypt_and_shadow), 5, "mask in variant_table.tres")
	var custom := VariantTable.new()
	custom.variant_ids = [&"a", &"b"] as Array[StringName]
	custom.variant_weights = [1.0, 1.0] as Array[float]
	custom.variant_biomes = [1, -1] as Array[int]
	custom.variant_biome_masks = [0, VariantTable.biome_mask([3] as Array[int])] as Array[int]
	assert_eq(custom.get_allowed(1), [&"a"] as Array[StringName], "single biome without a mask")
	assert_eq(custom.get_allowed(3), [&"b"] as Array[StringName], "the mask wins over -1")


# --- The guardian ---

func test_dark_means_stone_light_means_frozen_and_vulnerable() -> void:
	var guardian := _guardian(Vector2(1000, 0))
	var player := _player(Vector2(0, 0))
	assert_true(guardian.hurtbox.is_invulnerable(), "a dormant statue takes nothing")
	guardian.activate()
	assert_true(guardian.is_frozen(), "wakes as a frozen statue")
	assert_false(guardian.is_in_light(), "far from the player: dark")
	guardian.step_light(LightVariantRules.GUARDIAN_THAW_DELAY + 0.01, false)
	assert_false(guardian.is_frozen(), "the dark wakes it")
	assert_true(guardian.hurtbox.is_invulnerable(), "in the dark it is stone")
	var health := guardian.health.get_health()
	watch_signals(guardian.hurtbox)
	var result := guardian.hurtbox.receive_hit(_hit(player))
	assert_true(result.blocked)
	assert_eq(guardian.health.get_health(), health, "no damage in the dark")
	assert_signal_emitted(guardian.hurtbox, "deflected", "the player sees the hit bounce off")
	# The player walks up: its own light circle holds the guardian.
	player.global_position = guardian.global_position + Vector2(150, 0)
	assert_true(guardian.is_in_light())
	guardian.step_light(0.016, guardian.is_in_light())
	assert_true(guardian.is_frozen())
	assert_false(guardian.hurtbox.is_invulnerable(), "frozen = vulnerable")
	guardian.hurtbox.receive_hit(_hit(player, 5.0))
	assert_almost_eq(guardian.health.get_health(), health - 5.0, 0.01)


func test_frozen_guardian_does_not_move() -> void:
	var guardian := _guardian(Vector2(0, 0))
	_player(Vector2(100, 0))
	guardian.activate()
	var start := guardian.global_position
	guardian.set_physics_process(true)
	await wait_physics_frames(10)
	assert_true(guardian.is_frozen())
	assert_eq(guardian.global_position, start, "in the light it stands still")


func test_light_cuts_off_a_wind_up_but_not_a_leap() -> void:
	var guardian := _guardian(Vector2(0, 0))
	var player := _player(Vector2(330, 0))
	guardian.activate()
	guardian.step_light(1.0, false)
	assert_false(guardian.is_frozen())
	# In the dark and in reach: the leap's wind-up (yellow circle on the player).
	guardian.set_physics_process(true)
	await wait_physics_frames(3)
	assert_eq(guardian._state, Enemy.State.TELEGRAPH, "winds up the leap")
	assert_true(guardian._telegraph_circle.visible, "the landing spot is marked")
	guardian.set_physics_process(false)
	guardian.step_light(0.016, true)
	assert_true(guardian.is_frozen())
	assert_ne(guardian._state, Enemy.State.TELEGRAPH, "the light cuts the wind-up off")
	assert_false(guardian._telegraph_circle.visible)
	# A started leap goes on, even into the light.
	guardian.step_light(1.0, false)
	guardian._state = Enemy.State.LEAP
	guardian.step_light(0.016, true)
	assert_false(guardian.is_frozen(), "committed to the leap")
	assert_true(is_instance_valid(player))


func test_guardians_never_fall_and_ignore_knockback() -> void:
	assert_false(ChasmRules.can_enemy_fall(GUARDIAN_DATA, false), "heavy stone")
	assert_eq(GUARDIAN_DATA.knockback_resistance, 1.0)
	assert_eq(GUARDIAN_DATA.special, EnemyData.Special.LEAP_SLAM)


# --- The variant in a real room ---

func test_variant_places_dormant_statues_and_wakes_them_with_the_fight() -> void:
	var room := _room()
	var variant := _attach(room)
	assert_not_null(variant)
	var count := variant.guardians.size()
	assert_between(count, LightVariantRules.GUARDIAN_COUNT.x, LightVariantRules.GUARDIAN_COUNT.y)
	var entrance := room.tiles.get_entrance_inside_tile()
	for tile in variant.get_guardian_tiles():
		assert_gte(Vector2(tile - entrance).length(), 2.0, "away from the entrance")
	for guardian in variant.guardians:
		assert_false(guardian.active, "dormant before the fight")
		assert_true(guardian.hurtbox.is_invulnerable())
	assert_eq(room.get_alive_enemy_count(), 0, "statues do not count before the fight")
	room.activate()
	var skeletons := 0
	for child in room.enemy_container.get_children():
		if child is Enemy and not child is StoneGuardian:
			skeletons += 1
	assert_eq(room.get_alive_enemy_count(), skeletons + count, "guardians count for the room")
	assert_lt(skeletons, 4, "fewer normal enemies beside the guardians")
	for guardian in variant.guardians:
		assert_true(guardian.active)


func test_room_is_done_when_guardians_and_enemies_are_gone_and_gives_the_bonus() -> void:
	var room := _room()
	var variant := _attach(room)
	room.activate()
	for guardian in variant.get_living_guardians():
		guardian.health.take_damage(INF)
	assert_false(variant.is_finished(), "the other enemies are still there")
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)
	await wait_physics_frames(2)
	assert_true(variant.is_finished())
	assert_true(variant.is_bonus_achieved(), "cleared = bonus (KONZEPT names no failure)")
	assert_eq(variant.chests.size(), 1, "one bonus chest for the group")


func test_wall_torches_hold_the_guardians_too() -> void:
	var room := _room()
	_attach(room)
	var counted := 0
	for prop in room.get_node("Props").get_children():
		if String(prop.name).begins_with("Torch"):
			for child in prop.get_children():
				if child is LightSource:
					assert_true((child as LightSource).counts_as_light)
					counted += 1
	assert_gt(counted, 0, "the hall has wall torches")
