extends SceneTree
## Automated play-through (headless): village -> dungeon -> N rooms -> death -> village.
## Checks M2/M4/M5 acceptance rules at runtime and prints PASS/FAIL lines. After every boss room
## it walks through the campfire (D-103) and checks that it does not count as a room. Combat rooms:
## room kind rules (D-100), shape and ingredients (A3): every marker and the exit stay reachable
## after the ingredient scatter; the shapes and ingredients seen are printed at the end.
## Abysses (A4): rooms with pits keep exit and markers reachable on foot, no enemy and no gold over
## an abyss, the player never falls while standing on the walk-in tile.
## Way-finding (A10): rooms are entered through the south, west or east wall and never overlap a
## live room other than their neighbour; branch rooms prepare room n+1 only after the choice (the
## test walks up to a door, the elite nest when offered) and seal the other door; a cracked wall is
## blown up with a barrel blast and its niche (chest, crystals or merchant) is used. Branches and
## secrets are made more frequent for the test (BranchRules/SecretRules.chance_override).
## Usage: godot --headless --path . -s tools/smoke_test.gd -- [rooms]
## Classes are accessed dynamically: this script is compiled before autoloads exist.

const SAVE_PATH := "user://smoke_test_save.cfg"
const MAX_LIVE_ROOMS := 3
## Test aid: more branches and secret niches than in the game, so a run of 20+ rooms sees them.
const BRANCH_CHANCE := 0.7
const SECRET_CHANCE := 0.45

var _failures: Array[String] = []
var _max_live_rooms := 0
var _dungeon: Node = null
var _modal_log: Array[String] = []
## Room kinds (D-086): rolled per range and actually used, plus the previous combat room's kind.
var _rolled_early := {}
var _rolled_deep := {}
var _used_kinds := {}
var _previous_kind := -1
var _campfires_seen := 0
## Shapes and ingredients of the combat rooms played (A3).
var _shapes_seen := {}
var _ingredients_seen := {}
## Abysses (A4): chasm rooms and rooms with holes played.
var _chasm_rooms := 0
var _hole_rooms := 0
## Way-finding (A10): entrance walls seen, branches taken, secret niches opened.
var _entrance_sides := {}
var _branches_taken: Array[String] = []
var _secrets_opened: Array[String] = []
var _longest_corridor := 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var rooms_to_play := 12
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		rooms_to_play = int(args[0])
	# Buttons are found by their German texts; English is the default language (D-111).
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_manager.load_game()
	# Own settings in German: the buttons are found by their German texts, whatever the real
	# language is (the tools run with their own settings.cfg).
	save_manager.settings_path = "user://smoke_test_settings.cfg"
	save_manager.load_settings()
	save_manager.set_option(&"language", "de")
	process_frame.connect(_watch)
	load("res://dungeon/rooms/branches/branch_rules.gd").chance_override = BRANCH_CHANCE
	load("res://dungeon/rooms/secrets/secret_rules.gd").chance_override = SECRET_CHANCE

	change_scene_to_file("res://scenes/game.tscn")
	await _frames(20)
	# The game applies the saved language on start; the buttons are found by their German texts.
	TranslationServer.set_locale("de")
	var controller := current_scene.get_node("WorldController")
	_check(controller.get_world().get_script().get_global_name() == &"Village", "starts in the village")
	var village_player: Node = controller.get_player()
	_check(village_player != null, "player spawned in village")

	controller.enter_dungeon()
	await _frames(20)
	_dungeon = controller.get_world()
	var run_manager := root.get_node("RunManager")
	_check(_dungeon.get_script().get_global_name() == &"DungeonManager", "dungeon loaded")
	_check(run_manager.is_run_active(), "run started")
	var player: Node = controller.get_player()
	_check(player != village_player, "new player instance for the dungeon (D-041)")
	# Traps and explosions are real now; the test player must survive the walk-through.
	player.health.reset(99999.0)

	for index in range(1, rooms_to_play + 1):
		var ok: bool = await _play_room(index, player, run_manager)
		if not ok:
			break
		_check(controller.get_player() == player, "room %d keeps the same player instance" % index)

	_check(_max_live_rooms <= MAX_LIVE_ROOMS, "never more than 3 live rooms (max seen: %d)" % _max_live_rooms)
	if rooms_to_play >= 20:
		_check(_entrance_sides.size() >= 2, "rooms entered through side walls too (%s)" % _entrance_sides)
		_check(not _branches_taken.is_empty(), "at least one branch taken (%d)" % _branches_taken.size())
		_check(not _secrets_opened.is_empty(), "at least one secret niche opened (%d)" % _secrets_opened.size())
	var bosses := floori(rooms_to_play / 15.0)
	_check(_campfires_seen == bosses, "one campfire after each of the %d boss rooms (seen: %d)" % [bosses, _campfires_seen])
	var gold_before: int = run_manager.get_run_gold()
	var permanent_before: int = save_manager.get_permanent_gold()
	print("run gold before death: ", gold_before)

	# Death -> run end -> village.
	player.health.take_damage(999999.0)
	await _frames(150)
	_check(not run_manager.is_run_active(), "run ended after death")
	var summary: Dictionary = run_manager.get_last_summary()
	var expected := permanent_before + ceili(summary.get("remaining_gold", -1) * 0.5)
	_check(summary.get("payout", -1) == ceili(summary.get("remaining_gold", -1) * 0.5), "summary payout is 50 %")
	_check(save_manager.get_permanent_gold() == expected, "50 %% payout credited once (%d == %d)" % [save_manager.get_permanent_gold(), expected])
	await _press_modal_button("Zurück ins Dorf")
	await _frames(20)
	_check(controller.get_world().get_script().get_global_name() == &"Village", "back in the village after the run")
	_check(not root.get_node("GameManager").is_game_paused(), "no stale pause reason after the run")

	var reloaded := ConfigFile.new()
	_check(reloaded.load(SAVE_PATH) == OK and reloaded.get_value("progress", "permanent_gold", -1) == expected, "permanent gold persisted to disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("modals seen: ", ", ".join(_modal_log))
	_print_kind_distribution()
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		quit(1)


func _play_room(index: int, player: Node, run_manager: Node) -> bool:
	var room: Node = _dungeon.get_room(index)
	if room == null:
		_fail("room %d was not prepared" % index)
		return false
	var type_name: String = ["COMBAT", "COMBAT_UPGRADE", "SPECIAL", "MINIBOSS", "BOSS", "CAMPFIRE"][room.room_type]
	var expected_type := _expected_type(index)
	_check(type_name == expected_type, "room %d type %s (expected %s)" % [index, type_name, expected_type])
	if index > 1:
		# Room 1 is entered by spawning inside it.
		_check(not room.is_encounter_started(), "room %d: preparing does not start the encounter" % index)

	# Walk in: teleport onto the walkable tile nearest to the middle of the floor (shapes with a
	# solid middle, catacomb corridors).
	player.global_position = room.to_global(_walk_in_point(room))
	await _frames(6)
	_check(run_manager.get_current_room() == index, "RunManager room %d" % index)
	_check(_dungeon.get_room(index - 2) == null, "room %d unloaded when entering %d" % [index - 2, index])
	var tiles_of_room: Node = room.get_node("Tiles")
	_entrance_sides[tiles_of_room.entrance_side] = _entrance_sides.get(tiles_of_room.entrance_side, 0) + 1
	_longest_corridor = maxi(_longest_corridor, tiles_of_room.entrance_corridor_extra)
	_check_no_overlap(index)
	var is_branch: bool = room.is_branch_room()
	if type_name == "BOSS":
		# Behind a boss room comes the campfire, room index + 1 only behind it (D-103).
		_check(_dungeon.get_campfire(index) != null, "campfire prepared when entering boss room %d" % index)
	elif is_branch:
		# Branch (D-105): room n+1 waits for the choice; the doors show what lies behind them.
		_check(_dungeon.get_room(index + 1) == null, "branch room %d: room %d waits for the choice" % [index, index + 1])
		_check(room.get_exit_doors().size() == 2, "branch room %d has two exits" % index)
	else:
		_check(_dungeon.get_room(index + 1) != null, "room %d prepared when entering %d" % [index + 1, index])

	if type_name == "SPECIAL":
		print("room %d: special %s, portal=%s" % [index, room.special_type, room.has_portal])
		await _use_special(room, player)
	else:
		_check(room.is_encounter_started(), "room %d encounter started on entry" % index)
		var enemies: Array = room.enemy_container.get_children().filter(func(n): return n.get_script() != null and n.get_script().get_global_name() == &"Enemy")
		if type_name.begins_with("COMBAT"):
			_check_room_kind(index, room)
			_check_shape_and_ingredients(index, room)
			_check_abyss(index, room, player, enemies)
			var limits: Vector2i = load("res://dungeon/room_sequence.gd").get_enemy_count_range(index)
			# Encounter groups (A3): a quiet room has 1-2 strong enemies, themes may scale the count.
			# Same rule as EnemySpawner.roll_enemy_count.
			var group: Resource = room.spawner.encounter_group
			if group != null:
				var range: Vector2i = group.get_count_range(index)
				limits = Vector2i(maxi(1, roundi(range.x * group.count_factor)), maxi(1, roundi(range.y * group.count_factor)))
			_check(enemies.size() >= limits.x and enemies.size() <= limits.y, "room %d spawned %d enemies (%d-%d)" % [index, enemies.size(), limits.x, limits.y])
		elif type_name == "BOSS":
			_check(enemies.size() == 1, "room %d boss spawned alone" % index)
			# The boss intro (D-098) keeps the boss invulnerable: skip it like a player would.
			await _frames(30)
			_check(_skip_boss_intros() > 0, "room %d boss intro started and was skipped" % index)
		else:
			_check(enemies.size() >= 2, "room %d champion comes with an escort (%d)" % [index, enemies.size()])
		var kind_label: String = _describe_room(room)
		print("room %d: %s%s, %d enemies, doors %s" % [index, type_name, (" [%s]" % kind_label) if not kind_label.is_empty() else "", enemies.size(), _describe_doors(room)])
		# Combat variants (A7): fast-forward the soul flame raid so the room may close.
		var variant: Node = room.get_node_or_null("CombatVariant")
		if variant != null:
			variant.step(41.0)
		for enemy in enemies:
			_kill(enemy, player)
		# Splitting slimes, summons and later waves add enemies: keep clearing until empty.
		for sweep in 12:
			await _frames(25)
			var remaining: Array = room.enemy_container.get_children().filter(func(n): return _is_enemy(n) and not n.is_dead())
			if remaining.is_empty():
				break
			for enemy in remaining:
				_kill(enemy, player)
		# Banner first, dialogs only after the reward delay (D-070).
		await _frames(20)
		_check(_find_modal(root) == null, "room %d: no dialog right after the last kill" % index)
		await _frames(100)
		_check_no_gold_in_abyss(index, room)
		# Exactly one encounter: entering again must not respawn.
		room.start_encounter()
		await _frames(2)
		var alive: Array = room.enemy_container.get_children().filter(func(n): return _is_enemy(n) and not n.is_dead())
		_check(alive.is_empty(), "room %d: no respawn after clear" % index)
		# The upgrade dialog pauses the game; the blast needs running physics.
		await _resolve_modals()
		await _use_secret(index, room, player)

	if not type_name.begins_with("COMBAT"):
		_previous_kind = -1
	# Room 3 of each cycle: upgrade choice after the fight.
	await _resolve_modals()
	await _frames(10)
	if is_branch:
		await _take_branch(index, room, player)
	var exit_door: Node = room._exit_door
	_check(exit_door.is_open, "room %d exit opened after completion" % index)
	if type_name == "BOSS" and exit_door.is_open:
		return await _play_campfire(index, player, run_manager)
	return exit_door.is_open


## Live rooms never overlap (A10): neighbours share at most their corridor row or column, rooms two
## slots apart may share rock of their outer rings, nothing else (ExitRules.Footprint).
func _check_no_overlap(index: int) -> void:
	var rooms: Array = _dungeon.room_container.get_children()
	for a in rooms.size():
		for b in range(a + 1, rooms.size()):
			var first: Node = rooms[a]
			var second: Node = rooms[b]
			var cut: Rect2i = _dungeon.get_room_rect(first).intersection(_dungeon.get_room_rect(second))
			if absi(first.slot_index - second.slot_index) == 1:
				_check(cut.size.x <= 1 or cut.size.y <= 1, "room %d: neighbours %s/%s only share their corridor line (%s)" % [index, first.name, second.name, cut])
			else:
				# Rock may lie on rock (outer rings); never on a floor, a wall or a corridor.
				_check(not _dungeon.rooms_clash(first, second), "room %d: %s and %s do not overlap (%s %s / %s %s)" % [index, first.name, second.name,
						_dungeon.get_room_rect(first), _describe_doors(first), _dungeon.get_room_rect(second), _describe_doors(second)])


## "S3 -> N7 (+0)": entrance wall and place, exits, extra corridor tiles (test output).
func _describe_doors(room: Node) -> String:
	var tiles: Node = room.get_node("Tiles")
	var names := ["N", "E", "S", "W"]
	var exits: Array[String] = []
	for exit: Vector2i in tiles.get_exit_doors():
		exits.append("%s%d" % [names[exit.x], exit.y])
	return "%s%d -> %s (+%d)" % [names[tiles.entrance_side], tiles.entrance_x, "/".join(exits), tiles.entrance_corridor_extra]


## Branch room (D-105): the doors stay shut after the fight; walking up to one decides for the group.
## The elite nest is taken whenever it is offered. Room n+1 then exists with that way's content,
## the other door is sealed, the chosen one opens.
func _take_branch(index: int, room: Node, player: Node) -> void:
	var options: Array = room.branch_options
	_check(room.get_branch_choice().is_offered, "branch room %d: the doors wait for the choice" % index)
	_check(not room._exit_door.is_open, "branch room %d: no door opens before the choice" % index)
	var pick := 0
	for i in options.size():
		if options[i].kind == 1:
			pick = i
	var exit: Vector2i = room.get_node("Tiles").get_exit_doors()[pick]
	var tiles: Node = room.get_node("Tiles")
	var inside: Vector2i = tiles.inside_tile_of(exit.x, exit.y, tiles.room_size)
	player.global_position = room.to_global((Vector2(inside) + Vector2(0.5, 0.5)) * 64.0)
	await _frames(8)
	_check(room.get_chosen_branch() == pick, "branch room %d: walking up to door %d chooses it (got %d)" % [index, pick, room.get_chosen_branch()])
	var next: Node = _dungeon.get_room(index + 1)
	_check(next != null, "branch room %d: room %d prepared after the choice" % [index, index + 1])
	_check(_dungeon.get_live_room_count() <= MAX_LIVE_ROOMS, "branch room %d: at most 3 live rooms" % index)
	var other: Node = room.get_exit_doors()[1 - pick]
	_check(not other.is_open, "branch room %d: the other door stays sealed" % index)
	var option: Object = options[pick]
	_branches_taken.append("%d: %s" % [index, option.describe()])
	if next == null:
		return
	match int(option.kind):
		1:
			_check(next.get_variant_id() == &"elite_nest", "room %d: elite nest behind the swords" % (index + 1))
		2:
			_check(next.get_variant_id() == option.variant_id or next.get_variant_id() == &"", "room %d: the hidden variant %s" % [index + 1, option.variant_id])
		3:
			_check(next.special_type == option.special_type, "room %d: special type %d of the chosen way" % [index + 1, option.special_type])
		_:
			_check(next.get_variant_id() == &"" and not next.has_wager_altar(), "room %d: the safe way is a plain fight" % (index + 1))
	# The player leaves the zone; the chosen door must be open for the walk on.
	player.global_position = room.to_global(_walk_in_point(room))
	await _frames(4)


## A cracked wall (A10): a barrel blast in front of it opens the niche; its content is used.
func _use_secret(index: int, room: Node, player: Node) -> void:
	var niche: Node = room.get_node_or_null("SecretNiche")
	if niche == null:
		return
	var tiles: Node = room.get_node("Tiles")
	var site: Object = niche.site
	if niche.is_open:
		# A bomber's death or a barrel in the fight broke it already (as intended).
		print("room %d: cracked wall broken during the fight" % index)
	else:
		_check(not tiles.get_reachable_tiles().has(site.get_content_tile()), "room %d: the niche is sealed before the blast" % index)
		# A sword hit only taps it.
		var tap: RefCounted = load("res://components/combat/damage_data.gd").new()
		tap.amount = 5.0
		tap.source = player
		tap.tags.assign([&"melee"])
		niche.get_hurtbox().receive_hit(tap)
		_check(not niche.is_open, "room %d: a sword does not break the cracked wall" % index)
	var blast: Node = load("res://dungeon/rooms/ingredients/barrel_blast.gd").create(96.0, 0.0, 0.0, 0.0)
	room.add_child(blast)
	blast.global_position = room.to_global((Vector2(site.approach) + Vector2(0.5, 0.2)) * 64.0)
	await _frames(6)
	_check(niche.is_open, "room %d: the barrel blast breaks the cracked wall" % index)
	if not niche.is_open:
		return
	_check(tiles.get_reachable_tiles().has(site.get_content_tile()), "room %d: the niche is reachable after the blast" % index)
	var content: Node = niche.content
	_check(content != null, "room %d: something waits in the niche" % index)
	if content == null:
		return
	var kind_name: String = ["chest", "crystals", "merchant"][niche.content_kind]
	_secrets_opened.append("%d: %s" % [index, kind_name])
	match int(niche.content_kind):
		1:
			var before: int = root.get_node("RunManager").get_run_crystals()
			content.collect(player)
			_check(root.get_node("RunManager").get_run_crystals() > before, "room %d: niche crystals taken" % index)
		2:
			_check(content.offers.size() > 0, "room %d: the merchant has goods (%d)" % [index, content.offers.size()])
			for child in content.get_children():
				if child.get_script() != null and child.get_script().get_global_name() == &"Interactable":
					child.interact(player)
			await _frames(6)
			await _resolve_modals()
		_:
			await _frames(4)
			content.get_interactable().interact(player)
			await _frames(4)
			await _resolve_modals()
			_check(content.is_open, "room %d: the niche chest opened" % index)


## Campfire behind a boss room (D-103): no room number, no heal step, no enemies, one choice at
## the fire, the exit portal (CAMPFIRE_EXIT_PORTAL), music interlude, then on to boss_index + 1.
func _play_campfire(boss_index: int, player: Node, run_manager: Node) -> bool:
	var campfire: Node = _dungeon.get_campfire(boss_index)
	_check(campfire != null, "campfire prepared behind boss room %d" % boss_index)
	if campfire == null:
		return false
	_campfires_seen += 1
	var manager_constants: Dictionary = _dungeon.get_script().get_script_constant_map()
	var with_portal: bool = manager_constants["CAMPFIRE_EXIT_PORTAL"]
	_check(campfire.is_campfire(), "campfire %d has the campfire room type" % boss_index)
	_check(campfire.room_index == boss_index, "campfire keeps the number of boss room %d" % boss_index)
	_check(_dungeon.get_room(boss_index + 1) == null, "room %d waits until the campfire is entered" % (boss_index + 1))
	_check(_dungeon.get_room(boss_index).has_portal != with_portal, "boss room %d: portal only without the campfire portal" % boss_index)
	var heal_steps_before: int = _dungeon.get_rooms_until_heal()
	var tiles: Node = campfire.get_node("Tiles")
	# Walk in like the player: through the entrance, past the fire.
	player.global_position = campfire.to_global(tiles.position + (Vector2(tiles.entrance_x, tiles.room_size.y - 3) + Vector2(0.5, 0.5)) * 64.0)
	await _frames(6)
	_check(run_manager.get_current_room() == boss_index, "campfire %d does not count as a room (RunManager %d)" % [boss_index, run_manager.get_current_room()])
	_check(_dungeon.get_active_room_index() == boss_index, "campfire %d: active room number stays %d" % [boss_index, boss_index])
	_check(_dungeon.get_room(boss_index - 1) == null, "room %d unloaded when entering the campfire" % (boss_index - 1))
	_check(_dungeon.get_room(boss_index) != null, "boss room %d stays loaded behind the campfire" % boss_index)
	_check(_dungeon.get_room(boss_index + 1) != null, "room %d prepared when entering the campfire" % (boss_index + 1))
	_check(_dungeon.get_live_room_count() <= MAX_LIVE_ROOMS, "campfire %d: at most 3 live rooms" % boss_index)
	_check(campfire.enemy_container.get_child_count() == 0 and not campfire.is_encounter_started(), "campfire %d: no enemies" % boss_index)
	_check(campfire._exit_door.is_open, "campfire %d: exit open right away" % boss_index)
	_check(campfire.has_portal == with_portal, "campfire %d: exit portal = %s" % [boss_index, with_portal])
	_check(campfire.get_node("Tiles").has_biome_blend(), "campfire %d: floor blends into the next biome" % boss_index)
	var music: Node = root.get_tree().get_first_node_in_group(&"music_player")
	if music != null:
		_check(music.is_in_interlude(), "campfire %d: music interlude running" % boss_index)
		var ambient: String = load("res://components/audio/music_rules.gd").ambient_track(campfire.get_next_biome())
		_check(music.get_current_ambient() == ambient, "campfire %d: ambient of the next biome (%s)" % [boss_index, music.get_current_ambient()])
	# The one choice: heal (the test player is hurt a little first).
	player.health.take_damage(10.0)
	var hp_before: float = player.health.get_health()
	var content: Node = campfire.get_campfire_content()
	content._interactable.interact(player)
	await _press_modal_button("Heilen")
	await _frames(4)
	_check(is_equal_approx(player.health.get_health(), hp_before + content.HEAL_AMOUNT), "campfire %d heals +%s HP (%s -> %s)" % [boss_index, content.HEAL_AMOUNT, hp_before, player.health.get_health()])
	_check(content.has_rested(player) and not content._interactable.enabled, "campfire %d: one choice per player" % boss_index)
	_check(_dungeon.get_rooms_until_heal() == heal_steps_before, "campfire %d leaves the heal countdown alone" % boss_index)
	_check(_find_modal(root) == null, "campfire %d: no dialog left open" % boss_index)
	print("campfire after room %d: portal=%s, next biome %s" % [boss_index, campfire.has_portal, campfire.get_next_biome().display_name])
	return true


## Room kind rules (D-100): rooms 1-5 normal, no chasm twice in a row, fallback to a normal room
## only without a template, single-player sizes, spawn marker count per size.
func _check_room_kind(index: int, room: Node) -> void:
	var sequence: GDScript = load("res://dungeon/room_sequence.gd")
	var kinds: Dictionary = sequence.get_script_constant_map()["RoomKind"]
	var chasm: int = kinds["CHASM"]
	var solo_sizes: Array = sequence.get_script_constant_map()["SOLO_ROOM_SIZES"]
	var rolled: int = room.rolled_kind
	var used: int = room.room_kind
	_check(rolled >= 0, "room %d has a rolled room kind" % index)
	if index < sequence.get_script_constant_map()["CHASM_FROM_ROOM"]:
		_check(rolled == kinds["NORMAL"], "room %d: only normal rooms before room %d" % [index, sequence.get_script_constant_map()["CHASM_FROM_ROOM"]])
	_check(not (used == chasm and _previous_kind == chasm), "room %d: no chasm room right after a chasm room" % index)
	var catalog: Object = _dungeon.get_combat_catalog()
	var expected: int = rolled if catalog.has_kind(rolled, sequence.SOLO_ROOM_SIZES) else kinds["NORMAL"]
	_check(used == expected, "room %d: kind %d used for rolled %d (expected %d)" % [index, used, rolled, expected])
	_check(solo_sizes.has(room.room_size_class), "room %d: single-player size class" % index)
	var markers: int = room.get_spawn_markers().size()
	var min_markers: int = sequence.get_min_spawn_points(room.room_size_class)
	_check(markers >= min_markers and markers <= sequence.get_script_constant_map()["MAX_SPAWN_POINTS"], "room %d: %d spawn markers (min %d)" % [index, markers, min_markers])
	var bucket: Dictionary = _rolled_early if index < sequence.get_script_constant_map()["CHASM_FROM_ROOM"] else _rolled_deep
	var rolled_name: String = sequence.get_kind_name(rolled)
	var used_name: String = sequence.get_kind_name(used)
	bucket[rolled_name] = bucket.get(rolled_name, 0) + 1
	_used_kinds[used_name] = _used_kinds.get(used_name, 0) + 1
	_previous_kind = used


func _print_kind_distribution() -> void:
	var sequence: GDScript = load("res://dungeon/room_sequence.gd")
	var constants := sequence.get_script_constant_map()
	var first_kind_room: int = constants["CHASM_FROM_ROOM"]
	print("room kinds rolled, rooms 1-%d: %s (weights %s)" % [first_kind_room - 1, _format_counts(_rolled_early), constants["ROOM_KIND_WEIGHTS_EARLY"]])
	print("room kinds rolled, rooms %d+: %s (weights %s)" % [first_kind_room, _format_counts(_rolled_deep), constants["ROOM_KIND_WEIGHTS"]])
	print("room kinds used (after template fallback): %s" % _format_counts(_used_kinds))
	# One run is a small sample: the same draw over many simulated 47-room runs for comparison.
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	var early := {}
	var deep := {}
	for run in 1000:
		var previous := -1
		for index in range(1, 48):
			if not sequence.is_normal_combat(sequence.get_room_type(index)):
				previous = -1
				continue
			var kind: int = sequence.roll_room_kind(index, previous, rng)
			var bucket: Dictionary = early if index < constants["CHASM_FROM_ROOM"] else deep
			var kind_name: String = sequence.get_kind_name(kind)
			bucket[kind_name] = bucket.get(kind_name, 0) + 1
			previous = kind
	print("room kinds drawn over 1000 simulated runs, rooms 1-%d: %s" % [first_kind_room - 1, _format_counts(early)])
	print("room kinds drawn over 1000 simulated runs, rooms %d+: %s" % [first_kind_room, _format_counts(deep)])
	print("shapes played (kind · shape · size): %s" % _format_counts(_shapes_seen))
	print("ingredients scattered: %s" % _format_counts(_ingredients_seen))
	print("abyss: %d chasm rooms, %d rooms with holes" % [_chasm_rooms, _hole_rooms])
	print("entrance walls (0 N, 1 E, 2 S, 3 W): %s, longest extra corridor %d" % [_format_counts(_entrance_sides), _longest_corridor])
	print("branches taken: %s" % ", ".join(_branches_taken))
	print("secret niches opened: %s" % ", ".join(_secrets_opened))


## Rooms with pits (A4): exit and markers reachable on foot (enemies do not dash), no enemy spawned
## over the abyss, the player stands safely on the walk-in tile and has not fallen.
func _check_abyss(index: int, room: Node, player: Node, enemies: Array) -> void:
	var tiles: Node = room.get_node("Tiles")
	if not tiles.has_pits():
		return
	var chasm: int = load("res://dungeon/room_sequence.gd").get_script_constant_map()["RoomKind"]["CHASM"]
	if room.room_kind == chasm:
		_chasm_rooms += 1
	else:
		_hole_rooms += 1
	var on_foot: Dictionary = tiles.get_reachable_tiles(0)
	_check(on_foot.has(tiles.get_exit_inside_tile()), "room %d: exit reachable on foot with abysses" % index)
	var scatter: Node = room.get_node_or_null("Ingredients")
	if scatter != null:
		for marker in scatter.get_marker_tiles(room):
			_check(on_foot.has(marker) and not tiles.is_pit(marker), "room %d: marker %s on solid floor" % [index, marker])
	for enemy in enemies:
		if is_instance_valid(enemy):
			_check(not tiles.is_pit_at_local(room.to_local(enemy.global_position)), "room %d: %s not spawned over the abyss" % [index, enemy.name])
	_check(not player.is_falling() and player.fall.has_safe_spot(), "room %d: player safe on the walk-in tile" % index)


## No gold or heart lying over an abyss after the fight (A4). Pickups flying to the player may
## cross it (the reward dialog pauses them mid-flight), only resting ones count.
func _check_no_gold_in_abyss(index: int, room: Node) -> void:
	var tiles: Node = room.get_node("Tiles")
	if not tiles.has_pits():
		return
	for node in room.find_children("*", "Area2D", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"GoldPickup" and float(node.get(&"_homing_speed")) <= 0.0:
			var local: Vector2 = room.to_local(node.global_position)
			_check(not tiles.is_pit_at_local(local), "room %d: pickup not in the abyss (tile %s, age %.2f s)" % [index, tiles.local_to_tile(local), node.get(&"_age")])


## Shape and ingredients of a combat room (A3): the scatter ran once from the dungeon RNG, 2-3
## ingredients (the catacomb may get fewer), exit and every marker still reachable, the room name
## only for kinds with their own gameplay (D-110).
func _check_shape_and_ingredients(index: int, room: Node) -> void:
	var template: Resource = load("res://dungeon/rooms/templates/room_template.gd").of(room)
	_check(template != null, "room %d: template in the catalog" % index)
	if template == null:
		return
	var label := _describe_room(room)
	_shapes_seen[label] = _shapes_seen.get(label, 0) + 1
	var scatter: Node = room.get_node_or_null("Ingredients")
	_check(scatter != null and scatter.plan != null, "room %d: ingredients scattered" % index)
	if scatter == null or scatter.plan == null:
		return
	var set_script: GDScript = load("res://dungeon/rooms/ingredients/ingredient_set.gd")
	var count: int = scatter.plan.ingredients.size()
	var is_catacomb: bool = template.shape == template.Shape.CATACOMB
	_check(count <= 3 and (count >= 2 or is_catacomb), "room %d: %d ingredients" % [index, count])
	for kind in scatter.plan.ingredients:
		var kind_name: String = set_script.get_kind_name(kind)
		_ingredients_seen[kind_name] = _ingredients_seen.get(kind_name, 0) + 1
	var tiles: Node = room.get_node("Tiles")
	var reachable: Dictionary = tiles.get_reachable_tiles()
	var blocked: Array = scatter.get_blocked_tiles()
	_check(reachable.has(tiles.get_exit_inside_tile()), "room %d: exit reachable after the scatter" % index)
	for marker in scatter.get_marker_tiles(room):
		_check(reachable.has(marker) and not blocked.has(marker), "room %d: marker %s reachable after the scatter" % [index, marker])
	var name: String = _dungeon.get_room_kind_label(room)
	var normal: int = load("res://dungeon/room_sequence.gd").get_script_constant_map()["RoomKind"]["NORMAL"]
	if room.room_kind == normal and not is_catacomb:
		_check(name.is_empty(), "room %d: normal rooms stay unnamed (D-110)" % index)
	else:
		_check(not name.is_empty(), "room %d: '%s' named on entry (D-110)" % [index, name])


## "Normal · Ring · M" (test output only; the game shows names only via get_room_kind_label).
func _describe_room(room: Node) -> String:
	if not room.has_room_kind():
		return ""
	var sequence: GDScript = load("res://dungeon/room_sequence.gd")
	var template_script: GDScript = load("res://dungeon/rooms/templates/room_template.gd")
	var template: Resource = template_script.of(room)
	var shape: String = template_script.get_shape_name(template.shape) if template != null else "?"
	var label := "%s · %s · %s" % [sequence.get_kind_name(room.room_kind), shape, sequence.get_size_name(room.room_size_class)]
	if room.rolled_kind >= 0 and room.rolled_kind != room.room_kind:
		label += " (statt %s)" % sequence.get_kind_name(room.rolled_kind)
	return label


## Centre of the free walkable floor tile nearest to the middle of the room (local position).
func _walk_in_point(room: Node) -> Vector2:
	var tiles: Node = room.get_node("Tiles")
	var reachable: Dictionary = tiles.get_reachable_tiles()
	var scatter: Node = room.get_node_or_null("Ingredients")
	var occupied: Array = scatter.get_blocked_tiles() if scatter != null else []
	var middle: Vector2 = tiles.get_floor_rect().get_center()
	var best := Vector2i(tiles.entrance_x, tiles.room_size.y - 2)
	var best_distance := INF
	for tile: Vector2i in reachable:
		if tile.x < 0 or tile.y < 0 or tile.x >= tiles.room_size.x or tile.y >= tiles.room_size.y - 1 or occupied.has(tile):
			continue
		var distance := ((Vector2(tile) + Vector2(0.5, 0.5)) * 64.0).distance_to(middle)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return tiles.position + (Vector2(best) + Vector2(0.5, 0.5)) * 64.0


func _format_counts(counts: Dictionary) -> String:
	var total := 0
	for key in counts:
		total += counts[key]
	var parts: Array[String] = []
	for key in counts:
		parts.append("%s %d (%.0f %%)" % [key, counts[key], 100.0 * counts[key] / maxi(total, 1)])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _use_special(room: Node, player: Node) -> void:
	await _frames(4)
	for content in room.get_children():
		for child in content.get_children():
			if child.get_script() != null and child.get_script().get_global_name() == &"Interactable" and child.enabled:
				if child.prompt.begins_with("Dungeon verlassen"):
					continue
				child.interact(player)
				await _frames(4)
				await _resolve_modals()
				return


## Enemy or a subclass (summoning rifts, A7); the count check above stays on the exact class.
func _is_enemy(node: Object) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == &"Enemy":
			return true
		script = script.get_base_script()
	return false


func _kill(enemy: Node, player: Node) -> void:
	var damage: RefCounted = load("res://components/combat/damage_data.gd").new()
	damage.amount = 9999.0
	damage.source = player
	damage.hit_id = load("res://components/combat/damage_data.gd").next_hit_id()
	damage.tags.assign([&"melee"])
	enemy.hurtbox.receive_hit(damage)


## Skips every running boss intro (after its grace time). Returns how many were skipped.
func _skip_boss_intros() -> int:
	var skipped := 0
	for node in root.find_children("*", "Node", true, false):
		if node.get_script() != null and node.get_script().get_global_name() == &"BossIntro" and node.skip():
			skipped += 1
	return skipped


## Answers every open dialog: picks the first upgrade, closes shops, declines confirmations.
func _resolve_modals() -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			return
		var buttons := _buttons(modal)
		var labels: Array[String] = []
		for button in buttons:
			labels.append(button.text)
		_modal_log.append("[" + "|".join(labels) + "]")
		var preferred := ["Wählen", "Schließen", "Weiterspielen", "Abbrechen", "Zurück ins Dorf"]
		var pressed := false
		for wanted in preferred:
			for button in buttons:
				if button.text == wanted and not button.disabled:
					button.pressed.emit()
					pressed = true
					break
			if pressed:
				break
		if not pressed and not buttons.is_empty():
			buttons[0].pressed.emit()


func _press_modal_button(text: String) -> void:
	for attempt in 40:
		await _frames(3)
		var modal := _find_modal(root)
		if modal == null:
			continue
		for button in _buttons(modal):
			if button.text == text:
				button.pressed.emit()
				return
	_fail("dialog with button '%s' not found" % text)


func _find_modal(node: Node) -> Node:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal" and not child.is_queued_for_deletion():
			return child
		var found := _find_modal(child)
		if found != null:
			return found
	return null


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _expected_type(index: int) -> String:
	match (index - 1) % 5 + 1:
		3:
			return "COMBAT_UPGRADE"
		4:
			return "SPECIAL"
		5:
			return "BOSS" if index % 15 == 0 else "MINIBOSS"
	return "COMBAT"


func _watch() -> void:
	if _dungeon != null and is_instance_valid(_dungeon):
		_max_live_rooms = maxi(_max_live_rooms, _dungeon.get_live_room_count())


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	print("FAIL ", message)
	_failures.append(message)
