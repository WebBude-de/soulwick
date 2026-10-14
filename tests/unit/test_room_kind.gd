extends GutTest
## Room kinds and size classes (D-086, D-100): kind draw (rooms 1-5 normal, then 40/35/25), no
## chasm twice in a row, template choice with fallback to a normal room, overflow waves.

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


func test_kinds_are_normal_arena_chasm() -> void:
	assert_eq(RoomSequence.RoomKind.keys(), ["NORMAL", "ARENA", "CHASM"])


func test_rooms_one_to_five_are_normal_only() -> void:
	for room_index in [1, 2, 3, 5]:
		var shares := _shares(room_index, -1, 11 + room_index)
		assert_eq(shares[RoomSequence.RoomKind.NORMAL], 1.0, "room %d normal" % room_index)


func test_deeper_rooms_use_the_d100_weights() -> void:
	for room_index in [RoomSequence.CHASM_FROM_ROOM, 17, 120]:
		var shares := _shares(room_index, RoomSequence.RoomKind.ARENA, 23 + room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.NORMAL], 0.40, 0.02, "room %d normal" % room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.ARENA], 0.35, 0.02, "room %d arena" % room_index)
		assert_almost_eq(shares[RoomSequence.RoomKind.CHASM], 0.25, 0.02, "room %d chasm" % room_index)


func test_no_chasm_right_after_chasm() -> void:
	var shares := _shares(12, RoomSequence.RoomKind.CHASM, 5)
	assert_eq(shares[RoomSequence.RoomKind.CHASM], 0.0)
	# The chasm share is split proportionally: 40/75 normal, 35/75 arena.
	assert_almost_eq(shares[RoomSequence.RoomKind.NORMAL], 0.40 / 0.75, 0.02)
	assert_almost_eq(shares[RoomSequence.RoomKind.ARENA], 0.35 / 0.75, 0.02)


func test_chained_draws_never_repeat_chasm_and_start_normal() -> void:
	var rng := _rng(99)
	var previous := -1
	var chasm_rooms := 0
	for room_index in range(1, 3001):
		if not RoomSequence.is_normal_combat(RoomSequence.get_room_type(room_index)):
			previous = -1
			continue
		var kind := RoomSequence.roll_room_kind(room_index, previous, rng)
		if room_index < RoomSequence.CHASM_FROM_ROOM:
			assert_eq(kind, RoomSequence.RoomKind.NORMAL, "room %d before the first arena/chasm room" % room_index)
		if kind == RoomSequence.RoomKind.CHASM:
			chasm_rooms += 1
			assert_ne(previous, RoomSequence.RoomKind.CHASM, "room %d: chasm twice in a row" % room_index)
		previous = kind
	assert_gt(chasm_rooms, 0, "chasm rooms do appear")


func test_roll_draws_exactly_one_number() -> void:
	var a := _rng(4)
	var b := _rng(4)
	RoomSequence.roll_room_kind(9, RoomSequence.RoomKind.CHASM, a)
	b.randf()
	assert_eq(a.randi(), b.randi(), "same rng state after one draw")


func test_catalog_reads_kind_and_size_from_templates() -> void:
	assert_eq(RoomCatalog.read_template_info(HALL), Vector2i(RoomSequence.RoomKind.NORMAL, RoomSequence.RoomSize.S), "combat_hall = normal S")
	assert_eq(RoomCatalog.read_template_info(WIDE), Vector2i(RoomSequence.RoomKind.ARENA, RoomSequence.RoomSize.M), "combat_wide = arena M")
	assert_eq(RoomCatalog.read_template_info(PILLARS), Vector2i(RoomSequence.RoomKind.NORMAL, RoomSequence.RoomSize.S), "combat_pillars = normal S")


func test_generated_catalog_lists_every_combat_template() -> void:
	var catalog := RoomCatalog.create()
	assert_gte(catalog.get_template_count(), 20, "shapes x sizes")
	for scene in [HALL, PILLARS, WIDE]:
		assert_ne(catalog.get_kind_of(scene), -1, "%s in the catalog" % scene.resource_path)
	for entry in catalog.get_entries():
		assert_not_null(entry.scene, "%s has a scene" % entry.id)
		assert_eq(RoomCatalog.read_template_info(entry.scene), Vector2i(entry.room_kind, entry.size_class), "%s: scene and RoomTemplate agree" % entry.id)


func test_catalog_ignores_duplicates_from_the_export() -> void:
	var count := RoomCatalog.create().get_template_count()
	var extra: Array[PackedScene] = [HALL, WIDE]
	assert_eq(RoomCatalog.create(extra).get_template_count(), count)


func test_pick_respects_kind_and_sizes() -> void:
	var catalog := RoomCatalog.create()
	var rng := _rng(3)
	var only_s: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.S]
	for i in 100:
		var normal := catalog.pick_template(RoomSequence.RoomKind.NORMAL, only_s, rng)
		assert_eq(normal.room_kind, RoomSequence.RoomKind.NORMAL)
		assert_eq(normal.size_class, RoomSequence.RoomSize.S)
		var arena := catalog.pick_template(RoomSequence.RoomKind.ARENA, RoomSequence.SOLO_ROOM_SIZES, rng)
		assert_eq(arena.room_kind, RoomSequence.RoomKind.ARENA)
		assert_true(RoomSequence.SOLO_ROOM_SIZES.has(arena.size_class), "single-player size")
	var seen := {}
	for i in 600:
		seen[catalog.pick(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng)] = true
	assert_eq(seen.size(), catalog._candidates(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, &"").size(), "every normal S/M template appears")


func test_pick_finds_chasm_templates() -> void:
	var catalog := RoomCatalog.create()
	var rng := _rng(8)
	assert_true(catalog.has_kind(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES), "chasm templates (A4)")
	for i in 100:
		var scene := catalog.pick(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 6 + i)
		assert_eq(catalog.get_kind_of(scene), RoomSequence.RoomKind.CHASM)
	# Before room 6 a chasm template is never picked, the room falls back to a normal one.
	assert_false(catalog.has_kind(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES, &"", 5))
	for i in 50:
		var early := catalog.pick(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 3)
		assert_eq(catalog.get_kind_of(early), RoomSequence.RoomKind.NORMAL)


func test_no_catacomb_in_the_first_room() -> void:
	var catalog := RoomCatalog.create()
	var rng := _rng(5)
	var seen_catacomb := false
	for i in 400:
		var first := catalog.pick_template(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 1)
		assert_ne(first.shape, RoomTemplate.Shape.CATACOMB, "room 1 is never a catacomb (UX2)")
		var second := catalog.pick_template(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng, &"", 2)
		seen_catacomb = seen_catacomb or second.shape == RoomTemplate.Shape.CATACOMB
	assert_true(seen_catacomb, "catacombs from room 2 on")


func test_pick_falls_back_in_small_catalog() -> void:
	var catalog := RoomCatalog.new()
	catalog.add_template(WIDE)
	var rng := _rng(1)
	# No normal template at all: any template of the size rather than none.
	assert_eq(catalog.pick(RoomSequence.RoomKind.NORMAL, RoomSequence.SOLO_ROOM_SIZES, rng), WIDE)
	# Overridden kinds: a chasm template is chosen as soon as one exists.
	catalog.add_template(PILLARS, RoomSequence.RoomKind.CHASM, RoomSequence.RoomSize.M)
	assert_eq(catalog.pick(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES, rng), PILLARS)
	# No template in the allowed sizes at all: any template rather than none.
	var only_l: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.L]
	assert_not_null(catalog.pick(RoomSequence.RoomKind.ARENA, only_l, rng))
	assert_null(RoomCatalog.new().pick(RoomSequence.RoomKind.ARENA, only_l, rng), "empty catalog")


func test_pick_draws_exactly_one_number() -> void:
	var catalog := RoomCatalog.create()
	var a := _rng(17)
	var b := _rng(17)
	catalog.pick(RoomSequence.RoomKind.CHASM, RoomSequence.SOLO_ROOM_SIZES, a)
	b.randi()
	assert_eq(a.randi(), b.randi(), "one draw, also with fallback")


func test_biome_filter_of_templates() -> void:
	var catalog := RoomCatalog.new()
	var only_grotto := RoomTemplate.new()
	only_grotto.scene = HALL
	only_grotto.allowed_biomes = [&"slime_grotto"]
	catalog.add_entry(only_grotto)
	catalog.add_template(PILLARS)
	var rng := _rng(2)
	var only_s: Array[RoomSequence.RoomSize] = [RoomSequence.RoomSize.S]
	for i in 30:
		assert_eq(catalog.pick(RoomSequence.RoomKind.NORMAL, only_s, rng, &"crypt"), PILLARS, "crypt never gets the grotto-only template")
	var seen := {}
	for i in 60:
		seen[catalog.pick(RoomSequence.RoomKind.NORMAL, only_s, rng, &"slime_grotto")] = true
	assert_eq(seen.size(), 2)


func test_find_template_of_a_room() -> void:
	var room := HALL.instantiate()
	autofree(room)
	var template := RoomCatalog.find_template_of(room)
	assert_not_null(template)
	assert_eq(template.shape, RoomTemplate.Shape.RECTANGLE)
	assert_eq(RoomTemplate.get_shape_name(RoomTemplate.Shape.CATACOMB), "Katakombe")


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
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.NORMAL), "Normal")
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.ARENA), "Arena")
	assert_eq(RoomSequence.get_kind_name(RoomSequence.RoomKind.CHASM), "Abgrund")
	assert_eq(RoomSequence.get_size_name(RoomSequence.RoomSize.M), "M")
