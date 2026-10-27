class_name BossPressure
extends RefCounted
## Answers of a boss to how the players fight it (playtest #a8a87397: "ran around the ember golem
## with the bow, never near it, took nothing"; TESTWERTE): whoever keeps away is shelled with
## lobbed lava balls - the longer nobody came into melee reach, the more often - and whoever crowds
## the boss is thrown off by a short stunning stomp. Configured in EnemyData ("Lava balls", "Stomp").
## Timing and aiming only; Enemy runs the attacks (telegraph, Blast with warning circle and pool).
## One instance per boss, host side (the host runs enemies). No randomness: the extra balls rotate
## by the golden angle per throw.

## A player closer than this to the boss counts as "in melee reach" (px). TESTWERT
const NEAR_DISTANCE := 180.0
## Every warning lasts at least this long (wind-up of the stomp, flight of a ball; s).
const MIN_WARNING := 0.5
## No stun of the stomp is longer than this (s).
const MAX_STUN := 0.5
## A ball leads its target by this share of the way it would walk during the flight. TESTWERT
const LEAD_SHARE := 0.6
## Smoothing of the measured player velocity (share of the new frame).
const VELOCITY_SMOOTHING := 0.2
## While nobody is out of melee reach, the next ball waits at least this long (s).
const LOB_IDLE_DELAY := 1.5
## First ball after the fight starts (s).
const FIRST_LOB_DELAY := 2.0
## The stomp starts only while a player stands inside this share of its radius.
const STOMP_TRIGGER_SHARE := 0.8
## Phase two (TESTWERTE): balls come more often and fly a little faster; the stomp reaches further
## and comes back sooner.
const ENRAGE_LOB_INTERVAL_FACTOR := 1.0
const ENRAGE_FLIGHT_FACTOR := 0.85
const ENRAGE_STOMP_RADIUS_FACTOR := 1.2
const ENRAGE_STOMP_COOLDOWN_FACTOR := 0.7
## Every further boss tier adds this many balls per throw.
const LOBS_PER_TIER := 1
## Lava pool: share of the boss hit per tick (at least the 0.5 step).
const POOL_DAMAGE_FACTOR := 0.4
const GOLDEN_ANGLE := 2.399963

## Seconds since the last moment a living player stood in melee reach.
var far_time := 0.0
## Throws so far (rotates the pattern of the extra balls).
var throws := 0

var _data: EnemyData = null
var _lob_left := FIRST_LOB_DELAY
var _stomp_left := 0.0
## Smoothed velocity and last position per player (instance id), measured from positions so it also
## works for network copies of remote players.
var _velocities: Dictionary[int, Vector2] = {}
var _positions: Dictionary[int, Vector2] = {}


## A pressure for bosses whose data has lava balls or a stomp, else null.
static func create(enemy_data: EnemyData) -> BossPressure:
	if enemy_data == null or not uses_pressure(enemy_data):
		return null
	var pressure := BossPressure.new()
	pressure._data = enemy_data
	return pressure


static func uses_pressure(enemy_data: EnemyData) -> bool:
	return enemy_data.lob_interval > 0.0 or enemy_data.stomp_radius > 0.0


## Once per physics frame with all players (freed, dead and protected ones are skipped).
func tick(delta: float, boss_position: Vector2, players: Array) -> void:
	_lob_left -= delta
	_stomp_left -= delta
	var near := false
	for candidate: Variant in players:
		if not EnemyTargeting.is_targetable(candidate):
			continue
		var node := candidate as Node2D
		_track_velocity(node, delta)
		if node.global_position.distance_to(boss_position) <= NEAR_DISTANCE:
			near = true
	far_time = 0.0 if near else far_time + delta


# --- Lava balls ---

## Who the next throw goes at: the farthest player out of melee reach once the timer ran out, else
## null. Nobody out of reach: the next throw waits LOB_IDLE_DELAY at least.
func lob_target(boss_position: Vector2, players: Array) -> Node2D:
	if _data.lob_interval <= 0.0 or _lob_left > 0.0:
		return null
	var target := farthest_out_of_reach(players, boss_position)
	if target == null:
		_lob_left = maxf(_lob_left, LOB_IDLE_DELAY)
	return target


## Call when a throw starts: the timer restarts with the current interval.
func lob_started(phase: int) -> void:
	_lob_left = lob_interval(phase)
	throws += 1


## Seconds until the next throw: from lob_interval right after the players left down to
## lob_interval_min after lob_ramp_time seconds without anybody near; shorter in phase two.
func lob_interval(phase: int) -> float:
	var t := clampf(far_time / maxf(0.01, _data.lob_ramp_time), 0.0, 1.0)
	var interval := lerpf(_data.lob_interval, minf(_data.lob_interval, _data.lob_interval_min), t)
	if phase >= 2:
		interval *= ENRAGE_LOB_INTERVAL_FACTOR
	return maxf(MIN_WARNING, interval)


func flight_time(phase: int) -> float:
	var flight := _data.lob_flight_time * (ENRAGE_FLIGHT_FACTOR if phase >= 2 else 1.0)
	return maxf(MIN_WARNING, flight)


func pool_time(phase: int) -> float:
	return _data.enrage_lob_pool_time if phase >= 2 else _data.lob_pool_time


## Balls per throw.
static func lob_count(enemy_data: EnemyData, tier: int, phase: int) -> int:
	var count := enemy_data.lob_count + LOBS_PER_TIER * maxi(0, tier)
	if phase >= 2:
		count += enemy_data.enrage_lob_count
	return maxi(1, count)


## Where a ball aimed at target lands: ahead of it by LEAD_SHARE of its way during the flight.
func aim_point(target: Node2D, flight: float) -> Vector2:
	return lead_point(target.global_position, get_velocity(target), flight)


static func lead_point(target_position: Vector2, target_velocity: Vector2, flight: float) -> Vector2:
	return target_position + target_velocity * flight * LEAD_SHARE


## Landing spots of one throw: the first on center, the others on a ring of spread around it,
## rotated by the golden angle per throw.
static func lob_spots(center: Vector2, count: int, spread: float, throw_index: int) -> Array[Vector2]:
	var spots: Array[Vector2] = [center]
	var ring := count - 1
	for i in ring:
		var angle := GOLDEN_ANGLE * throw_index + TAU * float(i) / float(ring)
		spots.append(center + Vector2.from_angle(angle) * spread)
	return spots


## Smoothed velocity of a player (zero before the second frame).
func get_velocity(player: Node2D) -> Vector2:
	if player == null:
		return Vector2.ZERO
	return _velocities.get(player.get_instance_id(), Vector2.ZERO)


# --- Stomp ---

## True when the stomp is ready and a player stands well inside its radius.
func wants_stomp(boss_position: Vector2, players: Array, phase: int) -> bool:
	if _data.stomp_radius <= 0.0 or _stomp_left > 0.0:
		return false
	var reach := stomp_radius(phase) * STOMP_TRIGGER_SHARE
	for candidate: Variant in players:
		if EnemyTargeting.is_targetable(candidate) and (candidate as Node2D).global_position.distance_to(boss_position) <= reach:
			return true
	return false


func stomp_started(phase: int) -> void:
	_stomp_left = _data.stomp_cooldown * (ENRAGE_STOMP_COOLDOWN_FACTOR if phase >= 2 else 1.0)


func stomp_radius(phase: int) -> float:
	return _data.stomp_radius * (ENRAGE_STOMP_RADIUS_FACTOR if phase >= 2 else 1.0)


func stomp_stun(phase: int) -> float:
	return minf(MAX_STUN, _data.enrage_stomp_stun if phase >= 2 else _data.stomp_stun)


## Wind-up of the stomp: the data value scaled like every telegraph, never below MIN_WARNING.
func stomp_warning(telegraph_multiplier: float) -> float:
	return maxf(MIN_WARNING, _data.stomp_telegraph_time * telegraph_multiplier)


## Damage of one pool tick from the scaled boss hit.
static func pool_damage(boss_hit: float) -> float:
	if boss_hit <= 0.0:
		return 0.0
	return maxf(DamageProcessor.MIN_DAMAGE, boss_hit * POOL_DAMAGE_FACTOR)


# --- Helpers ---

## Farthest targetable player that is out of melee reach, or null.
static func farthest_out_of_reach(players: Array, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := NEAR_DISTANCE
	for candidate: Variant in players:
		if not EnemyTargeting.is_targetable(candidate):
			continue
		var node := candidate as Node2D
		var distance := node.global_position.distance_to(from)
		if distance > best_distance:
			best_distance = distance
			best = node
	return best


func _track_velocity(player: Node2D, delta: float) -> void:
	var id := player.get_instance_id()
	var position := player.global_position
	if _positions.has(id) and delta > 0.0:
		var measured := (position - _positions[id]) / delta
		# A teleport (respawn after a fall, revive) is no walking speed.
		if measured.length() > 1200.0:
			measured = Vector2.ZERO
		_velocities[id] = _velocities.get(id, Vector2.ZERO).lerp(measured, VELOCITY_SMOOTHING)
	_positions[id] = position
