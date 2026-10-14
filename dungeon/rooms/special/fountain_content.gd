extends SpecialContent
## Fountain: once and for free +3 HP up to max HP (D-037). A player under the pact curse
## "Versiegte Quellen" gets only part of it (PlayerCurses.fountain_heal_factor).

## Animated fountain (4 frames of 32x40, SPRITES_V4 delivery).
const FOUNTAIN_STRIP: Texture2D = preload("res://art/environment/props/fountain_4f.png")
const HEAL_AMOUNT := 3.0

var _interactable: Interactable = null
var _sprite: AnimatedProp = null


func _on_setup() -> void:
	add_light(170.0, Vector2(0, -30))
	_sprite = add_animated(FOUNTAIN_STRIP, Vector2i(32, 40), 6.0, Vector2(16, 38))
	add_blocker(Vector2(52, 28), Vector2(0, -12))
	_interactable = add_interactable(DungeonTexts.t(&"FOUNTAIN_PROMPT", [DamageNumber.format_amount(get_heal_amount(context.player))]), 56.0, Vector2(0, -20))
	_interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"ROOM_FOUNTAIN_TITLE"), Vector2(0, -96))


## Heal for this player: the full amount, halved by the fountain curse (in 0.5 steps).
static func get_heal_amount(player: Player) -> float:
	return DamageProcessor.round_to_step(HEAL_AMOUNT * PlayerCurses.fountain_heal_factor(player))


func _on_interacted(player: Player) -> void:
	player.health.heal(get_heal_amount(player))
	Sfx.play_at(self, &"heal", global_position)
	Burst.spawn(get_parent(), global_position + Vector2(0, -30), Color(0.4, 0.8, 1.0), 20, 140.0)
	_interactable.enabled = false
	_sprite.modulate = Color(0.6, 0.6, 0.7)
