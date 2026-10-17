class_name EncounterVariation
extends RefCounted
## Invisible variation of normal combat rooms (D-113): enemy groups by theme (mixed,
## ranged only, swarms only) and the quiet room (1-2 strong enemies with the same total health as the
## normal group). Pure rules, no nodes. roll() decides once per room, build_group() turns the result
## into the EncounterGroup data the EnemySpawner (A5) reads (RoomController.set_encounter_group):
## the theme groups are .tres files in dungeon/rooms/ingredients/groups/, the quiet group is built
## here because its health factor depends on the room. See the hook in the A3 report.
## The enemy shares of the biome tables (D-010, D-075) stay the same on average only if mixed rooms use
## compensated weights (mixed_weights(); needs a weight field in EncounterGroup, hook).

enum GroupTheme { MIXED, RANGED, SWARM }

## Themes and the quiet room start with the first rooms of the second cycle (like arena and chasm).
const FROM_ROOM := 6  # TESTWERT
## Theme chances in GroupTheme order (TESTWERTE).
const THEME_WEIGHTS: Array[float] = [0.75, 0.1, 0.15]  # D-118: ranged 0.15 -> 0.1
## Share of quiet rooms among the normal combat rooms from FROM_ROOM (KONZEPT §3.4). TESTWERT
const QUIET_CHANCE := 0.08
## Strong enemies in a quiet room.
const QUIET_COUNT := Vector2i(1, 2)
## Enemy ids that count as a swarm (slimes, KONZEPT §3.4) and the tag the swarm group filters on.
const SWARM_IDS: Array[StringName] = [&"slime", &"splitter_slime", &"mini_slime"]
const SWARM_TAG := &"swarm"
const RANGED_GROUP_PATH := "res://dungeon/rooms/ingredients/groups/ranged.tres"
const SWARM_GROUP_PATH := "res://dungeon/rooms/ingredients/groups/swarm.tres"
const QUIET_GROUP_ID := &"quiet"


## Result of roll() for one room.
class Plan:
	extends RefCounted
	var theme: GroupTheme = GroupTheme.MIXED
	var quiet := false
	## Strong enemies of a quiet room (QUIET_COUNT).
	var quiet_count := 1

	func is_plain() -> bool:
		return theme == GroupTheme.MIXED and not quiet


## Theme and quiet flag of a room. Always draws exactly three numbers for normal combat rooms (so
## the dungeon RNG stays in step whatever comes out), none for other room types. Quiet rooms are
## normal rooms only (an arena keeps its waves); the third number is the quiet enemy count.
static func roll(room_index: int, room_type: RoomSequence.RoomType, rng: RandomNumberGenerator, room_kind: int = RoomSequence.RoomKind.NORMAL) -> Plan:
	var plan := Plan.new()
	if not RoomSequence.is_normal_combat(room_type):
		return plan
	var theme_roll := rng.randf()
	var quiet_roll := rng.randf()
	var count_roll := rng.randf()
	if room_index < FROM_ROOM:
		return plan
	plan.quiet = quiet_roll < QUIET_CHANCE and room_kind == RoomSequence.RoomKind.NORMAL
	plan.quiet_count = QUIET_COUNT.x + mini(floori(count_roll * (QUIET_COUNT.y - QUIET_COUNT.x + 1)), QUIET_COUNT.y - QUIET_COUNT.x)
	plan.theme = _pick(THEME_WEIGHTS, theme_roll) as GroupTheme
	return plan


## EncounterGroup for a planned room (null = default rules). A quiet room wins over the theme:
## quiet_count strong melee enemies whose health adds up to an average normal group of the room.
static func build_group(plan: Plan, room_index: int, biome: BiomeData) -> EncounterGroup:
	if plan == null or plan.is_plain():
		return null
	if plan.quiet:
		return make_quiet_group(room_index, biome, plan.quiet_count)
	match plan.theme:
		GroupTheme.RANGED:
			return load(RANGED_GROUP_PATH) as EncounterGroup
		GroupTheme.SWARM:
			return load(SWARM_GROUP_PATH) as EncounterGroup
	return null


## Quiet group: count enemies of the melee types (an archer with triple health would just be
## tedious), health factor for the same total health as the mean normal group (D-074 range) of the
## room's biome table. Bombers are melee too; excluding them needs an exclude filter (hook).
static func make_quiet_group(room_index: int, biome: BiomeData, count: int) -> EncounterGroup:
	var group := EncounterGroup.new()
	group.id = QUIET_GROUP_ID
	group.attack_kind = EnemyData.AttackKind.MELEE
	var range_limits := RoomSequence.get_enemy_count_range(room_index)
	var normal_count := (range_limits.x + range_limits.y) * 0.5
	# Always fewer than the smallest normal group (otherwise the room would not be quieter).
	count = clampi(count, 1, maxi(1, range_limits.x - 1))
	group.count_range = Vector2i(count, count)
	group.allow_extra_types = false
	var normal_health := 0.0
	var quiet_health := 0.0
	if biome != null:
		var table := biome.get_table(room_index)
		var types: Array[EnemyData] = table[0]
		var weights: Array[float] = table[1]
		normal_health = average_health(types, weights)
		# The same filter the spawner applies to the table (EncounterGroup.filter_table).
		var quiet_table := group.filter_table(types, weights)
		var quiet_types: Array[EnemyData] = quiet_table[0]
		var quiet_weights: Array[float] = quiet_table[1]
		quiet_health = average_health(quiet_types, quiet_weights)
	group.health_factor = maxf(1.0, normal_count * normal_health / (count * quiet_health)) if quiet_health > 0.0 else normal_count / count
	return group


static func is_ranged(data: EnemyData) -> bool:
	return data != null and data.attack_kind == EnemyData.AttackKind.RANGED


static func is_swarm(data: EnemyData) -> bool:
	return data != null and (SWARM_IDS.has(data.id) or data.tags.has(SWARM_TAG))


static func fits_theme(data: EnemyData, theme: GroupTheme) -> bool:
	match theme:
		GroupTheme.RANGED:
			return is_ranged(data)
		GroupTheme.SWARM:
			return is_swarm(data)
	return true


## Weights of a biome table (types, weights) for a theme. Themed rooms keep only the fitting types;
## if none fits, the plain weights stay (a biome without archers never gets an empty room).
## The mixed theme gets mixed_weights(), so the average over all rooms matches the table.
static func weights_for_theme(types: Array[EnemyData], weights: Array[float], theme: GroupTheme) -> Array[float]:
	if theme == GroupTheme.MIXED:
		return mixed_weights(types, weights)
	var result: Array[float] = []
	var any := false
	for i in types.size():
		var fits := fits_theme(types[i], theme)
		result.append(weights[i] if fits else 0.0)
		any = any or (fits and weights[i] > 0.0)
	if not any:
		var plain: Array[float] = weights.duplicate()
		return plain
	return result


## Weights for mixed rooms that cancel out the themed rooms: share_mixed = (share - p_ranged *
## share_ranged - p_swarm * share_swarm) / p_mixed, clamped at 0 and normalised to the table total.
static func mixed_weights(types: Array[EnemyData], weights: Array[float]) -> Array[float]:
	var total := 0.0
	for weight in weights:
		total += weight
	var result: Array[float] = weights.duplicate()
	if total <= 0.0 or THEME_WEIGHTS[GroupTheme.MIXED] <= 0.0:
		return result
	var themed_total := 0.0
	for theme_weight in THEME_WEIGHTS:
		themed_total += theme_weight
	var share_mixed := THEME_WEIGHTS[GroupTheme.MIXED] / themed_total
	var shares: Array = [[], [], []]
	for theme in [GroupTheme.RANGED, GroupTheme.SWARM]:
		shares[theme] = _shares(weights_for_theme(types, weights, theme))
	var base := _shares(weights)
	var sum := 0.0
	for i in types.size():
		var value: float = base[i]
		for theme in [GroupTheme.RANGED, GroupTheme.SWARM]:
			value -= THEME_WEIGHTS[theme] / themed_total * float(shares[theme][i])
		result[i] = maxf(0.0, value / share_mixed)
		sum += result[i]
	if sum <= 0.0:
		return weights.duplicate()
	for i in result.size():
		result[i] *= total / sum
	return result


## Average base health of a weighted table (for quiet_health_multiplier()).
static func average_health(types: Array[EnemyData], weights: Array[float]) -> float:
	var total := 0.0
	var health := 0.0
	for i in types.size():
		total += weights[i]
		health += weights[i] * types[i].max_health
	return health / total if total > 0.0 else 0.0


## Code/test name of a group theme (never shown to the player).
static func get_theme_name(theme: int) -> String:
	match theme:
		GroupTheme.RANGED:
			return "Fernkämpfer"
		GroupTheme.SWARM:
			return "Schwarm"
	return "gemischt"


static func _shares(weights: Array[float]) -> Array[float]:
	var total := 0.0
	for weight in weights:
		total += weight
	var result: Array[float] = []
	for weight in weights:
		result.append(weight / total if total > 0.0 else 0.0)
	return result


static func _pick(weights: Array[float], roll: float) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var rest := roll * total
	for i in weights.size():
		rest -= weights[i]
		if rest < 0.0:
			return i
	return weights.size() - 1
