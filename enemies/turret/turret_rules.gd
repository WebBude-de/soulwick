class_name TurretRules
extends RefCounted
## Pure rules of the stationary turret (D-151): target choice, cadence and aim, without nodes,
## physics or drawing. The top-down Turret uses them, a side-view turret (M5 segments) can use the
## same object with its own body and look: feed tick() the direction to the target (or ZERO), fire
## when it returns true.
## Cadence: IDLE (watching) -> CHARGE (the telegraph: it lights up, the aim follows the target until
## AIM_LOCK_TIME before the shot, then holds) -> shot -> COOLDOWN -> IDLE. A target lost while the
## aim still follows breaks the charge off; after the lock the shot goes anyway.
## All numbers are TESTWERTE (D-151).

enum Phase { IDLE, CHARGE, COOLDOWN }

## Seconds from coming out of the ground to the first possible charge.
const FIRST_SHOT_DELAY := 0.8
## Seconds between two target choices (nearest living player in range and sight).
const RETARGET_INTERVAL := 0.25
## The aim holds this long before the shot (the telegraph line no longer moves).
const AIM_LOCK_TIME := 0.2
## A charge broken off by a lost target: look again after this pause.
const LOST_TARGET_RETRY := 0.3
## Depth makes the cadence faster (EnemyScaling.cooldown_multiplier), but never below this factor.
const MIN_COOLDOWN_FACTOR := 0.75
## The shot flies this many times the sight range before it fades.
const SHOT_DISTANCE_FACTOR := 1.6
## What a hit does to the player: speed x0.65 (-35 %) for 2.0 s, refreshed, never stacked.
## The damage stays the minimum hit (turret data damage 0.1 = 0.5 up to room 90): it slows, it
## does not kill.
const SLOW_FACTOR := 0.65  # TESTWERT (D-151)
const SLOW_DURATION := 2.0  # TESTWERT (D-151 follow-up: 1.5 -> 2.0, pressure through the slow instead of damage)

var sight_range := 300.0
var charge_time := 0.6
var cooldown := 1.8
var phase := Phase.IDLE
var time_left := FIRST_SHOT_DELAY
## Unit direction of the next (or last) shot.
var aim := Vector2.RIGHT
var shots := 0


func _init(range_px := 300.0, charge := 0.6, cooldown_time := 1.8, first_delay := FIRST_SHOT_DELAY) -> void:
	sight_range = range_px
	charge_time = maxf(0.05, charge)
	cooldown = maxf(0.0, cooldown_time)
	time_left = maxf(0.0, first_delay)


## Rules for an EnemyData (attack_range, telegraph_time, attack_cooldown) in a room: telegraph and
## cooldown scale with depth like every enemy's (D-074), the cooldown not below MIN_COOLDOWN_FACTOR.
static func for_data(data: EnemyData, room_index: int) -> TurretRules:
	var cooldown_factor := maxf(MIN_COOLDOWN_FACTOR, EnemyScaling.cooldown_multiplier(room_index))
	return TurretRules.new(data.attack_range, data.telegraph_time * EnemyScaling.telegraph_multiplier(room_index),
			data.attack_cooldown * cooldown_factor)


## One step. target_direction: unit direction to the target, Vector2.ZERO without a target in range
## and sight. Returns true in the step the shot leaves (along aim).
func tick(delta: float, target_direction: Vector2) -> bool:
	time_left -= delta
	var has_target := target_direction != Vector2.ZERO
	match phase:
		Phase.IDLE:
			if has_target:
				aim = target_direction.normalized()
				if time_left <= 0.0:
					phase = Phase.CHARGE
					time_left = charge_time
		Phase.CHARGE:
			if not is_aim_locked():
				if not has_target:
					phase = Phase.IDLE
					time_left = LOST_TARGET_RETRY
					return false
				aim = target_direction.normalized()
			if time_left <= 0.0:
				phase = Phase.COOLDOWN
				time_left = cooldown
				shots += 1
				return true
		Phase.COOLDOWN:
			# It keeps watching its target, so the next charge starts facing it.
			if has_target:
				aim = target_direction.normalized()
			if time_left <= 0.0:
				phase = Phase.IDLE
				time_left = 0.0
	return false


func is_charging() -> bool:
	return phase == Phase.CHARGE


## Charging and so close to the shot that the aim holds.
func is_aim_locked() -> bool:
	return phase == Phase.CHARGE and time_left <= AIM_LOCK_TIME


## 0 at the start of a charge, 1 at the shot (0 outside a charge).
func get_charge_progress() -> float:
	if phase != Phase.CHARGE:
		return 0.0
	return clampf(1.0 - time_left / charge_time, 0.0, 1.0)


## Seconds from one shot to the next while the target stays in sight.
func get_shot_interval() -> float:
	return charge_time + cooldown


func get_shot_distance() -> float:
	return sight_range * SHOT_DISTANCE_FACTOR


## Nearest candidate that can be targeted (alive, not protected, EnemyTargeting), lies within
## range_px of from and passes can_see (Callable(node) -> bool, e.g. a wall ray; invalid = always).
## Candidates may hold freed or dead nodes. Null if there is none.
static func choose_target(candidates: Array, from: Vector2, range_px: float, can_see: Callable = Callable()) -> Node2D:
	var in_range: Array[Node2D] = []
	var distances: Array[float] = []
	for candidate: Variant in candidates:
		if not EnemyTargeting.is_targetable(candidate):
			continue
		var node := candidate as Node2D
		var distance := from.distance_to(node.global_position)
		if distance > range_px:
			continue
		# Insertion by distance: few players, no sort with a lambda over freed nodes.
		var at := 0
		while at < distances.size() and distances[at] <= distance:
			at += 1
		in_range.insert(at, node)
		distances.insert(at, distance)
	for node in in_range:
		if not can_see.is_valid() or bool(can_see.call(node)):
			return node
	return null


## Unit direction from one point to another (RIGHT when they coincide).
static func direction_to(from: Vector2, to: Vector2) -> Vector2:
	var offset := to - from
	return offset / offset.length() if offset.length() > 0.001 else Vector2.RIGHT
