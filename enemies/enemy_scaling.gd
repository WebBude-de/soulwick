class_name EnemyScaling
extends RefCounted
## Room-based difficulty scaling (D-011, retuned D-074, D-154), k(room) = floor((room - 1) / 5):
##   HP       = base * 1.17^k * (champion factor)
##   damage   = base * 1.11^k * (champion factor)
##   cooldown = base * max(0.55, 1 - 0.03 k), telegraph * max(0.7, 1 - 0.015 k)
##   speed    = base * min(1.5, 1 + 0.03 k)
## The same formula continues endlessly (D-063); factors D-210, D-213.
## Danger level G (KE2, D-194, D-196, KONZEPT §3) is the second axis on top, linear so the balance
## bot can measure it cleanly: HP x (1 + 0.06 G), damage x (1 + 0.04 G), for normal enemies,
## champions and bosses alike; from G 6 one enemy type of the next biome joins each biome.
## The rules take danger as a parameter; run_danger() is the one place that reads the run's level.

const ROOMS_PER_BLOCK := 5
## TESTWERT (D-154: 1.18 -> 1.16; D-210: 1.16 -> 1.17, playtest "much too easy" up to room 63; room 15
## x1.37 instead of x1.35, room 45 x3.51 instead of x3.28, room 63 x6.6 instead of x5.9).
const HEALTH_FACTOR_PER_BLOCK := 1.17
## TESTWERT (D-154: 1.14 -> 1.12; D-210: 1.12 -> 1.13; rooms 1-25 hit like before, a normal hit (0.7)
## in room 26-30 1.5 instead of 1.0, 41-45 2.0 instead of 1.5, 51-55 2.5, 61-65 3.0 instead of 2.5).
## D-213: 1.13 -> 1.11 together with base damage 0.7 -> 1.02 (playtest "too easy, already early"):
## a normal hit is 1.0 in room 1-10, 1.5 in 11-30, 2.0 in 31-40, 2.5 in 41-50, 3.0 in 51-60 - the early
## run hits twice / 1.5x as hard, from room 41 on 0.5 more than before (61-65 3.5, 71-75 4.5).
const DAMAGE_FACTOR_PER_BLOCK := 1.11
## Minibosses are champions: tougher than a plain enemy (D-077).
## TESTWERT (D-213: 3.0 -> 6.0, playtest "the miniboss was two-hit"; a room-5 skeleton champion has
## 102 HP: about 4 s for the sword, 10 s for the bow).
const MINIBOSS_HEALTH_FACTOR := 6.0
## TESTWERT (D-213: 1.5 -> 1.7, "you should take damage too"; champion hit room 5 1.5, room 6-15 2.0).
const MINIBOSS_DAMAGE_FACTOR := 1.7
const COOLDOWN_REDUCTION_PER_BLOCK := 0.03
const MIN_COOLDOWN_FACTOR := 0.55
const TELEGRAPH_REDUCTION_PER_BLOCK := 0.015
const MIN_TELEGRAPH_FACTOR := 0.7
## TESTWERT (D-089). D-210 kept 0.03: 0.04 let the ember golem catch up with a kiting bow, so its
## lava balls (only thrown at players out of reach) came less often (boss_sim kiting check).
const SPEED_GAIN_PER_BLOCK := 0.03
const MAX_SPEED_FACTOR := 1.5

## danger argument meaning "the level of the current run" (run_danger()).
const RUN_DANGER := -1
## TESTWERT (KE2, KONZEPT §3): enemy HP +6 % per danger level (champions and bosses too).
const HEALTH_GAIN_PER_DANGER := 0.06
## TESTWERT (KE2, KONZEPT §3): enemy damage +4 % per danger level. Hits are rounded to 0.5
## (DamageProcessor), so small base hits only jump at some levels (0.65 -> 1.0 at G 4).
const DAMAGE_GAIN_PER_DANGER := 0.04
## TESTWERT (KE2, KONZEPT §3): from this level on one enemy type of the next biome mixes in.
const BIOME_MIX_FROM_DANGER := 6
## TESTWERT (KE2): share of the guest type in the biome's weighted table (0.12 = about every 8th).
const GUEST_WEIGHT_SHARE := 0.12


static func get_block(room_index: int) -> int:
	return maxi(0, floori(float(room_index - 1) / ROOMS_PER_BLOCK))


## danger: the danger level G; RUN_DANGER (default) takes the level of the current run.
static func health_multiplier(room_index: int, is_miniboss: bool, danger := RUN_DANGER) -> float:
	var factor := MINIBOSS_HEALTH_FACTOR if is_miniboss else 1.0
	return pow(HEALTH_FACTOR_PER_BLOCK, get_block(room_index)) * factor * danger_health_factor(resolve_danger(danger))


## danger: the danger level G; RUN_DANGER (default) takes the level of the current run.
static func damage_multiplier(room_index: int, is_miniboss: bool, danger := RUN_DANGER) -> float:
	var factor := MINIBOSS_DAMAGE_FACTOR if is_miniboss else 1.0
	return pow(DAMAGE_FACTOR_PER_BLOCK, get_block(room_index)) * factor * danger_damage_factor(resolve_danger(danger))


static func cooldown_multiplier(room_index: int) -> float:
	return maxf(MIN_COOLDOWN_FACTOR, 1.0 - COOLDOWN_REDUCTION_PER_BLOCK * get_block(room_index))


static func telegraph_multiplier(room_index: int) -> float:
	return maxf(MIN_TELEGRAPH_FACTOR, 1.0 - TELEGRAPH_REDUCTION_PER_BLOCK * get_block(room_index))


static func speed_multiplier(room_index: int) -> float:
	return minf(MAX_SPEED_FACTOR, 1.0 + SPEED_GAIN_PER_BLOCK * get_block(room_index))


# --- Danger level (KE2, D-194, D-196) ---

## The danger level of the current run, the only place that reads it (RunManager.get_danger_level:
## solo the player's own level, co-op the group level the host computed and sent along).
static func run_danger() -> int:
	var loop := Engine.get_main_loop() as SceneTree
	var run_manager := loop.root.get_node_or_null(^"RunManager") if loop != null else null
	return maxi(0, int(run_manager.get_danger_level())) if run_manager != null else 0


## RUN_DANGER -> the run's level, anything else is used as given (never below 0).
static func resolve_danger(danger: int) -> int:
	return run_danger() if danger == RUN_DANGER else maxi(0, danger)


## HP factor of danger level G alone: 1 + 0.06 G.
static func danger_health_factor(danger: int) -> float:
	return 1.0 + HEALTH_GAIN_PER_DANGER * maxi(0, danger)


## Damage factor of danger level G alone: 1 + 0.04 G.
static func danger_damage_factor(danger: int) -> float:
	return 1.0 + DAMAGE_GAIN_PER_DANGER * maxi(0, danger)


## True if a guest type of the next biome mixes into every biome (from G 6).
static func mixes_biomes(danger: int) -> bool:
	return danger >= BIOME_MIX_FROM_DANGER


## Number of the biome stretch a room belongs to (0 = rooms 1-15, 1 = rooms 16-30, ...): the guest
## type is rolled once per stretch.
static func get_biome_stretch(room_index: int) -> int:
	return maxi(0, floori(float(room_index - 1) / RoomSequence.BOSS_INTERVAL))


## First room of the stretch after the one room_index belongs to (the next biome's table is read
## there, so the guest is a type the player would meet first in that biome).
static func get_next_biome_room(room_index: int) -> int:
	return (get_biome_stretch(room_index) + 1) * RoomSequence.BOSS_INTERVAL + 1


## One guest type for a biome stretch: a type of next_types that own_types does not have, picked
## with one draw of the dungeon RNG. null (and no draw) if the next biome brings nothing new.
static func roll_guest_type(own_types: Array[EnemyData], next_types: Array[EnemyData], rng: RandomNumberGenerator) -> EnemyData:
	var candidates: Array[EnemyData] = []
	for type in next_types:
		if type != null and not _has_type(own_types, type) and not _has_type(candidates, type):
			candidates.append(type)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## The weighted table [types, weights] with the guest added at GUEST_WEIGHT_SHARE of the new total.
## A new table; the original stays as it was. Unchanged (copied) without a guest, if the guest is
## already in it or the table is empty.
static func add_guest(table: Array, guest: EnemyData, share := GUEST_WEIGHT_SHARE) -> Array:
	var types: Array[EnemyData] = []
	var weights: Array[float] = []
	types.assign(table[0])
	weights.assign(table[1])
	if guest == null or types.is_empty() or _has_type(types, guest):
		return [types, weights]
	var total := 0.0
	for weight in weights:
		total += weight
	types.append(guest)
	weights.append(total * share / maxf(0.01, 1.0 - share))
	return [types, weights]


static func _has_type(types: Array[EnemyData], type: EnemyData) -> bool:
	for other in types:
		if other == type or (other != null and other.id != &"" and other.id == type.id):
			return true
	return false


## EnemySpawner hook (KE2): the biome table of room_index with the guest of the next biome from
## G 6 on. biomes in RoomSequence.Biome order (EnemySpawner.biomes); guests caches the roll per
## biome stretch (a dictionary the spawner keeps for the run), so the guest is drawn once per
## stretch from the dungeon RNG and only from G 6 on (lower levels draw nothing).
static func table_with_guest(table: Array, biomes: Array[BiomeData], room_index: int, guests: Dictionary, rng: RandomNumberGenerator, danger := RUN_DANGER) -> Array:
	if biomes.is_empty() or not mixes_biomes(resolve_danger(danger)):
		return table
	var stretch := get_biome_stretch(room_index)
	if not guests.has(stretch):
		var own := biomes[RoomSequence.get_biome(room_index) % biomes.size()]
		var next_room := get_next_biome_room(room_index)
		var next := biomes[RoomSequence.get_biome(next_room) % biomes.size()]
		var next_types: Array[EnemyData] = next.get_table(next_room)[0]
		guests[stretch] = roll_guest_type(own.enemies, next_types, rng) if own != null and next != null else null
	return add_guest(table, guests[stretch] as EnemyData)
