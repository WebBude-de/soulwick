extends GutTest
## Champion crystal as a chance (KE9b, D-224, KONZEPT §5.3): a beaten champion leaves
## CRYSTALS_PER_CHAMPION with CHAMPION_CRYSTAL_CHANCE, rolled from the run seed (the same for the same
## run, never from the room stream); in a group game only the host decides, a client books nothing.

const ROLLS := 4000
## Allowed distance of the measured share from the chance over ROLLS rolls (about 4 standard deviations).
const TOLERANCE := 0.03


class FakeNet:
	extends Node
	var is_host := false


var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_champion_crystal_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _manager(run_seed: int, net: Node = null) -> DungeonManager:
	var manager := DungeonManager.new()
	manager._run_seed = run_seed
	manager.net = net
	return manager


func test_the_chance_holds_over_many_seeds() -> void:
	var hits := 0
	for run_seed in ROLLS:
		var crystals := DungeonManager.roll_champion_crystals(run_seed * 7919 + 13, 5)
		assert_true(crystals == 0 or crystals == DungeonManager.CRYSTALS_PER_CHAMPION, "0 or the champion's crystals")
		if crystals > 0:
			hits += 1
	var share := hits / float(ROLLS)
	assert_almost_eq(share, DungeonManager.CHAMPION_CRYSTAL_CHANCE, TOLERANCE, "share of champions with a crystal")


func test_the_chance_holds_over_the_rooms_of_one_run() -> void:
	var hits := 0
	for room_index in ROLLS:
		if DungeonManager.roll_champion_crystals(424242, room_index + 1) > 0:
			hits += 1
	assert_almost_eq(hits / float(ROLLS), DungeonManager.CHAMPION_CRYSTAL_CHANCE, TOLERANCE)


func test_numbers_are_the_concept_ones() -> void:
	assert_eq(DungeonManager.CRYSTALS_PER_CHAMPION, 1, "one crystal (KONZEPT §5.3)")
	assert_eq(DungeonManager.CHAMPION_CRYSTAL_CHANCE, 0.3, "30 % (D-224, TESTWERT)")


func test_the_same_run_rolls_the_same() -> void:
	for run_seed in [1, 77, 123456789]:
		for room_index in [5, 10, 25]:
			assert_eq(DungeonManager.roll_champion_crystals(run_seed, room_index),
					DungeonManager.roll_champion_crystals(run_seed, room_index), "seed %d room %d" % [run_seed, room_index])


func test_two_champions_of_one_room_roll_on_their_own() -> void:
	var differ := 0
	for run_seed in 200:
		if DungeonManager.roll_champion_crystals(run_seed, 10, 0) != DungeonManager.roll_champion_crystals(run_seed, 10, 1):
			differ += 1
	assert_gt(differ, 0, "the second champion is not a copy of the first")


func test_the_roll_does_not_touch_the_room_stream() -> void:
	var manager := _manager(99)
	manager.context.rng = RandomNumberGenerator.new()
	manager.context.rng.seed = 99
	var state := manager.context.rng.state
	for room_index in 50:
		manager.get_champion_crystals(room_index)
	assert_eq(manager.context.rng.state, state, "context.rng is left alone, the rooms of the seed stay the same")
	manager.free()


func test_solo_and_host_decide() -> void:
	var host_net := FakeNet.new()
	host_net.is_host = true
	for run_seed in 300:
		var expected := DungeonManager.roll_champion_crystals(run_seed, 5)
		var solo := _manager(run_seed)
		var host := _manager(run_seed, host_net)
		assert_eq(solo.get_champion_crystals(5), expected, "solo: the roll")
		assert_eq(host.get_champion_crystals(5), expected, "host: the roll")
		solo.free()
		host.free()
	host_net.free()


func test_a_client_books_nothing() -> void:
	var client_net := FakeNet.new()
	var hits := 0
	for run_seed in 300:
		var client := _manager(run_seed, client_net)
		hits += client.get_champion_crystals(5)
		client.free()
	assert_eq(hits, 0, "the client takes the crystals from the host's pot (NetDungeon), it never rolls")
	client_net.free()
