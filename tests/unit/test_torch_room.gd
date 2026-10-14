extends GutTest
## Torch room (A9, KONZEPT_RAEUME §4.7, shadow realm only): unlit torch stands, lit for good by a
## player's hit or E (never by enemies), every burning torch widens the light circle and is a light
## for LightQuery, enemies in torchlight deal -20 % damage (and get their own data back outside),
## all torches burning = bonus chest.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
## Rooms 31-45 lie in the shadow realm.
const SHADOW_ROOM := 38

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_torch_room_save.cfg"


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


func _room(room_index := SHADOW_ROOM) -> RoomController:
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


func _attach(room: RoomController, seed_value := 5) -> TorchRoomVariant:
	var pick := VariantTable.Pick.new()
	pick.variant_id = VariantRules.TORCH_ROOM
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	assert_eq(RoomVariants.attach(room, pick, rng), VariantRules.TORCH_ROOM)
	return CombatVariant.of(room) as TorchRoomVariant


func _hit(source: Node) -> DamageData:
	var hit := DamageData.new()
	hit.amount = 3.0
	hit.source = source
	hit.hit_id = DamageData.next_hit_id()
	return hit


## Beats every enemy, also later waves (deeper rooms fight in two waves).
func _clear(room: RoomController) -> void:
	for sweep in 5:
		var living := _living(room)
		if living.is_empty():
			return
		for enemy in living:
			enemy.health.take_damage(INF)
		await wait_physics_frames(3)


func _living(room: RoomController) -> Array[Enemy]:
	var living: Array[Enemy] = []
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			living.append(enemy)
	return living


# --- Rules and draw ---

func test_torch_numbers() -> void:
	assert_eq(LightVariantRules.torch_count(0.0, 20), LightVariantRules.TORCH_COUNT.x)
	assert_eq(LightVariantRules.torch_count(0.99, 20), LightVariantRules.TORCH_COUNT.y)
	assert_eq(LightVariantRules.torch_count(0.99, 3), 3, "never more than there is room for")
	assert_almost_eq(LightVariantRules.torch_vision_factor(0, 4), LightVariantRules.TORCH_ROOM_VISION_FACTOR, 0.001, "dark at the start")
	assert_almost_eq(LightVariantRules.torch_vision_factor(4, 4), 1.0, 0.001, "the normal circle when all burn")
	assert_gt(LightVariantRules.torch_vision_factor(2, 4), LightVariantRules.torch_vision_factor(1, 4), "every torch widens the sight")
	assert_almost_eq(LightVariantRules.enemy_damage_factor(true), 0.8, 0.001, "-20 % in torchlight")
	assert_eq(LightVariantRules.enemy_damage_factor(false), 1.0)
	assert_true(LightVariantRules.torches_complete(4, 4))
	assert_false(LightVariantRules.torches_complete(3, 4))
	assert_false(LightVariantRules.torches_complete(0, 0))


func test_torch_room_only_in_the_shadow_realm() -> void:
	var table := VariantTable.load_default()
	for biome in RoomSequence.Biome.values():
		assert_eq(table.get_allowed(biome).has(VariantRules.TORCH_ROOM), biome == RoomSequence.Biome.SHADOW_REALM, "biome %d" % biome)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 4000:
		var room := 6 + i % 70
		var pick := table.roll(room, RoomSequence.RoomType.COMBAT, &"", rng)
		if pick.variant_id == VariantRules.TORCH_ROOM:
			assert_eq(RoomSequence.get_biome(room), RoomSequence.Biome.SHADOW_REALM, "room %d" % room)


# --- A torch ---

func test_player_hit_or_e_lights_a_torch_enemies_never() -> void:
	var torch := RoomTorch.new()
	torch.build()
	add_child_autofree(torch)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var enemy_hit := _hit(Enemy.new())
	assert_true(torch.get_hurtbox().receive_hit(enemy_hit).blocked)
	assert_false(torch.lit, "enemies never light torches")
	enemy_hit.source.free()
	watch_signals(torch)
	var result := torch.get_hurtbox().receive_hit(_hit(player))
	assert_true(result.blocked, "no damage, no on-hit effects, projectiles fly on")
	assert_true(torch.lit)
	assert_signal_emitted(torch, "ignited")
	assert_true(torch.light.counts_as_light, "a burning torch is light")
	assert_false(torch.get_interactable().enabled)
	assert_false(torch.ignite(player), "lit for good, once")
	var other := RoomTorch.new()
	other.build()
	add_child_autofree(other)
	other.get_interactable().interact(player)
	assert_true(other.lit, "E lights it too")


# --- The variant ---

func test_torches_stand_unlit_away_from_the_doors() -> void:
	var room := _room()
	var variant := _attach(room)
	assert_between(variant.torches.size(), LightVariantRules.TORCH_COUNT.x, LightVariantRules.TORCH_COUNT.y)
	var doors: Array[Vector2i] = [room.tiles.get_entrance_inside_tile(), room.tiles.get_exit_inside_tile()]
	for torch in variant.torches:
		assert_false(torch.lit)
		var tile := RoomTiles.local_to_tile(torch.position)
		assert_true(VariantSpots.is_clear_of(tile, doors, LightVariantRules.TORCH_DOOR_CLEARANCE), "away from the doors")


func test_room_goes_dark_and_all_torches_give_the_bonus() -> void:
	var room := _room()
	var variant := _attach(room)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	room.activate()
	for prop in room.get_node("Props").get_children():
		if String(prop.name).begins_with("Torch"):
			assert_false((prop as Node2D).visible, "the wall torches are out")
	for torch in variant.torches:
		torch.ignite(player)
	assert_eq(variant.get_lit_count(), variant.torches.size())
	assert_true(variant.is_bonus_achieved(), "all torches burn")
	await _clear(room)
	assert_true(variant.is_finished())
	assert_eq(variant.chests.size(), 1)


func test_unlit_torches_at_the_end_mean_no_bonus() -> void:
	var room := _room()
	var variant := _attach(room)
	room.activate()
	variant.torches[0].ignite(null)
	await _clear(room)
	assert_true(variant.is_finished(), "the room is done as always")
	assert_false(variant.is_bonus_achieved())
	assert_eq(variant.chests.size(), 0)


func test_enemies_in_torchlight_deal_less_damage() -> void:
	var room := _room()
	var variant := _attach(room)
	room.activate()
	var enemy := _living(room)[0]
	var original := enemy.data
	var torch := variant.torches[0]
	torch.ignite(null)
	enemy.global_position = torch.light.get_lit_center() + Vector2(10, 0)
	assert_true(variant.is_in_torchlight(enemy))
	variant.update_enemy_damage()
	assert_true(variant.is_dimmed(enemy))
	assert_almost_eq(enemy.data.damage, original.damage * LightVariantRules.TORCH_DAMAGE_FACTOR, 0.001)
	assert_eq(original.damage, SKELETON.damage, "the shared .tres stays untouched")
	assert_eq(enemy.data.id, original.id)
	enemy.global_position = torch.light.get_lit_center() + Vector2(torch.light.get_lit_radius() + 50.0, 0)
	variant.update_enemy_damage()
	assert_false(variant.is_dimmed(enemy))
	assert_eq(enemy.data, original, "its own data back outside the light")
