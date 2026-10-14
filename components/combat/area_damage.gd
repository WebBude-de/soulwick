class_name AreaDamage
extends RefCounted
## Circular area hits (staff impact, later the "Explosiver Treffer" upgrade).
## Every hurtbox in the circle receives the same hit ID exactly once.
## Must be called from _physics_process: the physics space is locked inside collision callbacks.

const MAX_TARGETS := 32


static func apply(context: Node2D, center: Vector2, radius: float, hurtbox_mask: int, template: DamageData, knockback_strength: float) -> Array[DamageResult]:
	var results: Array[DamageResult] = []
	if radius <= 0.0 or template == null:
		return results

	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = hurtbox_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits := context.get_world_2d().direct_space_state.intersect_shape(query, MAX_TARGETS)
	var already_hit: Dictionary[int, bool] = {}
	for hit in hits:
		var hurtbox := hit["collider"] as Hurtbox
		if hurtbox == null or already_hit.has(hurtbox.get_instance_id()):
			continue
		already_hit[hurtbox.get_instance_id()] = true
		var damage := template.duplicate_for_target()
		damage.knockback = (hurtbox.global_position - center).normalized() * knockback_strength
		damage.impact_position = center
		damage.has_impact_position = true
		results.append(hurtbox.receive_hit(damage))
	return results
