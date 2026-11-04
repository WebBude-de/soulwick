extends GutTest
## One Flint for the whole group (WK13, D-225): the group point (FlintGroup: middle of the standing
## players pulled towards the one furthest behind, the bigger part or the host's when they split),
## the one Flint of a world following it clear of every member, excursions held by several local
## guides, a client drawing him from the host's spot (net_driven, NetFlint) and the look owner.
## A single player keeps the solo Flint (test_companion_flint.gd).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const DT := 1.0 / 60.0

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_group_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_phase = GameManager.get_phase()
	GameManager.set_phase(GameManager.Phase.DUNGEON)


func after_each() -> void:
	GameManager.set_phase(_old_phase)
	HitStop.reset()


func _world() -> Node2D:
	return add_child_autofree(Node2D.new()) as Node2D


func _player(world: Node2D, at: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = at
	LightQuery.set_player_radius(player, 300.0)
	return player


## Every player of the list joins; Flint is driven by hand (no engine frames in between).
func _group(players: Array[Player]) -> FlintCompanion:
	var flint: FlintCompanion = null
	for player in players:
		flint = FlintCompanion.attach_to(player)
	flint.set_process(false)
	flint.snap()
	return flint


func _run(flint: FlintCompanion, frames: int) -> void:
	for i in frames:
		flint._process(DT)


func _picture_clear(flint: FlintCompanion, player: Player) -> bool:
	return not FlintFollow.overlaps_player(flint.get_follow_position() - player.global_position)


# --- FlintGroup (pure) ---

func test_players_close_together_are_one_part_far_ones_another() -> void:
	var positions := PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(700, 0), Vector2(2000, 0)])
	var parts := FlintGroup.parts(positions)
	assert_eq(parts.size(), 2, "0-1-2 chain within the link, 3 far away")
	assert_eq(parts[0], PackedInt32Array([0, 1, 2]))
	assert_eq(parts[1], PackedInt32Array([3]))
	assert_eq(FlintGroup.main_part(positions), PackedInt32Array([0, 1, 2]), "the bigger part")


func test_a_tie_goes_to_the_hosts_part() -> void:
	var positions := PackedVector2Array([Vector2(0, 0), Vector2(2000, 0)])
	assert_eq(FlintGroup.main_part(positions, 0), PackedInt32Array([0]))
	assert_eq(FlintGroup.main_part(positions, 1), PackedInt32Array([1]), "D-225 §2: with the host")


func test_the_rearmost_is_against_the_walking_direction() -> void:
	var positions := PackedVector2Array([Vector2(100, 0), Vector2(0, 0), Vector2(60, 40)])
	var walking_right := PackedVector2Array([Vector2(150, 0), Vector2(150, 0), Vector2(150, 0)])
	var part := PackedInt32Array([0, 1, 2])
	assert_eq(FlintGroup.rearmost(positions, walking_right, part), 1, "walking right: the leftmost is behind")
	var walking_left := PackedVector2Array([Vector2(-150, 0), Vector2(-150, 0), Vector2(-150, 0)])
	assert_eq(FlintGroup.rearmost(positions, walking_left, part), 0)
	var resting := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var spread := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(300, 0)])
	assert_eq(FlintGroup.rearmost(spread, resting, part), 2, "at rest: the one furthest from the middle")


func test_the_group_point_is_the_middle_pulled_to_the_rear() -> void:
	var one := PackedVector2Array([Vector2(50, 70)])
	assert_eq(FlintGroup.target(one, PackedVector2Array([Vector2(100, 0)])), Vector2(50, 70), "alone: the player himself")
	var two := PackedVector2Array([Vector2(200, 0), Vector2(0, 0)])
	var walking := PackedVector2Array([Vector2(150, 0), Vector2(150, 0)])
	var point := FlintGroup.target(two, walking)
	assert_almost_eq(point.x, 100.0 - 100.0 * FlintGroup.REAR_PULL, 0.01, "pulled towards the one behind")
	assert_almost_eq(point.y, 0.0, 0.01)
	assert_eq(FlintGroup.target(PackedVector2Array(), PackedVector2Array()), Vector2.INF)
	var split := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(3000, 0)])
	var still := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	assert_lt(FlintGroup.target(split, still).x, 100.0, "with the bigger part, not in between")


func test_the_group_point_glides_and_jumps_when_far() -> void:
	var step := FlintGroup.glide(Vector2.ZERO, Vector2(300, 0), DT)
	assert_gt(step.x, 0.0)
	assert_lte(step.x, FlintGroup.POINT_MAX_SPEED * DT + 0.001, "never faster than the cap")
	assert_eq(FlintGroup.glide(Vector2.ZERO, Vector2(FlintGroup.JUMP_DISTANCE + 10.0, 0), DT), Vector2(FlintGroup.JUMP_DISTANCE + 10.0, 0),
			"teleport: there at once")


# --- One Flint for the group ---

func test_two_players_share_one_flint_between_them() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(560, 300))
	var flint := _group([a, b] as Array[Player])
	_run(flint, 120)
	assert_eq(FlintCompanion.of(a), FlintCompanion.of(b), "D-225 §1: one Flint")
	var middle := (a.global_position + b.global_position) * 0.5
	assert_lt(flint.get_anchor().distance_to(middle), 60.0, "the group point is between them")
	assert_lt(flint.get_follow_position().distance_to(middle), FlintFollow.LEASH_DISTANCE + 60.0, "Flint hovers with the group")
	assert_true(_picture_clear(flint, a) and _picture_clear(flint, b), "never on anybody's picture")


func test_flint_stays_with_the_bigger_part_or_the_host() -> void:
	var world := _world()
	var host := _player(world, Vector2(400, 300))
	var mate := _player(world, Vector2(2400, 300))
	var flint := _group([host, mate] as Array[Player])
	_run(flint, 90)
	assert_lt(flint.get_follow_position().distance_to(host.global_position), 120.0, "a tie: with the host's player")
	assert_eq(flint.player, host, "the host's player leads")
	var third := _player(world, Vector2(2460, 300))
	FlintCompanion.attach_to(third)
	_run(flint, 120)
	assert_lt(flint.get_follow_position().distance_to(mate.global_position), 160.0, "two over there: with the bigger part")
	assert_ne(flint.player, host)


func test_downed_members_do_not_hold_him_back() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(700, 300))
	var flint := _group([a, b] as Array[Player])
	b.health.take_damage(999.0)
	HitStop.reset()
	_run(flint, 180)
	assert_lt(flint.get_anchor().distance_to(a.global_position), 4.0, "the point is the standing player")
	assert_eq(flint.get_mood(), FlintMood.Mood.SAD, "a friend is down")


func test_walking_group_keeps_him_clear_and_trailing() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(400, 340))
	var flint := _group([a, b] as Array[Player])
	for frame in 240:
		a.global_position += Vector2(2.5, 0)
		b.global_position += Vector2(2.5, 0)
		a.velocity = Vector2(150, 0)
		b.velocity = Vector2(150, 0)
		flint._process(DT)
		assert_true(_picture_clear(flint, a) and _picture_clear(flint, b), "frame %d: clear of both" % frame)
	assert_lt(flint.get_follow_position().x, a.global_position.x + 8.0, "he trails, not leads")
	assert_lt(flint.get_follow_position().distance_to(flint.get_anchor()), FlintFollow.LEASH_DISTANCE + 30.0)


func test_a_player_who_leaves_leaves_the_group() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(500, 300))
	var flint := _group([a, b] as Array[Player])
	b.free()
	_run(flint, 2)
	assert_eq(flint.get_members(), [a] as Array[Player])
	assert_false(flint.is_group(), "alone again: the solo Flint")
	_run(flint, 120)
	assert_eq(flint.get_anchor(), a.global_position)


func test_alone_the_group_point_is_the_player() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var flint := _group([a] as Array[Player])
	a.global_position += Vector2(30, 0)
	flint._process(DT)
	assert_eq(flint.get_anchor(), a.global_position, "solo: no gliding point, Flint as before")
	assert_eq(flint.get_look_owner(), a)


func test_the_look_comes_from_the_host() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(500, 300))
	var flint := _group([a, b] as Array[Player])
	assert_eq(flint.get_look_owner(), a, "by default the first (primary) player")
	flint.host_player = b
	assert_eq(flint.get_look_owner(), b, "D-225 §6: the host's player")


func test_two_local_guides_hold_the_excursion_together() -> void:
	var world := _world()
	var flint := _group([_player(world, Vector2(400, 300))] as Array[Player])
	flint.set_excursion(Vector2(100, -80), 2.0, 0.5, 11)
	flint.set_excursion(Vector2(100, -80), 2.0, 0.5, 22)
	flint.clear_excursion(11)
	assert_true(flint.is_on_excursion(), "the other guide still flies him")
	flint.clear_excursion(22)
	assert_false(flint.is_on_excursion(), "lands with the last one")


func test_excursion_flies_the_one_flint_of_the_group() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var b := _player(world, Vector2(500, 300))
	var flint := _group([a, b] as Array[Player])
	var excursion_a := FlintExcursion.new(FlintCompanion.of(a))
	var excursion_b := FlintExcursion.new(FlintCompanion.of(b))
	excursion_a.out(0.5)
	excursion_b.out(0.5)
	excursion_a.land()
	assert_true(flint.is_on_excursion(), "b's guide still talks")
	excursion_b.land()
	assert_false(flint.is_on_excursion())


# --- Client: the host moves him (D-225 §3) ---

func test_a_client_draws_flint_at_the_hosts_spot() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var flint := _group([a] as Array[Player])
	flint.set_net_driven(true)
	var spot := a.global_position + Vector2(-50, 30)
	flint.apply_net_follow(spot)
	_run(flint, 60)
	assert_almost_eq(flint.get_follow_position(), spot, Vector2.ONE, "glides to the host's spot")
	assert_almost_eq(flint.get_light_center(), spot + (flint.get_light_center() - flint.get_follow_position()), Vector2.ONE)
	var far := spot + Vector2(900, 0)
	flint.apply_net_follow(far)
	assert_eq(flint.get_follow_position(), far, "a jump: there at once")
	flint.set_net_driven(false)
	_run(flint, 120)
	assert_lt(flint.get_follow_position().distance_to(a.global_position), 120.0, "deciding again himself")


func test_net_flint_hangs_under_the_worlds_flint() -> void:
	var world := _world()
	var a := _player(world, Vector2(400, 300))
	var flint := _group([a] as Array[Player])
	var net := NetFlint.attach(flint)
	assert_eq(NetFlint.attach(flint), net, "idempotent")
	assert_eq(net.get_parent(), flint)
	assert_eq(String(world.get_path_to(net)), "Flint/NetFlint", "the same path on every machine")
	assert_true(net.is_host(), "without a session this machine decides")
	net._process(DT)
	assert_false(flint.net_driven, "the host draws his own decision")
	assert_eq(net.sent_count, 0, "nothing to send without a session")
	net.flint_spot(1.0, 2.0)
	assert_eq(net.received_count, 0, "the host takes no spot from anybody")
