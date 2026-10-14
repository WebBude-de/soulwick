class_name VariantTable
extends Resource
## Draw of combat variants and the wager altar for the normal combat rooms (places 1-3 of the
## cycle), KONZEPT_RAEUME §2, D-101, D-104. The weights live in variant_table.tres, so balancing
## needs no code change. Randomness only through the RNG handed in (the dungeon RNG).
##
## From room from_room: variant_chance of the combat rooms become a combat variant, never two in a
## row (D-101); of the other ones wager_chance get a wager altar behind the entrance (D-104). A
## variant room is fought as a normal room kind (no arena, no chasm): the DungeonManager forces
## RoomKind.NORMAL when roll() picked a variant (hook in the A7 report).
## roll() draws exactly three numbers for every normal combat room, also before from_room, and none
## for other room types, so the dungeon RNG stays in step whatever comes out.

const DEFAULT_PATH := "res://dungeon/variants/variant_table.tres"
const NONE := &""

## First room with variants and wager altars (rooms 1-5 stay plain, KONZEPT §2).
@export var from_room := 6
## Share of the combat rooms that become a variant (D-101). TESTWERT
@export_range(0.0, 1.0) var variant_chance := 0.2
## Share of the other combat rooms with a wager altar (D-104). TESTWERT
@export_range(0.0, 1.0) var wager_chance := 0.12
## Variants of the draw and their weights (TESTWERTE), parallel arrays.
@export var variant_ids: Array[StringName] = []
@export var variant_weights: Array[float] = []
## Biome a variant is bound to (RoomSequence.Biome value), -1 = every biome; parallel to variant_ids.
@export var variant_biomes: Array[int] = []


## Result of one draw.
class Pick:
	extends RefCounted
	var variant_id: StringName = &""
	var wager := false

	func has_variant() -> bool:
		return variant_id != &""

	func is_empty() -> bool:
		return variant_id == &"" and not wager


static func load_default() -> VariantTable:
	return load(DEFAULT_PATH) as VariantTable


## Variant or wager altar (or nothing) for one room. previous_variant: variant of the combat room
## right before this one (&"" if that one was none or not a combat room) - never two in a row.
func roll(room_index: int, room_type: RoomSequence.RoomType, previous_variant: StringName, rng: RandomNumberGenerator) -> Pick:
	var pick := Pick.new()
	if rng == null or not RoomSequence.is_normal_combat(room_type):
		return pick
	var variant_roll := rng.randf()
	var choice_roll := rng.randf()
	var wager_roll := rng.randf()
	if room_index < from_room:
		return pick
	if previous_variant == NONE and variant_roll < variant_chance:
		pick.variant_id = choose_variant(RoomSequence.get_biome(room_index), choice_roll)
	if not pick.has_variant():
		pick.wager = wager_roll < wager_chance
	return pick


## Weighted choice among the variants allowed in a biome; roll in [0, 1). &"" if none is allowed.
func choose_variant(biome: int, roll: float) -> StringName:
	var ids := get_allowed(biome)
	if ids.is_empty():
		return NONE
	var total := 0.0
	for id in ids:
		total += get_weight(id)
	if total <= 0.0:
		return NONE
	var rest := roll * total
	for id in ids:
		rest -= get_weight(id)
		if rest < 0.0:
			return id
	return ids[ids.size() - 1]


## Variants with a positive weight that may appear in the biome (gravedigger: crypt only).
func get_allowed(biome: int) -> Array[StringName]:
	var allowed: Array[StringName] = []
	for i in variant_ids.size():
		var bound := variant_biomes[i] if i < variant_biomes.size() else -1
		if (bound < 0 or bound == biome) and get_weight(variant_ids[i]) > 0.0:
			allowed.append(variant_ids[i])
	return allowed


func get_weight(variant_id: StringName) -> float:
	var index := variant_ids.find(variant_id)
	if index < 0 or index >= variant_weights.size():
		return 0.0
	return maxf(0.0, variant_weights[index])
