class_name RoomSequence
extends RefCounted
## Pure rules of the room order (D-002 .. D-006, endless D-073, room kinds D-086, campfire D-103).
## No nodes, fully unit-testable.
##
## Room numbers vs. slots: every room instance of a run has a slot (its place in the stack of
## instances). A campfire follows every boss room (D-103) but is no room: it takes a slot of its
## own and keeps the number of the boss room before it, so room numbers, scaling, heals and the
## five-room cycle stay exactly as without it. Slot 16 is the campfire after room 15, room 16 sits
## in slot 17, and so on.

## CAMPFIRE never comes from get_room_type(): it only exists between two room numbers (slots).
enum RoomType { COMBAT, COMBAT_UPGRADE, SPECIAL, MINIBOSS, BOSS, CAMPFIRE }
enum SpecialType { SHOP, WEAPON, FOUNTAIN, UPGRADE }

enum Biome { CRYPT, SLIME_GROTTO, SHADOW_REALM, EMBER_FORGE }
## Kind of a normal combat room (D-086). Independent of the biome.
enum RoomKind { ARENA, STRUCTURED, ABYSS }
## Size class of a combat template in tiles (D-086): S ~ 15x9, M ~ 19x11, L ~ 25x15.
enum RoomSize { S, M, L }

const CYCLE_LENGTH := 5
## Every 15th room is a boss room, endlessly (D-073).
const BOSS_INTERVAL := 15
const BIOME_COUNT := 4
const PORTAL_CHANCE := 0.3


static func get_room_type(room_index: int) -> RoomType:
	var position := (room_index - 1) % CYCLE_LENGTH + 1
	match position:
		3:
			return RoomType.COMBAT_UPGRADE
		4:
			return RoomType.SPECIAL
		5:
			return RoomType.BOSS if room_index % BOSS_INTERVAL == 0 else RoomType.MINIBOSS
	return RoomType.COMBAT


# --- Slots: room numbers plus the campfires between the biomes (D-103) ---

## Slots per boss interval: the rooms of one biome plus the campfire after its boss.
static func get_slots_per_biome() -> int:
	return BOSS_INTERVAL + 1


## True for the slot right after a boss room (16, 32, 48, ...).
static func is_campfire_slot(slot: int) -> bool:
	return slot > 0 and slot % get_slots_per_biome() == 0


## Room number shown and used for scaling. A campfire slot keeps the number of its boss room.
static func get_room_for_slot(slot: int) -> int:
	return slot - floori(float(slot) / get_slots_per_biome())


## Slot of a room number (rooms 1-15 keep their number, room 16 is slot 17, ...).
static func get_slot_for_room(room_index: int) -> int:
	return room_index + floori(float(room_index - 1) / BOSS_INTERVAL)


## Slot of the campfire behind a boss room (0 if room_index is no boss room).
static func get_campfire_slot_after(room_index: int) -> int:
	if room_index <= 0 or room_index % BOSS_INTERVAL != 0:
		return 0
	return get_slot_for_room(room_index) + 1


## Room type of a slot: CAMPFIRE between the biomes, otherwise the type of its room number.
static func get_slot_type(slot: int) -> RoomType:
	if is_campfire_slot(slot):
		return RoomType.CAMPFIRE
	return get_room_type(get_room_for_slot(slot))


static func is_normal_combat(room_type: RoomType) -> bool:
	return room_type == RoomType.COMBAT or room_type == RoomType.COMBAT_UPGRADE


## Inclusive min/max number of normal enemies (D-074): gentle start, denser deeper down.
static func get_enemy_count_range(room_index: int) -> Vector2i:
	if room_index <= 3:
		return Vector2i(1, 2)
	if room_index < 15:
		return Vector2i(2, 3)
	if room_index < 30:
		return Vector2i(2, 4)
	return Vector2i(3, 5)


## Number of enemy waves in a normal combat room: more pressure deeper down (D-074).
static func get_wave_count(room_index: int) -> int:
	if room_index >= 60:
		return 3
	if room_index >= 30:
		return 2
	return 1


## Biome of a room: a new theme every 15 rooms, cycling (D-075).
static func get_biome(room_index: int) -> Biome:
	return (floori(float(room_index - 1) / BOSS_INTERVAL) % BIOME_COUNT) as Biome


## 1 for room 15, 2 for room 30, ...
static func get_boss_number(room_index: int) -> int:
	return maxi(1, floori(float(room_index) / BOSS_INTERVAL))


## Boss difficulty tier: rises after every full cycle of the four bosses (D-076).
static func get_boss_tier(room_index: int) -> int:
	return floori(float(get_boss_number(room_index) - 1) / BIOME_COUNT)


static func get_biome_name(biome: int) -> String:
	match biome:
		Biome.SLIME_GROTTO:
			return "Schleimgrotte"
		Biome.SHADOW_REALM:
			return "Schattenreich"
		Biome.EMBER_FORGE:
			return "Glutkammer"
	return "Krypta"


## Equal weights over the four types, never the same type twice in a row (D-005).
static func roll_special_type(previous: int, rng: RandomNumberGenerator) -> SpecialType:
	var options: Array[int] = []
	for special_type in SpecialType.values():
		if special_type != previous:
			options.append(special_type)
	return options[rng.randi_range(0, options.size() - 1)] as SpecialType


const EXTRA_DARK_FROM_ROOM := 6
const EXTRA_DARK_CHANCE := 0.25


## Extra-dark rooms have a smaller light circle (D-067). The shadow realm is always dark.
static func roll_extra_dark(room_index: int, room_type: RoomType, rng: RandomNumberGenerator) -> bool:
	if get_biome(room_index) == Biome.SHADOW_REALM and room_type != RoomType.SPECIAL:
		return true
	if room_index < EXTRA_DARK_FROM_ROOM or not is_normal_combat(room_type):
		return false
	return rng.randf() < EXTRA_DARK_CHANCE


## Rolled independently after the special type (draw order OPEN, proposal D-058).
static func roll_portal(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < PORTAL_CHANCE


## Abyss rooms appear from this room on (D-086, TESTWERT).
const ABYSS_FROM_ROOM := 6
## Room kind weights in RoomKind order (D-086, TESTWERTE): rooms 1-5 and from ABYSS_FROM_ROOM.
const ROOM_KIND_WEIGHTS_EARLY: Array[float] = [0.5, 0.5, 0.0]
const ROOM_KIND_WEIGHTS: Array[float] = [0.35, 0.4, 0.25]
## Spawn markers per combat template (D-086): at least S 5 / M 8 / L 12, never more than 14.
const MIN_SPAWN_POINTS: Array[int] = [5, 8, 12]
const MAX_SPAWN_POINTS := 14
## Size classes a single player may get (D-086); L is kept for tests and later multiplayer.
const SOLO_ROOM_SIZES: Array[RoomSize] = [RoomSize.S, RoomSize.M]


## Room kind of a normal combat room (D-086). previous_kind is the kind of the room directly
## before (-1 if that was no combat room): never two abyss rooms in a row, the abyss share is then
## split proportionally between arena and structured. Always draws exactly one random number.
## Missing templates of a kind are handled by the template choice (RoomCatalog falls back to arena).
static func roll_room_kind(room_index: int, previous_kind: int, rng: RandomNumberGenerator) -> RoomKind:
	var weights := get_room_kind_weights(room_index, previous_kind)
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for kind in weights.size():
		roll -= weights[kind]
		if roll < 0.0 and weights[kind] > 0.0:
			return kind as RoomKind
	# Rounding at the upper end: the last kind with a weight.
	for kind in range(weights.size() - 1, -1, -1):
		if weights[kind] > 0.0:
			return kind as RoomKind
	return RoomKind.ARENA


## Effective (unnormalised) weights in RoomKind order for one draw.
static func get_room_kind_weights(room_index: int, previous_kind: int) -> Array[float]:
	var weights: Array[float] = []
	weights.assign(ROOM_KIND_WEIGHTS if room_index >= ABYSS_FROM_ROOM else ROOM_KIND_WEIGHTS_EARLY)
	if previous_kind == RoomKind.ABYSS:
		weights[RoomKind.ABYSS] = 0.0
	return weights


static func get_min_spawn_points(size: RoomSize) -> int:
	return MIN_SPAWN_POINTS[size]


## Splits an encounter of enemy_count enemies into waves of at most marker_count enemies:
## if a room has fewer markers than enemies, the rest arrives as an extra wave (D-086).
static func split_into_waves(enemy_count: int, marker_count: int) -> Array[int]:
	var waves: Array[int] = []
	if enemy_count <= 0 or marker_count <= 0:
		return waves
	var remaining := enemy_count
	while remaining > 0:
		waves.append(mini(remaining, marker_count))
		remaining -= marker_count
	return waves


static func get_kind_name(kind: int) -> String:
	match kind:
		RoomKind.STRUCTURED:
			return "Strukturiert"
		RoomKind.ABYSS:
			return "Abgrund"
	return "Arena"


static func get_size_name(size: int) -> String:
	match size:
		RoomSize.M:
			return "M"
		RoomSize.L:
			return "L"
	return "S"


static func get_type_name(room_type: RoomType) -> String:
	match room_type:
		RoomType.COMBAT_UPGRADE:
			return "Kampf + Upgrade"
		RoomType.SPECIAL:
			return "Spezialraum"
		RoomType.MINIBOSS:
			return "Miniboss"
		RoomType.BOSS:
			return "Boss"
		RoomType.CAMPFIRE:
			return "Lagerfeuer"
	return "Kampf"


static func get_special_name(special_type: int) -> String:
	match special_type:
		SpecialType.SHOP:
			return "Shop"
		SpecialType.WEAPON:
			return "Waffenauswahl"
		SpecialType.FOUNTAIN:
			return "Brunnen"
		SpecialType.UPGRADE:
			return "Upgrade-Altar"
	return ""
