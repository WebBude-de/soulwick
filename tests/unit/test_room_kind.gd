extends GutTest
## Room kinds and size classes (D-086): kind draw, no abyss twice in a row, template choice with
## arena fallback, overflow waves.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PILLARS: PackedScene = preload("res://dungeon/rooms/combat/combat_pillars.tscn")
const WIDE: PackedScene = preload("res://dungeon/rooms/combat/combat_wide.tscn")
const DRAWS := 20000

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_kind_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _shares(room_index: int, previous_kind: int, seed_value: int) -> Array[float]:
	var rng := _rng(seed_value)
	var counts: Array[float] = [0.0, 0.0, 0.0]
	for i in DRAWS:
		counts[RoomSequence.roll_room_kind(room_index, previous_kind, rng)] += 1.0
	for kind in counts.size():
		counts[kind] /= DRAWS
	return counts


func test_rooms_one_to_five_are_half_arena_half_structured() -> void:
	for room_index in [1, 2, 3, 5]:
		var shares := _shares(room_index, -1, 11 + room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.ARENA], 0.5, 0.02, "room %d arena" % room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.STRUCTURED], 0.5, 0.02, "room %d structured" % room_index)
		assert_eq(shares[RoomSequence.RoomKind.ABYSS], 0.0, "room %d never abyss" % room_index)


func test_deeper_rooms_use_the_d086_weights() -> void:
	for room_index in [6, 17, 120]:
		var shares := _shares(room_index, RoomSequence.RoomKind.ARENA, 23 + room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.ARENA], 0.35, 0.02, "room %d arena" % room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.STRUCTURED], 0.40, 0.02, "room %d structured" % room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.ABYSS], 0.25, 0.02, "room %d abyss" % room_index)


func test_no_abyss_right_after_abyss() -> void:
	var shares := _shares(8, RoomSequence.RoomKind.ABYSS, 5)
	assert_eq(shares[RoomSequence.RoomKind.ABYSS], 0.0)
	# The abyss share is split proportionally: 35/75 arena, 40/75 structured.
	assert_almost_eq(shares[RoomSequence.RoomKind.ARENA], 0.35 / 0.75, 0.02)
	assert_almost_eq(shares[RoomSequence.RoomKind.STRUCTURED], 0.40 / 0.75, 0.02)


func test_chained_draws_never_repeat_abyss_and_start_without_abyss() -> void:
	var rng := _rng(99)
	var previous := -1
	var abyss_rooms := 0
	for room_index in range(1, 3001):
		if not RoomSequence.is_normal_combat(RoomSequence.get_room_type(room_index)):
			previous = -1
			continue
		var kind := RoomSequence.roll_room_kind(room_index, previous, rng)
		if room_index < RoomSequence.ABYSS_FROM_ROOM:
			assert_ne(kind, RoomSequence.RoomKind.ABYSS, "room %d before the first abyss room" % room_index)
		if kind == RoomSequence.RoomKind.ABYSS:
			abyss_rooms += 1
			assert_ne(previous, RoomSequence.RoomKind.ABYSS, "room %d: abyss twice in a row" % room_index)
		previous = kind
	assert_gt(abyss_rooms, 0, "abyss rooms do appear")


func test_roll_draws_exactly_one_number() -> void:
	var a := _rng(4)
	var b := _rng(4)
	RoomSequence.roll_room_kind(9, RoomSequence.RoomKind.ABYSS, a)
	b.randf()
	assert_eq(a.randi(), b.randi(), "same rng state after one draw")


func test_catalog_reads_kind_and_size_from_templates() -> void:
	assert_eq(RoomCatalog.read_template_info(HALL), Vector2i(RoomSequence.RoomKind.ARENA, RoomSequence.RoomSize.S), "combat_hall = arena S")
	assert_eq(RoomCatalog.read_template_info(WIDE), Vector2i(RoomSequence.RoomKind.ARENA, RoomSequence.RoomSize.M), "combat_wide = arena M")
	assert_eq(RoomCatalog.read_template_info(PILLARS), Vector2i(RoomSequence.RoomKind.STRUCTURED, RoomSequence.RoomSize.S), "combat_pillars = structured S")


func test_generated_catalog_lists_every_combat_template() -> void:
	var catalog := RoomCatalog.create()
	assert_eq(catalog.get_template_count(), 3)
	for scene in [HALL, PILLARS, WIDE]:
		assert_ne(catalog.get_kind_of(scene), -1, "%s in the catalog" % scene.resource_path)


func test_catalog_ignores_duplicates_from_the_export() -> void:
	var extra: Array[PackedScene] = [HALL, WIDE]
	assert_eq(RoomCatalog.create(extra).get_template_count(), 3)


func test_pick_respects_kind_and_sizes() -> void:
	var catalog := RoomCatalog.create()
	var rng := _rng(3)
	var only_s: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.S]
	for i in 50:
		assert_eq(catalog.pick(RoomSequence.RoomKind.STRUCTURED, RoomSequence.SOLO_ROOM_SIZES, rng), PILLARS)
		assert_eq(catalog.pick(RoomSequence.RoomKind.ARENA, only_s, rng), HALL)
	var seen := {}
	for i in 200:
		seen[catalog.pick(RoomSequence.RoomKind.ARENA, RoomSequence.SOLO_ROOM_SIZES, rng)] = true
	assert_eq(seen.size(), 2, "both arena templates (S and M) appear")


func test_pick_falls_back_to_arena_without_template() -> void:
	var catalog := RoomCatalog.create()
	var rng := _rng(8)
	assert_false(catalog.has_kind(RoomSequence.RoomKind.ABYSS, RoomSequence.SOLO_ROOM_SIZES), "no abyss template yet")
	for i in 100:
		var scene := catalog.pick(RoomSequence.RoomKind.ABYSS, RoomSequence.SOLO_ROOM_SIZES, rng)
		assert_eq(catalog.get_kind_of(scene), RoomSequence.RoomKind.ARENA)


func test_pick_falls_back_to_arena_for_missing_kind_in_small_catalog() -> void:
	var catalog := RoomCatalog.new()
	catalog.add_template(HALL)
	var rng := _rng(1)
	assert_eq(catalog.pick(RoomSequence.RoomKind.STRUCTURED, RoomSequence.SOLO_ROOM_SIZES, rng), HALL)
	# Overridden kinds: an abyss template is chosen as soon as one exists.
	catalog.add_template(PILLARS, RoomSequence.RoomKind.ABYSS, RoomSequence.RoomSize.M)
	assert_eq(catalog.pick(RoomSequence.RoomKind.ABYSS, RoomSequence.SOLO_ROOM_SIZES, rng), PILLARS)
	# No template in the allowed sizes at all: any template rather than none.
	var only_l: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.L]
	assert_not_null(catalog.pick(RoomSequence.RoomKind.ARENA, only_l, rng))
	assert_null(RoomCatalog.new().pick(RoomSequence.RoomKind.ARENA, only_l, rng), "empty catalog")


func test_overflow_enemies_become_extra_waves() -> void:
	assert_eq(RoomSequence.split_into_waves(4, 5), [4] as Array[int])
	assert_eq(RoomSequence.split_into_waves(5, 5), [5] as Array[int])
	assert_eq(RoomSequence.split_into_waves(12, 5), [5, 5, 2] as Array[int])
	assert_eq(RoomSequence.split_into_waves(0, 5), [] as Array[int])


func test_minimum_spawn_points_per_size() -> void:
	assert_eq(RoomSequence.get_min_spawn_points(RoomSequence.RoomSize.S), 5)
	assert_eq(RoomSequence.get_min_spawn_points(RoomSequence.RoomSize.M), 8)
	assert_eq(RoomSequence.get_min_spawn_points(RoomSequence.RoomSize.L), 12)
	assert_eq(RoomSequence.MAX_SPAWN_POINTS, 14)


func test_kind_and_size_names() -> void:
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.ARENA), "Arena")
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.STRUCTURED), "Strukturiert")
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.ABYSS), "Abgrund")
	assert_eq(RoomSequence.get_size_name(RoomSequence.RoomSize.M), "M")
