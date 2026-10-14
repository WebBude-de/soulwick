class_name Hitbox
extends Area2D
## Attacking side of a hit. One begin_attack() call is one attack instance with its own hit ID and
## hit history, so the instance damages each target at most once (D-020). Overlaps are polled
## every physics frame, which also catches targets that already overlapped when the attack began.

signal hit_landed(hurtbox: Hurtbox, result: DamageResult)

@export var knockback_strength := 0.0

var _active := false
var _template: DamageData = null
var _hit_targets: Dictionary[int, bool] = {}
## Physics frames to wait after begin_attack(): overlaps are only refreshed by the next physics
## step, so polling immediately would still report targets at the hitbox's previous position.
var _settle_frames := 0


func _ready() -> void:
	monitoring = true
	monitorable = false


func begin_attack(template: DamageData) -> void:
	_template = template
	_template.hit_id = DamageData.next_hit_id()
	_hit_targets.clear()
	_active = true
	_settle_frames = 1


func end_attack() -> void:
	_active = false
	_template = null


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if _active and _settle_frames > 0:
		_settle_frames -= 1
		return
	if not _active:
		return
	for area in get_overlapping_areas():
		if not _active:
			break
		var hurtbox := area as Hurtbox
		if hurtbox == null or _hit_targets.has(hurtbox.get_instance_id()):
			continue
		_handle_contact(hurtbox)


## Default contact: deal direct damage. Subclasses (e.g. AOE projectiles) override this.
func _handle_contact(hurtbox: Hurtbox) -> void:
	var damage := _template.duplicate_for_target()
	damage.knockback = (hurtbox.global_position - global_position).normalized() * knockback_strength
	var result := hurtbox.receive_hit(damage)
	# A blocked hit did not take effect, so the same attack may still land once the target is vulnerable.
	if result.blocked:
		return
	_hit_targets[hurtbox.get_instance_id()] = true
	hit_landed.emit(hurtbox, result)
