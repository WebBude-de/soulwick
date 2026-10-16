extends SpecialContent
## Shop: counter with merchant; offers are rolled once when the room is entered (D-036). The
## merchant already stands behind the counter while the room is prepared (playtest #9).

const COUNTER_TEXTURE: Texture2D = preload("res://art/environment/props/shop_counter.png")
const MERCHANT_TEXTURE: Texture2D = preload("res://art/environment/props/merchant_idle_4f.png")

var _offers: Array[ShopOffer] = []


func _on_prepare() -> void:
	add_light(200.0, Vector2(0, -20))
	add_animated(MERCHANT_TEXTURE, Vector2i(32, 32), 4.0, Vector2(16, 30), Vector2(0, -28))
	add_sprite(COUNTER_TEXTURE, Vector2(32, 30))
	add_blocker(Vector2(120, 36), Vector2(0, -16))
	var interactable := add_interactable(DungeonTexts.t(&"SHOP_PROMPT"), 64.0, Vector2(0, 10))
	interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"ROOM_SHOP_TITLE"), Vector2(0, -110))


func _on_setup() -> void:
	_offers = context.economy.generate_shop_offers(room.room_index, context)


func _on_interacted(player: Player) -> void:
	await context.ui.open_shop(_offers, player)
