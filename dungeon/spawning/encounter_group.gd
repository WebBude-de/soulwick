class_name EncounterGroup
extends Resource
## Content rules for the normal enemies of one combat room, decided before anything spawns
## (A5 hook for A3 and D-084). A3 builds them as data: theme groups (mixed, ranged only, swarm)
## and the quiet room (few strong enemies, same total HP); the player count scales the number.
## Every field left at its default keeps the normal rules (biome table, D-074 counts).
## Hand it to EnemySpawner.encounter_group (or RoomController.set_encounter_group) before the
## encounter starts. Only normal combat rooms use it; champions and bosses ignore it.

## Name for logs and tests (e.g. &"ranged", &"swarm", &"quiet").
@export var id: StringName
## Only enemy types of the biome table with this attack kind (-1 = all, else EnemyData.AttackKind).
@export var attack_kind := -1
## Only enemy types carrying at least one of these EnemyData.tags (empty = all).
@export var tags: Array[StringName] = []
## Inclusive enemy count of one wave (x <= 0 = RoomSequence.get_enemy_count_range).
@export var count_range := Vector2i.ZERO
## Multiplies the rolled count, rounded, at least 1 (D-084: 1 + 0.6 * (players - 1)).
@export var count_factor := 1.0
## Multiplies the HP of every normal enemy of the room (quiet room: same total HP with fewer).
@export var health_factor := 1.0
## Elite traits and the shadow/bomber replacement (D-069) stay allowed unless switched off.
@export var allow_elites := true
@export var allow_extra_types := true


## Keeps the entries of a biome table [types, weights] that match the filters. Returns the table
## unchanged if no type matches, so a theme can never leave a room without enemies.
func filter_table(types: Array[EnemyData], weights: Array[float]) -> Array:
	if attack_kind < 0 and tags.is_empty():
		return [types, weights]
	var kept_types: Array[EnemyData] = []
	var kept_weights: Array[float] = []
	for i in types.size():
		if _matches(types[i]):
			kept_types.append(types[i])
			kept_weights.append(weights[i] if i < weights.size() else 1.0)
	if kept_types.is_empty():
		return [types, weights]
	return [kept_types, kept_weights]


## True if the room data sets the count itself (no arena shaping, WaveRules.get_wave_size).
func has_fixed_count() -> bool:
	return count_range.x > 0


## Enemy count of one wave from the range of the room, before the factor.
func get_count_range(room_index: int) -> Vector2i:
	if count_range.x > 0:
		return Vector2i(count_range.x, maxi(count_range.x, count_range.y))
	return RoomSequence.get_enemy_count_range(room_index)


func _matches(data: EnemyData) -> bool:
	if data == null:
		return false
	if attack_kind >= 0 and int(data.attack_kind) != attack_kind:
		return false
	if tags.is_empty():
		return true
	for tag in tags:
		if data.tags.has(tag):
			return true
	return false
