extends GutTest
## Atomic purchases (D-038), shop composition (D-036), gold drop scaling.

const PLAYER_SCENE := preload("res://player/player.tscn")

var _economy: EconomySystem
var _upgrades: UpgradeManager
var _player: Player
var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_economy_save.cfg"


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func before_each() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	_economy = autofree(EconomySystem.new())
	_economy.config = EconomyConfig.new()
	_upgrades = autofree(UpgradeManager.new())
	_upgrades.upgrade_pool.append(load("res://upgrades/data/strong_attack.tres"))
	_player = add_child_autofree(PLAYER_SCENE.instantiate())


func _offer(kind: ShopOffer.Kind, price: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = kind
	offer.price = price
	offer.amount = 4.0
	return offer


func test_purchase_without_enough_gold_changes_nothing() -> void:
	RunManager.add_run_gold(5)
	var offer := _offer(ShopOffer.Kind.SHIELD, 10)
	assert_false(_economy.try_purchase(offer, _player, _upgrades))
	assert_eq(RunManager.get_run_gold(), 5)
	assert_eq(_player.shield.get_shield(), 0.0)
	assert_false(offer.sold)


func test_successful_purchase_spends_and_delivers() -> void:
	RunManager.add_run_gold(20)
	var offer := _offer(ShopOffer.Kind.SHIELD, 15)
	assert_true(_economy.try_purchase(offer, _player, _upgrades))
	assert_eq(RunManager.get_run_gold(), 5)
	assert_eq(_player.shield.get_shield(), 4.0)
	assert_false(_economy.try_purchase(offer, _player, _upgrades), "sold offers cannot be bought twice")


func test_heal_at_full_hp_is_not_purchasable() -> void:
	RunManager.add_run_gold(50)
	var offer := _offer(ShopOffer.Kind.HEAL, 10)
	offer.amount = 2.0
	assert_false(_economy.can_purchase(offer, _player, _upgrades))
	_player.health.take_damage(3.0)
	assert_true(_economy.try_purchase(offer, _player, _upgrades))
	assert_eq(_player.health.get_health(), 5.0)


func test_weapon_purchase_needs_valid_slot_and_no_duplicate_type() -> void:
	RunManager.add_run_gold(100)
	var offer := _offer(ShopOffer.Kind.WEAPON, 30)
	offer.weapon = load("res://weapons/data/sword.tres")
	assert_false(_economy.try_purchase(offer, _player, _upgrades, 1), "player already owns a sword")
	offer.weapon = load("res://weapons/data/bow.tres")
	assert_false(_economy.try_purchase(offer, _player, _upgrades, -1), "no slot chosen")
	assert_eq(RunManager.get_run_gold(), 100)
	assert_true(_economy.try_purchase(offer, _player, _upgrades, 1))
	assert_eq(_player.weapon_controller.get_weapon(1), offer.weapon)
	assert_eq(RunManager.get_run_gold(), 70)


func test_shop_has_at_most_six_valid_offers() -> void:
	var context := DungeonContext.new()
	context.player = _player
	context.upgrade_manager = _upgrades
	context.rng = RandomNumberGenerator.new()
	context.weapon_pool.assign([load("res://weapons/data/sword.tres"), load("res://weapons/data/bow.tres"), load("res://weapons/data/staff.tres")])
	var offers := _economy.generate_shop_offers(3, context)
	assert_lte(offers.size(), 6)
	var weapons := offers.filter(func(o: ShopOffer) -> bool: return o.kind == ShopOffer.Kind.WEAPON)
	assert_eq(weapons.size(), 2, "sword is owned, bow and staff are offered")
	var upgrades := offers.filter(func(o: ShopOffer) -> bool: return o.kind == ShopOffer.Kind.UPGRADE)
	assert_eq(upgrades.size(), 1, "only one upgrade is available in this pool, no filler")


func test_gold_drop_and_price_grow_per_block() -> void:
	# KE3 (KONZEPT §2): the depth bonus is back, +10 % gold per enemy per five-room block.
	var slime: EnemyData = load("res://enemies/data/slime.tres")
	var factor := _economy.config.gold_drop_factor
	assert_eq(_economy.get_gold_drop(slime, 1, false), maxi(1, roundi(slime.gold_drop * factor)))
	assert_eq(_economy.get_gold_drop(slime, 26, false), maxi(1, roundi(slime.gold_drop * factor * 1.5)), "block 5: +50 %")
	assert_eq(_economy.get_gold_drop(slime, 5, true), roundi(slime.gold_drop * factor * _economy.config.miniboss_gold_multiplier), "champions drop more")
	assert_gt(_economy.get_price(ShopOffer.Kind.UPGRADE, 30), _economy.get_price(ShopOffer.Kind.UPGRADE, 1))
