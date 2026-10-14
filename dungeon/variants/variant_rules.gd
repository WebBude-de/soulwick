class_name VariantRules
extends RefCounted
## Shared rules of the room modes (D-109, D-120): the bonus chest and the crypt's gravedigger trait
## (KONZEPT_RAEUME_V2 §2: "Totengräber wird Gegner-Eigenschaft der Krypta"). The minigames keep their
## own numbers next to their scripts (FlameRules, RelicRules, RiftRules, HuntRules, LightfireRules).
## No nodes, unit-testable. Co-op values are parameters prepared for MP5 (D-109); with one player every
## factor is neutral.

# --- Gravedigger trait (crypt) ---

## Biome of the trait (RoomSequence.Biome.CRYPT) and first room.
const GRAVEDIGGER_BIOME := 0
const GRAVEDIGGER_FROM_ROOM := 3  # TESTWERT
## Share of the skeletons of a crypt combat room that leave a bone heap and rise once. TESTWERT
const GRAVEDIGGER_SKELETON_CHANCE := 0.35
## A bone heap that is not destroyed within this time rises again ...
const RISE_TIME := 5.0  # TESTWERT
## ... the last part of it visibly (bone_heap_rise animation).
const RISE_ANIMATION_TIME := 1.0
## ... with this share of its health, at most once.
const RISE_HEALTH_SHARE := 0.5  # TESTWERT
## Enemy types that leave a bone heap.
const RISING_IDS: Array[StringName] = [&"skeleton"]
## A player whose feet come this close destroys the heap (walking over it or dashing through).
const STOMP_RADIUS := 30.0

# --- Reward (D-109) ---

## Upgrade choices of the bonus chest (D-109: upgrade choice through the existing dialog).
const CHEST_UPGRADE_CHOICES := 1  # TESTWERT
## Co-op (D-109, set in MP5): one chest per player instead of one for the group.
const CHESTS_PER_PLAYER := false  # TESTWERT


# --- Gravedigger ---

## Does a combat room of this number and biome get the trait?
static func has_gravedigger(room_index: int, biome: int) -> bool:
	return biome == GRAVEDIGGER_BIOME and room_index >= GRAVEDIGGER_FROM_ROOM


## One roll per skeleton: does it leave a bone heap?
static func skeleton_rises(enemy_id: StringName, roll: float) -> bool:
	return can_rise(enemy_id) and roll < GRAVEDIGGER_SKELETON_CHANCE


static func can_rise(enemy_id: StringName) -> bool:
	return RISING_IDS.has(enemy_id)


## Health of a risen skeleton (0.5 steps, at least 0.5).
static func risen_health(max_health: float) -> float:
	return maxf(DamageProcessor.DAMAGE_STEP, DamageProcessor.round_to_step(max_health * RISE_HEALTH_SHARE))


## Has the heap been lying long enough to start its rise animation / to stand up?
static func is_rising(age: float) -> bool:
	return age >= RISE_TIME - RISE_ANIMATION_TIME


static func should_rise(age: float) -> bool:
	return age >= RISE_TIME


static func is_stomped(feet_distance: float) -> bool:
	return feet_distance <= STOMP_RADIUS


# --- Reward ---

static func chest_count(players: int) -> int:
	return maxi(1, players) if CHESTS_PER_PLAYER else 1
