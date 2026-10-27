extends GutTest
## The crowned one of "Jagd" (BountyFlight) in the hall of report #eff1c81c (room 52, Glutkammer,
## jagd_saeulenhalle_ember_forge, player at room tile 15,4 next to his corner): he zigzags only to
## spots that lead away from the players and cowers when cornered instead of running to and fro past
## the player; the guards of that hall still reach and hit a player standing there. Cornered with a
## player right next to him he strikes back once, announced, then cools down (D-206).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const LONE_ENEMY := "res://enemies/data/skeleton.tres"
const LONE_SPOT := Vector2(400, 400)
const PLAN := "res://dungeon/rooms/combat/jagd_saeulenhalle_ember_forge.tscn"
const REPORT_PLAYER_TILE := Vector2i(15, 4)
## Frames until the intro countdown is over and he has spotted the player.
const SPOT_FRAMES := 400

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_enemy_hunt_flight_save.cfg"


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
	var room := (load(PLAN) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(52, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	return room


func _attach_hunt(room: RoomController) -> HuntMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"hunt"), rng), &"hunt")
	return CombatVariant.of(room) as HuntMode


func _player(room: RoomController, tile: Vector2i) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.global_position = room.to_global(RoomTiles.tile_center(tile)) - Player.FEET_OFFSET
	return player


# --- Rule ---

func test_evade_spot_leads_away_and_never_past_a_player() -> void:
	var players: Array[Vector2] = [Vector2(50, 0)]
	assert_true(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(-200, 0), players), "straight away")
	assert_true(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(0, 200), players), "sideways, farther off")
	assert_false(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(100, 0), players), "through the player")
	assert_false(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(150, 100), players), "farther off, but past the player")
	assert_false(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(-5, 0), players), "a step back gains too little")
	var far_player: Array[Vector2] = [Vector2(100, 0)]
	assert_false(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(400, 200), far_player), "a long way that brushes past a player")
	assert_true(BountyFlight.is_evade_spot(Vector2.ZERO, Vector2(-100, 300), far_player), "a long way off to the side")


# --- Report #eff1c81c ---

func test_cornered_crowned_one_never_runs_back_past_the_player() -> void:
	var room := _room()
	var mode := _attach_hunt(room)
	var player := _player(room, REPORT_PLAYER_TILE)
	await wait_physics_frames(2)
	room.activate()
	var flight := mode.flight
	var crowned := mode.crowned
	# Only the crowned one and the player: the guards would down the standing player.
	for guard in mode.guards:
		guard.health.take_damage(INF)
	for i in SPOT_FRAMES:
		if flight.is_fleeing():
			break
		await wait_physics_frames(1)
	assert_true(flight.is_fleeing(), "he saw the player")
	var start_distance := crowned.global_position.distance_to(player.get_feet_position())
	var closest := start_distance
	while is_instance_valid(crowned) and flight.state == BountyFlight.State.FLEEING and not HuntRules.runs_to_hole(flight.time_fleeing):
		closest = minf(closest, crowned.global_position.distance_to(player.get_feet_position()))
		await wait_physics_frames(1)
	assert_gte(closest, start_distance - BountyFlight.EVADE_PASS_SLACK,
		"he never runs towards the standing player (before: from %.0f px down to 22 px, to and fro)" % start_distance)


func test_guards_reach_and_hit_a_player_at_the_reported_spot() -> void:
	var room := _room()
	_attach_hunt(room)
	var player := _player(room, REPORT_PLAYER_TILE)
	await wait_physics_frames(2)
	room.activate()
	var full := player.health.get_health() + player.shield.get_shield()
	# Intro countdown (about 2.5 s) plus 8 s to walk over and strike.
	for i in 630:
		if player.health.get_health() + player.shield.get_shield() < full:
			break
		await wait_physics_frames(1)
	assert_lt(player.health.get_health() + player.shield.get_shield(), full, "the guards reach the player and hit")


# --- Strike back in the corner (D-206) ---

func test_strike_back_rule() -> void:
	assert_true(BountyFlight.wants_defense(true, BountyFlight.DEFENSE_RANGE, 0.0), "cornered, player next to him")
	assert_false(BountyFlight.wants_defense(false, 10.0, 0.0), "not cornered: he flees")
	assert_false(BountyFlight.wants_defense(true, BountyFlight.DEFENSE_RANGE + 1.0, 0.0), "player not next to him")
	assert_false(BountyFlight.wants_defense(true, 10.0, 0.5), "cooldown running")
	assert_gte(BountyFlight.DEFENSE_WIND_UP, 0.4, "readable announcement")


func test_cornered_crowned_one_announces_strikes_and_cools_down() -> void:
	var setup := _lone_hunt(LONE_SPOT + Vector2(90, 0))
	var flight: BountyFlight = setup[0]
	var player: Player = setup[1]
	var circle := flight.enemy.get_node("TelegraphCircle") as CanvasItem
	var full := _life(player)
	# Times on his own clock (time_fleeing): frame counts drift when headless physics catches up.
	var telegraph_time := -1.0
	var hit_time := -1.0
	for frame in 120:
		await wait_physics_frames(1)
		if telegraph_time < 0.0 and flight.is_defending() and circle.visible:
			telegraph_time = flight.time_fleeing
		if _life(player) < full:
			hit_time = flight.time_fleeing
			break
	assert_true(flight.is_cornered(), "no spot leads away from the player")
	assert_gte(telegraph_time, 0.0, "the strike is announced")
	assert_gt(hit_time, telegraph_time, "the hit comes after the announcement")
	assert_gte(hit_time - telegraph_time, 0.4, "at least 0.4 s warning")
	assert_almost_eq(full - _life(player), BountyFlight.DEFENSE_DAMAGE, 0.01, "little damage (half a heart)")
	assert_gt(flight.get_defense_cooldown(), 0.0, "cooldown after the strike")
	var shoved_from := player.get_feet_position().distance_to(flight.enemy.global_position)
	await wait_physics_frames(20)
	assert_gt(player.get_feet_position().distance_to(flight.enemy.global_position), shoved_from + 10.0, "knockback")
	# Back next to him: no new wind-up within the cooldown, the next strike after it.
	_place_feet(player, LONE_SPOT + Vector2(40, 0))
	var early_wind_up := false
	var again := false
	while flight.time_fleeing < hit_time + BountyFlight.DEFENSE_COOLDOWN + BountyFlight.DEFENSE_WIND_UP + 0.5:
		await wait_physics_frames(1)
		if flight.is_defending() and flight.time_fleeing < hit_time + BountyFlight.DEFENSE_COOLDOWN - 0.05:
			early_wind_up = early_wind_up or flight.get_defense_cooldown() <= 0.0
		if flight.is_defending() and flight.time_fleeing > hit_time + BountyFlight.DEFENSE_COOLDOWN - 0.05:
			again = true
	assert_false(early_wind_up, "no new strike within the cooldown")
	assert_true(again, "after the cooldown he strikes again")
	assert_true(flight.is_fleeing(), "he still flees afterwards")


func test_crowned_one_with_a_way_out_flees_and_never_strikes() -> void:
	var setup := _lone_hunt(LONE_SPOT + Vector2(-200, 0))
	var flight: BountyFlight = setup[0]
	var player: Player = setup[1]
	var full := _life(player)
	var struck := false
	var cornered_early := true
	for frame in 90:
		await wait_physics_frames(1)
		struck = struck or flight.is_defending()
		if frame == 5:
			cornered_early = flight.is_cornered()
	assert_false(cornered_early, "a spot leads away")
	assert_false(struck, "no strike while he can flee")
	assert_eq(_life(player), full, "no damage")
	assert_gt(flight.enemy.global_position.distance_to(player.get_feet_position()), BountyFlight.DEFENSE_RANGE, "he ran away")


func test_dash_protects_against_the_strike() -> void:
	var setup := _lone_hunt(LONE_SPOT + Vector2(90, 0))
	var flight: BountyFlight = setup[0]
	var player: Player = setup[1]
	player.hurtbox.set_invulnerable(Player.INVULNERABLE_DASH, true)
	var full := _life(player)
	var struck := false
	for frame in 60:
		await wait_physics_frames(1)
		struck = struck or flight.is_defending()
	assert_true(struck, "he struck")
	assert_gt(flight.get_defense_cooldown(), 0.0, "the strike happened")
	assert_eq(_life(player), full, "the dash blocks it (D-017)")


## A crowned skeleton at LONE_SPOT that already flees, one evade point, a player whose feet stand
## 40 px east of him. [flight, player]
func _lone_hunt(evade_point: Vector2) -> Array:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = load(LONE_ENEMY)
	enemy.apply_scaling(10, false)
	enemy.global_position = LONE_SPOT
	add_child_autofree(enemy)
	var flight := BountyFlight.attach(enemy)
	flight.hole_fixed = true
	flight.hole_position = LONE_SPOT + Vector2(0, 600)
	var points: Array[Vector2] = [evade_point]
	flight.evade_points = points
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.health.reset(20.0)
	_place_feet(player, LONE_SPOT + Vector2(40, 0))
	assert_true(flight.spot(), "he flees")
	return [flight, player]


func _place_feet(player: Player, feet: Vector2) -> void:
	player.global_position = feet - Player.FEET_OFFSET


func _life(player: Player) -> float:
	return player.health.get_health() + player.shield.get_shield()
