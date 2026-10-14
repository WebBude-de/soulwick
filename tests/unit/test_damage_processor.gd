extends GutTest
## DamageProcessor rules: D-017, D-018, DECISIONS §6.


func _make_health(max_health: float) -> HealthComponent:
	var health: HealthComponent = autofree(HealthComponent.new())
	health.reset(max_health)
	return health


func _make_shield(amount: float) -> ShieldComponent:
	var shield: ShieldComponent = autofree(ShieldComponent.new())
	shield.add_shield(amount)
	return shield


func _make_damage(amount: float) -> DamageData:
	var damage := DamageData.new()
	damage.amount = amount
	return damage


func test_rounds_once_to_half_steps() -> void:
	assert_eq(DamageProcessor.round_damage(12.0), 12.0)
	assert_eq(DamageProcessor.round_damage(12.3), 12.5)
	assert_eq(DamageProcessor.round_damage(12.2), 12.0)
	assert_eq(DamageProcessor.round_damage(16.8), 17.0)


func test_positive_damage_is_at_least_half() -> void:
	assert_eq(DamageProcessor.round_damage(0.1), 0.5)


func test_zero_or_negative_damage_is_zero() -> void:
	assert_eq(DamageProcessor.round_damage(0.0), 0.0)
	assert_eq(DamageProcessor.round_damage(-3.0), 0.0)


func test_shield_absorbs_before_health() -> void:
	var health := _make_health(6.0)
	var shield := _make_shield(2.0)
	var result := DamageProcessor.process_hit(_make_damage(3.0), health, shield, false)
	assert_eq(result.shield_damage, 2.0)
	assert_eq(result.health_damage, 1.0)
	assert_eq(shield.get_shield(), 0.0)
	assert_eq(health.get_health(), 5.0)


func test_shield_only_hit_is_effective() -> void:
	var health := _make_health(6.0)
	var shield := _make_shield(10.0)
	var result := DamageProcessor.process_hit(_make_damage(1.0), health, shield, false)
	assert_true(result.is_effective(), "Shield-only damage must count as effective (starts I-frames)")
	assert_eq(health.get_health(), 6.0)


func test_blocked_hit_changes_nothing() -> void:
	var health := _make_health(6.0)
	var shield := _make_shield(4.0)
	var result := DamageProcessor.process_hit(_make_damage(3.0), health, shield, true)
	assert_true(result.blocked)
	assert_false(result.is_effective())
	assert_eq(health.get_health(), 6.0)
	assert_eq(shield.get_shield(), 4.0)


func test_dead_target_is_blocked() -> void:
	var health := _make_health(1.0)
	DamageProcessor.process_hit(_make_damage(5.0), health, null, false)
	var second := DamageProcessor.process_hit(_make_damage(5.0), health, null, false)
	assert_true(second.blocked)


func test_kill_emits_died_once() -> void:
	var health := _make_health(6.0)
	watch_signals(health)
	var result := DamageProcessor.process_hit(_make_damage(10.0), health, null, false)
	DamageProcessor.process_hit(_make_damage(10.0), health, null, false)
	assert_true(result.killed)
	assert_eq(result.health_damage, 6.0, "Applied HP loss is capped at remaining HP")
	assert_signal_emit_count(health, "died", 1)


func test_target_without_shield_takes_full_health_damage() -> void:
	var health := _make_health(20.0)
	var result := DamageProcessor.process_hit(_make_damage(12.0), health, null, false)
	assert_eq(result.health_damage, 12.0)
	assert_eq(health.get_health(), 8.0)


func test_hit_ids_are_unique() -> void:
	var first := DamageData.next_hit_id()
	var second := DamageData.next_hit_id()
	assert_ne(first, second)


func test_duplicate_for_target_keeps_hit_id_and_tags() -> void:
	var damage := _make_damage(5.0)
	damage.hit_id = 42
	damage.tags.assign([&"melee"])
	damage.origin = DamageData.Origin.SECONDARY
	var copy := damage.duplicate_for_target()
	assert_eq(copy.hit_id, 42)
	assert_eq(copy.tags, damage.tags)
	assert_eq(copy.origin, DamageData.Origin.SECONDARY)
	copy.tags.append(&"extra")
	assert_eq(damage.tags.size(), 1, "Copy must not share the tag array")
