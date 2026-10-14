extends GutTest
## Enemies and abysses (A4, D-086): the pit layer blocks them like a wall; only a strong knockback
## (> 250 px/s) pushes normal enemies and elites in. They die (a kill, gold at the rim); champions,
## golems and bosses never fall. Gold and hearts never stay over an abyss.

const RING_HOLE_S: PackedScene = preload("res://dungeon/rooms/combat/chasm_ring_hole_s.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const GOLD_SCENE: PackedScene = preload("res://economy/gold_pickup.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const SLIME: EnemyData = preload("res://enemies/data/slime.tres")
const GOLEM: EnemyData = preload("res://enemies/data/golem.tres")
## Ring hole S: the abyss covers rows 3-5 of columns 4-10 (bridge and platform in row 4); the ring
## floor south of it starts at row 6.
const RIM_TILE := Vector2i(8, 6)

var _old_save_path: String
var _room: RoomController


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_fall_enemy_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 11
	_room = RING_HOLE_S.instantiate() as RoomController
	_room.setup(8, RoomSequence.RoomType.COMBAT, -1, false, context)
	add_child_autofree(_room)
	await wait_physics_frames(2)


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(2)


## An enemy standing on the rim, its body 16 px south of the abyss edge.
func _enemy(data: EnemyData, champion := false) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = data
	enemy.apply_scaling(8, champion)
	enemy.gold_drop = 3
	_room.enemy_container.add_child(enemy)
	var rim_top := RoomTiles.tile_to_local(RIM_TILE).y
	enemy.global_position = _room.to_global(Vector2(RoomTiles.tile_center(RIM_TILE).x, rim_top + 16.0))
	return enemy


func _push(enemy: Enemy, speed: float) -> void:
	var hit := DamageData.new()
	hit.amount = 0.5
	hit.knockback = Vector2.UP * speed
	hit.hit_id = DamageData.next_hit_id()
	enemy.hurtbox.receive_hit(hit)


func _gold_pickups() -> Array[GoldPickup]:
	var result: Array[GoldPickup] = []
	for child in _room.enemy_container.get_children():
		if child is GoldPickup:
			result.append(child)
	return result


func test_strong_knockback_pushes_an_enemy_into_the_abyss() -> void:
	var enemy := _enemy(SKELETON)
	var kills: Array = []
	var on_damaged := func(target: Enemy, result: DamageResult, damage: DamageData) -> void:
		if result.killed:
			kills.append([target, damage.tags.duplicate()])
	EventBus.enemy_damaged.connect(on_damaged)
	var fell: Array = []
	enemy.fell_into_pit.connect(func(e: Enemy) -> void: fell.append(e))
	await wait_physics_frames(1)
	_push(enemy, ChasmRules.ENEMY_FALL_MIN_KNOCKBACK + 50.0)
	assert_true(enemy.is_pit_unbound(), "the abyss lies on the push's way")
	await wait_physics_frames(30)
	EventBus.enemy_damaged.disconnect(on_damaged)
	assert_eq(fell.size(), 1, "fell")
	assert_true(not is_instance_valid(enemy) or enemy.is_dead(), "dead")
	assert_eq(kills.size(), 1, "counts as a kill")
	assert_true((kills[0][1] as Array).has(ChasmRules.DAMAGE_TAG))
	await wait_physics_frames(2)
	var gold := _gold_pickups()
	assert_eq(gold.size(), 1, "gold dropped")
	if not gold.is_empty():
		var tile := RoomTiles.local_to_tile(_room.to_local(gold[0].global_position))
		assert_false(_room.tiles.is_pit(tile), "gold at the rim, not in the abyss (%s)" % tile)


func test_weak_knockback_stops_at_the_rim() -> void:
	var enemy := _enemy(SLIME)
	await wait_physics_frames(1)
	_push(enemy, ChasmRules.ENEMY_FALL_MIN_KNOCKBACK - 20.0)
	assert_false(enemy.is_pit_unbound())
	await wait_physics_frames(30)
	assert_false(enemy.is_dead(), "the abyss blocks like a wall")
	assert_false(enemy.has_fallen_into_pit())
	assert_false(_room.tiles.is_pit_at_local(_room.to_local(enemy.global_position)), "still on the rim")


func test_champions_and_golems_never_fall() -> void:
	var golem := _enemy(GOLEM)
	await wait_physics_frames(1)
	# Golems resist knockback anyway; even a huge push leaves them standing.
	_push(golem, 5000.0)
	assert_false(golem.is_pit_unbound())
	await wait_physics_frames(30)
	assert_false(golem.is_dead())
	golem.queue_free()
	var champion := _enemy(SKELETON, true)
	assert_true(champion.is_champion())
	await wait_physics_frames(1)
	_push(champion, 600.0)
	assert_false(champion.is_pit_unbound(), "champions never")
	await wait_physics_frames(30)
	assert_false(champion.is_dead())
	assert_false(champion.can_fall_into_pit())


func test_no_push_without_an_abyss_on_the_way() -> void:
	var enemy := _enemy(SKELETON)
	await wait_physics_frames(1)
	var hit := DamageData.new()
	hit.amount = 0.5
	hit.knockback = Vector2.DOWN * 400.0
	hit.hit_id = DamageData.next_hit_id()
	enemy.hurtbox.receive_hit(hit)
	assert_false(enemy.is_pit_unbound(), "away from the abyss nothing changes")
	assert_eq(enemy.collision_mask & PhysicsLayers.PIT, PhysicsLayers.PIT)


func test_gold_and_hearts_never_stay_in_the_abyss() -> void:
	var pit: Vector2i = _room.tiles.get_pit_tiles()[0]
	for kind: GoldPickup.Kind in [GoldPickup.Kind.GOLD, GoldPickup.Kind.HEART]:
		var pickup := GOLD_SCENE.instantiate() as GoldPickup
		pickup.kind = kind
		pickup.position = _room.enemy_container.to_local(_room.to_global(RoomTiles.tile_center(pit)))
		_room.enemy_container.add_child(pickup)
		await wait_physics_frames(20)
		var tile := RoomTiles.local_to_tile(_room.to_local(pickup.global_position))
		assert_false(_room.tiles.is_pit(tile), "%s moved to solid floor (%s)" % [GoldPickup.Kind.keys()[kind], tile])
	# Popping towards the abyss stops at the rim.
	var rim := GOLD_SCENE.instantiate() as GoldPickup
	rim.position = _room.enemy_container.to_local(_room.to_global(Vector2(RoomTiles.tile_center(RIM_TILE).x, RoomTiles.tile_to_local(RIM_TILE).y + 4.0)))
	_room.enemy_container.add_child(rim)
	rim._pop_velocity = Vector2.UP * 120.0
	await wait_physics_frames(20)
	assert_false(_room.tiles.is_pit(RoomTiles.local_to_tile(_room.to_local(rim.global_position))), "stopped at the rim")
