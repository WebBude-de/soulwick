extends GutTest
## The room intro (R3, KONZEPT_RAEUME_V2 §1.3, 07_ui.md): door → camera on the goal → banner →
## 3-2-1 → go; the first time per save full (input locked per player, camera swing, card), later
## short (about 2 s); skippable; it holds the fight back (RoomIntro.after_intro) and never locks over
## a running fight. DungeonUI shows the banner, the countdown and the card; the arena starts its
## intro on entry. Also the banner queue (stale banners) and world captions near the player.
## Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_room_intro.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


## Stand-in for a RoomController whose fight may already run.
class FakeRoom:
	extends Node2D
	var started := false
	var room_index := 7

	func is_encounter_started() -> bool:
		return started


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _ui() -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	return ui


func _room() -> FakeRoom:
	return add_child_autofree(FakeRoom.new())


func _goal(room: Node2D, mode := RoomObjective.FLAME) -> RoomObjective:
	var goal := RoomObjective.attach(room, RoomObjective.create(mode))
	goal.goal_args = [40]
	return goal


## Records what an intro emits (it frees itself after "go", so GUT's watcher cannot be asked later).
func _record(intro: RoomIntro) -> Dictionary:
	var log := {"phases": [], "ticks": [], "released": 0, "finished": []}
	intro.phase_changed.connect(func(phase: RoomIntro.Phase) -> void: (log["phases"] as Array).append(phase))
	intro.countdown_tick.connect(func(number: int) -> void: (log["ticks"] as Array).append(number))
	intro.released.connect(func() -> void: log["released"] = int(log["released"]) + 1)
	intro.finished.connect(func(skipped: bool) -> void:
		(log["finished"] as Array).append(skipped)
		log["running"] = intro.fight_was_running)
	return log


func _player() -> Player:
	return add_child_autofree(PLAYER_SCENE.instantiate())


func _arena_room(count := 3) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.ARENA
	room.forced_ambush = 0
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 31
	room.setup(12, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.count_range = Vector2i(count, count)
	group.allow_elites = false
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


# --- Sequence ---

func test_full_intro_the_first_time() -> void:
	var player := _player()
	var room := _room()
	var goal := _goal(room)
	assert_true(RoomIntro.is_first_time(goal), "fresh save")
	var intro := RoomIntro.start(room, goal, player.global_position + Vector2(300, 0))
	assert_true(intro.full)
	assert_eq(RoomIntro.start(room, goal), intro, "one intro per room")
	var log := _record(intro)
	assert_eq(intro.phase, RoomIntro.Phase.DOOR)
	assert_true(player.is_input_locked(), "locked from the closing door on")
	assert_true(RoomIntro.holds_encounter(room))
	assert_false(GameManager.is_game_paused(), "no global pause")
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.PAN, "camera swings to the goal")
	await wait_seconds(RoomIntro.PAN_MOVE_TIME + 0.1)
	var camera := player.get_node("Camera2D") as Camera2D
	assert_gt(camera.position.x, 100.0, "the camera looks at the goal")
	assert_true(player.is_input_locked())
	await wait_seconds(RoomIntro.PAN_TIME - RoomIntro.PAN_MOVE_TIME + RoomIntro.BANNER_LEAD + 0.1)
	assert_eq(intro.phase, RoomIntro.Phase.COUNTDOWN)
	assert_false(player.is_input_locked(), "free to move during 3-2-1")
	assert_eq(log["ticks"], [3])
	await wait_seconds(RoomIntro.COUNTDOWN_FROM * RoomIntro.COUNTDOWN_STEP + 0.2)
	assert_eq(log["ticks"], [3, 2, 1, 0], "3-2-1-go")
	assert_eq(log["phases"], [RoomIntro.Phase.PAN, RoomIntro.Phase.BANNER, RoomIntro.Phase.COUNTDOWN, RoomIntro.Phase.DONE])
	assert_eq(log["released"], 1)
	assert_eq(log["finished"], [false])
	assert_false(RoomIntro.holds_encounter(room))
	await wait_seconds(RoomIntro.CAMERA_RETURN_TIME + 0.1)
	assert_eq(camera.position, Vector2.ZERO, "camera back home")


func test_short_intro_later() -> void:
	var player := _player()
	var room := _room()
	var goal := _goal(room)
	RoomGenre.mark_explained(goal.genre)
	assert_false(RoomIntro.is_first_time(goal))
	var intro := RoomIntro.start(room, goal, Vector2(500, 0))
	assert_false(intro.full)
	assert_false(player.is_input_locked(), "short version: no lock")
	var log := _record(intro)
	var total := RoomIntro.get_total_time(false)
	assert_between(total, 1.6, 2.6, "about 2 s")
	await wait_seconds(total + 0.25)
	assert_eq(log["released"], 1)
	assert_false((log["phases"] as Array).has(RoomIntro.Phase.PAN), "no camera swing")
	assert_eq((player.get_node("Camera2D") as Camera2D).position, Vector2.ZERO, "no camera swing")


func test_after_intro_holds_the_fight() -> void:
	var room := _room()
	var calls: Array[int] = []
	RoomIntro.after_intro(room, func() -> void: calls.append(1))
	assert_eq(calls.size(), 1, "no intro: the fight starts at once")
	var intro := RoomIntro.start(room, _goal(room), Vector2.INF, RoomIntro.Style.SHORT)
	RoomIntro.after_intro(room, func() -> void: calls.append(2))
	assert_eq(calls.size(), 1, "held while the intro runs")
	intro.skip()
	assert_eq(calls, [1, 2] as Array[int], "starts with the release")
	assert_true(intro.skipped)


func test_skip_frees_players_and_camera() -> void:
	var player := _player()
	var room := _room()
	var intro := RoomIntro.start(room, _goal(room), player.global_position + Vector2(0, 400), RoomIntro.Style.FULL)
	await wait_seconds(RoomIntro.DOOR_TIME + 0.2)
	assert_true(player.is_input_locked())
	intro.skip()
	assert_false(player.is_input_locked())
	assert_true(intro.is_released())
	await wait_seconds(RoomIntro.CAMERA_RETURN_TIME + 0.1)
	assert_eq((player.get_node("Camera2D") as Camera2D).position, Vector2.ZERO)


func test_never_holds_a_running_fight() -> void:
	var player := _player()
	var room := _room()
	var intro := RoomIntro.start(room, _goal(room), Vector2(300, 0), RoomIntro.Style.FULL)
	var log := _record(intro)
	room.started = true
	await wait_process_frames(2)
	assert_true(log.get("running", false), "RoomController started without asking (hook missing)")
	assert_false(player.is_input_locked())
	assert_eq(log["phases"], [RoomIntro.Phase.BANNER, RoomIntro.Phase.DONE], "names the goal")
	assert_eq(log["ticks"], [], "no 3-2-1 over a running fight")
	assert_eq(log["finished"], [true])


func test_room_freed_mid_intro_lets_go() -> void:
	var player := _player()
	var room := _room()
	RoomIntro.start(room, _goal(room), Vector2(300, 0), RoomIntro.Style.FULL)
	assert_true(player.is_input_locked())
	room.free()
	assert_false(player.is_input_locked(), "never stuck behind an unloaded room")


# --- DungeonUI ---

func test_ui_shows_banner_countdown_and_card() -> void:
	var ui := _ui()
	var room := _room()
	var goal := _goal(room)
	var intro := RoomIntro.start(room, goal, Vector2.INF, RoomIntro.Style.FULL)
	await wait_process_frames(1)
	assert_eq(ui.get_intro(), intro)
	assert_eq(ui.get_objective_bar().objective, goal, "the task bar comes with the intro")
	var card := ui.get_room_intro_card()
	assert_not_null(card, "first time: the explanation card from the start")
	assert_eq(card.genre, goal.genre)
	# Recorded when it happens: "go" comes up to 0.3 s before the check below and the card frees
	# itself 0.4 s after it starts to fade, so reading card._finishing then could hit a freed card.
	var card_finished := [false]
	card.finished.connect(func() -> void: card_finished[0] = true)
	await wait_seconds(RoomIntro.DOOR_TIME + 0.1)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq(banner.name, &"IntroBanner")
	assert_eq((banner.find_child("Title", true, false) as Label).text, "Halte die Flamme 40 s")
	assert_not_null(banner.find_child("SkipHint", true, false), "full version: skip hint")
	await wait_seconds(RoomIntro.BANNER_LEAD + 0.1)
	assert_eq(ui.get_countdown().get_text(), "3")
	ui.show_banner("Etwas anderes")
	assert_eq(ui.get_banner(), banner, "the intro banner stays while the intro runs")
	await wait_seconds(RoomIntro.COUNTDOWN_FROM * RoomIntro.COUNTDOWN_STEP + 0.1)
	assert_eq(ui.get_countdown().get_text(), "Los!")
	assert_true(card_finished[0], "the card fades with go")
	await wait_seconds(DungeonUI.INTRO_BANNER_AFTER + 0.8)
	assert_ne(ui.get_banner(), banner, "the intro banner is gone after go")


func test_arena_entry_starts_the_intro() -> void:
	var ui := _ui()
	var room := _arena_room()
	await wait_process_frames(2)
	assert_eq(ui.show_room_genre(room), RoomGenre.ARENA)
	var intro := RoomIntro.get_intro(room)
	assert_not_null(intro, "the arena is announced with the intro, not just a banner")
	assert_true(RoomObjective.of_room(room) is ArenaObjective)
	assert_ne(intro.focus, Vector2.INF)
	assert_null(ui.get_banner(), "no plain genre banner")
	# RoomController waits for the intro (hook wired): activate() does not start the fight yet.
	room.activate()
	await wait_process_frames(3)
	assert_false(room.is_encounter_started(), "the fight waits for 3-2-1")
	var bar := ui.get_objective_bar()
	assert_true(bar.visible)
	ui.on_arena_started(room, false)
	assert_null(ui.get_banner() if ui.get_banner() != null and ui.get_banner().name != &"IntroBanner" else null, "no second genre banner")


func test_arena_intro_with_the_room_hook() -> void:
	var ui := _ui()
	var room := _arena_room()
	await wait_process_frames(2)
	ui.show_room_genre(room)
	# What RoomController.activate() does once the hook is wired.
	RoomIntro.after_intro(room, room.start_encounter)
	assert_false(room.is_encounter_started(), "the fight waits for the intro")
	await wait_seconds(RoomIntro.get_total_time(true) + 0.3)
	assert_true(room.is_encounter_started(), "and starts with go")
	assert_eq(ui.get_countdown().get_text(), "Los!")


# --- Banner queue and world captions ---

func test_banners_of_a_room_left_behind_are_dropped() -> void:
	var ui := _ui()
	var old_room: int = RunManager._current_room
	RunManager._current_room = 5
	ui.show_banner("Raum geschafft!")
	ui.show_banner("Neu im Dorf")
	assert_eq(ui.get_banner_queue_size(), 1)
	RunManager._current_room = 6
	ui.show_banner("Ein neues Gebiet")
	await wait_process_frames(2)
	assert_eq((ui.get_banner().find_child("Title", true, false) as Label).text, "Ein neues Gebiet",
		"the news of the new room comes at once, the old one is dropped")
	assert_eq(ui.get_banner_queue_size(), 0)
	RunManager._current_room = old_room


func test_banner_style() -> void:
	var ui := _ui()
	ui.show_banner("Raum geschafft!", "Der Weg ist frei", UiKit.COLOR_GOLD)
	var banner := ui.get_banner()
	assert_true(banner is PanelContainer, "dark plaque (07_ui.md)")
	var stripe := banner.find_child("Stripe", true, false) as ColorRect
	assert_not_null(stripe, "colour stripe on the left")
	assert_eq(stripe.color, UiKit.COLOR_GOLD)


func test_world_captions_only_near_and_never_with_a_banner() -> void:
	var ui := _ui()
	var player := _player()
	var content: SpecialContent = add_child_autofree(SpecialContent.new())
	content.global_position = player.global_position + Vector2(WorldCaption.NEAR_DISTANCE * 3.0, 0)
	var caption := content.add_caption("Brunnen", Vector2(0, -96))
	assert_true(caption.is_in_group(WorldCaption.GROUP), "taken in by itself")
	await wait_seconds(0.5)
	assert_almost_eq(caption.self_modulate.a, 0.0, 0.01, "far away: hidden")
	player.global_position = WorldCaption.get_center(caption) + Vector2(0, 60)
	await wait_seconds(0.5)
	assert_almost_eq(caption.self_modulate.a, 1.0, 0.01, "near: shown")
	ui.show_banner("Raum geschafft!")
	await wait_seconds(0.5)
	assert_almost_eq(caption.self_modulate.a, 0.0, 0.01, "never together with a banner")
