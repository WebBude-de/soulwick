extends GutTest
## Branches (D-105, D-117): the draw (from room 6, at most once per cycle, not in a
## variant room, fixed number of RNG draws), the two ways (special pair, elite nest or unknown vs.
## safe), the two doors (west/east fork, north + side, two north doors for special rooms), the group
## vote and a branch room in the tree (doors wait after the fight, the chosen one opens, the other
## is sealed, signals for the manager). M5: the ladder way stands in for the safe way in a share of
## the combat branches where a side segment may come (same draws, ladder sign, plain fight behind).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")

var _old_save_path: String
var _special_table := SpecialTable.new()
var _variant_table: VariantTable = VariantTable.load_default()


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_branch_rules_save.cfg"


func after_all() -> void:
	BranchRules.chance_override = -1.0
	BranchRules.ladder_override = -1.0
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	BranchRules.chance_override = -1.0
	BranchRules.ladder_override = -1.0


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _roll(room_index: int, room_type: int, next_type: int, seed_value: int, branch_cycle := -1, has_variant := false, ladder_allowed := false) -> BranchRules.Plan:
	return BranchRules.roll(room_index, room_type, next_type, has_variant, branch_cycle, -1, _special_table, _variant_table, _rng(seed_value), ladder_allowed)


# --- Draw ---

func test_draws_a_fixed_number_of_rng_values() -> void:
	for index in [1, 6, 12]:
		var rng := _rng(3)
		BranchRules.roll(index, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT, false, -1, -1, _special_table, _variant_table, rng)
		var reference := _rng(3)
		for i in BranchRules.DRAWS:
			reference.randf()
		assert_eq(rng.state, reference.state, "room %d: %d draws" % [index, BranchRules.DRAWS])
	var untouched := _rng(3)
	BranchRules.roll(9, RoomSequence.RoomType.SPECIAL, RoomSequence.RoomType.MINIBOSS, false, -1, -1, _special_table, _variant_table, untouched)
	assert_eq(untouched.state, _rng(3).state, "no draws for other rooms")


func test_no_branch_before_room_six_in_variants_or_twice_a_cycle() -> void:
	BranchRules.chance_override = 1.0
	assert_false(_roll(4, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, 1).is_branch())
	assert_true(_roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, 1).is_branch())
	assert_false(_roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, 1, BranchRules.get_cycle(7)).is_branch(), "once per cycle")
	assert_true(_roll(12, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT, 1, BranchRules.get_cycle(7)).is_branch(), "next cycle again")
	assert_false(_roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, 1, -1, true).is_branch(), "no branch in a variant room")
	assert_eq(BranchRules.get_cycle(6), 1)
	assert_eq(BranchRules.get_cycle(10), 1)
	assert_eq(BranchRules.get_cycle(11), 2)


func test_branch_share_is_the_chance() -> void:
	var branches := 0
	for seed_value in 2000:
		if _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, seed_value).is_branch():
			branches += 1
	assert_almost_eq(branches / 2000.0, BranchRules.CHANCE, 0.04)


func test_combat_ways_are_safe_against_elite_nest_or_unknown() -> void:
	BranchRules.chance_override = 1.0
	var kinds := {}
	for seed_value in 300:
		var plan := _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, seed_value)
		assert_true(plan.is_branch())
		var safe := 0
		for option in plan.options:
			if option.kind == BranchOption.Kind.SAFE:
				safe += 1
			else:
				kinds[option.kind] = kinds.get(option.kind, 0) + 1
				if option.kind == BranchOption.Kind.ELITE_NEST:
					assert_eq(option.variant_id, BranchOption.ELITE_NEST_ID)
					assert_eq(option.get_symbol(), &"elite_nest")
				else:
					assert_true(_variant_table.get_allowed(RoomSequence.get_biome(8)).has(option.variant_id), "unknown is a variant of the next biome")
					assert_eq(option.get_symbol(), &"unknown")
		assert_eq(safe, 1, "exactly one safe way")
	assert_almost_eq(kinds.get(BranchOption.Kind.ELITE_NEST, 0) / 300.0, BranchRules.ELITE_SHARE, 0.08)
	assert_gt(kinds.get(BranchOption.Kind.UNKNOWN, 0), 0)


# --- Ladder way (M5) ---

func test_ladder_way_stands_in_for_the_safe_way_in_its_share() -> void:
	BranchRules.chance_override = 1.0
	var ladders := 0
	var ladder_first := 0
	for seed_value in 1000:
		var plan := _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, seed_value, -1, false, true)
		var plain := _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, seed_value)
		assert_true(plan.is_branch())
		var calm := 0
		for i in plan.options.size():
			var option := plan.options[i]
			if option.kind == BranchOption.Kind.SAFE or option.kind == BranchOption.Kind.LADDER:
				calm += 1
				assert_eq(plain.options[i].kind, BranchOption.Kind.SAFE, "the ladder takes the place of the safe way, same door")
			else:
				assert_eq(option.kind, plain.options[i].kind, "the other way stays what it was")
			if option.is_ladder():
				ladders += 1
				ladder_first += 1 if i == 0 else 0
				assert_eq(option.get_symbol(), &"ladder")
				assert_true(option.is_combat() and option.forces_variant(), "a plain fight behind it")
				assert_eq(option.get_room_type(RoomSequence.RoomType.COMBAT), RoomSequence.RoomType.COMBAT)
				assert_eq(option.variant_id, &"")
		assert_eq(calm, 1, "exactly one safe or ladder way")
	assert_almost_eq(ladders / 1000.0, BranchRules.LADDER_SHARE, 0.05)
	assert_almost_eq(ladder_first / float(maxi(ladders, 1)), 0.5, 0.08, "the ladder door is left or right alike")


func test_no_ladder_way_where_no_segment_may_come_or_before_special_rooms() -> void:
	BranchRules.chance_override = 1.0
	BranchRules.ladder_override = 1.0
	for seed_value in 200:
		for option in _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, seed_value).options:
			assert_false(option.is_ladder(), "ladder_allowed false: never")
		var special := BranchRules.roll(8, RoomSequence.RoomType.COMBAT_UPGRADE, RoomSequence.RoomType.SPECIAL, false, -1,
				-1, _special_table, _variant_table, _rng(seed_value), true)
		for option in special.options:
			assert_eq(option.kind, BranchOption.Kind.SPECIAL, "special ways stay special rooms")
	var forced := _roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE, 3, -1, false, true)
	assert_eq(forced.options.filter(func(option: BranchOption) -> bool: return option.is_ladder()).size(), 1, "test aid: always the ladder")


func test_ladder_way_draws_nothing_extra() -> void:
	BranchRules.chance_override = 1.0
	var rng := _rng(9)
	BranchRules.roll(7, RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT, false, -1, -1, _special_table, _variant_table, rng, true)
	var reference := _rng(9)
	for i in BranchRules.DRAWS:
		reference.randf()
	assert_eq(rng.state, reference.state, "still %d draws" % BranchRules.DRAWS)
	assert_true(BranchRules.is_ladder_roll(0.0))
	assert_true(BranchRules.is_ladder_roll(0.5), "the second half starts again")
	assert_false(BranchRules.is_ladder_roll(0.49))
	assert_false(BranchRules.is_ladder_roll(0.99))


func test_ladder_door_shows_the_ladder_sign_and_a_plain_way() -> void:
	var options: Array[BranchOption] = [BranchOption.create(BranchOption.Kind.ELITE_NEST, -1, BranchOption.ELITE_NEST_ID), BranchOption.create(BranchOption.Kind.LADDER)]
	var room := _branch_room(options)
	var doors := room.get_exit_doors()
	assert_eq(doors[1].get_style().symbol, &"ladder")
	assert_eq(DoorStyle.branch_symbol_index(&"ladder"), 3, "fourth column of door_branch_symbols_4.png")
	assert_true(DoorArt.has_symbol_file(&"ladder"), "the V9 sheet with the ladder is there")
	assert_eq(DoorSigns.mode_for_way(room, options[1]), &"", "the ladder way shows no mode over the door")
	assert_eq(options[1].describe(), "Leiter-Weg")


func test_special_ways_are_two_different_types_never_the_previous() -> void:
	BranchRules.chance_override = 1.0
	for seed_value in 300:
		var plan := BranchRules.roll(8, RoomSequence.RoomType.COMBAT_UPGRADE, RoomSequence.RoomType.SPECIAL, false, -1,
				SpecialTable.SHOP, _special_table, _variant_table, _rng(seed_value))
		assert_true(plan.is_branch())
		var first := plan.options[0]
		var second := plan.options[1]
		assert_eq(first.kind, BranchOption.Kind.SPECIAL)
		assert_ne(first.special_type, second.special_type)
		assert_ne(first.special_type, SpecialTable.SHOP, "not the previous special room")
		assert_ne(second.special_type, SpecialTable.SHOP)
		assert_eq(first.get_room_type(RoomSequence.RoomType.SPECIAL), RoomSequence.RoomType.SPECIAL)


# --- Doors ---

func _tiles() -> RoomTiles:
	var room := HALL.instantiate() as RoomController
	autofree(room)
	return room.get_node("Tiles") as RoomTiles


func _combat_options() -> Array[BranchOption]:
	var options: Array[BranchOption] = [BranchOption.create(BranchOption.Kind.ELITE_NEST, -1, BranchOption.ELITE_NEST_ID), BranchOption.create(BranchOption.Kind.SAFE)]
	return options


func test_combat_fork_west_and_east_when_entered_from_the_south() -> void:
	var tiles := _tiles()
	var sides: Array[int] = [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST]
	var pair := BranchRules.pick_exit_pair(tiles, _combat_options(), sides, [0, 0, 0] as Array[int])
	assert_eq(pair.size(), 2)
	assert_eq(pair[0].x, ExitRules.WEST)
	assert_eq(pair[1].x, ExitRules.EAST)
	var no_east := BranchRules.pick_exit_pair(tiles, _combat_options(), sides, [0, 9, 0] as Array[int])
	assert_eq(no_east[0].x, ExitRules.NORTH, "the east turn would need a long corridor: north and west")
	assert_eq(no_east[1].x, ExitRules.WEST)


func test_special_ways_take_two_north_doors() -> void:
	var tiles := _tiles()
	var options: Array[BranchOption] = [BranchOption.create(BranchOption.Kind.SPECIAL, SpecialTable.SHOP), BranchOption.create(BranchOption.Kind.SPECIAL, SpecialTable.TRIAL)]
	var pair := BranchRules.pick_exit_pair(tiles, options, [ExitRules.NORTH, ExitRules.EAST, ExitRules.WEST] as Array[int], [0, 0, 0] as Array[int])
	assert_eq(pair.size(), 2)
	assert_eq(pair[0].x, ExitRules.NORTH)
	assert_eq(pair[1].x, ExitRules.NORTH)
	assert_gte(absi(pair[1].y - pair[0].y), 5, "far apart")


# --- Vote (D-105) ---

func test_vote_alone_decides_at_once() -> void:
	assert_eq(BranchRules.resolve_vote([0, 1] as Array[int], 1, 0.0), 1)
	assert_eq(BranchRules.resolve_vote([0, 0] as Array[int], 1, 30.0), -1, "nobody at a door")


func test_vote_of_a_split_group_waits_then_majority_then_draw() -> void:
	assert_eq(BranchRules.resolve_vote([2, 0] as Array[int], 2, 0.0), 0, "all at one door")
	assert_eq(BranchRules.resolve_vote([1, 1] as Array[int], 2, 3.0), -1, "split: wait")
	assert_eq(BranchRules.resolve_vote([2, 1] as Array[int], 4, 20.0), -1, "one player is elsewhere")
	assert_eq(BranchRules.resolve_vote([2, 1] as Array[int], 3, BranchRules.VOTE_TIMEOUT), 0, "majority after the timeout")
	assert_eq(BranchRules.resolve_vote([1, 1] as Array[int], 2, BranchRules.VOTE_TIMEOUT, 0.2), 0, "tie drawn")
	assert_eq(BranchRules.resolve_vote([1, 1] as Array[int], 2, BranchRules.VOTE_TIMEOUT, 0.8), 1)


# --- Branch room in the tree ---

func _branch_room(options: Array[BranchOption] = []) -> RoomController:
	if options.is_empty():
		options = _combat_options()
	var room := HALL.instantiate() as RoomController
	var context := DungeonContext.new()
	context.rng = _rng(5)
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, context)
	var tiles := room.get_node("Tiles") as RoomTiles
	var west := tiles.get_door_slots(RoomTiles.DoorSide.WEST)[0]
	var east := tiles.get_door_slots(RoomTiles.DoorSide.EAST)[0]
	var exits: Array[Vector2i] = [Vector2i(RoomTiles.DoorSide.WEST, west), Vector2i(RoomTiles.DoorSide.EAST, east)]
	room.apply_door_plan(Vector2i(RoomTiles.DoorSide.SOUTH, tiles.entrance_x), exits, 0, options)
	add_child_autofree(room)
	return room


func test_branch_room_has_two_signed_doors_that_wait() -> void:
	var room := _branch_room()
	assert_true(room.is_branch_room())
	var doors := room.get_exit_doors()
	assert_eq(doors.size(), 2)
	assert_eq(doors[0].get_style().symbol, &"elite_nest")
	assert_eq(doors[1].get_style().symbol, &"safe")
	assert_true(doors[0].is_side_door())
	watch_signals(room)
	room.open_exit()
	assert_signal_emitted(room, "branch_offered")
	assert_true(room.get_branch_choice().is_offered)
	assert_false(doors[0].is_open or doors[1].is_open, "no door opens before the choice")


func test_choosing_opens_one_door_and_seals_the_other() -> void:
	var room := _branch_room()
	room.state = RoomController.State.CLEARED
	room.open_exit()
	watch_signals(room)
	assert_true(room.choose_branch(1))
	assert_signal_emitted_with_parameters(room, "branch_chosen", [room, 1])
	var doors := room.get_exit_doors()
	assert_true(doors[1].is_open, "the chosen way opens")
	assert_false(doors[0].is_open, "the other is sealed")
	assert_eq(room.get_chosen_branch(), 1)
	assert_eq(room.get_chosen_option().kind, BranchOption.Kind.SAFE)
	assert_eq(room.get_chosen_exit().x, RoomTiles.DoorSide.EAST, "the next room joins the chosen door")
	assert_false(room.choose_branch(0), "the choice holds")


func test_walking_up_to_a_door_chooses_it() -> void:
	var room := _branch_room()
	room.state = RoomController.State.CLEARED
	room.open_exit()
	var player := preload("res://player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var tiles := room.tiles
	var exit := tiles.get_exit_doors()[0]
	player.global_position = room.to_global(RoomTiles.tile_center(RoomTiles.inside_tile_of(exit.x, exit.y, tiles.room_size)))
	await wait_physics_frames(6)
	assert_eq(room.get_chosen_branch(), 0)
