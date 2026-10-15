extends GutTest
## The session object (MP1, D-080, D-081, D-084, D-085/D-123): kinds, player count, local players,
## what each kind allows, the input per player, and the lookup through the tree (solo without a
## session owner, so unit tests and the main menu behave like single player).


func test_solo_is_one_local_player_with_pause_hit_stop_and_local_meta() -> void:
	var mode := GameMode.solo()
	assert_eq(mode.kind, GameMode.Kind.SOLO)
	assert_eq(mode.get_player_count(), 1)
	assert_true(mode.is_local(0))
	assert_false(mode.is_multiplayer())
	assert_true(mode.pauses_for_menus(), "D-043")
	assert_true(mode.allows_hit_stop())
	assert_eq(mode.get_meta_source(), GameMode.MetaSource.LOCAL)


func test_quick_and_guild_never_pause_or_freeze_time() -> void:
	for mode: GameMode in [GameMode.quick(2), GameMode.guild(3)]:
		assert_true(mode.is_multiplayer())
		assert_false(mode.pauses_for_menus(), "D-085: menus do not hold the group")
		assert_false(mode.allows_hit_stop(), "D-085: no hit stop in a group")
	assert_eq(GameMode.quick(2).get_meta_source(), GameMode.MetaSource.NONE, "D-081: quick games without village upgrades")
	assert_eq(GameMode.guild(2).get_meta_source(), GameMode.MetaSource.GUILD)


func test_player_count_is_clamped_and_local_ids_are_checked() -> void:
	assert_eq(GameMode.quick(9).get_player_count(), GameMode.MAX_PLAYERS)
	assert_eq(GameMode.quick(0).get_player_count(), 1)
	var mode := GameMode.quick(2, [1, 1, 5, -1])
	assert_eq(mode.local_player_ids, [1] as Array[int], "duplicates and unknown ids dropped")
	assert_false(mode.is_local(0))
	assert_true(mode.is_local(1))


func test_spawn_order_starts_with_the_primary_player() -> void:
	assert_eq(GameMode.quick(4).get_spawn_order(), [0, 1, 2, 3] as Array[int])
	assert_eq(GameMode.quick(3, [2]).get_spawn_order(), [2, 0, 1] as Array[int])
	var host_only := GameMode.quick(2, [])
	assert_false(host_only.has_local_player(), "a host without a player of its own")
	assert_eq(host_only.get_primary_player_id(), 0)
	assert_eq(host_only.get_spawn_order(), [0, 1] as Array[int])


func test_inputs_keyboard_for_the_local_player_remote_for_the_others() -> void:
	var mode := GameMode.quick(3, [1])
	assert_true(mode.create_input(1) is LocalKeyboardMouseInput)
	assert_true(mode.create_input(0) is RemoteInput)
	assert_true(mode.create_input(2) is RemoteInput)
	var host_only := GameMode.quick(2, [])
	assert_true(host_only.create_input(0) is RemoteInput, "nobody at this machine")


func test_lookup_without_session_owner_is_solo() -> void:
	var node := Node.new()
	assert_eq(GameMode.of(node).kind, GameMode.Kind.SOLO, "outside the tree")
	add_child_autofree(node)
	assert_eq(GameMode.of(node).kind, GameMode.Kind.SOLO, "no owner in the tree")
	assert_eq(GameMode.of_tree(null).kind, GameMode.Kind.SOLO)


func test_lookup_finds_the_session_owner() -> void:
	var owner_node := SessionOwner.new()
	owner_node.game_mode = GameMode.quick(3)
	add_child_autofree(owner_node)
	owner_node.add_to_group(GameMode.OWNER_GROUP)
	var probe := Node.new()
	owner_node.add_child(probe)
	assert_eq(GameMode.of(probe), owner_node.game_mode)
	assert_eq(GameMode.of(probe).get_player_count(), 3)


func test_room_sizes_follow_the_player_count() -> void:
	assert_eq(RoomSequence.room_sizes_for(1), RoomSequence.SOLO_ROOM_SIZES)
	assert_eq(RoomSequence.room_sizes_for(2), RoomSequence.SOLO_ROOM_SIZES, "D-084: 1-2 players S/M")
	assert_eq(RoomSequence.room_sizes_for(3), RoomSequence.GROUP_ROOM_SIZES, "D-084: 3-4 players L")
	assert_eq(RoomSequence.room_sizes_for(4), RoomSequence.GROUP_ROOM_SIZES)


func test_describe_names_kind_and_players() -> void:
	assert_eq(GameMode.quick(3).describe(), "QUICK 3 players, local [0]")
	assert_eq(GameMode.solo().describe(), "SOLO 1 player, local [0]")


## Stand-in for the WorldController: any node of the owner group with a game_mode property.
class SessionOwner:
	extends Node
	var game_mode: GameMode = null
