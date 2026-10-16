extends SpecialContent
## Extra upgrade: one free choice out of up to three available upgrades.
## In a third of these rooms (SpecialTable.pact_chance) a pact altar stands instead (KONZEPT_RAEUME
## §6.2): the player takes the normal extra upgrade or seals a pact, an upgrade from a better offer
## (more cards, one stack more) against a curse for the rest of the run. The altar shows the price
## before the choice. Curses lie on the player who seals the pact (PlayerCurses, co-op: only them).
## Every player chooses once. take_choice() decides, choice_taken carries it to the effects.

signal choice_taken(player: Player, upgrade: UpgradeData, curse: int)

## Animated altar (4 frames of 32x48, SPRITES_V4 delivery).
const ALTAR_STRIP: Texture2D = preload("res://art/environment/props/upgrade_altar_4f.png")
## Better offer of a pact (TESTWERTE): the chosen upgrade gains PACT_STACKS stacks, and the offer
## prefers upgrades that can still take all of them (no "1 / 1" cards).
const PACT_OFFER_SIZE := 3
const PACT_STACKS := 2
const PACT_COLOR := Color(0.75, 0.5, 1.0)
const PACT_LIGHT_RADIUS := 150.0
## Short explanation line for the first-time explanation of the pact altar, built centrally by UX2
## (D-110); the altar itself shows none. Translation key (D-111).
const PACT_INTRO_KEY := &"ROOM_PACT_INTRO"

## -1 = roll with the dungeon RNG, 0 = normal altar, 1 = pact altar (tests, screenshots).
var forced_pact := -1
var is_pact := false
## Curse the pact demands (PlayerCurses.Curse), rolled when the room is built; -1 = no pact.
var pact_curse := -1

var _interactable: Interactable = null
var _sprite: AnimatedProp = null
var _chosen: Dictionary[int, bool] = {}
var _choosing := false


## Pact or plain altar is rolled when the room is prepared: the altar stands there before anyone enters.
func _on_prepare() -> void:
	if forced_pact >= 0:
		is_pact = forced_pact == 1
	else:
		is_pact = SpecialTable.load_default().roll_pact(context.rng)
	if is_pact:
		pact_curse = context.rng.randi_range(0, PlayerCurses.Curse.size() - 1)
		_build_pact_altar()
	else:
		_build_altar()
	choice_taken.connect(_on_choice_taken)


func _build_altar() -> void:
	add_light(170.0, Vector2(0, -40))
	_sprite = add_animated(ALTAR_STRIP, Vector2i(32, 48), 6.0, Vector2(16, 46))
	add_blocker(Vector2(44, 24), Vector2(0, -10))
	_interactable = add_interactable(DungeonTexts.t(&"ALTAR_PROMPT"), 56.0, Vector2(0, -24))
	_interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"ROOM_UPGRADE_ALTAR_TITLE"), Vector2(0, -116))


func _build_pact_altar() -> void:
	var light := add_light(PACT_LIGHT_RADIUS, Vector2(0, -50))
	light.flicker = 0.1
	_sprite = add_animated(TrialArt.get_texture(TrialArt.PACT_ALTAR), TrialArt.get_frame_size(TrialArt.PACT_ALTAR), 6.0, TrialArt.get_pivot(TrialArt.PACT_ALTAR))
	add_blocker(Vector2(44, 24), Vector2(0, -10))
	_interactable = add_interactable(DungeonTexts.t(&"PACT_PROMPT"), 56.0, Vector2(0, -24))
	_interactable.interacted.connect(_on_interacted)
	var title := add_caption(DungeonTexts.t(&"ROOM_PACT_TITLE"), Vector2(0, -132))
	title.add_theme_color_override("font_color", PACT_COLOR)
	var price := add_caption(DungeonTexts.t(&"PACT_PRICE", [PlayerCurses.get_curse_effect(pact_curse)]), Vector2(0, -110))
	price.add_theme_font_size_override("font_size", 13)
	price.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
	_add_curse_icon(Vector2(0, -160))


func has_chosen(player: Player) -> bool:
	return player != null and _chosen.has(player.get_instance_id())


## Curse a pact costs this player: the rolled one, or the next one they can still take
## (-1 = no pact possible for them).
func get_curse_for(player: Player) -> int:
	if not is_pact:
		return -1
	if PlayerCurses.can_take(player, pact_curse as PlayerCurses.Curse):
		return pact_curse
	var available := PlayerCurses.get_available(player)
	return available[0] if not available.is_empty() else -1


## The one choice of a player: upgrade with curse -1 (normal) or with the pact's curse. Returns false
## if not allowed: already chosen, no upgrade, a pact on a normal altar or a curse they cannot take.
func take_choice(player: Player, upgrade: UpgradeData, curse: int = -1) -> bool:
	if player == null or upgrade == null or has_chosen(player):
		return false
	if curse >= 0 and (not is_pact or curse != get_curse_for(player)):
		return false
	_chosen[player.get_instance_id()] = true
	choice_taken.emit(player, upgrade, curse)
	_update_interactable()
	return true


func _on_interacted(player: Player) -> void:
	if _choosing or has_chosen(player):
		return
	_choosing = true
	var pact := false
	var curse := get_curse_for(player)
	if is_pact:
		var pick := await _ask_pact(curse)
		if pick < 0 or not is_instance_valid(player):
			# Esc: the altar waits, the player may come back.
			_choosing = false
			return
		pact = pick == 1
	var owned := player.weapon_controller.get_owned_weapons()
	var offer := roll_pact_offer(owned) if pact else context.upgrade_manager.roll_offer(owned, context.rng)
	if offer.is_empty():
		_choosing = false
		_interactable.enabled = false
		_sprite.modulate = Color(0.6, 0.6, 0.7)
		add_caption(DungeonTexts.t(&"UPGRADES_NONE"), Vector2(0, -140))
		return
	var title := DungeonTexts.t(&"PACT_DETAIL") if pact else DungeonTexts.t(&"ROOM_PACT_TITLE" if is_pact else &"ROOM_UPGRADE_ALTAR_TITLE")
	var choice: UpgradeData = await context.ui.choose_upgrade(offer, title, PACT_STACKS if pact else 1)
	_choosing = false
	if choice != null and is_instance_valid(player):
		take_choice(player, choice, curse if pact else -1)


## The better offer of a pact: PACT_OFFER_SIZE upgrades that can take PACT_STACKS more stacks,
## filled up with other available ones if there are not enough (dungeon RNG).
func roll_pact_offer(owned: Array[WeaponData]) -> Array[UpgradeData]:
	var manager := context.upgrade_manager
	var strong: Array[UpgradeData] = []
	var rest: Array[UpgradeData] = []
	for upgrade in manager.get_available_upgrades(owned):
		if not upgrade.is_limited() or upgrade.max_stacks - manager.get_stacks(upgrade.id) >= PACT_STACKS:
			strong.append(upgrade)
		else:
			rest.append(upgrade)
	var offer: Array[UpgradeData] = []
	for pool: Array[UpgradeData] in [strong, rest]:
		while not pool.is_empty() and offer.size() < PACT_OFFER_SIZE:
			offer.append(pool.pop_at(context.rng.randi_range(0, pool.size() - 1)))
	return offer


## 0 = normal extra upgrade, 1 = pact, -1 = Esc.
func _ask_pact(curse: int) -> int:
	var options: Array = [{"text": DungeonTexts.t(&"PACT_OPTION_PLAIN"), "sub": DungeonTexts.t(&"PACT_OPTION_PLAIN_SUB"), "color": UiKit.COLOR_GOLD}]
	var details: Array = []
	var text := DungeonTexts.t(&"PACT_QUESTION")
	if curse >= 0:
		options.append({"text": DungeonTexts.t(&"PACT_OPTION_PACT"), "sub": DungeonTexts.t(&"PACT_OPTION_CURSE", [PlayerCurses.get_curse_name(curse)]), "color": UiKit.COLOR_DANGER_SOFT})
		details = [
			[DungeonTexts.t(&"PACT_DETAIL"), DungeonTexts.t(&"PACT_DETAIL_VALUE", [PACT_STACKS]), UiKit.COLOR_GOLD],
			[DungeonTexts.t(&"PACT_DETAIL_CURSE"), PlayerCurses.get_curse_effect(curse), UiKit.COLOR_DANGER_SOFT],
		]
	else:
		text = DungeonTexts.t(&"PACT_NOTHING")
	var footnote := DungeonTexts.t(&"PACT_FOOTNOTE") if curse >= 0 else ""
	return await context.ui.choose_option(DungeonTexts.t(&"ROOM_PACT_TITLE"), text, details, options, true, footnote)


## Effects of a choice: the upgrade (one stack, or PACT_STACKS for a pact) and the curse.
func _on_choice_taken(player: Player, upgrade: UpgradeData, curse: int) -> void:
	var stacks := PACT_STACKS if curse >= 0 else 1
	for i in stacks:
		context.upgrade_manager.acquire_upgrade(upgrade)
	if curse >= 0:
		PlayerCurses.ensure(player).add_curse(curse as PlayerCurses.Curse)
		Sfx.play_at(self, &"blind", global_position)
		Burst.spawn(get_parent(), global_position + Vector2(0, -50), PACT_COLOR, 24, 150.0)
		if context.ui != null:
			context.ui.show_banner(DungeonTexts.t(&"PACT_DONE"), "%s: %s" % [PlayerCurses.get_curse_name(curse), PlayerCurses.get_curse_effect(curse)], PACT_COLOR)
	else:
		Sfx.play_at(self, &"upgrade", global_position)


## The altar stays usable until every player has chosen.
func _update_interactable() -> void:
	for player in get_players():
		if not has_chosen(player):
			return
	_interactable.enabled = false
	_sprite.modulate = Color(0.6, 0.6, 0.7)


func _add_curse_icon(offset_position: Vector2) -> void:
	var icon := Sprite2D.new()
	icon.texture = CurseArt.get_icon(pact_curse)
	icon.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	icon.position = offset_position
	icon.z_index = 30
	add_child(icon)
