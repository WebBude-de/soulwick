extends SpecialContent
## Fountain: once and for free +3 HP up to max HP (D-037).

const FOUNTAIN_TEXTURE: Texture2D = preload("res://art/environment/props/fountain.png")
const HEAL_AMOUNT := 3.0

var _interactable: Interactable = null
var _sprite: Sprite2D = null


func _on_setup() -> void:
	add_light(170.0, Vector2(0, -30))
	_sprite = add_sprite(FOUNTAIN_TEXTURE, Vector2(16, 38))
	add_blocker(Vector2(52, 28), Vector2(0, -12))
	_interactable = add_interactable("Aus dem Brunnen trinken (+3 HP)", 56.0, Vector2(0, -20))
	_interactable.interacted.connect(_on_interacted)
	add_caption("Brunnen", Vector2(0, -96))


func _on_interacted(player: Player) -> void:
	player.health.heal(HEAL_AMOUNT)
	Sfx.play_at(self, &"heal", global_position)
	Burst.spawn(get_parent(), global_position + Vector2(0, -30), Color(0.4, 0.8, 1.0), 20, 140.0)
	_interactable.enabled = false
	_sprite.modulate = Color(0.6, 0.6, 0.7)
