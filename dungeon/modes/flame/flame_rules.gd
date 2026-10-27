class_name FlameRules
extends RefCounted
## Rules and numbers of "Flamme hüten" (RAEUME §3.4, R4b; before: Seelenflamme, D-114,
## D-118). No nodes, unit-testable; FlameMode only applies them.

## Raid time: enemies come in short pushes for this long after the fight started ("Halte die Flamme
## 40 s"); then the sources go dark and the rest must be beaten.
const DURATION := 40.0  # TESTWERT
## A push every this many seconds, or earlier once at most PUSH_AT_ALIVE enemies are left ...
const PUSH_INTERVAL := 8.0  # TESTWERT (Claude Design: "Schübe alle 8 s")
const PUSH_AT_ALIVE := 1
## ... but never two pushes closer than this.
const PUSH_MIN_GAP := 5.0  # TESTWERT
## Size of a push: the room's normal roll times this factor, at least PUSH_MIN (#56d68b40, the
## flame was never touched: 0.4 -> 0.7, more enemies arrive at once from the two sides).
const PUSH_FACTOR := 0.7  # TESTWERT
const PUSH_MIN := 2
## The room's own first wave is smaller (the pushes bring the rest).
const FIRST_WAVE_FACTOR := 0.7  # TESTWERT
## Share of the enemies that go for the flame instead of the players (playtest 23.10.2026
## #56d68b40, "die Flamme bekommt nie Schaden": 0.7 -> 0.85).
const RAID_SHARE := 0.85  # TESTWERT
## Flame health in hits of a plain enemy, scaled with the enemy damage of the room (#56d68b40:
## 16 -> 10).
const FLAME_HITS := 10.0  # TESTWERT
## Every push comes from two sides of the flame (#56d68b40): two sources whose directions from the
## flame differ by at least this angle (degrees), so one player cannot catch the whole push at one
## spot; without such a pair the room's usual choice. TESTWERT
const TWO_SIDES_MIN_ANGLE := 100.0
## Co-op (D-109, set in MP5): extra flame health per additional player.
## #56d68b40: two defenders at the flame held it untouched, 0.5 -> 0.3.
const HEALTH_PER_EXTRA_PLAYER := 0.3  # TESTWERT
## The flame's light follows its health: radius from OUT_LIGHT_RADIUS (empty) to LIGHT_RADIUS (full).
const LIGHT_RADIUS := 200.0  # TESTWERT
const LOW_LIGHT_RADIUS := 70.0
## Flame out: the room gets darker, light circle times this factor.
const OUT_VISION_FACTOR := 0.8  # TESTWERT
## Flame untouched at the end of the raid ("volle Flamme"): extra soul crystals.
const FULL_FLAME_CRYSTALS := 1  # TESTWERT


## Maximum health of the flame in a room for a number of players (0.5 steps).
static func flame_health(room_index: int, players: int) -> float:
	var extra := HEALTH_PER_EXTRA_PLAYER * (maxi(1, players) - 1)
	var health := FLAME_HITS * EnemyScaling.damage_multiplier(room_index, false) * (1.0 + extra)
	return maxf(DamageProcessor.DAMAGE_STEP, DamageProcessor.round_to_step(health))


## One roll per enemy: does it go for the flame?
static func is_raider(roll: float) -> bool:
	return roll < RAID_SHARE


## Is a push due? Only while the flame burns and the raid time runs.
static func should_push(elapsed: float, since_push: float, alive: int, flame_alive: bool) -> bool:
	if not flame_alive or elapsed >= DURATION:
		return false
	if since_push >= PUSH_INTERVAL:
		return true
	return alive <= PUSH_AT_ALIVE and since_push >= PUSH_MIN_GAP


## Do two sources (directions from the flame) lie on two sides of it?
static func on_two_sides(a: Vector2, b: Vector2) -> bool:
	if a.is_zero_approx() or b.is_zero_approx():
		return false
	return rad_to_deg(absf(a.angle_to(b))) >= TWO_SIDES_MIN_ANGLE


static func push_size(rolled: int) -> int:
	return maxi(PUSH_MIN, roundi(rolled * PUSH_FACTOR))


## The room stays shut while the raid time runs (RoomController hook).
static func holds_room(elapsed: float, started: bool) -> bool:
	return started and elapsed < DURATION


static func time_left(elapsed: float) -> float:
	return maxf(0.0, DURATION - elapsed)


## Light radius of the flame for its health share (0..1).
static func light_radius(health_ratio: float) -> float:
	return lerpf(LOW_LIGHT_RADIUS, LIGHT_RADIUS, clampf(health_ratio, 0.0, 1.0))


## Extra crystals at the end of the raid: only for a flame that never lost health.
static func full_flame_crystals(health_ratio: float) -> int:
	return FULL_FLAME_CRYSTALS if health_ratio >= 1.0 else 0
