extends GutTest
## Pure rules for bosses, champions, badges, hints, art lookup and biome hazards.

const SKELETON := preload("res://enemies/data/skeleton.tres")
const SLIME := preload("res://enemies/data/slime.tres")
const ARCHER := preload("res://enemies/data/archer.tres")
const BOMBER := preload("res://enemies/data/bomber.tres")
const SHADOW := preload("res://enemies/data/shadow.tres")
const GOLEM := preload("res://enemies/data/golem.tres")
const NECROMANCER := preload("res://enemies/data/necromancer.tres")
const SPLITTER := preload("res://enemies/data/splitter_slime.tres")
const BOSSES: Array[String] = [
	"res://enemies/data/boss_bone_king.tres",
	"res://enemies/data/boss_slime_queen.tres",
	"res://enemies/data/boss_shadow_lord.tres",
	"res://enemies/data/boss_ember_golem.tres",
]


# --- BossRules ---

func test_enrage_threshold() -> void:
	assert_false(BossRules.should_enrage(60.0, 100.0, 1))
	assert_true(BossRules.should_enrage(50.0, 100.0, 1), "exactly half")
	assert_true(BossRules.should_enrage(10.0, 100.0, 1))
	assert_false(BossRules.should_enrage(10.0, 100.0, 2), "only once")
	assert_false(BossRules.should_enrage(0.0, 100.0, 1), "not when dead")


func test_patterns_grow_with_phase_and_tier() -> void:
	assert_eq(BossRules.volley_waves(0, 1, true), 1, "tier 0 phase 1: single ring")
	assert_eq(BossRules.volley_waves(0, 2, false), 2)
	assert_eq(BossRules.volley_waves(0, 2, true), 3, "spiral in phase 2")
	assert_eq(BossRules.volley_waves(2, 1, false), 2, "tier 2 already doubles in phase 1")
	assert_lte(BossRules.volley_waves(9, 2, true), BossRules.MAX_VOLLEY_WAVES)
	assert_eq(BossRules.special_repeats(0, 1, 2), 0)
	assert_eq(BossRules.special_repeats(0, 2, 2), 2)
	assert_eq(BossRules.special_repeats(1, 2, 2), 3)
	assert_eq(BossRules.special_repeats(5, 2, 9), BossRules.MAX_SPECIAL_REPEATS, "capped")
	assert_eq(BossRules.landing_ring_count(0, 1, 10), 0)
	assert_eq(BossRules.landing_ring_count(1, 1, 10), 5, "half ring from tier 1")
	assert_eq(BossRules.landing_ring_count(1, 2, 10), 14)
	assert_eq(BossRules.landing_ring_count(3, 2, 0), 0, "no ring without base")
	assert_eq(BossRules.eruption_count(0, 1, 4), 0)
	assert_eq(BossRules.eruption_count(2, 1, 4), 4)
	assert_eq(BossRules.eruption_count(1, 2, 4), 5)
	assert_eq(BossRules.summon_bonus(1), 0)
	assert_eq(BossRules.summon_bonus(2), 1)


func test_boss_title_with_tier() -> void:
	assert_eq(BossRules.boss_title("Knochenkönig", 0), "Knochenkönig")
	assert_eq(BossRules.boss_title("Knochenkönig", 1), "Knochenkönig II")
	assert_eq(BossRules.boss_title("Knochenkönig", 2), "Knochenkönig III")
	assert_eq(BossRules.tier_numeral(12), "13")


func test_every_boss_has_a_phase_two_pattern() -> void:
	for path in BOSSES:
		var boss: EnemyData = load(path)
		var has_pattern := boss.enrage_special_repeats > 0 or boss.enrage_spiral or boss.enrage_landing_ring > 0 or boss.enrage_eruptions > 0
		assert_true(has_pattern, "%s has a phase-two pattern" % boss.id)
		assert_false(boss.enrage_text.is_empty(), "%s has a phase-two banner text" % boss.id)
		assert_false(boss.hint.is_empty(), "%s has a hint" % boss.id)


# --- ChampionRules ---

func test_champion_copy_does_not_touch_the_base() -> void:
	var cooldown := SKELETON.attack_cooldown
	var special_every := SKELETON.special_every
	var champion := ChampionRules.make_champion_data(SKELETON)
	assert_ne(champion, SKELETON)
	assert_eq(SKELETON.attack_cooldown, cooldown)
	assert_eq(SKELETON.special_every, special_every)
	assert_lt(champion.attack_cooldown, cooldown)
	assert_eq(champion.special_every, 2, "charges more often")
	assert_eq(champion.id, SKELETON.id, "same type for hints and art")


func test_every_champion_has_a_threatening_ability() -> void:
	for base: EnemyData in [SKELETON, SLIME, ARCHER, BOMBER, SHADOW, GOLEM, NECROMANCER, SPLITTER]:
		var champion := ChampionRules.make_champion_data(base)
		var has_special := champion.special != EnemyData.Special.NONE and champion.special_every > 0
		var has_volley := champion.volley_every > 0
		assert_true(has_special or has_volley, "%s champion uses an ability" % base.id)
		assert_gte(champion.knockback_resistance, ChampionRules.MIN_KNOCKBACK_RESISTANCE)


func test_champion_bomber_throws_bombs_instead_of_exploding() -> void:
	var champion := ChampionRules.make_champion_data(BOMBER)
	assert_eq(champion.special, EnemyData.Special.ERUPTION)
	assert_gt(champion.eruption_count, 0)


func test_champion_summoner_and_splitter_get_more() -> void:
	assert_eq(ChampionRules.make_champion_data(NECROMANCER).summon_count, NECROMANCER.summon_count + 1)
	assert_eq(ChampionRules.make_champion_data(SPLITTER).death_spawn_count, SPLITTER.death_spawn_count + 2)


# --- Badges and hints ---

func test_badges_describe_abilities() -> void:
	assert_eq(EnemyBadges.badges_for(SLIME, Enemy.Elite.NONE, false), [] as Array[StringName], "plain slime has none")
	assert_has(EnemyBadges.badges_for(SKELETON, Enemy.Elite.NONE, false), EnemyBadges.STUN)
	assert_has(EnemyBadges.badges_for(SHADOW, Enemy.Elite.NONE, false), EnemyBadges.BLIND)
	assert_has(EnemyBadges.badges_for(NECROMANCER, Enemy.Elite.NONE, false), EnemyBadges.SUMMONER)
	assert_has(EnemyBadges.badges_for(BOMBER, Enemy.Elite.NONE, false), EnemyBadges.EXPLODE)
	assert_has(EnemyBadges.badges_for(SPLITTER, Enemy.Elite.NONE, false), EnemyBadges.SPLIT)
	var champion := EnemyBadges.badges_for(SLIME, Enemy.Elite.ARMORED, true)
	assert_eq(champion[0], EnemyBadges.CHAMPION, "crown first")
	assert_has(champion, EnemyBadges.ARMORED)
	assert_has(EnemyBadges.badges_for(SLIME, Enemy.Elite.SWIFT, false), EnemyBadges.SWIFT)
	assert_has(EnemyBadges.badges_for(SLIME, Enemy.Elite.VOLATILE, false), EnemyBadges.VOLATILE)


func test_every_badge_has_a_12px_icon() -> void:
	for badge in EnemyBadges.ALL:
		var rows: Array = EnemyBadges.MAPS[badge]
		assert_eq(rows.size(), EnemyBadges.ICON_SIZE, "%s rows" % badge)
		for row: String in rows:
			assert_eq(row.length(), EnemyBadges.ICON_SIZE, "%s row width" % badge)
		var texture := EnemyBadges.get_texture(badge)
		assert_not_null(texture)
		assert_eq(texture.get_size(), Vector2(12, 12))
		assert_true(EnemyBadges.COLORS.has(badge))


func test_hint_entries() -> void:
	var entries := EnemyHints.get_entries(SKELETON, Enemy.Elite.VOLATILE, true)
	var ids: Array = entries.map(func(entry: Dictionary) -> StringName: return entry["id"])
	assert_eq(ids, [&"hint_champion", &"hint_elite_volatile", &"hint_skeleton"])
	assert_eq(entries[2]["title"], "Skelett")
	assert_false((entries[2]["text"] as String).begins_with("Skelett:"), "name prefix stripped")
	assert_eq(entries[2]["badge"], EnemyBadges.STUN)
	assert_eq(EnemyHints.get_entries(load("res://enemies/data/mini_slime.tres"), Enemy.Elite.NONE, false).size(), 0, "no hint text, no card")
	for elite in [Enemy.Elite.SWIFT, Enemy.Elite.ARMORED, Enemy.Elite.VOLATILE]:
		assert_eq(EnemyHints.get_entries(SLIME, elite, false).size(), 2, "elite + type hint")


# --- Art lookup ---

func test_art_locations_and_strip_names() -> void:
	assert_eq(EnemyArt.get_location(&"golem", false), ["res://art/characters/enemies/golem/", "golem"] as Array[String])
	assert_eq(EnemyArt.get_location(&"boss_bone_king", true), ["res://art/characters/bosses/bone_king/", "bone_king"] as Array[String])
	assert_eq(EnemyArt.parse_strip_name("golem_walk_6f.png", "golem"), {"animation": &"walk", "frames": 6})
	assert_eq(EnemyArt.parse_strip_name("bone_king_attack2_4f.png", "bone_king"), {"animation": &"attack2", "frames": 4})
	assert_eq(EnemyArt.parse_strip_name("mini_slime_idle_4f.png", "slime"), {}, "other prefix")
	assert_eq(EnemyArt.parse_strip_name("golem.json", "golem"), {})
	assert_eq(EnemyArt.parse_strip_name("golem_walk.png", "golem"), {})


func test_placeholders_stay_without_art() -> void:
	EnemyArt.clear_cache()
	var unknown := EnemyData.new()
	unknown.id = &"no_such_enemy"
	assert_null(EnemyArt.get_art(unknown), "no files: tinted placeholder")
	assert_null(EnemyArt.get_portrait(unknown))
	assert_null(EnemyArt.get_art(SKELETON), "already uses its own art")


func test_delivered_art_is_picked_up() -> void:
	EnemyArt.clear_cache()
	# Only checks what is actually delivered (docs/design/sprites/SPRITES_V2.md), so it never blocks missing art.
	if not ResourceLoader.exists("res://art/characters/enemies/golem/golem_idle_4f.png"):
		pass_test("no golem art delivered yet")
		return
	var art := EnemyArt.get_art(GOLEM)
	assert_not_null(art)
	assert_eq(art.frame_size, Vector2i(48, 48))
	assert_true(art.frames.has_animation(&"walk"))
	assert_eq(art.sprite_scale_for(1.0), 1.0, "snapped to whole pixels")
	assert_eq(fmod(art.sprite_scale_for(GOLEM.sprite_scale), 1.0), 0.0)


# --- Biome hazards ---

func test_hazard_tiles_avoid_pillars_doors_and_each_other() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pillars: Array[Vector2i] = [Vector2i(4, 3), Vector2i(12, 3)]
	var blocked: Array[Vector2i] = [Vector2i(7, 4)]
	for attempt in 30:
		var tiles := BiomeHazards.pick_tiles(Vector2i(15, 9), pillars, 7, 7, blocked, 4, rng)
		assert_eq(tiles.size(), 4)
		for i in tiles.size():
			var tile := tiles[i]
			assert_true(tile.x >= 1 and tile.x <= 13 and tile.y >= 1 and tile.y <= 7, "inside, not on the edge")
			for pillar in pillars:
				assert_true(absi(tile.x - pillar.x) > 1 or absi(tile.y - pillar.y) > 1, "not next to a pillar")
			assert_true(absi(tile.x - 7) > 1 or absi(tile.y - 4) > 1, "not next to a marker")
			assert_false(absi(tile.x - 7) <= 1 and tile.y <= 2, "exit lane free")
			assert_false(absi(tile.x - 7) <= 1 and tile.y >= 6, "entrance lane free")
			for j in range(i + 1, tiles.size()):
				assert_ne(tile, tiles[j])
				assert_true(absi(tile.x - tiles[j].x) >= 2 or absi(tile.y - tiles[j].y) >= 2, "spaced out")


func test_hazard_count_per_biome() -> void:
	var rng := RandomNumberGenerator.new()
	var grotto: BiomeData = load("res://dungeon/biomes/slime_grotto.tres")
	var forge: BiomeData = load("res://dungeon/biomes/ember_forge.tres")
	var crypt: BiomeData = load("res://dungeon/biomes/crypt.tres")
	assert_eq(crypt.get_hazard_count(3, RoomSequence.RoomType.COMBAT, rng), 0, "crypt only has spike traps")
	assert_eq(grotto.get_hazard_count(19, RoomSequence.RoomType.SPECIAL, rng), 0, "special rooms stay safe")
	for i in 50:
		var count := grotto.get_hazard_count(17, RoomSequence.RoomType.COMBAT, rng)
		assert_between(count, 1, 3)
	assert_eq(forge.get_hazard_count(60, RoomSequence.RoomType.BOSS, rng), forge.boss_hazard_count)
	assert_eq(forge.get_hazard_count(120, RoomSequence.RoomType.BOSS, rng), forge.boss_hazard_count + 1, "more in the next cycle")
