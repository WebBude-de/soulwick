extends SpecialContent
## Weapon choice: up to two weapons the player does not own; taking one may replace a slot (D-022).
## The weapons are picked when the room is prepared, so they already float over their pedestals
## (playtest #9); one the player has got since is gone when the room is entered.

## Animated pedestal (4 frames of 32x32, SPRITES_V4 delivery).
const PEDESTAL_STRIP: Texture2D = preload("res://art/environment/props/weapon_pedestal_4f.png")
const MAX_WEAPONS := 2
const PEDESTAL_SPACING := 150.0
## Weapon floats 10 art px above the pedestal (art note), plus a gentle bob.
const WEAPON_HEIGHT := 56.0

var _pedestals: Array[Dictionary] = []
var _taken := false


func _on_prepare() -> void:
	var weapons := context.get_unowned_weapons()
	while weapons.size() > MAX_WEAPONS:
		weapons.remove_at(context.rng.randi_range(0, weapons.size() - 1))
	if weapons.is_empty():
		add_caption(DungeonTexts.t(&"WEAPON_NONE_LEFT"), Vector2(0, -40))
		return
	add_caption(DungeonTexts.t(&"WEAPON_ROOM_CAPTION"), Vector2(0, -130))
	add_light(240.0, Vector2(0, -30))
	for i in weapons.size():
		var x := (float(i) - float(weapons.size() - 1) * 0.5) * PEDESTAL_SPACING
		_add_pedestal(weapons[i], Vector2(x, 0))


func _on_setup() -> void:
	var player := context.player if context != null else null
	if player == null or not is_instance_valid(player):
		return
	for pedestal in _pedestals:
		var weapon: WeaponData = pedestal["weapon"]
		if player.weapon_controller.has_weapon_type(weapon.weapon_type):
			(pedestal["interactable"] as Interactable).enabled = false
			(pedestal["sprite"] as Sprite2D).visible = false


func _process(_delta: float) -> void:
	var bob := sin(Time.get_ticks_msec() / 300.0) * 4.0
	for pedestal in _pedestals:
		var sprite: Sprite2D = pedestal["sprite"]
		sprite.position.y = pedestal["base_y"] + bob


func _add_pedestal(weapon: WeaponData, at: Vector2) -> void:
	add_animated(PEDESTAL_STRIP, Vector2i(32, 32), 6.0, Vector2(16, 30), at)
	add_blocker(Vector2(40, 20), at + Vector2(0, -8))
	# Same base line as the pedestal (drawn after it), floating WEAPON_HEIGHT above inside its holder.
	var weapon_sprite := add_sprite(weapon.sprite, Vector2(16, 16), at)
	weapon_sprite.position.y -= WEAPON_HEIGHT
	weapon_sprite.rotation = -PI / 4.0
	weapon_sprite.modulate = weapon.tint
	weapon_sprite.scale *= weapon.sprite_scale
	var interactable := add_interactable(DungeonTexts.t(&"WEAPON_TAKE", [DataTexts.weapon_name(weapon)]), 48.0, at + Vector2(0, -20))
	interactable.interacted.connect(_on_pedestal_used.bind(weapon))
	_pedestals.append({"sprite": weapon_sprite, "base_y": weapon_sprite.position.y, "interactable": interactable, "weapon": weapon})


func _on_pedestal_used(player: Player, weapon: WeaponData) -> void:
	if _taken:
		return
	var controller := player.weapon_controller
	var slot := controller.find_free_slot()
	if slot < 0:
		slot = await context.ui.choose_weapon_slot(weapon, player)
		if slot < 0:
			return
	if not controller.equip_weapon(weapon, slot):
		return
	# Only one weapon per room: the other one vanishes.
	_taken = true
	for pedestal in _pedestals:
		(pedestal["interactable"] as Interactable).enabled = false
		(pedestal["sprite"] as Sprite2D).visible = false
