extends GutTest
## Campfire between two biomes (D-103, ROADMAP A6): slots outside the room count, the
## template, the floor blend, the one choice per player (heal or one more stack) and the dialog.

const CAMPFIRE_SCENE: PackedScene = preload("res://dungeon/rooms/campfire/campfire_room.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _upgrades: UpgradeManager


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_campfire_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _upgrades.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func _context(player: Player = null) -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 7
	context.upgrade_manager = _upgrades
	context.player = player
	return context


func _campfire_room(context: DungeonContext, after_boss := 15, portal := true) -> RoomController:
	var room := CAMPFIRE_SCENE.instantiate() as RoomController
	room.setup(after_boss, RoomSequence.RoomType.CAMPFIRE, -1, portal, context)
	room.slot_index = RoomSequence.get_campfire_slot_after(after_boss)
	add_child_autofree(room)
	return room


# --- Slots: the campfire does not count as a room ---

func test_campfire_slots_sit_between_the_biomes() -> void:
	assert_true(RoomSequence.is_campfire_slot(16))
	assert_true(RoomSequence.is_campfire_slot(32))
	assert_true(RoomSequence.is_campfire_slot(48))
	assert_false(RoomSequence.is_campfire_slot(15))
	assert_false(RoomSequence.is_campfire_slot(17))
	assert_false(RoomSequence.is_campfire_slot(0))
	assert_eq(RoomSequence.get_slot_type(16), RoomSequence.RoomType.CAMPFIRE)
	assert_eq(RoomSequence.get_slot_type(15), RoomSequence.RoomType.BOSS)
	assert_eq(RoomSequence.get_slot_type(17), RoomSequence.RoomType.COMBAT, "room 16 opens the next cycle")
	assert_eq(RoomSequence.get_campfire_slot_after(15), 16)
	assert_eq(RoomSequence.get_campfire_slot_after(30), 32)
	assert_eq(RoomSequence.get_campfire_slot_after(45), 48)
	assert_eq(RoomSequence.get_campfire_slot_after(14), 0, "only boss rooms have a campfire")
	assert_eq(RoomSequence.get_campfire_slot_after(10), 0, "not after a champion room")


func test_room_numbers_are_unchanged_by_the_campfires() -> void:
	var expected := 1
	var campfires := 0
	for slot in range(1, 200):
		var room := RoomSequence.get_room_for_slot(slot)
		if RoomSequence.is_campfire_slot(slot):
			campfires += 1
			assert_eq(room, expected - 1, "slot %d: the campfire keeps the boss room number" % slot)
			assert_eq(RoomSequence.get_room_type(room), RoomSequence.RoomType.BOSS)
			continue
		assert_eq(room, expected, "slot %d is room %d" % [slot, expected])
		assert_eq(RoomSequence.get_slot_for_room(room), slot, "room %d maps back to slot %d" % [room, slot])
		assert_eq(RoomSequence.get_slot_type(slot), RoomSequence.get_room_type(room), "slot %d: same type as room %d" % [slot, room])
		expected += 1
	assert_eq(campfires, 12, "one campfire per 15 rooms")


func test_campfire_type_has_a_name() -> void:
	assert_eq(RoomSequence.get_type_name(RoomSequence.RoomType.CAMPFIRE), "Lagerfeuer")


# --- Template and floor blend ---

func test_campfire_template_is_walkable_around_the_fire() -> void:
	var room := CAMPFIRE_SCENE.instantiate() as RoomController
	autofree(room)
	var tiles := room.get_node("Tiles") as RoomTiles
	var reachable := tiles.get_reachable_tiles()
	assert_true(reachable.has(tiles.get_exit_inside_tile()), "exit reachable")
	var anchor := RoomTiles.local_to_tile((room.get_node("ContentAnchor") as Marker2D).position)
	var portal := RoomTiles.local_to_tile((room.get_node("PortalAnchor") as Marker2D).position)
	assert_true(reachable.has(portal), "portal on reachable floor")
	assert_ne(anchor, portal, "portal away from the fire")
	assert_eq(room.get_node("SpawnPoints").get_child_count(), 5, "non-combat templates keep five markers")


func test_campfire_room_blends_old_into_new_biome() -> void:
	var room := _campfire_room(_context())
	var tiles := room.tiles
	assert_true(room.is_campfire())
	assert_eq(room.spawner.get_biome(room.room_index).id, &"crypt")
	assert_eq(room.get_next_biome().id, &"slime_grotto")
	assert_true(tiles.has_biome_blend())
	var blend := tiles.get_blend_layer()
	assert_eq(blend.get_used_cells().size(), tiles.get_used_cells().size(), "the blend layer covers every cell")
	assert_false(blend.collision_enabled, "only the base layer collides")
	assert_false(blend.navigation_enabled, "only the base layer carries navigation")
	var entrance_y := (tiles.room_size.y + 1.5) * RoomTiles.TILE_WORLD
	var exit_y := -2.5 * RoomTiles.TILE_WORLD
	assert_eq(tiles.get_blend_progress(entrance_y), 0.0, "entrance corridor: old biome")
	assert_eq(tiles.get_blend_progress(exit_y), 1.0, "exit corridor: new biome")
	var middle := tiles.get_blend_progress(tiles.room_size.y * 0.5 * RoomTiles.TILE_WORLD)
	assert_between(middle, 0.2, 0.8, "the middle is mixed")


func test_campfire_back_into_the_crypt_uses_the_crypt_tiles() -> void:
	# Room 60 (ember forge boss) -> 61 (crypt, which has no biome tileset of its own).
	var room := _campfire_room(_context(), 60)
	assert_eq(room.spawner.get_biome(60).id, &"ember_forge")
	assert_eq(room.get_next_biome().id, &"crypt")
	assert_eq(room.tiles.tile_set.resource_path, "res://dungeon/environment/ember_forge_tileset.tres")
	assert_eq(room.tiles.get_blend_layer().tile_set.resource_path, "res://dungeon/environment/dungeon_tileset.tres")


func test_backdrop_of_the_room_before_can_make_way() -> void:
	var room := _campfire_room(_context())
	assert_eq(room.tiles.get_backdrop_north_rows(), RoomTiles.BACKDROP_MARGIN.y)
	var full := room.tiles.get_backdrop().get_used_cells().size()
	room.make_way_for_campfire()
	assert_eq(room.tiles.get_backdrop_north_rows(), 0)
	assert_lt(room.tiles.get_backdrop().get_used_cells().size(), full, "rock above the north wall removed")


func test_transition_overlays_get_denser_towards_the_new_biome() -> void:
	var room := _campfire_room(_context())
	var rng := RandomNumberGenerator.new()
	var south := 0
	var north := 0
	for run in 40:
		rng.seed = run
		for tile in CampfireContent.get_overlay_tiles(room.tiles, rng):
			var progress := room.tiles.get_blend_progress((tile.y + 0.5) * RoomTiles.TILE_WORLD)
			assert_between(progress, CampfireContent.OVERLAY_BAND.x, CampfireContent.OVERLAY_BAND.y)
			if progress < 0.5:
				south += 1
			else:
				north += 1
	assert_gt(north, south, "more overlays near the exit (%d) than near the entrance (%d)" % [north, south])


func test_campfire_art_falls_back_to_placeholders() -> void:
	var texture := CampfireArt.get_texture("does_not_exist_" + str(Time.get_ticks_usec()))
	assert_not_null(texture)
	var fire := CampfireArt.get_texture(CampfireArt.FIRE)
	assert_eq(fire.get_width(), CampfireArt.FIRE_FRAME_SIZE.x * CampfireArt.FIRE_FRAMES)
	assert_eq(fire.get_height(), CampfireArt.FIRE_FRAME_SIZE.y)
	var placeholder := CampfireArt._placeholder(CampfireArt.get_overlay_name(&"ember_forge"))
	assert_eq(placeholder.get_size(), Vector2i(32 * CampfireArt.OVERLAY_TILES, 32))


# --- Entering: no encounter, no room events, exit open ---

func test_entering_the_campfire_is_calm_and_counts_nothing() -> void:
	var room := _campfire_room(_context())
	watch_signals(room)
	watch_signals(EventBus)
	room.activate()
	assert_eq(room.state, RoomController.State.CLEARED)
	assert_false(room.is_encounter_started())
	assert_eq(room.enemy_container.get_child_count(), 0)
	assert_true(room._exit_door.is_open, "the way on is open right away")
	assert_signal_not_emitted(room, "completed", "no completed room")
	assert_signal_not_emitted(EventBus, "room_entered", "no room entry for stats, music, hints")
	assert_signal_not_emitted(EventBus, "room_completed")
	assert_not_null(room.get_campfire_content())


func test_exit_portal_follows_the_switch() -> void:
	var with_portal := _campfire_room(_context(), 15, true)
	var without := _campfire_room(_context(), 30, false)
	var portals := func(room: RoomController) -> int:
		var count := 0
		for child in room.get_children():
			if child.get_script() == preload("res://dungeon/rooms/special/exit_portal.gd"):
				count += 1
		return count
	assert_eq(portals.call(with_portal), 1)
	assert_eq(portals.call(without), 0)
	assert_eq(without.get_next_biome().id, &"shadow_realm", "campfire 30 leads into the shadow realm")


# --- Music: interlude at the fire, no second blend when the next biome starts (C3 hook) ---

func test_campfire_music_crosses_the_ambient_only_once() -> void:
	MusicPlayer.clear_handoff()
	var music := MusicPlayer.new()
	add_child_autofree(music)
	music.enter_room(15)
	await wait_process_frames(2)
	music.complete_room(15)
	var room := _campfire_room(_context())
	# Same call as DungeonManager._begin_campfire().
	get_tree().call_group(MusicPlayer.GROUP, &"begin_interlude", room.get_next_biome())
	assert_true(music.is_in_interlude())
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto", "the next biome's ambient at the fire")
	var ambient_players := music._ambient.get_audible_count()
	music.enter_room(16)
	assert_eq(music.get_current_ambient(), "ambient_slime_grotto")
	assert_eq(music._ambient.get_audible_count(), ambient_players, "room 16 does not blend the ambient again")
	assert_eq(music.get_current_track(), "", "the loop waits for the biome entry stinger")
	music.complete_transition()
	assert_eq(music.get_current_track(), "dungeon_slime_grotto")
	MusicPlayer.clear_handoff()


# --- The one choice ---

func test_stackable_upgrades_are_owned_and_below_their_limit() -> void:
	assert_true(CampfireContent.get_stackable_upgrades(_upgrades).is_empty(), "nothing owned yet")
	_upgrades.acquire_upgrade(_upgrade(&"strong_attack"))
	_upgrades.acquire_upgrade(_upgrade(&"double_shot"))
	var pierce := _upgrade(&"pierce")
	for i in pierce.max_stacks:
		_upgrades.acquire_upgrade(pierce)
	_upgrades.acquire_upgrade(_upgrade(&"wide_swing"))
	var stackable := CampfireContent.get_stackable_upgrades(_upgrades)
	assert_true(stackable.has(_upgrade(&"strong_attack")), "unlimited")
	assert_true(stackable.has(_upgrade(&"wide_swing")), "1 / 3")
	assert_false(stackable.has(_upgrade(&"double_shot")), "1 / 1 is at its limit")
	assert_false(stackable.has(pierce), "3 / 3 is at its limit")
	assert_false(stackable.has(_upgrade(&"fast_attack")), "not owned")


func test_heal_once_up_to_max_health() -> void:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var room := _campfire_room(_context(player))
	var content := room.get_campfire_content()
	watch_signals(content)
	assert_false(content.take_rest(player, null), "nothing to heal at full health")
	player.health.take_damage(5.0)
	var before := player.health.get_health()
	assert_true(content.take_rest(player, null))
	assert_eq(player.health.get_health(), minf(before + CampfireContent.HEAL_AMOUNT, player.health.get_max_health()))
	assert_signal_emitted_with_parameters(content, "rest_taken", [player, null])
	assert_true(content.has_rested(player))
	player.health.take_damage(2.0)
	assert_false(content.take_rest(player, null), "one choice per player")
	assert_false(content._interactable.enabled, "the fire is done once every player rested")


func test_heal_stops_at_max_health() -> void:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var content := _campfire_room(_context(player)).get_campfire_content()
	player.health.take_damage(1.0)
	assert_true(content.take_rest(player, null))
	assert_eq(player.health.get_health(), player.health.get_max_health())


func test_strengthen_an_owned_upgrade_by_one_stack() -> void:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var content := _campfire_room(_context(player)).get_campfire_content()
	var swing := _upgrade(&"wide_swing")
	_upgrades.acquire_upgrade(swing)
	assert_false(content.take_rest(player, _upgrade(&"fast_attack")), "only owned upgrades")
	var double_shot := _upgrade(&"double_shot")
	_upgrades.acquire_upgrade(double_shot)
	assert_false(content.take_rest(player, double_shot), "not above the limit")
	assert_true(content.take_rest(player, swing))
	assert_eq(_upgrades.get_stacks(swing.id), 2)
	assert_false(content.take_rest(player, swing), "one choice per player")
	assert_eq(_upgrades.get_stacks(swing.id), 2)


func test_every_player_chooses_for_themselves() -> void:
	var first: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var second: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var content := _campfire_room(_context(first)).get_campfire_content()
	first.health.take_damage(4.0)
	second.health.take_damage(4.0)
	assert_true(content.take_rest(first, null))
	assert_false(content.has_rested(second), "the rest of one player is not the rest of the other")
	assert_true(content.take_rest(second, null))


# --- Dialog ---

func test_rest_dialog_offers_heal_and_the_stackable_upgrades() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = _context()
	var swing := _upgrade(&"wide_swing")
	_upgrades.acquire_upgrade(swing)
	var upgrades: Array[UpgradeData] = [swing, _upgrade(&"strong_attack")]
	var result := [-2]
	var ask := func() -> void: result[0] = await ui.choose_campfire_rest(4.0, false, upgrades)
	ask.call()
	await wait_physics_frames(2)
	var modal := ui.find_children("*", "Modal", true, false)
	assert_eq(modal.size(), 1)
	var heal: Button = null
	var labels: Array[String] = []
	for button: Button in modal[0].find_children("*", "Button", true, false):
		labels.append(button.text)
		if button.text == "Heilen":
			heal = button
	assert_not_null(heal)
	assert_true(heal.disabled, "full health: heal is off")
	assert_true(labels.has(swing.display_name))
	assert_true(GameManager.is_game_paused(), "pauses like the other choice dialogs")
	(modal[0] as Modal).finish(2)
	await wait_physics_frames(2)
	assert_eq(result[0], 2, "second upgrade picked")
	assert_false(GameManager.is_game_paused())
