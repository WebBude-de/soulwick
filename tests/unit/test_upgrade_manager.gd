extends GutTest
## Upgrade rules: tag matching (D-028), stack limits (D-029), distinct offers (D-027), modifiers.

var _manager: UpgradeManager
var _sword: WeaponData
var _bow: WeaponData
var _staff: WeaponData


func before_each() -> void:
	_manager = autofree(UpgradeManager.new())
	for path in DirAccess.get_files_at("res://upgrades/data/"):
		if path.ends_with(".tres"):
			_manager.upgrade_pool.append(load("res://upgrades/data/" + path))
	_sword = load("res://weapons/data/sword.tres")
	_bow = load("res://weapons/data/bow.tres")
	_staff = load("res://weapons/data/staff.tres")


func _upgrade(id: StringName) -> UpgradeData:
	for upgrade in _manager.upgrade_pool:
		if upgrade.id == id:
			return upgrade
	return null


func test_pool_has_exactly_fifteen_upgrades() -> void:
	assert_eq(_manager.upgrade_pool.size(), 15)


func test_or_tag_matching() -> void:
	var precise := _upgrade(&"precise_arrows")
	assert_true(precise.applies_to(_bow.tags))
	assert_false(precise.applies_to(_sword.tags))
	assert_true(_upgrade(&"strong_attack").applies_to(_sword.tags), "no tags = every attack")


func test_required_tags_must_all_match() -> void:
	var upgrade := UpgradeData.new()
	upgrade.applicable_tags.assign([&"projectile"])
	upgrade.required_tags.assign([&"magic", &"aoe"])
	assert_true(upgrade.applies_to(_staff.tags))
	assert_false(upgrade.applies_to(_bow.tags), "bow is a projectile but not magic")


func test_stack_limits() -> void:
	var pierce := _upgrade(&"pierce")
	for i in 3:
		assert_true(_manager.acquire_upgrade(pierce))
	assert_false(_manager.acquire_upgrade(pierce), "Durchschlag max 3")
	assert_eq(_manager.get_stacks(&"pierce"), 3)
	assert_true(_manager.acquire_upgrade(_upgrade(&"double_shot")))
	assert_false(_manager.acquire_upgrade(_upgrade(&"double_shot")), "Doppelschuss max 1")
	for i in 5:
		assert_true(_manager.acquire_upgrade(_upgrade(&"strong_attack")), "attributes are unlimited")


func test_maxed_upgrades_are_not_offered() -> void:
	var bounce := _upgrade(&"wall_bounce")
	_manager.acquire_upgrade(bounce)
	var owned: Array[WeaponData] = [_bow]
	assert_false(_manager.get_available_upgrades(owned).has(bounce))


func test_offer_is_distinct_and_at_most_three() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var owned: Array[WeaponData] = [_sword, _bow]
	for i in 50:
		var offer := _manager.roll_offer(owned, rng)
		assert_lte(offer.size(), 3)
		var ids := {}
		for upgrade in offer:
			ids[upgrade.id] = true
		assert_eq(ids.size(), offer.size(), "no duplicates in one offer")


func test_irrelevant_upgrades_are_not_offered() -> void:
	var owned: Array[WeaponData] = [_sword]
	var available := _manager.get_available_upgrades(owned)
	assert_false(available.has(_upgrade(&"precise_arrows")), "no bow upgrades without a bow")
	assert_true(available.has(_upgrade(&"strength_training")))


func test_modifiers_sum_per_attack_tags() -> void:
	_manager.acquire_upgrade(_upgrade(&"strong_attack"))
	_manager.acquire_upgrade(_upgrade(&"strong_attack"))
	_manager.acquire_upgrade(_upgrade(&"precise_arrows"))
	assert_almost_eq(_manager.get_modifier(UpgradeData.Effect.DAMAGE_PERCENT, _bow.tags), 0.4, 0.0001)
	assert_almost_eq(_manager.get_modifier(UpgradeData.Effect.DAMAGE_PERCENT, _sword.tags), 0.2, 0.0001)


func test_on_kill_totals() -> void:
	_manager.acquire_upgrade(_upgrade(&"heal_on_kill"))
	_manager.acquire_upgrade(_upgrade(&"heal_on_kill"))
	assert_eq(_manager.get_total(UpgradeData.Effect.HEAL_ON_KILL), 1.0, "+0.5 HP per kill and stack (D-074)")
