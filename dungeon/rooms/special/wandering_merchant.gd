class_name WanderingMerchant
extends SpecialContent
## Rare wandering merchant in a secret niche (A10, D-109): the shop's dialog and price formula
## (EconomySystem.get_price), but rarer goods: only mechanic and effect upgrades (pierce, bouncing,
## extra projectiles, explosive hits, ...), no plain stat bumps, no heal or shield. Offers are rolled
## once when the niche opens.

signal traded(merchant: WanderingMerchant)

const TEXTURE: Texture2D = preload("res://art/characters/npcs/wandering_merchant_idle_4f.png")
const FRAME := Vector2i(32, 32)
const PIVOT := Vector2(16, 30)
## Upgrades on offer. TESTWERT
const OFFER_COUNT := 3
## The rarer goods: upgrade categories the merchant sells (falls back to every upgrade). TESTWERT
const RARE_CATEGORIES: Array[UpgradeData.Category] = [UpgradeData.Category.MECHANIC, UpgradeData.Category.EFFECT]
const INTERACT_RADIUS := 72.0

var offers: Array[ShopOffer] = []


func _on_setup() -> void:
	add_light(150.0, Vector2(0, -24))
	add_animated(TEXTURE, FRAME, 4.0, PIVOT)
	add_blocker(Vector2(34, 18), Vector2(0, -9))
	var interactable := add_interactable(DungeonTexts.t(&"SECRET_MERCHANT_PROMPT"), INTERACT_RADIUS, Vector2(0, 8))
	interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"SECRET_MERCHANT_NAME"), Vector2(0, -92))
	if context != null and room != null:
		offers = roll_offers(context, room.room_index)


## Up to OFFER_COUNT different rare upgrades at the shop's upgrade price, drawn with the dungeon RNG.
static func roll_offers(dungeon_context: DungeonContext, room_index: int) -> Array[ShopOffer]:
	var result: Array[ShopOffer] = []
	if dungeon_context == null or dungeon_context.upgrade_manager == null or dungeon_context.rng == null:
		return result
	var available := dungeon_context.upgrade_manager.get_available_upgrades(dungeon_context.get_owned_weapons())
	var rare: Array[UpgradeData] = []
	for upgrade in available:
		if RARE_CATEGORIES.has(upgrade.category):
			rare.append(upgrade)
	var pool := rare if rare.size() >= OFFER_COUNT or available.size() <= rare.size() else _fill(rare, available)
	while not pool.is_empty() and result.size() < OFFER_COUNT:
		var offer := ShopOffer.new()
		offer.kind = ShopOffer.Kind.UPGRADE
		offer.upgrade = pool.pop_at(dungeon_context.rng.randi_range(0, pool.size() - 1))
		offer.price = dungeon_context.economy.get_price(ShopOffer.Kind.UPGRADE, room_index) if dungeon_context.economy != null else 0
		result.append(offer)
	return result


## Rare upgrades first; too few of them are topped up with the others.
static func _fill(rare: Array[UpgradeData], available: Array[UpgradeData]) -> Array[UpgradeData]:
	var pool: Array[UpgradeData] = rare.duplicate()
	for upgrade in available:
		if not pool.has(upgrade) and pool.size() < OFFER_COUNT:
			pool.append(upgrade)
	return pool


func _on_interacted(player: Player) -> void:
	var sold_before := _sold_count()
	await context.ui.open_shop(offers, player)
	if _sold_count() > sold_before:
		traded.emit(self)


func _sold_count() -> int:
	var sold := 0
	for offer in offers:
		if offer.sold:
			sold += 1
	return sold
