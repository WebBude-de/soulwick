extends GutTest
## FS7c ("Jagd zu leicht", D-213): the crowned one starts in the middle part of both hunt halls, on
## the far side of the gallery from his escape hole (not in the bay at the hole, where he was cornered
## at once: measured 2.8 s in the column hall before), with free floor around to zigzag, and runs at
## HuntRules.FLEE_SPEED_FACTOR. A plain chaser (the player's walking speed and his dash whenever it is
## ready, no cutting off, the guards gone) still reaches him before the hole takes him: the hunt stays
## winnable, but not at once (MIN_CHASE).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PLANS: Array[String] = [
	"res://dungeon/rooms/combat/jagd_saeulenhalle_crypt.tscn",
	"res://dungeon/rooms/combat/jagd_l_slime_grotto.tscn",
]
## Close enough for a sword swing (px, feet to his body).
const REACH := 44.0
## The chaser has the countdown plus this long (s); the hole takes him at CATCH_TIME + STUCK_GRACE
## at the latest.
const GIVE_UP := HuntRules.CATCH_TIME + HuntRules.STUCK_GRACE + 1.0
const ROOM_INDEX := 22
## The chaser dashes when he is this close (px) and the dash is ready.
const DASH_FROM := 200.0
## He is not reached sooner than this (s fleeing).
const MIN_CHASE := 3.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_hunt_chase_save.cfg"


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


func _room(path: String) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.room_kind = RoomSequence.RoomKind.NORMAL
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 41
	room.setup(ROOM_INDEX, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(room)
	return room


func _hunt(room: RoomController) -> HuntMode:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"hunt"), rng), &"hunt")
	return CombatVariant.of(room) as HuntMode


func test_crowned_one_starts_in_the_middle_of_the_hall() -> void:
	for path in PLANS:
		var room := _room(path)
		var mode := _hunt(room)
		var crowned_tile := mode.get_marker_tiles(&"crowned")[0]
		var hole_tile := mode.get_marker_tiles(&"escape_hole")[0]
		var width := room.tiles.room_size.x
		assert_between(crowned_tile.x, roundi(width * 0.25), roundi(width * 0.75), "%s: in the middle part of the hall, not in a corner" % path)
		assert_gte(Vector2(hole_tile - crowned_tile).length(), HuntRules.HOLE_MIN_TILES * 1.5, "%s: across the hall from his hole" % path)
		# Free floor around him to zigzag (BountyFlight): not cornered from the start.
		var near := 0
		for point in mode._evade_points():
			var distance := Vector2(RoomTiles.local_to_tile(room.to_local(point)) - crowned_tile).length()
			if distance >= 1.0 and distance <= HuntRules.EVADE_RANGE_TILES:
				near += 1
		assert_gte(near, 4, "%s: spots to run to around his start" % path)


func test_plain_chaser_reaches_him_before_the_hole_takes_him() -> void:
	for path in PLANS:
		var result := await _chase(path)
		gut.p("%s: reached after %.1f s fleeing (escaped %s, closest %.0f px)" % [path.get_file(), result["time"], result["escaped"], result["closest"]])
		assert_false(result["escaped"], "%s: a player walking after him reaches him" % path)
		assert_gt(float(result["time"]), MIN_CHASE, "%s: not at once" % path)


## Chases the crowned one of a plan from the way in once the fight runs (the chaser stands still during
## the intro), with the player's walking speed and dash. {"time": seconds he fled until reached (or
## the test clock when he escaped), "escaped": bool, "closest": px}
func _chase(path: String) -> Dictionary:
	var room := _room(path)
	var mode := _hunt(room)
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	room.context.player = player
	player.health.reset(50.0)
	player.global_position = room.to_global(room.get_player_start()) - Player.FEET_OFFSET
	await wait_physics_frames(2)
	room.activate()
	for guard in mode.guards:
		guard.health.take_damage(INF)
	var flight := mode.flight
	var crowned := mode.crowned
	var closest := INF
	var clock := 0.0
	var dash_ready_at := 0.0
	var dash_until := -1.0
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	while clock < GIVE_UP + 6.0:
		# One physics frame each (GUT's wait_physics_frames(1) lets two pass).
		await get_tree().physics_frame
		clock += step
		if not is_instance_valid(crowned) or flight.is_escaped():
			return {"time": clock, "escaped": true, "closest": closest}
		var feet := player.get_feet_position()
		var distance := feet.distance_to(crowned.global_position)
		closest = minf(closest, distance)
		if crowned.is_in_intro() and not flight.is_fleeing():
			continue  # the chaser waits at the way in until the fight runs
		if flight.is_fleeing() and distance <= REACH:
			return {"time": flight.time_fleeing, "escaped": false, "closest": closest}
		if flight.is_fleeing() and clock >= dash_ready_at and distance < DASH_FROM:
			dash_until = clock + player.dash_duration
			dash_ready_at = clock + player.dash_cooldown
		var speed := player.dash_speed if clock < dash_until else player.move_speed
		_walk_towards(room, player, crowned.global_position, speed * step)
	return {"time": flight.time_fleeing, "escaped": true, "closest": closest}


## One step of length towards goal along the shortest way over the ground floor (4-neighbour BFS
## over the room's walkable tiles without the gallery; the chaser does not climb), sliding along walls
## like the player's own movement.
func _walk_towards(room: RoomController, player: Player, goal: Vector2, length: float) -> void:
	var feet := player.get_feet_position()
	var from := RoomTiles.local_to_tile(room.to_local(feet))
	var to := RoomTiles.local_to_tile(room.to_local(goal))
	var target := goal
	if from != to:
		var next := _next_tile(room, from, to)
		if next != from:
			target = room.to_global(RoomTiles.tile_center(next))
	var direction := (target - feet).normalized()
	player.velocity = direction * length * float(Engine.physics_ticks_per_second)
	player.move_and_slide()
	player.velocity = Vector2.ZERO


## First tile after from on a shortest ground way to to (from itself without a way).
func _next_tile(room: RoomController, from: Vector2i, to: Vector2i) -> Vector2i:
	var ground := room.tiles.get_walkable_tiles()
	for tile in room.tiles.plateau_tiles + room.tiles.stair_tiles:
		ground.erase(tile)
	ground[from] = true
	ground[to] = true
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		if tile == to:
			break
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var near: Vector2i = tile + step
			if ground.has(near) and not came.has(near):
				came[near] = tile
				queue.append(near)
	if not came.has(to):
		return from
	var tile := to
	while came[tile] != from:
		tile = came[tile]
	return tile
