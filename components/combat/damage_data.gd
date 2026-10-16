class_name DamageData
extends RefCounted
## One hit before DamageProcessor resolves it. amount is D_raw: all modifiers applied, not yet rounded.

enum Origin { PRIMARY, SECONDARY }

static var _next_hit_id := 1

var amount := 0.0
var source: Node = null
var tags: Array[StringName] = []
## SECONDARY hits must never trigger further secondary effects (D-030).
var origin := Origin.PRIMARY
## Identifies one attack instance; the same instance never affects the same target twice (D-020).
var hit_id := 0
## Velocity impulse in px/s applied to the target.
var knockback := Vector2.ZERO
## Centre of an area hit; secondary explosions of one AOE are placed there (D-031).
var impact_position := Vector2.ZERO
var has_impact_position := false
## Status effects on the player; only applied by effective (not blocked) hits (D-017, D-066, D-067).
var stun_duration := 0.0
var blind_duration := 0.0
## Slow (SlowStatus, D-148): move speed factor and seconds; 1.0 / 0.0 = no slow. Like stun and blind
## only with effective hits.
var slow_factor := 1.0
var slow_duration := 0.0


static func next_hit_id() -> int:
	var id := _next_hit_id
	_next_hit_id += 1
	return id


func duplicate_for_target() -> DamageData:
	var copy := DamageData.new()
	copy.amount = amount
	# A projectile can outlive its shooter: a freed source becomes no source.
	copy.source = source if is_instance_valid(source) else null
	copy.tags.assign(tags)
	copy.origin = origin
	copy.hit_id = hit_id
	copy.knockback = knockback
	copy.impact_position = impact_position
	copy.has_impact_position = has_impact_position
	copy.stun_duration = stun_duration
	copy.blind_duration = blind_duration
	copy.slow_factor = slow_factor
	copy.slow_duration = slow_duration
	return copy
