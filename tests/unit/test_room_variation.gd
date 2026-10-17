extends GutTest
## Invisible variation of combat rooms (D-113, A3): theme groups and the quiet room
## (8 %, same total health), as EncounterGroup data for the spawner (A5).

const DRAWS := 20000

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_variation_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _biome(id: String) -> BiomeData:
	return load("res://dungeon/biomes/%s.tres" % id) as BiomeData


func test_early_rooms_and_other_types_stay_plain() -> void:
	var rng := _rng(1)
	for room_index in range(1, EncounterVariation.FROM_ROOM):
		for i in 200:
			assert_true(EncounterVariation.roll(room_index, RoomSequence.RoomType.COMBAT, rng).is_plain(), "room %d" % room_index)
	assert_true(EncounterVariation.roll(20, RoomSequence.RoomType.MINIBOSS, rng).is_plain())


func test_roll_draws_three_numbers_for_combat_rooms_only() -> void:
	var a := _rng(9)
	var b := _rng(9)
	EncounterVariation.roll(3, RoomSequence.RoomType.COMBAT, a)
	b.randf()
	b.randf()
	b.randf()
	assert_eq(a.randi(), b.randi(), "three draws, also before FROM_ROOM")
	var c := _rng(9)
	EncounterVariation.roll(20, RoomSequence.RoomType.SPECIAL, c)
	assert_eq(c.randi(), _rng(9).randi(), "no draw for special rooms")


func test_quiet_room_share_and_theme_shares() -> void:
	var rng := _rng(42)
	var quiet := 0
	var themes: Array[float] = [0.0, 0.0, 0.0]
	for i in DRAWS:
		var plan := EncounterVariation.roll(17, RoomSequence.RoomType.COMBAT, rng)
		if plan.quiet:
			quiet += 1
		themes[plan.theme] += 1.0
	assert_almost_eq(float(quiet) / DRAWS, EncounterVariation.QUIET_CHANCE, 0.01, "about 8 % quiet rooms")
	for theme in themes.size():
		assert_almost_eq(themes[theme] / DRAWS, EncounterVariation.THEME_WEIGHTS[theme], 0.015, EncounterVariation.get_theme_name(theme))


func test_arena_is_never_quiet() -> void:
	var rng := _rng(5)
	for i in 2000:
		assert_false(EncounterVariation.roll(20, RoomSequence.RoomType.COMBAT, rng, RoomSequence.RoomKind.ARENA).quiet)


func test_quiet_group_keeps_the_total_health() -> void:
	for biome_id in ["crypt", "slime_grotto", "shadow_realm", "ember_forge"]:
		var biome := _biome(biome_id)
		for room_index in [8, 20, 40]:
			var limits := RoomSequence.get_enemy_count_range(room_index)
			var group := EncounterVariation.make_quiet_group(room_index, biome, 2)
			var table := biome.get_table(room_index)
			var types: Array[EnemyData] = table[0]
			var weights: Array[float] = table[1]
			var filtered := group.filter_table(types, weights)
			var quiet_types: Array[EnemyData] = filtered[0]
			var quiet_weights: Array[float] = filtered[1]
			var count := group.count_range.x
			assert_lt(count, limits.x + 1, "%s room %d: fewer enemies" % [biome_id, room_index])
			var normal_total := (limits.x + limits.y) * 0.5 * EncounterVariation.average_health(types, weights)
			var quiet_total := count * EncounterVariation.average_health(quiet_types, quiet_weights) * group.health_factor
			assert_almost_eq(quiet_total, normal_total, normal_total * 0.2, "%s room %d: same total health" % [biome_id, room_index])
			for data in quiet_types:
				assert_false(EncounterVariation.is_ranged(data), "%s: quiet enemies fight up close" % biome_id)


func test_theme_groups_filter_the_table() -> void:
	var crypt := _biome("crypt")
	var table := crypt.get_table(20)
	var ranged := EncounterVariation.build_group(_plan(EncounterVariation.GroupTheme.RANGED), 20, crypt)
	assert_not_null(ranged)
	var kept: Array[EnemyData] = ranged.filter_table(table[0], table[1])[0]
	for data in kept:
		assert_true(EncounterVariation.is_ranged(data), "%s is ranged" % data.id)
	assert_null(EncounterVariation.build_group(_plan(EncounterVariation.GroupTheme.MIXED), 20, crypt), "mixed = default rules")
	var swarm := EncounterVariation.build_group(_plan(EncounterVariation.GroupTheme.SWARM), 20, crypt)
	assert_eq(swarm.id, &"swarm")
	assert_true(swarm.tags.has(EncounterVariation.SWARM_TAG))


func test_mixed_weights_keep_the_average_shares() -> void:
	# D-010, D-075: themed rooms must not shift the mix over many rooms.
	for biome_id in ["crypt", "slime_grotto", "shadow_realm", "ember_forge"]:
		var table := _biome(biome_id).get_table(40)
		var types: Array[EnemyData] = table[0]
		var weights: Array[float] = table[1]
		var total_weights := 0.0
		for weight in weights:
			total_weights += weight
		var themed_total := 0.0
		for share in EncounterVariation.THEME_WEIGHTS:
			themed_total += share
		var mixed := EncounterVariation.weights_for_theme(types, weights, EncounterVariation.GroupTheme.MIXED)
		var ranged := EncounterVariation.weights_for_theme(types, weights, EncounterVariation.GroupTheme.RANGED)
		var swarm := EncounterVariation.weights_for_theme(types, weights, EncounterVariation.GroupTheme.SWARM)
		var shares: Array = [mixed, ranged, swarm]
		# A theme whose types are rarer than the theme itself cannot be balanced out exactly
		# (shadow realm: slimes 12 % < swarm rooms 15 %); then mixed rooms leave that type out.
		var clamped := false
		for i in types.size():
			clamped = clamped or (mixed[i] <= 0.0 and weights[i] > 0.0)
		if clamped:
			for i in types.size():
				if weights[i] > 0.0 and not EncounterVariation.is_swarm(types[i]) and not EncounterVariation.is_ranged(types[i]):
					assert_gt(mixed[i], weights[i], "%s: %s more often in mixed rooms" % [biome_id, types[i].id])
			continue
		for i in types.size():
			var average := 0.0
			for theme in 3:
				var theme_weights: Array[float] = shares[theme]
				var sum := 0.0
				for weight in theme_weights:
					sum += weight
				average += EncounterVariation.THEME_WEIGHTS[theme] / themed_total * theme_weights[i] / sum
			assert_almost_eq(average, weights[i] / total_weights, 0.01, "%s: %s keeps its share" % [biome_id, types[i].id])


func _plan(theme: EncounterVariation.GroupTheme) -> EncounterVariation.Plan:
	var plan := EncounterVariation.Plan.new()
	plan.theme = theme
	return plan
