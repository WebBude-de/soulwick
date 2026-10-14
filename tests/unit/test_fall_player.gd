extends GutTest
## A player falling into an abyss (A4, D-086): only without a dash and after the grace time, input
## locked during the fall, a whole heart past the shield, back to the last safe spot (kept at the
## player), 1 s invulnerable; a room can change landing and damage (trials). One test plays it with
## the real pit physics of a chasm template.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const RING_HOLE_S: PackedScene = preload("res://dungeon/rooms/combat/chasm_ring_hole_s.tscn")
const STEP := 1.0 / 60.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_fall_player_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


## Pits: every point with x >= 100 (feet coordinates).
func _is_pit(point: Vector2) -> bool:
	return point.x >= 100.0


## A player driven by hand: no own physics step, pits from _is_pit.
func _player() -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	player.fall.pit_probe = Callable(self, &"_is_pit")
	return player


func _put_feet(player: Player, feet: Vector2) -> void:
	player.global_position = feet - Player.FEET_OFFSET


func _run(player: Player, seconds: float) -> void:
	var time := 0.0
	while time < seconds:
		player._tick_timers(STEP)
		player.fall.update(STEP)
		time += STEP


func test_no_fall_while_dashing_and_within_the_grace_time() -> void:
	var player := _player()
	_put_feet(player, Vector2(40, 0))
	_run(player, 0.1)
	assert_true(player.fall.has_safe_spot(), "solid ground is remembered")
	player._start_dash(Vector2.RIGHT, Vector2.RIGHT)
	_put_feet(player, Vector2(150, 0))
	player.fall.update(STEP)
	player.fall.update(STEP)
	assert_false(player.is_falling(), "in the air while dashing")
	# Dash over (0.2 s), still over the pit: falls after the grace time.
	_run(player, player.dash_duration)
	assert_false(player.is_falling(), "the grace time starts when the dash ends")
	_run(player, ChasmRules.FALL_GRACE_TIME + 0.02)
	assert_true(player.is_falling(), "after the dash and 0.1 s grace")


func test_grace_time_lets_you_step_back() -> void:
	var player := _player()
	_put_feet(player, Vector2(40, 0))
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 0))
	_run(player, ChasmRules.FALL_GRACE_TIME * 0.5)
	assert_false(player.is_falling())
	_put_feet(player, Vector2(40, 0))
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 0))
	_run(player, ChasmRules.FALL_GRACE_TIME * 0.5)
	assert_false(player.is_falling(), "the grace time starts again")
	_run(player, ChasmRules.FALL_GRACE_TIME)
	assert_true(player.is_falling())


func test_fall_costs_a_heart_past_the_shield_and_returns_to_the_safe_spot() -> void:
	var player := _player()
	player.shield.add_shield(4.0)
	var hp := player.health.get_health()
	_put_feet(player, Vector2(30, 5))
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 5))
	var started: Array = []
	var landed: Array = []
	player.fall.fall_started.connect(func(p: Player) -> void: started.append(p))
	player.fall.landed.connect(func(p: Player, damage: float) -> void: landed.append(damage))
	_run(player, 0.12)
	assert_eq(started.size(), 1)
	assert_true(player.is_input_locked(), "no input while falling")
	assert_true(player.hurtbox.is_invulnerable(), "no hits while falling")
	assert_eq(player.health.get_health(), hp, "the damage comes with the landing")
	_run(player, ChasmRules.FALL_TIME)
	assert_false(player.is_falling())
	assert_eq(landed, [2.0])
	assert_eq(player.health.get_health(), hp - 2.0, "a whole heart")
	assert_eq(player.shield.get_shield(), 4.0, "past the shield")
	assert_almost_eq(player.get_feet_position().x, 30.0, 0.5, "back at the last safe spot")
	assert_false(player.is_input_locked())
	assert_true(player.hurtbox.is_invulnerable(), "invulnerable after landing")
	_run(player, ChasmRules.RESPAWN_INVULNERABILITY - 0.1)
	assert_true(player.hurtbox.is_invulnerable(), "for a second")
	_run(player, 0.2)
	assert_false(player.hurtbox.is_invulnerable())


func test_a_fall_can_kill() -> void:
	var player := _player()
	player.health.take_damage(player.health.get_health() - 2.0)
	player.shield.add_shield(10.0)
	_put_feet(player, Vector2(30, 0))
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 0))
	_run(player, 0.12 + ChasmRules.FALL_TIME)
	assert_true(player.health.is_dead(), "2 HP left, the shield does not help (D-086)")


func test_the_fall_names_the_abyss_as_cause() -> void:
	var player := _player()
	var hits: Array = []
	player.hurtbox.hit_received.connect(func(result: DamageResult, damage: DamageData) -> void: hits.append([result.health_damage, damage.tags.duplicate()]))
	_put_feet(player, Vector2(30, 0))
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 0))
	_run(player, 0.12 + ChasmRules.FALL_TIME)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0][0], 2.0)
	assert_true((hits[0][1] as Array).has(ChasmRules.DAMAGE_TAG))


func test_a_room_can_change_landing_and_damage() -> void:
	var player := _player()
	var hp := player.health.get_health()
	_put_feet(player, Vector2(30, 0))
	_run(player, 0.05)
	player.fall.fall_started.connect(func(p: Player) -> void: p.fall.set_landing(Vector2(-200, 40), 0.5), CONNECT_ONE_SHOT)
	_put_feet(player, Vector2(150, 0))
	_run(player, 0.12 + ChasmRules.FALL_TIME)
	assert_almost_eq(player.get_feet_position(), Vector2(-200, 40), Vector2.ONE)
	assert_eq(player.health.get_health(), hp - 0.5)
	# The override is only for that fall.
	_run(player, 0.05)
	_put_feet(player, Vector2(150, 0))
	_run(player, 0.12 + ChasmRules.FALL_TIME)
	assert_almost_eq(player.get_feet_position(), Vector2(-200, 40), Vector2.ONE, "the last safe spot is the landing now")
	assert_eq(player.health.get_health(), hp - 2.5)


func test_the_safe_spot_keeps_distance_to_the_rim() -> void:
	var player := _player()
	_put_feet(player, Vector2(20, 0))
	_run(player, 0.05)
	_put_feet(player, Vector2(95, 0))
	_run(player, 0.05)
	assert_almost_eq(player.get_last_safe_position().x, 20.0, 0.5, "right at the rim is not safe")


func test_falls_into_a_real_abyss() -> void:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 3
	var room := RING_HOLE_S.instantiate() as RoomController
	room.setup(8, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var safe_feet := room.to_global(RoomTiles.tile_center(Vector2i(1, 1)))
	player.global_position = safe_feet - Player.FEET_OFFSET
	await wait_physics_frames(4)
	assert_false(player.is_falling())
	var pit: Vector2i = room.tiles.get_pit_tiles()[0]
	player.global_position = room.to_global(RoomTiles.tile_center(pit)) - Player.FEET_OFFSET
	await wait_physics_frames(12)
	assert_true(player.is_falling(), "over the abyss on foot")
	await wait_seconds(ChasmRules.FALL_TIME + 0.1)
	assert_false(player.is_falling())
	assert_lt(player.get_feet_position().distance_to(safe_feet), 2.0, "back on the last safe tile")
	assert_eq(player.fall.falls, 1)
	# Bridges carry the player.
	var bridge: Vector2i = room.tiles.get_bridge_tiles()[0]
	player.global_position = room.to_global(RoomTiles.tile_center(bridge)) - Player.FEET_OFFSET
	await wait_physics_frames(15)
	assert_false(player.is_falling(), "a bridge is solid ground")
