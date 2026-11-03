extends GutTest
## The crowned one of "Jagd" during the room intro (FS7b, feedback #5d3cb8f7 "Man konnte den Gekrönten
## einfach instant fangen"): players may walk during the goal banner and the 3-2-1, so he watches then
## too. A player in sight wakes him: he flees at once but stays invulnerable until the fight starts,
## and his "spotted" banner waits for the end of the countdown. Not during the door or Flint's tour,
## never on a client (the host decides).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const STEP := 1.0 / 60.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_hunt_intro_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _room() -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(20, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(3, 3)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _hunt(room: RoomController) -> HuntMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"hunt"), rng), &"hunt")
	return CombatVariant.of(room) as HuntMode


## A player a tile beside him (in sight), the intro started and held in phase.
func _setup(phase: RoomIntro.Phase) -> HuntMode:
	var room := _room()
	var mode := _hunt(room)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = mode.crowned.global_position + Vector2(RoomTiles.TILE_WORLD, 0)
	var intro := mode.start_intro()
	assert_not_null(intro, "the intro runs")
	if intro != null:
		intro.set_process(false)
		intro.phase = phase
	return mode


func test_he_watches_during_banner_and_countdown_only() -> void:
	assert_true(HuntRules.watches_in_intro(RoomIntro.Phase.BANNER))
	assert_true(HuntRules.watches_in_intro(RoomIntro.Phase.COUNTDOWN))
	for phase in [RoomIntro.Phase.DOOR, RoomIntro.Phase.PAN, RoomIntro.Phase.FLINT]:
		assert_false(HuntRules.watches_in_intro(phase), "not in phase %d" % phase)


func test_a_player_in_sight_during_the_countdown_wakes_him() -> void:
	var mode := _setup(RoomIntro.Phase.COUNTDOWN)
	var banners: Array[String] = []
	mode.banner_shown.connect(func(_variant: CombatVariant, title: String, _subtitle: String, _color: Color) -> void:
		banners.append(title))
	mode._physics_process(STEP)
	assert_true(mode.is_woken_in_intro(), "he saw the player")
	assert_false(mode.crowned.is_in_intro(), "no longer frozen")
	assert_true(mode.flight.is_fleeing(), "he flees at once")
	assert_true(mode.crowned.hurtbox.is_invulnerable(), "but cannot be hit before the fight")
	assert_false(mode.flight.evade_points.is_empty(), "with his zigzag spots")
	assert_true(banners.is_empty(), "no banner over the 3-2-1")
	mode.room.activate()
	assert_false(mode.is_started(), "the intro still holds the fight")
	RoomIntro.get_intro(mode.room).skip()
	assert_true(mode.is_started(), "Los!")
	assert_false(mode.crowned.hurtbox.is_invulnerable(), "the fight started: catchable")
	assert_true(banners.has(DungeonTexts.t(&"MODE_HUNT_SPOTTED")), "the spotted banner comes now")
	assert_true(mode.flight.is_fleeing(), "still fleeing")


func test_door_and_flint_tour_do_not_wake_him() -> void:
	for phase in [RoomIntro.Phase.DOOR, RoomIntro.Phase.FLINT]:
		var mode := _setup(phase)
		mode._physics_process(STEP)
		assert_false(mode.is_woken_in_intro(), "phase %d: he waits" % phase)
		assert_true(mode.crowned.is_in_intro())
		assert_eq(mode.flight.state, BountyFlight.State.WATCHING)


func test_a_client_room_never_decides() -> void:
	var mode := _setup(RoomIntro.Phase.COUNTDOWN)
	mode.room.remote_encounter = true
	mode._physics_process(STEP)
	assert_false(mode.is_woken_in_intro(), "the host decides")
	assert_true(mode.crowned.is_in_intro())


func test_a_player_out_of_sight_leaves_him_frozen() -> void:
	var mode := _setup(RoomIntro.Phase.COUNTDOWN)
	mode.room.context.player.global_position = mode.crowned.global_position + Vector2(HuntRules.SIGHT_RANGE + 200.0, 0)
	mode._physics_process(STEP)
	assert_false(mode.is_woken_in_intro())
	assert_true(mode.crowned.is_in_intro())
