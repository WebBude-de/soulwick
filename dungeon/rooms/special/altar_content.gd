extends SpecialContent
## Extra upgrade: one free choice out of up to three available upgrades.

const ALTAR_TEXTURE: Texture2D = preload("res://art/environment/props/upgrade_altar.png")

var _interactable: Interactable = null
var _sprite: Sprite2D = null


func _on_setup() -> void:
	add_light(170.0, Vector2(0, -40))
	_sprite = add_sprite(ALTAR_TEXTURE, Vector2(16, 46))
	add_blocker(Vector2(44, 24), Vector2(0, -10))
	_interactable = add_interactable("Upgrade wählen", 56.0, Vector2(0, -24))
	_interactable.interacted.connect(_on_interacted)
	add_caption("Upgrade-Altar", Vector2(0, -116))


func _on_interacted(player: Player) -> void:
	var offer := context.upgrade_manager.roll_offer(player.weapon_controller.get_owned_weapons(), context.rng)
	_interactable.enabled = false
	_sprite.modulate = Color(0.6, 0.6, 0.7)
	if offer.is_empty():
		add_caption("Keine Upgrades verfügbar", Vector2(0, -140))
		return
	var choice: UpgradeData = await context.ui.choose_upgrade(offer, "Upgrade-Altar")
	if choice != null:
		context.upgrade_manager.acquire_upgrade(choice)
