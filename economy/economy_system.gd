class_name EconomySystem
extends Node
## Prices, shop offers and purchase validation (D-036, D-038). Run gold itself is owned by
## RunManager; a purchase is atomic: validate -> spend -> deliver, or nothing changes.

@export var config: EconomyConfig


static func scale_by_block(base: float, room_index: int, growth_per_block: float) -> int:
	return roundi(base * (1.0 + growth_per_block * EnemyScaling.get_block(room_index)))


func get_gold_drop(enemy: EnemyData, room_index: int, is_miniboss: bool) -> int:
	var base := float(enemy.gold_drop) * config.gold_drop_factor * (config.miniboss_gold_multiplier if is_miniboss else 1.0)
	# Every enemy drops at least 1 gold.
	return maxi(1, scale_by_block(base, room_index, config.gold_growth_per_block))


func get_price(kind: ShopOffer.Kind, room_index: int) -> int:
	var base := config.shield_price
	match kind:
		ShopOffer.Kind.UPGRADE:
			base = config.upgrade_price
		ShopOffer.Kind.WEAPON:
			base = config.weapon_price
		ShopOffer.Kind.HEAL:
			base = config.heal_price
	return scale_by_block(base, room_index, config.price_growth_per_block)


## Up to six valid offers: 2 upgrades + 2 unowned weapons + heal + shield (D-036).
func generate_shop_offers(room_index: int, context: DungeonContext) -> Array[ShopOffer]:
	var offers: Array[ShopOffer] = []
	for upgrade in context.upgrade_manager.roll_offer(context.get_owned_weapons(), context.rng, config.upgrade_offers):
		var offer := _make_offer(ShopOffer.Kind.UPGRADE, room_index)
		offer.upgrade = upgrade
		offers.append(offer)
	var weapons := context.get_unowned_weapons()
	while not weapons.is_empty() and offers.size() < config.upgrade_offers + config.weapon_offers:
		var offer := _make_offer(ShopOffer.Kind.WEAPON, room_index)
		offer.weapon = weapons.pop_at(context.rng.randi_range(0, weapons.size() - 1))
		offers.append(offer)
	var heal := _make_offer(ShopOffer.Kind.HEAL, room_index)
	heal.amount = config.heal_amount
	offers.append(heal)
	var shield := _make_offer(ShopOffer.Kind.SHIELD, room_index)
	shield.amount = config.shield_amount
	offers.append(shield)
	return offers


## weapon_slot: target slot for weapon offers (needed when both slots are taken).
func can_purchase(offer: ShopOffer, player: Player, upgrades: UpgradeManager, weapon_slot := -1) -> bool:
	if offer.sold or player == null or RunManager.get_run_gold() < offer.price:
		return false
	return can_deliver(offer, player, upgrades, weapon_slot)


func can_deliver(offer: ShopOffer, player: Player, upgrades: UpgradeManager, weapon_slot := -1) -> bool:
	match offer.kind:
		ShopOffer.Kind.UPGRADE:
			return upgrades != null and not upgrades.is_maxed(offer.upgrade)
		ShopOffer.Kind.WEAPON:
			var controller := player.weapon_controller
			return not controller.has_weapon_type(offer.weapon.weapon_type) and controller.can_equip(offer.weapon, weapon_slot)
		ShopOffer.Kind.HEAL:
			return player.health.get_health() < player.health.get_max_health()
	return true


func try_purchase(offer: ShopOffer, player: Player, upgrades: UpgradeManager, weapon_slot := -1) -> bool:
	if not can_purchase(offer, player, upgrades, weapon_slot):
		return false
	if not RunManager.try_spend_run_gold(offer.price):
		return false
	match offer.kind:
		ShopOffer.Kind.UPGRADE:
			upgrades.acquire_upgrade(offer.upgrade)
		ShopOffer.Kind.WEAPON:
			player.weapon_controller.equip_weapon(offer.weapon, weapon_slot)
		ShopOffer.Kind.HEAL:
			player.health.heal(offer.amount)
		ShopOffer.Kind.SHIELD:
			player.shield.add_shield(offer.amount)
	offer.sold = true
	return true


func _make_offer(kind: ShopOffer.Kind, room_index: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.kind = kind
	offer.price = get_price(kind, room_index)
	return offer
