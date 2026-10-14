class_name LightPalette
extends RefCounted
## Colour of the light a LightSource throws (R6, "Licht ist Information"): warm = safe, cold = goal,
## red = danger. Pure optics, the light's gameplay meaning (LightQuery) does not depend on it.
## A LightSource with an explicit colour keeps it; otherwise its colour is derived once from the
## node that owns it (script class or node name), so existing lights get colours without touching
## their scripts. New lights simply set LightSource.color (e.g. spawn sources: DANGER).
## All colours and strengths are TESTWERTE.

## Torches, candles, braziers, campfire, lanterns, lamps.
const WARM := Color(1.0, 0.6, 0.28)
## Goals: crystals, soul flame, sockets, fountain.
const COLD := Color(0.42, 0.82, 1.0)
## Danger: enemy glows, gates, breaches, threat lights.
const DANGER := Color(1.0, 0.24, 0.18)
## Lava cracks, flame jets: hot but readable as fire.
const EMBER := Color(1.0, 0.42, 0.14)
## Treasure and gold.
const GOLD := Color(1.0, 0.8, 0.38)
## Magic: portals, pacts, wager altar, shadow wisps.
const VIOLET := Color(0.72, 0.45, 1.0)
## Poison and slime.
const TOXIC := Color(0.5, 1.0, 0.32)
## Flashes (explosions, openings) and unknown sources: almost white.
const NEUTRAL := Color(1.0, 0.92, 0.82)
## Biome torches with coloured flames (L1): the light matches the flame of the torch strip
## (room_controller swaps torch_4f for torch_green_4f / torch_purple_4f).
const FIRE_GREEN := Color(0.56, 1.0, 0.46)
const FIRE_VIOLET := Color(0.76, 0.52, 1.0)
## Torch strip file name part -> flame colour.
const FLAME_BY_STRIP := {
	"green": FIRE_GREEN,
	"purple": FIRE_VIOLET,
}

## Owner script class (or one of its base classes) -> colour.
const BY_CLASS := {
	&"LightIsland": WARM,
	&"RoomTorch": WARM,
	&"TrialTorch": WARM,
	&"CampfireContent": WARM,
	&"ShopContent": WARM,
	&"WanderingMerchant": WARM,
	&"Relic": GOLD,
	&"RelicAltar": GOLD,
	&"AnimatedProp": WARM,
	&"SoulFlame": COLD,
	&"SecretCrystal": COLD,
	&"FountainContent": COLD,
	&"TreasureChest": GOLD,
	&"TrialChest": GOLD,
	&"GoldPickup": GOLD,
	&"WeaponContent": GOLD,
	&"AltarContent": VIOLET,
	&"ExitPortal": VIOLET,
	&"WagerAltar": VIOLET,
	&"LavaCrack": EMBER,
	&"TrialFlameJet": EMBER,
	&"ToxicPuddle": TOXIC,
	&"WallBreach": DANGER,
	&"StoneGuardian": DANGER,
	&"Enemy": DANGER,
}
## Node name of the light -> colour (checked before the owner class).
const BY_NAME := {
	&"ThreatLight": DANGER,
	&"TorchLight": WARM,
	&"LampLight": WARM,
	&"Eyes": DANGER,
}
## How strongly a light tints what it touches (shader), per colour family. Flashes stay pale.
const DEFAULT_TINT := 1.0
const NEUTRAL_TINT := 0.35
const BIOME_FLAME_TINT := 0.75
## IngredientSet.LightStyle.CRYSTAL (kept as a number: this helper stays free of dungeon classes).
const CRYSTAL_STYLE := 0

## Glow halo (L1, TESTWERTE): strength of the additive "bloom" core a light draws around itself, per
## colour family. Flames and lava glow most, flashes stay pale.
const HALO_FIRE := 1.0
const HALO_EMBER := 1.15
const HALO_MAGIC := 0.9
const HALO_DIM := 0.7
const HALO_NEUTRAL := 0.6
## Node name -> halo, checked first: soft fills (the way light of a door cone) must not draw a blob.
const HALO_BY_NAME := {
	&"WayLight": 0.0,
	&"ThreatLight": 0.5,
	&"WindowLight": 0.8,
}
## Soul and magic lights breathe slowly (L1): amplitude of the intensity and period in seconds.
const BREATH_AMPLITUDE := 0.14
const BREATH_PERIOD := 2.6
## Fire lights flicker their brightness too (not only the radius): share of LightSource.flicker.
const FIRE_INTENSITY_FLICKER := 1.4


## Colour for a light: explicit colour if set (alpha > 0), else derived from its name and owner.
static func resolve(light: Node) -> Color:
	if light == null:
		return NEUTRAL
	var explicit: Variant = light.get(&"color")
	if explicit is Color and (explicit as Color).a > 0.0:
		return explicit
	var by_name: Variant = BY_NAME.get(StringName(light.name))
	if by_name != null:
		return by_name
	var owner_node := light.get_parent()
	# The light may hang one level deeper (e.g. a "Flame" child of a torch prop).
	for _i in 2:
		if owner_node == null:
			break
		if _is_crystal_island(owner_node):
			return COLD
		var flame := flame_color_of(owner_node)
		if flame.a > 0.0:
			return flame
		var found := color_for_class_of(owner_node)
		if found.a > 0.0:
			return found
		owner_node = owner_node.get_parent()
	return NEUTRAL


## Colour for the script class of node (walking up its base scripts); transparent if none matches.
static func color_for_class_of(node: Node) -> Color:
	var script: Script = node.get_script()
	while script != null:
		var class_id := script.get_global_name()
		if BY_CLASS.has(class_id):
			return BY_CLASS[class_id]
		script = script.get_base_script()
	return Color(0, 0, 0, 0)


## Flame colour of a torch prop whose strip is a coloured torch (green, purple); transparent if the
## node has no such strip.
static func flame_color_of(node: Node) -> Color:
	var strip: Variant = node.get(&"strip")
	if not strip is Texture2D:
		return Color(0, 0, 0, 0)
	var file := (strip as Texture2D).resource_path.get_file()
	if not file.begins_with("torch"):
		return Color(0, 0, 0, 0)
	for part in FLAME_BY_STRIP:
		if file.contains(part):
			return FLAME_BY_STRIP[part]
	return WARM


## A light island in crystal style (IngredientSet.LightStyle.CRYSTAL = 0) is a goal/orientation
## light (cold); the torch-stand style stays warm.
static func _is_crystal_island(node: Node) -> bool:
	var script: Script = node.get_script()
	if script == null or script.get_global_name() != &"LightIsland":
		return false
	var style: Variant = node.get(&"style")
	return style != null and int(style) == CRYSTAL_STYLE


## Shader tint strength for a colour: pale flashes tint less than coloured lights, the green and
## violet biome torches a little less than the rest (the flame colour stays readable, the walls do
## not turn neon).
static func tint_strength(color: Color) -> float:
	if color.is_equal_approx(NEUTRAL):
		return NEUTRAL_TINT
	if color.is_equal_approx(FIRE_GREEN) or color.is_equal_approx(FIRE_VIOLET):
		return BIOME_FLAME_TINT
	return DEFAULT_TINT


## Halo strength of a light as drawn (L1): an explicit LightSource.halo wins, then the node name, then
## the colour family.
static func halo_for(light: Node, color: Color) -> float:
	if light != null:
		var explicit: Variant = light.get(&"halo")
		if explicit != null and float(explicit) >= 0.0:
			return float(explicit)
		var by_name: Variant = HALO_BY_NAME.get(StringName(light.name))
		if by_name != null:
			return float(by_name)
	return halo_for_color(color)


static func halo_for_color(color: Color) -> float:
	if color.is_equal_approx(EMBER):
		return HALO_EMBER
	if is_fire(color):
		return HALO_FIRE
	if color.is_equal_approx(COLD) or color.is_equal_approx(VIOLET):
		return HALO_MAGIC
	if color.is_equal_approx(NEUTRAL):
		return HALO_NEUTRAL
	return HALO_DIM


## True for lights that breathe slowly (goals and magic: soul flame, crystals, portals).
static func breathes(color: Color) -> bool:
	return color.is_equal_approx(COLD) or color.is_equal_approx(VIOLET)


## True for lights whose brightness flickers like fire.
static func is_fire(color: Color) -> bool:
	return color.is_equal_approx(WARM) or color.is_equal_approx(EMBER) \
			or color.is_equal_approx(FIRE_GREEN) or color.is_equal_approx(FIRE_VIOLET)
