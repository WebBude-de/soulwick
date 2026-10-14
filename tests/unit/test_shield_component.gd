extends GutTest
## Shield softcap (D-014, threshold retuned to 15 in D-074).


func test_gain_below_softcap_is_full() -> void:
	assert_eq(ShieldComponent.compute_gain(0.0, 10.0), 10.0)
	assert_eq(ShieldComponent.compute_gain(5.0, 10.0), 10.0)


func test_gain_crossing_softcap() -> void:
	# 10 shield + requested 10 -> 5 normal + 2.5 halved = 7.5
	assert_eq(ShieldComponent.compute_gain(10.0, 10.0), 7.5)


func test_gain_above_softcap_is_halved() -> void:
	assert_eq(ShieldComponent.compute_gain(20.0, 10.0), 5.0)


func test_gain_is_rounded_to_half_steps() -> void:
	assert_eq(ShieldComponent.compute_gain(15.0, 3.0), 1.5)
	assert_eq(ShieldComponent.compute_gain(15.0, 1.0), 0.5)


func test_add_shield_applies_softcap() -> void:
	var shield: ShieldComponent = autofree(ShieldComponent.new())
	shield.add_shield(10.0)
	shield.add_shield(10.0)
	assert_eq(shield.get_shield(), 17.5)


func test_small_gains_above_softcap_are_halved_with_carry() -> void:
	# D-091: 0.5 above the softcap is worth 0.25; two such gains add up to 0.5 instead of 1.0.
	var shield: ShieldComponent = autofree(ShieldComponent.new())
	shield.add_shield(20.0)
	var start := shield.get_shield()
	assert_eq(shield.add_shield(0.5), 0.0)
	assert_eq(shield.add_shield(0.5), 0.5)
	assert_eq(shield.get_shield(), start + 0.5)


func test_add_shield_up_to_never_exceeds_cap() -> void:
	var shield: ShieldComponent = autofree(ShieldComponent.new())
	for i in 40:
		shield.add_shield_up_to(0.5, 10.0)
	assert_eq(shield.get_shield(), 10.0)
	assert_eq(shield.add_shield_up_to(0.5, 10.0), 0.0)


func test_absorb_never_goes_negative() -> void:
	var shield: ShieldComponent = autofree(ShieldComponent.new())
	shield.add_shield(4.0)
	assert_eq(shield.absorb(10.0), 4.0)
	assert_eq(shield.get_shield(), 0.0)
	assert_eq(shield.absorb(1.0), 0.0)
