class_name MeleeHitbox
extends Hitbox
## Swing hitbox of melee weapons. Same attack-instance rules as Hitbox (one hit ID, each target at
## most once, D-020), plus a per-target backstab multiplier for the dagger: a hit counts as backstab
## when the target moves away from the attacker or the whole swing is an ambush (right after a dash).

signal backstab_landed(hurtbox: Hurtbox)

## TESTWERTE: a target faster than this has a readable movement direction.
const MIN_FACING_SPEED := 10.0
## Target velocity and direction to the attacker point apart at least this much (cos of ~105°).
const BEHIND_DOT := -0.25

## Damage multiplier for backstabs (situational, D-019); 1.0 disables backstabs.
var backstab_multiplier := 1.0
## The current swing started shortly after a dash: every hit is a backstab.
var ambush := false


## True when the target's body moves away from attacker_position (attacker is behind it).
static func is_behind(hurtbox: Hurtbox, attacker_position: Vector2) -> bool:
	var body := hurtbox.get_parent() as CharacterBody2D
	if body == null or body.velocity.length() < MIN_FACING_SPEED:
		return false
	var to_attacker := attacker_position - body.global_position
	if to_attacker == Vector2.ZERO:
		return false
	return body.velocity.normalized().dot(to_attacker.normalized()) < BEHIND_DOT


func _handle_contact(hurtbox: Hurtbox) -> void:
	var damage := _template.duplicate_for_target()
	var backstab := backstab_multiplier > 1.0 and (ambush or is_behind(hurtbox, global_position))
	if backstab:
		damage.amount *= backstab_multiplier
		damage.tags.append(&"backstab")
	damage.knockback = (hurtbox.global_position - global_position).normalized() * knockback_strength
	var result := hurtbox.receive_hit(damage)
	# Blocked hits do not consume the hit ID (D-054), same as Hitbox.
	if result.blocked:
		return
	_hit_targets[hurtbox.get_instance_id()] = true
	if backstab:
		backstab_landed.emit(hurtbox)
	hit_landed.emit(hurtbox, result)
