extends GutTest
## Lantern bearer (A9, KONZEPT_RAEUME §4.4): the lantern lies inside the entrance, the socket stands
## at the exit, the room stays shut until the lantern is in. Carrying is state at the player
## (slower, no attacks, dash stays); E takes and puts down; put down at the socket = set in. A
## player in time -> bonus chest; after LANTERN_TIME it comes home by itself without bonus.

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_lantern_save.cfg"


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


func _room(room_index := 8) -> RoomController:
	var room := HALL.instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(room_index, RoomSequence.RoomType.COMBAT, -1, false, context)
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	var group := EncounterGroup.new()
	group.allow_elites = false
	group.count_range = Vector2i(4, 4)
	spawner.encounter_group = group
	add_child_autofree(room)
	return room


func _attach(room: RoomController, seed_value := 5) -> LanternVariant:
	var pick := VariantTable.Pick.new()
	pick.variant_id = VariantRules.LANTERN
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	assert_eq(RoomVariants.attach(room, pick, rng), VariantRules.LANTERN)
	return CombatVariant.of(room) as LanternVariant


func _player(room: RoomController, tile := Vector2i(7, 7)) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	if room != null:
		room.context.player = player
		player.global_position = room.to_global(RoomTiles.tile_center(tile)) - Player.FEET_OFFSET
	return player


func _kill_all(room: RoomController) -> void:
	for child in room.enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_dead():
			enemy.health.take_damage(INF)


# --- Rules ---

func test_lantern_numbers() -> void:
	assert_true(LightVariantRules.lantern_bonus_open(0.0))
	assert_false(LightVariantRules.lantern_bonus_open(LightVariantRules.LANTERN_TIME))
	assert_false(LightVariantRules.lantern_returns(LightVariantRules.LANTERN_TIME - 0.1, false))
	assert_true(LightVariantRules.lantern_returns(LightVariantRules.LANTERN_TIME, false))
	assert_false(LightVariantRules.lantern_returns(99.0, true), "home already")
	assert_true(LightVariantRules.can_insert(LightVariantRules.SOCKET_RADIUS))
	assert_false(LightVariantRules.can_insert(LightVariantRules.SOCKET_RADIUS + 1.0))
	assert_eq(LightVariantRules.lantern_wave_size(1), LightVariantRules.LANTERN_WAVE_MIN)
	assert_eq(LightVariantRules.lantern_wave_size(10), 6)
	assert_true(LightVariantRules.lantern_holds_room(true, false))
	assert_false(LightVariantRules.lantern_holds_room(true, true))
	assert_false(LightVariantRules.lantern_holds_room(false, false), "nothing held before the fight")
	assert_gt(LightVariantRules.LANTERN_CARRIED_RADIUS, LightVariantRules.LANTERN_LIGHT_RADIUS, "much more light in the hand")


func test_lantern_in_every_biome() -> void:
	var table := VariantTable.load_default()
	for biome in RoomSequence.Biome.values():
		assert_true(table.get_allowed(biome).has(VariantRules.LANTERN), "biome %d" % biome)


# --- Carrying: state at the player ---

func test_carrier_is_slower_cannot_attack_and_gets_it_all_back() -> void:
	var player := _player(null)
	var speed := player.move_speed
	var lantern := Node2D.new()
	add_child_autofree(lantern)
	LanternCarry.attach(player, lantern)
	assert_true(LanternCarry.is_carrying(player))
	assert_false(LanternCarry.can_attack(player), "the hook decision")
	assert_almost_eq(player.move_speed, speed * LightVariantRules.LANTERN_CARRY_SPEED_FACTOR, 0.01)
	assert_false(player.weapon_controller.handle_special_input, "no special while carrying")
	await wait_physics_frames(2)
	assert_false(player.weapon_controller.request_attack(), "no swing while carrying (fallback until the hook)")
	assert_true(player.can_dash(), "dash untouched")
	LanternCarry.detach(player)
	assert_false(LanternCarry.is_carrying(player))
	assert_true(LanternCarry.can_attack(player))
	assert_almost_eq(player.move_speed, speed, 0.01, "speed back")
	assert_true(player.weapon_controller.handle_special_input, "special back")


# --- The variant ---

func test_lantern_at_the_entrance_socket_at_the_exit() -> void:
	var room := _room()
	var variant := _attach(room)
	assert_not_null(variant.lantern)
	assert_not_null(variant.socket)
	var lantern_tile := RoomTiles.local_to_tile(variant.lantern.position)
	var socket_tile := RoomTiles.local_to_tile(variant.socket.position)
	var entrance := room.tiles.get_entrance_inside_tile()
	var exit := room.tiles.get_exit_inside_tile()
	assert_lt(Vector2(lantern_tile - entrance).length(), Vector2(lantern_tile - exit).length(), "lantern near the entrance")
	assert_lt(Vector2(socket_tile - exit).length(), Vector2(socket_tile - entrance).length(), "socket near the exit")
	assert_true(variant.lantern.get_light().counts_as_light, "its light holds stone guardians too")


func test_room_stays_shut_until_a_player_sets_the_lantern_in() -> void:
	var room := _room()
	var variant := _attach(room)
	var player := _player(room)
	room.activate()
	assert_true(variant.holds_completion())
	_kill_all(room)
	await wait_physics_frames(2)
	assert_false(variant.is_finished(), "all enemies down, but the exit waits for the light")
	# Take it with E: the wave out of the dark comes once.
	variant.lantern.get_interactable().interact(player)
	assert_true(variant.lantern.is_carried())
	assert_true(LanternCarry.is_carrying(player))
	assert_true(variant.is_wave_sent())
	assert_gt(room.get_alive_enemy_count(), 0, "enemies out of the dark")
	assert_eq(variant.lantern.get_light().radius, LightVariantRules.LANTERN_CARRIED_RADIUS)
	# Walk to the socket and put it down there.
	player.global_position = variant.socket.global_position + Vector2(20, 0)
	await wait_physics_frames(1)
	variant.lantern.get_interactable().interact(player)
	assert_true(variant.lantern.is_socketed(), "put down at the socket = set in")
	assert_false(LanternCarry.is_carrying(player), "hands free again")
	assert_true(variant.is_bonus_achieved(), "in time -> bonus")
	assert_false(variant.holds_completion())
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(variant.is_finished())
	assert_eq(variant.chests.size(), 1)


func test_put_down_elsewhere_lies_on_the_floor() -> void:
	var room := _room()
	var variant := _attach(room)
	var player := _player(room)
	room.activate()
	assert_true(variant.lantern.pick_up(player))
	await wait_physics_frames(1)
	assert_lt(variant.lantern.global_position.distance_to(player.global_position), 40.0, "follows the carrier")
	assert_true(variant.lantern.drop(player.get_feet_position()))
	assert_false(variant.lantern.is_socketed())
	assert_eq(variant.lantern.state, SoulLantern.State.LYING)
	assert_eq(variant.lantern.get_light().radius, LightVariantRules.LANTERN_LIGHT_RADIUS)
	assert_false(variant.lantern.pick_up(null))


func test_only_the_carrier_puts_it_down() -> void:
	var room := _room()
	var variant := _attach(room)
	var carrier := _player(room)
	var other := _player(room, Vector2i(8, 7))
	room.activate()
	variant.lantern.get_interactable().interact(carrier)
	variant.lantern.get_interactable().interact(other)
	assert_true(variant.lantern.is_carried())
	assert_eq(variant.lantern.carrier, carrier, "nobody snatches it")
	assert_false(variant.lantern.pick_up(other), "one lantern, one carrier")


func test_carrier_gone_drops_the_lantern() -> void:
	var room := _room()
	var variant := _attach(room)
	var carrier := _player(room)
	room.activate()
	variant.lantern.pick_up(carrier)
	var spot := variant.lantern.global_position
	carrier.free()
	await wait_physics_frames(2)
	assert_eq(variant.lantern.state, SoulLantern.State.LYING, "falls where it was")
	assert_almost_eq(variant.lantern.global_position.distance_to(spot), 0.0, 1.0)


func test_chasers_go_for_the_carrier() -> void:
	var room := _room()
	var variant := _attach(room)
	var carrier := _player(room)
	_player(room, Vector2i(3, 3))
	room.activate()
	variant.lantern.pick_up(carrier)
	var chasers := variant.get_chasers()
	assert_gt(chasers.size(), 0, "some enemies prefer the carrier (60 %)")
	for enemy in chasers:
		assert_eq(EnemyDecoy.get_decoy(enemy), carrier)
	variant.lantern.drop(carrier.get_feet_position())
	for enemy in chasers:
		assert_null(EnemyDecoy.get_decoy(enemy), "lantern down: back to the nearest player")


func test_after_the_time_the_lantern_comes_home_without_bonus() -> void:
	var room := _room()
	var variant := _attach(room)
	var player := _player(room)
	room.activate()
	variant.lantern.pick_up(player)
	variant.step(LightVariantRules.LANTERN_TIME + 1.0)
	assert_false(LanternCarry.is_carrying(player), "it leaves the carrier")
	assert_eq(variant.bonus, CombatVariant.Bonus.LOST)
	assert_true(variant.lantern.is_socketed(), "decided at once: home in the socket")
	assert_false(variant.holds_completion())
	await wait_seconds(SoulLantern.RETURN_TIME + 0.2)
	assert_true(variant.socket.lit, "seen floating home, then the socket glows")
	assert_false(variant.lantern.visible)
	_kill_all(room)
	await wait_physics_frames(2)
	assert_true(variant.is_finished(), "the room can always be finished")
	assert_eq(variant.chests.size(), 0, "no bonus chest")
