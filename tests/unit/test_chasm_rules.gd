extends GutTest
## Pure abyss rules (A4, D-086): when a player falls, which enemies a knockback can push into a pit,
## the first-time hint, and the combined abyss pieces (AbyssAutotile).

const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const GOLEM: EnemyData = preload("res://enemies/data/golem.tres")
const BOSS: EnemyData = preload("res://enemies/data/boss_bone_king.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_chasm_rules_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


## Pits: every x >= 100 (a straight rim at x = 100).
func _is_pit(point: Vector2) -> bool:
	return point.x >= 100.0


func test_falling_needs_feet_over_the_pit_without_a_dash() -> void:
	assert_false(ChasmRules.should_fall(true, true, 1.0), "a dash is in the air")
	assert_false(ChasmRules.should_fall(false, false, 1.0), "solid ground")
	assert_false(ChasmRules.should_fall(true, false, 0.05), "grace time 0.1 s")
	assert_true(ChasmRules.should_fall(true, false, ChasmRules.FALL_GRACE_TIME))


func test_time_over_the_pit_resets_on_ground_and_in_the_air() -> void:
	var time := ChasmRules.tick_over_pit(0.0, 0.06, true, false)
	time = ChasmRules.tick_over_pit(time, 0.06, true, false)
	assert_almost_eq(time, 0.12, 0.001)
	assert_eq(ChasmRules.tick_over_pit(time, 0.06, true, true), 0.0, "dashing")
	assert_eq(ChasmRules.tick_over_pit(time, 0.06, false, false), 0.0, "back on the floor")


func test_feet_need_to_be_inside_the_pit_by_the_margin() -> void:
	var probe := Callable(self, &"_is_pit")
	assert_false(ChasmRules.is_over_pit(Vector2(100 + ChasmRules.FALL_EDGE_MARGIN - 1.0, 0), probe), "right at the rim: forgiven")
	assert_true(ChasmRules.is_over_pit(Vector2(100 + ChasmRules.FALL_EDGE_MARGIN + 1.0, 0), probe))
	assert_false(ChasmRules.is_safe_spot(Vector2(100 - ChasmRules.SAFE_MARGIN + 1.0, 0), probe), "too close to the rim")
	assert_true(ChasmRules.is_safe_spot(Vector2(100 - ChasmRules.SAFE_MARGIN - 1.0, 0), probe))


func test_a_fall_costs_a_whole_heart() -> void:
	assert_eq(ChasmRules.fall_damage(), 2.0, "D-086: 2 HP = one heart")
	assert_eq(ChasmRules.FALL_TIME, 0.5)
	assert_eq(ChasmRules.RESPAWN_INVULNERABILITY, 1.0)


func test_only_normal_enemies_and_elites_can_fall() -> void:
	assert_true(ChasmRules.can_enemy_fall(SKELETON, false))
	assert_false(ChasmRules.can_enemy_fall(SKELETON, true), "champions never")
	assert_false(ChasmRules.can_enemy_fall(GOLEM, false), "golems never")
	assert_false(ChasmRules.can_enemy_fall(BOSS, false), "bosses never")
	assert_false(ChasmRules.can_enemy_fall(null, false))


func test_only_strong_knockback_pushes() -> void:
	assert_false(ChasmRules.knockback_can_push(ChasmRules.ENEMY_FALL_MIN_KNOCKBACK))
	assert_true(ChasmRules.knockback_can_push(ChasmRules.ENEMY_FALL_MIN_KNOCKBACK + 1.0))
	assert_almost_eq(ChasmRules.knockback_travel(300.0, 900.0), 50.0, 0.01)


func test_hint_only_for_holes_outside_chasm_rooms_and_only_once() -> void:
	assert_true(ChasmRules.get_hint_entry(false, false, false, false).is_empty(), "no pits")
	assert_true(ChasmRules.get_hint_entry(true, true, false, false).is_empty(), "the chasm room explains itself")
	assert_true(ChasmRules.get_hint_entry(true, false, true, false).is_empty(), "chasm card already seen")
	assert_true(ChasmRules.get_hint_entry(true, false, false, true).is_empty(), "hint already seen")
	var entry := ChasmRules.get_hint_entry(true, false, false, false)
	assert_eq(entry["id"], ChasmRules.HINT_ID)
	assert_false(String(entry["text"]).contains("%s"), "dash key filled in")
	assert_true(DungeonTexts.has_text(ChasmRules.HINT_TITLE_KEY))
	assert_true(DungeonTexts.has_text(ChasmRules.HINT_TEXT_KEY))
	assert_true(DungeonTexts.t(&"ROOM_CHASM_INTRO", ["Space"]).contains("Herz"), "the chasm card names the cost")


# --- AbyssAutotile ---

func _pits(tiles: Array[Vector2i]) -> Callable:
	var set := {}
	for tile in tiles:
		set[tile] = true
	return func(tile: Vector2i) -> bool: return set.has(tile)


func test_abyss_pieces_by_neighbours() -> void:
	# A one-tile gap running north-south: floor east and west.
	var gap: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 0), Vector2i(0, 1)]
	assert_eq(AbyssAutotile.cell_for(Vector2i.ZERO, _pits(gap)), Vector2i(AbyssAutotile.N | AbyssAutotile.S, 0))
	# Enclosed: the delivered void tiles.
	var block: Array[Vector2i] = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			block.append(Vector2i(x, y))
	assert_eq(AbyssAutotile.cell_for(Vector2i.ZERO, _pits(block)), AbyssAutotile.VOID)
	# Floor only on the diagonal north-east: an inner corner.
	block.erase(Vector2i(1, -1))
	assert_eq(AbyssAutotile.cell_for(Vector2i.ZERO, _pits(block)), Vector2i(15, AbyssAutotile.CORNER_TOP_RIGHT))
	# A single hole: rims on all four sides.
	var single: Array[Vector2i] = [Vector2i.ZERO]
	assert_eq(AbyssAutotile.cell_for(Vector2i.ZERO, _pits(single)), Vector2i(0, 0))


func test_abyss_atlas_is_built_from_the_biome_art() -> void:
	for biome: String in ["crypt", "slime_grotto", "shadow_realm", "ember_forge"]:
		var art := (load("res://art/environment/tiles/abyss_tiles_%s.png" % biome) as Texture2D).get_image()
		var atlas := AbyssAutotile.build_atlas(art)
		assert_eq(atlas.get_size(), Vector2i(16 * 32, 16 * 32), biome)
		# One open side = the delivered edge tile, unchanged.
		var edge := atlas.get_region(Rect2i(Vector2i(15 & ~AbyssAutotile.N, 0) * 32, Vector2i(32, 32)))
		var delivered := art.get_region(Rect2i(AbyssAutotile.ART_EDGE[AbyssAutotile.N] * 32, Vector2i(32, 32)))
		assert_eq(edge.get_pixel(16, 2), delivered.get_pixel(16, 2), "%s: north edge from the art" % biome)
