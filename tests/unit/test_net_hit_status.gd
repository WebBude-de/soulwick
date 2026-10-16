extends GutTest
## Co-op hits carry their statuses (D-148, version 0.9.1): the host sends a hit on a player with
## stun, blind and the slow of a turret orb (slow_factor, slow_duration); the client rebuilds the
## DamageData and its player gets the slow through Player._on_hit_received, like on the host.
## The upgrade round waits for a client whose choice appeared late (dialog queue), within a limit.
## No network: the RPC methods are called directly, sending is recorded. Uses a test save.

const TEST_SAVE_PATH := "user://test_net_hit_status.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


## NetDungeon without a session: _send records instead of sending, the players are given.
class FakeNet extends NetDungeon:
	var sent: Array = []
	var players: Dictionary = {}

	func _send(method: StringName, args: Array = []) -> void:
		sent.append([method, args])

	func _player_of(peer: int) -> Player:
		return players.get(peer) as Player


var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path


func _player() -> Player:
	return add_child_autofree(PLAYER_SCENE.instantiate()) as Player


func _net(host: bool) -> FakeNet:
	var net := FakeNet.new()
	net.is_host = host
	autofree(net)
	return net


func test_host_sends_the_slow_and_the_client_applies_it() -> void:
	var host_player := _player()
	var client_player := _player()
	await wait_physics_frames(1)
	var base := client_player.move_speed
	var host := _net(true)
	var client := _net(false)
	client.players[0] = client_player
	var damage := DamageData.new()
	damage.amount = 0.25
	damage.slow_factor = TurretRules.SLOW_FACTOR
	damage.slow_duration = TurretRules.SLOW_DURATION
	damage.blind_duration = 0.0
	var result := host_player.hurtbox.receive_hit(damage)
	assert_true(result.is_effective())
	assert_true(SlowStatus.is_slowed(host_player), "the host's own hit slows through Player._on_hit_received")
	host._on_player_hit_host(result, damage, host_player)
	assert_eq(host.sent.size(), 1)
	var method: StringName = host.sent[0][0]
	var args: Array = host.sent[0][1]
	assert_eq(method, &"player_hit")
	assert_true(args.has(TurretRules.SLOW_FACTOR) and args.has(TurretRules.SLOW_DURATION), "slow factor and duration are sent")
	# The client gets exactly these arguments (same order as the RPC).
	client.callv(method, args)
	assert_true(SlowStatus.is_slowed(client_player), "the client's copy of the hit slows")
	assert_almost_eq(client_player.move_speed, base * TurretRules.SLOW_FACTOR, 0.01)
	assert_almost_eq(SlowStatus.get_for(client_player).time_left, TurretRules.SLOW_DURATION, 0.05)


func test_a_hit_without_slow_does_not_slow_on_the_client() -> void:
	var client_player := _player()
	await wait_physics_frames(1)
	var client := _net(false)
	client.players[2] = client_player
	client.player_hit(2, 0.5, 0.0, 0.0, 0.0, 1.0, 0.0, client_player.health.get_health(), 0.0)
	assert_false(SlowStatus.is_slowed(client_player))
	# A blocked copy (nothing taken) carries no status either (D-017).
	client.player_hit(2, 0.0, 0.0, 0.0, 0.0, 0.5, 2.0, client_player.health.get_health(), 0.0)
	assert_false(SlowStatus.is_slowed(client_player), "no slow without an effective hit")


func test_host_waits_longer_for_a_choice_that_appeared_late() -> void:
	var host := _net(true)
	var start := 100000
	var normal := start + int((CoopRules.UPGRADE_TIMEOUT + NetDungeon.PICK_GRACE) * 1000.0)
	assert_eq(host._pick_deadline(4, start), normal, "without reports: time limit plus grace")
	# The client's choice waited in its dialog queue and appeared 10 s after the host had picked.
	host._pick_starts[4] = {2: start + 10000}
	assert_eq(host._pick_deadline(4, start), normal + 10000, "its full time from when it appeared")
	host._pick_starts[4] = {2: start + 600000}
	assert_eq(host._pick_deadline(4, start), start + int(NetDungeon.PICK_WAIT_MAX * 1000.0), "never longer than the limit")
	assert_eq(host._pick_deadline(5, start), normal, "other rounds are not affected")
