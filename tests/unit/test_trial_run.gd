extends GutTest
## A run through a trial (D-102, D-109, D-112): starting and leaving the parcours,
## mistakes cost half a heart but never the run, flawless gives a soul crystal per player, the chest
## opens once for the first player and offers an upgrade choice, darkness hurts in the light run.

const TRIAL_ROOM: PackedScene = preload("res://dungeon/rooms/trials/trial_room.tscn")
const CONTENT: PackedScene = preload("res://dungeon/rooms/trials/trial_content.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SAFE_TILE := Vector2i(2, 5)
const START_TILE := Vector2i(5, 9)
const FINISH_TILE := Vector2i(7, 5)

var _old_save_path: String
var _upgrades: UpgradeManager


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_trial_run_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	_upgrades = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_upgrades.upgrade_pool.append(load("res://upgrades/data/" + path))


func after_each() -> void:
	HitStop.reset()
	# Door views free their pieces with queue_free (D1): let a frame pass so they are not orphans.
	await wait_process_frames(1)


func _context(player: Player = null, seed_value := 21) -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = seed_value
	context.upgrade_manager = _upgrades
	context.player = player
	return context


func _trial(context: DungeonContext, kind := SpecialTable.TrialKind.GAUNTLET) -> TrialContent:
	var room := TRIAL_ROOM.instantiate() as RoomController
	room.setup(4, RoomSequence.RoomType.SPECIAL, SpecialTable.TRIAL, false, context)
	add_child_autofree(room)
	var content := CONTENT.instantiate() as TrialContent
	content.forced_kind = kind
	room.add_child(content)
	content.setup(context, room)
	return content


func _player() -> Player:
	return add_child_autofree(PLAYER_SCENE.instantiate()) as Player


## Puts the player's feet on the centre of a room tile.
func _put(player: Player, content: TrialContent, tile: Vector2i) -> void:
	player.global_position = content.room.to_global(RoomTiles.tile_center(tile)) - Player.FEET_OFFSET


# --- Rules ---

func test_mistakes_never_end_the_run() -> void:
	assert_eq(TrialRules.capped_damage(1.0, 6.0, 0.0), 1.0, "half a heart")
	assert_eq(TrialRules.capped_damage(1.0, 1.0, 0.0), 0.5, "leaves half a heart")
	assert_eq(TrialRules.capped_damage(1.0, 0.5, 0.0), 0.0, "the last half heart is safe")
	assert_eq(TrialRules.capped_damage(1.0, 0.5, 1.0), 1.0, "the shield takes it")
	assert_eq(TrialRules.capped_damage(1.0, 1.0, 0.5), 1.0)


func test_darkness_ticks_every_two_seconds_and_resets_in_the_light() -> void:
	var state := TrialRules.tick_darkness(0.0, 1.9, false)
	assert_eq(state[1], 0.0)
	state = TrialRules.tick_darkness(state[0], 0.2, false)
	assert_eq(state[1], TrialRules.DARK_DAMAGE)
	assert_almost_eq(state[0], 0.1, 0.0001)
	assert_eq(TrialRules.tick_darkness(1.5, 0.1, true), [0.0, 0.0] as Array[float], "back in the light")


# --- Run state ---

func test_stepping_into_the_parcours_starts_and_leaving_pauses_the_run() -> void:
	var player := _player()
	var content := _trial(_context(player))
	watch_signals(content)
	_put(player, content, SAFE_TILE)
	content.update_player(player, 0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.IDLE, "the safe way starts nothing")
	_put(player, content, START_TILE)
	content.update_player(player, 0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.RUNNING)
	assert_signal_emitted_with_parameters(content, "run_started", [player])
	_put(player, content, SAFE_TILE)
	content.update_player(player, 0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.IDLE, "back on the safe way")


func test_a_hazard_hit_costs_half_a_heart() -> void:
	var player := _player()
	var content := _trial(_context(player))
	var course := content.course as GauntletCourse
	var hazard := course.hazards[0]
	while not hazard.is_dangerous():
		course.advance(1.0 / 60.0)
	_put(player, content, START_TILE)
	content.update_player(player, 0.016)
	player.global_position = content.room.to_global(hazard.hit_rect.get_center()) - Player.FEET_OFFSET
	var before := player.health.get_health()
	watch_signals(content)
	content.update_player(player, 0.016)
	assert_eq(content.get_mistakes(player), 1)
	assert_signal_emitted_with_parameters(content, "mistake_made", [player, TrialRules.MISTAKE_DAMAGE])
	assert_eq(player.health.get_health(), before - TrialRules.MISTAKE_DAMAGE)
	content.update_player(player, 0.016)
	assert_eq(content.get_mistakes(player), 1, "I-frames and the cooldown: one hit, one mistake")


func test_no_mistake_while_invulnerable_or_outside_a_run() -> void:
	var player := _player()
	# No player in the context: step() only runs the timers, the test moves nobody.
	var content := _trial(_context())
	assert_false(content.register_mistake(player, 1.0), "not running")
	content.start_run(player)
	player.hurtbox.set_invulnerable(Player.INVULNERABLE_DASH, true)
	assert_false(content.register_mistake(player, 1.0), "dashing through is allowed")
	player.hurtbox.set_invulnerable(Player.INVULNERABLE_DASH, false)
	assert_true(content.register_mistake(player, 1.0))
	assert_false(content.register_mistake(player, 1.0), "cooldown after a mistake")
	content.step(TrialRules.MISTAKE_COOLDOWN + 0.01)
	player.hurtbox.set_invulnerable(Player.INVULNERABLE_HIT, false)
	assert_true(content.register_mistake(player, 1.0))
	assert_eq(content.get_mistakes(player), 2)


func test_a_trial_never_ends_the_run() -> void:
	var player := _player()
	var content := _trial(_context(player))
	content.start_run(player)
	player.health.take_damage(player.health.get_health() - 0.5)
	watch_signals(content)
	assert_true(content.register_mistake(player, 1.0))
	assert_signal_emitted_with_parameters(content, "mistake_made", [player, 0.0])
	assert_true(player.is_alive())
	assert_eq(player.health.get_health(), 0.5)
	assert_eq(content.get_mistakes(player), 1, "still a mistake: no flawless bonus")


# --- Finish, flawless, chest ---

func test_flawless_finish_gives_a_soul_crystal() -> void:
	var player := _player()
	var content := _trial(_context(player))
	watch_signals(content)
	_put(player, content, START_TILE)
	content.update_player(player, 0.016)
	_put(player, content, FINISH_TILE)
	content.update_player(player, 0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.FINISHED)
	assert_signal_emitted_with_parameters(content, "run_finished", [player, true])
	assert_eq(RunManager.get_run_crystals(), TrialRules.FLAWLESS_CRYSTALS)


func test_a_mistake_costs_the_crystal_but_not_the_chest() -> void:
	var player := _player()
	var content := _trial(_context(player))
	watch_signals(content)
	content.start_run(player)
	content.register_mistake(player, 1.0)
	assert_true(content.finish_run(player))
	assert_signal_emitted_with_parameters(content, "run_finished", [player, false])
	assert_eq(RunManager.get_run_crystals(), 0)
	assert_true(content.is_chest_open())
	assert_false(content.finish_run(player), "finished once")


func test_flawless_counts_per_player_and_the_chest_opens_once() -> void:
	var first := _player()
	var second := _player()
	var content := _trial(_context(first))
	watch_signals(content)
	content.start_run(first)
	content.start_run(second)
	content.register_mistake(second, 1.0)
	assert_eq(content.get_mistakes(first), 0, "the mistake of one player is not the other's")
	content.finish_run(first)
	assert_true(content.is_chest_open(), "opens as soon as one player arrives")
	assert_signal_emit_count(content, "chest_opened", 1)
	assert_true(content.chest.is_open())
	content.finish_run(second)
	assert_signal_emit_count(content, "chest_opened", 1, "the chest opens once")
	assert_signal_emit_count(content, "run_finished", 2)
	assert_eq(RunManager.get_run_crystals(), TrialRules.FLAWLESS_CRYSTALS, "only the flawless player")


func test_open_chest_opens_the_shortcut_and_offers_an_upgrade() -> void:
	var player := _player()
	var context := _context(player)
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	ui.context = context
	context.ui = ui
	var content := _trial(context)
	content.start_run(player)
	content.finish_run(player)
	assert_eq(content.room.tiles.wall_rects, TrialLayout.get_wall_rects(true), "gate open")
	await wait_physics_frames(2)
	var modals := ui.find_children("*", "Modal", true, false)
	assert_eq(modals.size(), 1, "upgrade choice from the chest (D-109)")
	var labels: Array[String] = []
	for label: Label in modals[0].find_children("*", "Label", true, false):
		labels.append(label.text)
	assert_true(labels.has("Truhe der Prüfung"))
	var before := _upgrades.get_active_upgrades().size()
	var offer_card := modals[0].find_children("*", "UiCard", true, false)
	assert_gt(offer_card.size(), 0)
	(offer_card[0] as UiCard).activate()
	await wait_physics_frames(2)
	assert_eq(_upgrades.get_active_upgrades().size(), before + 1)
	assert_false(GameManager.is_game_paused())


# --- Light run ---

func test_darkness_costs_half_a_heart_every_two_seconds() -> void:
	var player := _player()
	var content := _trial(_context(player), SpecialTable.TrialKind.LIGHT_RUN)
	var course := content.course as LightRunCourse
	for torch in course.torches:
		torch.set_lit(false)
	_put(player, content, Vector2i(15, 7))
	content.update_player(player, 0.016)
	assert_eq(content.get_run_state(player), TrialContent.RunState.RUNNING)
	var before := player.health.get_health()
	for i in 3:
		content.update_player(player, 0.5)
	assert_eq(content.get_mistakes(player), 0, "1.5 s in the dark are fine")
	content.update_player(player, 0.5)
	assert_eq(content.get_mistakes(player), 1)
	assert_eq(player.health.get_health(), before - TrialRules.DARK_DAMAGE)


func test_staying_in_the_torch_light_is_flawless() -> void:
	var player := _player()
	var content := _trial(_context(player), SpecialTable.TrialKind.LIGHT_RUN)
	var course := content.course as LightRunCourse
	_put(player, content, START_TILE)
	content.update_player(player, 0.016)
	for i in 20:
		content.update_player(player, 0.5)
	assert_eq(content.get_mistakes(player), 0, "next to a burning torch")
	assert_true(course.is_sequence_running(), "the first run start lit the fuse")
