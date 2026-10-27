class_name SideElementRules
extends RefCounted
## The elements of the jump trial (Sprungprobe, SV2, D-195): every number and every pure decision in
## one place - moving platforms, springs, tilting platforms, saws on rails, collapsing bridges,
## wall-jump shafts and lanterns (no dash gaps: no side dash since D-216). No nodes: SideLayout plans with these numbers, the element
## nodes in dungeon/side/elements/ move and decide with them, SideBot and the tests read them.
## Timing (platforms, saws) is a pure function of the segment clock plus a phase derived from the
## segment seed (run seed + slot) and the element's build index, never from randf() (multiplayer
## rule): every machine computes the same place for the same clock; the host's clock is the truth.
## All numbers TESTWERT (D-195).

## The element kinds a plan can use ("Besonderheiten" of a tier, D-195).
const KIND_MOVER := &"moving_platform"
const KIND_SPRING := &"spring"
const KIND_TILT := &"tilt_platform"
const KIND_SAW := &"saw"
const KIND_BRIDGE := &"collapse_bridge"
const KIND_SHAFT := &"wall_shaft"

# --- Moving platforms (plan "M" with track "-", "V" with track "|") ---
## Speed along the track (px/s) and the rest at each end (s).
const MOVER_SPEED := 100.0
const MOVER_PAUSE := 0.6
## Depth of the one-way collision strip (px) and of the drawn platform (art 16 px ×2).
const MOVER_DEPTH := 20.0
const MOVER_ART_HEIGHT := 32.0

# --- Springs (plan "j") ---
## Launch height in tiles (D-195: 4.5).
const SPRING_HEIGHT_TILES := 4.5
## Feet within this distance of the spring's middle (px) and at most this far above its top press it.
const SPRING_HALF_WIDTH := 22.0
const SPRING_TRIGGER_HEIGHT := 14.0
## A launched player is not launched again for this long (s).
const SPRING_REARM := 0.25
## Planning reach of a spring launch: rows up -> furthest column distance (plain), and with the
## double jump on top (SideLayout spring edges).
const SPRING_REACH_UP_MAX := 4
const SPRING_REACH_BY_RISE := {4: 2, 3: 3, 2: 3, 1: 3, 0: 3}
const SPRING_DOUBLE_REACH_UP_MAX := 6
const SPRING_DOUBLE_REACH_BY_RISE := {6: 2, 5: 3, 4: 4, 3: 4, 2: 4, 1: 4, 0: 4}
const SPRING_REACH_DROP := 3

# --- Tilting platforms (plan "//", exactly TILT_CELLS wide) ---
## Falls TILT_DELAY seconds after a player stands on it, back after TILT_RESPAWN (D-195: 0.4 s).
const TILT_DELAY := 0.4
const TILT_RESPAWN := 2.5
const TILT_CELLS := 2

# --- Collapsing bridges (plan "_") ---
## Each bridge piece falls this long after a player stepped on it (the bridge breaks behind the
## runner and drives them on), and is back after BRIDGE_RESPAWN once nobody is in the way.
const BRIDGE_DELAY := 0.35
const BRIDGE_RESPAWN := 4.0

# --- Saws on rails (plan "X" on a rail of "+") ---
## Speed along the rail (px/s), rest at each end (s), hit radius (px), damage like the spikes (one
## heart, SideSpikes.DAMAGE), and a new hit at the earliest after SAW_REARM seconds.
const SAW_SPEED := 150.0
const SAW_PAUSE := 0.2
const SAW_RADIUS := 22.0
const SAW_DAMAGE := 1.0
const SAW_REARM := 0.9
## The bot keeps this far (px) from a saw's path ahead and waits for it to move away.
const SAW_BOT_MARGIN := 52.0

# --- Wall-jump shafts (plan "*" fills the shaft) ---
## A shaft is SHAFT_WIDTH columns wide between rock and at least SHAFT_MIN_ROWS high, more than any
## double jump climbs (SideLayout.DOUBLE_REACH_UP_MAX), so only wall jumps get out of it.
const SHAFT_WIDTH := 2
const SHAFT_MIN_ROWS := 5
## A stand cell this many columns beside the shaft and up to SHAFT_EXIT_ROWS above its top row is an
## exit of the shaft. Its walls are rock from the row below its top down to the row above its floor
## (the floor row may open sideways: the way in).
const SHAFT_EXIT_COLUMNS := 2
const SHAFT_EXIT_ROWS := 2

# --- Lanterns (plan "L") ---
## A player passing this close (px) lights the lantern; its stand cell is a safe return spot.
const LANTERN_REACH := 56.0

# --- Plan rules (fairness, D-195) ---
## New element kinds per tier: tier 1 at most one, tier 2 exactly two, tier 3 at least three.
const TIER_ELEMENTS := {1: Vector2i(0, 1), 2: Vector2i(2, 2), 3: Vector2i(3, 7)}
## No blind jump: one jump of the way rises at most WAY_MAX_RISE_ROWS rows (a spring with the double
## jump) and drops at most WAY_MAX_DROP_ROWS (the view is about 7.8 tiles high at the dungeon zoom,
## the feet sit low in it and the camera looks ahead along the way, SideCamera.way_look).
const WAY_MAX_RISE_ROWS := 6
const WAY_MAX_DROP_ROWS := 5
## A long plan (more than SideRules.ROWS rows, or tier 2 and up) has at least one lantern.
const LANTERN_FROM_TIER := 2


## Launch speed of a spring (px/s): SPRING_HEIGHT_TILES high under SideRules.GRAVITY.
static func spring_velocity() -> float:
	return SideRules.jump_velocity_for(SPRING_HEIGHT_TILES * SideRules.TILE)


## Offset (px, 0..length) of something going back and forth along length at speed with a rest of
## pause at both ends, time seconds after its start at the 0 end; eased = slow in and out.
static func ping_pong(time: float, length: float, speed: float, pause: float, eased := false) -> float:
	if length <= 0.0 or speed <= 0.0:
		return 0.0
	var travel := length / speed
	var t := fposmod(time, period(length, speed, pause))
	if t < pause:
		return 0.0
	t -= pause
	if t < travel:
		return _ease(t / travel, eased) * length
	t -= travel
	if t < pause:
		return length
	t -= pause
	return (1.0 - _ease(t / travel, eased)) * length


## Seconds of one full back-and-forth.
static func period(length: float, speed: float, pause: float) -> float:
	if length <= 0.0 or speed <= 0.0:
		return 1.0
	return 2.0 * (length / speed + pause)


## Start phase in seconds of element index of a segment (seed from the run seed and the slot,
## SideSegment): the same on every machine, different from element to element.
static func phase_for(segment_seed: int, index: int, cycle: float) -> float:
	var roll := absi(hash([segment_seed, index, "side_element"])) % 10000
	return roll / 10000.0 * maxf(cycle, 0.001)


## Whether a tier fits the number of new element kinds of a plan.
static func tier_allows(tier: int, element_kinds: int) -> bool:
	var span: Vector2i = TIER_ELEMENTS.get(clampi(tier, 1, SideRules.MAX_TIER), Vector2i(0, 1))
	return element_kinds >= span.x and element_kinds <= span.y


static func _ease(t: float, eased: bool) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x) if eased else x
