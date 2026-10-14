class_name Hurtbox
extends Area2D
## Receiving side of a hit. Holds independent invulnerability reasons (e.g. dash and hit I-frames, D-016).

signal hit_received(result: DamageResult, damage: DamageData)

@export var health: HealthComponent
@export var shield: ShieldComponent

var _invulnerability_reasons: Dictionary[StringName, bool] = {}


func _ready() -> void:
	monitoring = false
	monitorable = true


func set_invulnerable(reason: StringName, enabled: bool) -> void:
	if enabled:
		_invulnerability_reasons[reason] = true
	else:
		_invulnerability_reasons.erase(reason)


func is_invulnerable() -> bool:
	return not _invulnerability_reasons.is_empty()


## Blocked hits cause neither damage nor damage-dependent effects, so no signal is emitted (D-017).
func receive_hit(damage: DamageData) -> DamageResult:
	var result := DamageProcessor.process_hit(damage, health, shield, is_invulnerable())
	if not result.blocked:
		hit_received.emit(result, damage)
	return result
