extends GutTest
## Five-room cycle, boss rooms, spawn ranges and special room draws (D-002 .. D-006, D-009).


func test_five_room_cycle() -> void:
	assert_eq(RoomSequence.get_room_type(1), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(2), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(3), RoomSequence.RoomType.COMBAT_UPGRADE)
	assert_eq(RoomSequence.get_room_type(4), RoomSequence.RoomType.SPECIAL)
	assert_eq(RoomSequence.get_room_type(5), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(6), RoomSequence.RoomType.COMBAT)
	assert_eq(RoomSequence.get_room_type(8), RoomSequence.RoomType.COMBAT_UPGRADE)


func test_boss_every_fifteen_rooms_endlessly() -> void:
	assert_eq(RoomSequence.get_room_type(10), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(15), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(30), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(45), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_room_type(50), RoomSequence.RoomType.MINIBOSS)
	assert_eq(RoomSequence.get_room_type(105), RoomSequence.RoomType.BOSS, "endless: bosses keep coming")


func test_enemy_count_range() -> void:
	assert_eq(RoomSequence.get_enemy_count_range(1), Vector2i(1, 2), "gentle start")
	assert_eq(RoomSequence.get_enemy_count_range(6), Vector2i(2, 3))
	assert_eq(RoomSequence.get_enemy_count_range(16), Vector2i(2, 4))
	assert_eq(RoomSequence.get_enemy_count_range(31), Vector2i(3, 5))


func test_biomes_and_boss_tiers() -> void:
	assert_eq(RoomSequence.get_biome(1), RoomSequence.Biome.CRYPT)
	assert_eq(RoomSequence.get_biome(16), RoomSequence.Biome.SLIME_GROTTO)
	assert_eq(RoomSequence.get_biome(45), RoomSequence.Biome.SHADOW_REALM)
	assert_eq(RoomSequence.get_biome(60), RoomSequence.Biome.EMBER_FORGE)
	assert_eq(RoomSequence.get_biome(61), RoomSequence.Biome.CRYPT)
	assert_eq(RoomSequence.get_boss_tier(60), 0)
	assert_eq(RoomSequence.get_boss_tier(75), 1, "second cycle of bosses")


func test_special_type_never_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var previous := -1
	var seen := {}
	for i in 400:
		var special := RoomSequence.roll_special_type(previous, rng)
		assert_ne(special, previous)
		seen[special] = true
		previous = special
	assert_eq(seen.size(), RoomSequence.SpecialType.size(), "every special type appears")


func test_portal_chance_is_about_thirty_percent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var portals := 0
	for i in 5000:
		if RoomSequence.roll_portal(rng):
			portals += 1
	assert_almost_eq(portals / 5000.0, 0.3, 0.03)
