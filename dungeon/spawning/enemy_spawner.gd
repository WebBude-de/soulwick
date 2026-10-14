class_name EnemySpawner
extends Node
## Draws one encounter per room exactly once: count, distinct markers and enemy types (D-008 .. D-010).
## Extensions (D-069): from room 6 a spawn may be replaced by a shadow or bomber and may become an
## elite. Bosses depend on the boss room (D-065). Does not know the room order itself.

const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const REQUIRED_SPAWN_POINTS := 5
const EXTENDED_FROM_ROOM := 6
const EXTRA_TYPE_CHANCE := 0.2
const ELITE_BASE_CHANCE := 0.12
const ELITE_CHANCE_PER_BLOCK := 0.02
const MAX_ELITE_CHANCE := 0.5
const ELITE_GOLD_MULTIPLIER := 2

## Standard enemy types and their independent per-spawn weights (Slime 50 %, Skeleton 35 %, Archer 15 %).
@export var enemy_types: Array[EnemyData] = []
@export var spawn_weights: Array[float] = [0.5, 0.35, 0.15]
## Shadow and bomber, chosen with equal weight when a spawn is replaced.
@export var extra_types: Array[EnemyData] = []
## Bosses in their cycle order (room 15, 30, 45, 60, then again with a higher tier).
@export var bosses: Array[EnemyData] = []
## Minion for champions and high-tier bosses without own summons.
@export var escort_minion: EnemyData
## Enemy tables per biome in RoomSequence.Biome order (D-075). Falls back to enemy_types.
@export var biomes: Array[BiomeData] = []


## count distinct marker indices out of marker_count, drawn without replacement.
static func pick_markers(marker_count: int, count: int, rng: RandomNumberGenerator) -> Array[int]:
	var pool: Array[int] = []
	for i in marker_count:
		pool.append(i)
	var picked: Array[int] = []
	while picked.size() < count and not pool.is_empty():
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked


static func pick_weighted(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1


static func get_elite_chance(room_index: int) -> float:
	if room_index < EXTENDED_FROM_ROOM:
		return 0.0
	return minf(MAX_ELITE_CHANCE, ELITE_BASE_CHANCE + ELITE_CHANCE_PER_BLOCK * EnemyScaling.get_block(room_index))


static func roll_elite(room_index: int, rng: RandomNumberGenerator) -> Enemy.Elite:
	if rng.randf() >= get_elite_chance(room_index):
		return Enemy.Elite.NONE
	return [Enemy.Elite.SWIFT, Enemy.Elite.ARMORED, Enemy.Elite.VOLATILE][rng.randi_range(0, 2)]


## Boss for a boss room: the bosses take turns endlessly (D-065, D-076).
func get_boss_for_room(room_index: int) -> EnemyData:
	if bosses.is_empty():
		return null
	return bosses[(RoomSequence.get_boss_number(room_index) - 1) % bosses.size()]


## Spawns the encounter of a combat, miniboss or boss room. Returns no enemies on invalid input,
## which keeps the room closed instead of completing it by mistake.
func spawn_encounter(room_index: int, room_type: RoomSequence.RoomType, markers: Array[Marker2D], center: Vector2, container: Node2D, context: DungeonContext, arena := Rect2()) -> Array[Enemy]:
	var spawned: Array[Enemy] = []
	if enemy_types.is_empty() or enemy_types.size() != spawn_weights.size():
		push_error("EnemySpawner: enemy types and weights are not configured.")
		return spawned
	var rng := context.rng
	match room_type:
		RoomSequence.RoomType.COMBAT, RoomSequence.RoomType.COMBAT_UPGRADE:
			if markers.size() != REQUIRED_SPAWN_POINTS:
				push_error("Room %d: expected %d spawn markers, found %d." % [room_index, REQUIRED_SPAWN_POINTS, markers.size()])
				return spawned
			var range_limits := RoomSequence.get_enemy_count_range(room_index)
			var count := rng.randi_range(range_limits.x, range_limits.y)
			for marker_index in pick_markers(markers.size(), count, rng):
				var data := _pick_type(room_index, rng)
				var enemy := _create(data, markers[marker_index].position, room_index, false, context, arena)
				var elite := roll_elite(room_index, rng)
				if elite != Enemy.Elite.NONE:
					enemy.make_elite(elite)
					enemy.gold_drop *= ELITE_GOLD_MULTIPLIER
				spawned.append(enemy)
		RoomSequence.RoomType.MINIBOSS:
			# Champion: a random standard enemy with miniboss factor, an elite trait, summons
			# and an escort that grows with depth (D-077).
			# The champion gets a type-specific special and a second phase (ChampionRules, BossRules);
			# in deeper cycles it uses the boss tier as well.
			var data := _pick_type(room_index, rng)
			var champion := _create(data, center, room_index, true, context, arena)
			champion.make_elite([Enemy.Elite.SWIFT, Enemy.Elite.ARMORED, Enemy.Elite.VOLATILE][rng.randi_range(0, 2)])
			champion.set_boss_tier(RoomSequence.get_boss_tier(room_index))
			champion.extra_summon_data = escort_minion if data.summon_data == null else null
			spawned.append(champion)
			var escorts := 1 + floori(EnemyScaling.get_block(room_index) / 3.0)
			if markers.size() == REQUIRED_SPAWN_POINTS:
				for marker_index in pick_markers(markers.size(), mini(escorts, REQUIRED_SPAWN_POINTS), rng):
					spawned.append(_create(_pick_type(room_index, rng), markers[marker_index].position, room_index, false, context, arena))
		RoomSequence.RoomType.BOSS:
			var boss := get_boss_for_room(room_index)
			if boss == null:
				push_error("EnemySpawner: no boss configured.")
				return spawned
			var boss_enemy := _create(boss, center, room_index, false, context, arena)
			var tier := RoomSequence.get_boss_tier(room_index)
			boss_enemy.set_boss_tier(tier)
			if tier >= 2:
				boss_enemy.extra_summon_data = escort_minion
			spawned.append(boss_enemy)
	for enemy in spawned:
		container.add_child(enemy)
	return spawned


func get_biome(room_index: int) -> BiomeData:
	if biomes.is_empty():
		return null
	return biomes[RoomSequence.get_biome(room_index) % biomes.size()]


func _pick_type(room_index: int, rng: RandomNumberGenerator) -> EnemyData:
	var biome := get_biome(room_index)
	if biome != null:
		var table := biome.get_table(room_index)
		var types: Array[EnemyData] = table[0]
		if not types.is_empty():
			var type_weights: Array[float] = table[1]
			return types[pick_weighted(type_weights, rng)]
	if room_index >= EXTENDED_FROM_ROOM and not extra_types.is_empty() and rng.randf() < EXTRA_TYPE_CHANCE:
		return extra_types[rng.randi_range(0, extra_types.size() - 1)]
	return enemy_types[pick_weighted(spawn_weights, rng)]


func _create(data: EnemyData, local_position: Vector2, room_index: int, miniboss: bool, context: DungeonContext, arena: Rect2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = data
	enemy.position = local_position
	enemy.arena = arena
	enemy.apply_scaling(room_index, miniboss)
	if context.economy != null:
		# Village "Goldgier" bonus on top of the pure economy value (D-078).
		enemy.gold_drop = roundi(context.economy.get_gold_drop(data, room_index, miniboss) * MetaProgression.get_gold_multiplier())
	return enemy
