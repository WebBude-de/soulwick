extends GutTest
## Danger level G (KE2, D-194, D-196, KONZEPT §3): enemy HP and damage, elite chance, early elites,
## the guest type of the next biome, the loot factor and the group level. All numbers TESTWERT.

const TEST_SAVE_PATH := "user://test_danger_scaling.cfg"
const SLIME := preload("res://enemies/data/slime.tres")
const SKELETON := preload("res://enemies/data/skeleton.tres")
const ARCHER := preload("res://enemies/data/archer.tres")
const SPLITTER := preload("res://enemies/data/splitter_slime.tres")
const GOLEM := preload("res://enemies/data/golem.tres")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const BIOME_PATHS: Array[String] = [
	"res://dungeon/biomes/crypt.tres",
	"res://dungeon/biomes/slime_grotto.tres",
	"res://dungeon/biomes/shadow_realm.tres",
	"res://dungeon/biomes/ember_forge.tres",
]

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func after_each() -> void:
	RunManager.set_danger_level(0)


func after_all() -> void:
	RunManager.set_danger_level(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path


# --- Enemy HP and damage ---

func test_level_zero_changes_nothing() -> void:
	RunManager.set_danger_level(0)
	for room in [1, 5, 11, 45, 120]:
		for champion in [false, true]:
			var block := EnemyScaling.get_block(room)
			var health := pow(1.17, block) * (6.0 if champion else 1.0)
			var damage := pow(1.11, block) * (1.7 if champion else 1.0)
			assert_almost_eq(EnemyScaling.health_multiplier(room, champion), health, 0.0001, "room %d" % room)
			assert_almost_eq(EnemyScaling.damage_multiplier(room, champion), damage, 0.0001, "room %d" % room)
	assert_almost_eq(EnemyScaling.health_multiplier(11, false, 0), 1.17 * 1.17, 0.0001, "the room curve stays (D-210)")
	assert_almost_eq(EnemyScaling.damage_multiplier(11, false, 0), 1.11 * 1.11, 0.0001)


func test_health_and_damage_grow_linearly_per_level() -> void:
	for danger in [0, 1, 3, 6, 9, 15]:
		assert_almost_eq(EnemyScaling.danger_health_factor(danger), 1.0 + 0.06 * danger, 0.0001, "HP +6 %% per level (G %d)" % danger)
		assert_almost_eq(EnemyScaling.danger_damage_factor(danger), 1.0 + 0.04 * danger, 0.0001, "damage +4 %% per level (G %d)" % danger)
	assert_almost_eq(EnemyScaling.danger_health_factor(-3), 1.0, 0.0001, "below 0 counts as 0")


func test_danger_multiplies_onto_room_curve_champions_and_bosses() -> void:
	assert_almost_eq(EnemyScaling.health_multiplier(11, false, 6), 1.17 * 1.17 * 1.36, 0.0001)
	assert_almost_eq(EnemyScaling.damage_multiplier(11, false, 6), 1.11 * 1.11 * 1.24, 0.0001)
	assert_almost_eq(EnemyScaling.health_multiplier(5, true, 3), 6.0 * 1.18, 0.0001, "champions too")
	assert_almost_eq(EnemyScaling.damage_multiplier(5, true, 3), 1.7 * 1.12, 0.0001)
	assert_almost_eq(EnemyScaling.health_multiplier(15, false, 9) / EnemyScaling.health_multiplier(15, false, 0), 1.54, 0.0001, "boss rooms too")


func test_default_reads_the_run_level_once() -> void:
	RunManager.set_danger_level(6)
	assert_eq(EnemyScaling.run_danger(), 6)
	assert_almost_eq(EnemyScaling.health_multiplier(1, false), 1.36, 0.0001, "no argument = the run's level")
	assert_almost_eq(EnemyScaling.damage_multiplier(1, false), 1.24, 0.0001)
	assert_almost_eq(EnemyScaling.health_multiplier(1, false, 0), 1.0, 0.0001, "an explicit level wins")
	RunManager.set_danger_level(-2)
	assert_eq(EnemyScaling.run_danger(), 0, "never below 0")


func test_enemy_and_boss_take_the_run_level() -> void:
	RunManager.set_danger_level(5)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = SLIME
	enemy.apply_scaling(1, false)
	add_child_autofree(enemy)
	assert_almost_eq(enemy.health.get_max_health(), SLIME.max_health * 1.3, 0.01, "slime HP x1.3 at G 5")
	var boss := ENEMY_SCENE.instantiate() as Enemy
	boss.data = load("res://enemies/data/boss_bone_king.tres")
	boss.apply_scaling(15, false)
	add_child_autofree(boss)
	var plain := boss.data.max_health * EnemyScaling.health_multiplier(15, false, 0)
	assert_almost_eq(boss.health.get_max_health() / plain, 1.3, 0.01, "the boss carries the factor as well")


# --- Elites and the first cycle ---

func test_elite_chance_gains_one_and_a_half_points_per_level() -> void:
	assert_almost_eq(RoomSequence.get_elite_chance(6, 0), EnemySpawner.get_elite_chance(6), 0.0001, "G 0 = today's chance")
	assert_almost_eq(RoomSequence.get_elite_chance(40, 0), EnemySpawner.get_elite_chance(40), 0.0001)
	assert_almost_eq(RoomSequence.get_elite_chance(6, 4), 0.15 + 0.06, 0.0001)
	assert_almost_eq(RoomSequence.get_elite_chance(26, 10), 0.12 + 0.03 * 5 + 0.15, 0.0001)
	assert_almost_eq(RoomSequence.get_elite_chance(500, 0), 0.5, 0.0001, "cap like today")
	assert_almost_eq(RoomSequence.get_elite_chance(100, 20), 0.5, 0.0001, "the level never lifts the cap")


func test_elites_in_the_first_cycle_from_level_three() -> void:
	for danger in [0, 1, 2]:
		assert_eq(RoomSequence.get_elite_from_room(danger), 6, "G %d: first cycle stays a warm-up" % danger)
		assert_eq(RoomSequence.get_elite_chance(5, danger), 0.0)
	assert_eq(RoomSequence.get_elite_from_room(3), 1)
	assert_almost_eq(RoomSequence.get_elite_chance(1, 3), 0.12 + 0.045, 0.0001, "room 1 at G 3")
	assert_almost_eq(RoomSequence.get_elite_chance(5, 9), 0.12 + 0.135, 0.0001)


# --- Guest type of the next biome (from G 6) ---

func test_biome_mixing_starts_at_level_six() -> void:
	assert_false(EnemyScaling.mixes_biomes(5))
	assert_true(EnemyScaling.mixes_biomes(6))
	assert_eq(EnemyScaling.get_biome_stretch(1), 0)
	assert_eq(EnemyScaling.get_biome_stretch(15), 0)
	assert_eq(EnemyScaling.get_biome_stretch(16), 1)
	assert_eq(EnemyScaling.get_next_biome_room(3), 16)
	assert_eq(EnemyScaling.get_next_biome_room(30), 31)


func test_guest_is_a_new_type_of_the_next_biome() -> void:
	var own: Array[EnemyData] = [SLIME, SKELETON, ARCHER]
	var next: Array[EnemyData] = [SLIME, SPLITTER, SKELETON, GOLEM]
	var rng := RandomNumberGenerator.new()
	for i in 30:
		rng.seed = 100 + i
		var guest := EnemyScaling.roll_guest_type(own, next, rng)
		assert_true(guest == SPLITTER or guest == GOLEM, "never a type the biome already has")
	var same: Array[EnemyData] = [SKELETON, SLIME]
	rng.seed = 7
	var state := rng.state
	assert_null(EnemyScaling.roll_guest_type(own, same, rng), "nothing new: no guest")
	assert_eq(rng.state, state, "and no draw")


func test_add_guest_keeps_the_table_and_sets_the_share() -> void:
	var types: Array[EnemyData] = [SLIME, SKELETON]
	var weights: Array[float] = [0.6, 0.4]
	var table := [types, weights]
	var mixed := EnemyScaling.add_guest(table, SPLITTER)
	var mixed_types: Array[EnemyData] = mixed[0]
	var mixed_weights: Array[float] = mixed[1]
	assert_eq(mixed_types.size(), 3)
	assert_eq(mixed_types[2], SPLITTER)
	var total := 0.0
	for weight in mixed_weights:
		total += weight
	assert_almost_eq(mixed_weights[2] / total, EnemyScaling.GUEST_WEIGHT_SHARE, 0.0001, "guest share of the new total")
	assert_eq(types.size(), 2, "the biome's table is not changed")
	assert_eq((EnemyScaling.add_guest(table, null)[0] as Array).size(), 2, "no guest: same types")
	assert_eq((EnemyScaling.add_guest(table, SLIME)[0] as Array).size(), 2, "a type already there is not added twice")


func test_table_with_guest_rolls_once_per_biome_and_only_from_level_six() -> void:
	var biomes: Array[BiomeData] = []
	for path in BIOME_PATHS:
		biomes.append(load(path) as BiomeData)
	var crypt := biomes[0]
	var table := crypt.get_table(8)
	var guests := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var state := rng.state
	var plain := EnemyScaling.table_with_guest(table, biomes, 8, guests, rng, 5)
	assert_eq((plain[0] as Array).size(), (table[0] as Array).size(), "G 5: no guest")
	assert_eq(rng.state, state, "G 5: the dungeon RNG is not touched")
	assert_true(guests.is_empty())
	var mixed := EnemyScaling.table_with_guest(table, biomes, 8, guests, rng, 6)
	var mixed_types: Array = mixed[0]
	assert_eq(mixed_types.size(), (table[0] as Array).size() + 1, "G 6: one guest in the crypt")
	var guest: EnemyData = mixed_types[mixed_types.size() - 1]
	assert_false(crypt.enemies.has(guest), "the guest is not a crypt type")
	assert_true(biomes[1].enemies.has(guest), "the guest comes from the slime grotto")
	var after_first := rng.state
	var again := EnemyScaling.table_with_guest(crypt.get_table(12), biomes, 12, guests, rng, 6)
	assert_eq((again[0] as Array).back(), guest, "same guest for the whole biome")
	assert_eq(rng.state, after_first, "rolled once per biome")
	EnemyScaling.table_with_guest(biomes[3].get_table(50), biomes, 50, guests, rng, 6)
	assert_true(guests.has(EnemyScaling.get_biome_stretch(50)), "the ember forge gets its own guest (from the crypt)")


func test_same_seed_same_guest() -> void:
	var biomes: Array[BiomeData] = []
	for path in BIOME_PATHS:
		biomes.append(load(path) as BiomeData)
	var picks: Array = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		var mixed := EnemyScaling.table_with_guest(biomes[2].get_table(35), biomes, 35, {}, rng, 8)
		picks.append((mixed[0] as Array).back())
	assert_eq(picks[0], picks[1], "co-op: the host's seed decides, same run = same guest")


# --- Loot and group ---

func test_loot_gains_five_percent_per_level() -> void:
	assert_eq(EconomySystem.apply_danger_loot(100, 0), 100, "G 0 unchanged")
	assert_eq(EconomySystem.apply_danger_loot(100, 6), 130)
	assert_eq(EconomySystem.apply_danger_loot(3, 9), 4, "3 crystals x1.45 = 4.35 -> 4")
	assert_eq(EconomySystem.apply_danger_loot(10, 1), 11, "10.5 rounds up")
	assert_eq(EconomySystem.apply_danger_loot(0, 9), 0)
	assert_almost_eq(EconomySystem.danger_loot_factor(4), 1.2, 0.0001)


func test_group_level_is_the_rounded_mean() -> void:
	assert_eq(CoopRules.group_danger([4]), 4, "alone: own level")
	assert_eq(CoopRules.group_danger([0, 9]), 5, "4.5 rounds up")
	assert_eq(CoopRules.group_danger([2, 3, 3]), 3)
	assert_eq(CoopRules.group_danger([1, 1, 2, 2]), 2)
	assert_eq(CoopRules.group_danger([6, 6, 6, 0]), 5, "4.5 -> 5: the low player does not pull it to 4")
	assert_eq(CoopRules.group_danger([-3, 3]), 2, "below 0 counts as 0 (1.5 -> 2)")
	assert_eq(CoopRules.group_danger([]), 0)
