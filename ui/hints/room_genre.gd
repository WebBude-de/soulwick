class_name RoomGenre
extends RefCounted
## Room genres (D-110): rooms with gameplay of their own show their name as a banner when entered,
## and the first time per save a short explanation card. Normal combat rooms (every shape) stay
## unnamed. One table: genre -> texts (DungeonTexts keys), banner group, colour and symbol.
## Pure: describe() reads a room once, resolve() decides from that, so tests need no rooms.
##
## Ambush arenas look empty on entry: they resolve to NONE and are named when they spring
## (RoomController.arena_started, DungeonUI.on_arena_started). Combat variants and the wager altar
## (A7) are prepared: a room that answers get_variant_id() -> StringName (e.g. &"soul_flame") or
## has_wager_altar() -> true gets that genre.

enum Group { COMBAT, SPECIAL, TRIAL, REST, WAGER }

const NONE: StringName = &""
const ARENA: StringName = WaveRules.INTRO_GENRE_ARENA
const AMBUSH: StringName = WaveRules.INTRO_GENRE_AMBUSH
const CATACOMB: StringName = &"catacomb"
const CHASM: StringName = &"chasm"
const TRIAL_GAUNTLET: StringName = &"trial_gauntlet"
const TRIAL_LIGHT_RUN: StringName = &"trial_light_run"
const TRIAL_CRUMBLE: StringName = &"trial_crumble"
const PACT_ALTAR: StringName = &"pact_altar"
const UPGRADE_ALTAR: StringName = &"upgrade_altar"
const WAGER_ALTAR: StringName = &"wager_altar"
const CAMPFIRE: StringName = &"campfire"
const SHOP: StringName = &"shop"
const WEAPON: StringName = &"weapon"
const FOUNTAIN: StringName = &"fountain"
## A secret niche opened behind a cracked wall (A10): no room of its own, named when it opens.
const SECRET: StringName = &"secret"
## SaveManager seen id of the first-time card: "room_intro_<genre>" (D-110).
const SEEN_PREFIX := "room_intro_"

const WAVE_ICON := "res://art/environment/rooms/wave_banner_icon.png"
const SKULL_ICON := "res://art/ui/skull_icon.png"
const CROWN_ICON := "res://art/environment/variants/bounty_crown.png"
const WAGER_ICONS := "res://art/environment/variants/wager_icons.png"

## key: prefix of the DungeonTexts keys (<key>_TITLE, <key>_SUB, <key>_INTRO); icon: a file, a door
## symbol (DoorStyle.SYMBOLS, "door:<id>") or ""; tint: colour the (grey) symbol in the genre colour.
const TABLE: Dictionary[StringName, Dictionary] = {
	# Arena: crossed swords in red like its door (07_ui.md, RoomObjective.MODES).
	ARENA: {"key": "ROOM_ARENA", "group": Group.COMBAT, "color": Color("#e0463a"), "icon": "mode:arena", "tint": true},
	AMBUSH: {"key": "ROOM_AMBUSH", "group": Group.COMBAT, "color": Color("#e0463a"), "icon": WAVE_ICON, "tint": true},
	CATACOMB: {"key": "ROOM_CATACOMB", "group": Group.COMBAT, "color": Color("#b8b09a"), "icon": SKULL_ICON, "tint": false},
	CHASM: {"key": "ROOM_CHASM", "group": Group.COMBAT, "color": Color("#6cb2ec"), "icon": "", "tint": false},
	TRIAL_GAUNTLET: {"key": "ROOM_TRIAL_GAUNTLET", "group": Group.TRIAL, "color": Color("#f2cf4a"), "icon": "door:trial", "tint": true},
	TRIAL_LIGHT_RUN: {"key": "ROOM_TRIAL_LIGHT_RUN", "group": Group.TRIAL, "color": Color("#ffd166"), "icon": "door:trial", "tint": true},
	TRIAL_CRUMBLE: {"key": "ROOM_TRIAL_CRUMBLE", "group": Group.TRIAL, "color": Color("#b9b3c9"), "icon": "door:trial", "tint": true},
	PACT_ALTAR: {"key": "ROOM_PACT", "group": Group.SPECIAL, "color": Color("#a66ef0"), "icon": "door:upgrade", "tint": true},
	UPGRADE_ALTAR: {"key": "ROOM_UPGRADE_ALTAR", "group": Group.SPECIAL, "color": Color("#f2cf4a"), "icon": "door:upgrade", "tint": true},
	WAGER_ALTAR: {"key": "ROOM_WAGER", "group": Group.WAGER, "color": Color("#dcbcff"), "icon": "wager:1", "tint": true},
	CAMPFIRE: {"key": "ROOM_CAMPFIRE", "group": Group.REST, "color": Color("#ff8a3c"), "icon": "door:campfire", "tint": true},
	SHOP: {"key": "ROOM_SHOP", "group": Group.SPECIAL, "color": Color("#f2cf4a"), "icon": "door:shop", "tint": true},
	WEAPON: {"key": "ROOM_WEAPON", "group": Group.SPECIAL, "color": Color("#a98cf5"), "icon": "door:weapon", "tint": true},
	FOUNTAIN: {"key": "ROOM_FOUNTAIN", "group": Group.SPECIAL, "color": Color("#6cb2ec"), "icon": "door:fountain", "tint": true},
	# Combat variants (A7, KONZEPT_RAEUME §4): ids proposed for get_variant_id().
	&"soul_flame": {"key": "ROOM_SOUL_FLAME", "group": Group.COMBAT, "color": Color("#a66ef0"), "icon": "", "tint": false},
	&"rifts": {"key": "ROOM_RIFTS", "group": Group.COMBAT, "color": Color("#7ff0c8"), "icon": "", "tint": false},
	&"stone_guardian": {"key": "ROOM_STONE_GUARDIAN", "group": Group.COMBAT, "color": Color("#9a94b5"), "icon": "", "tint": false},
	&"lantern": {"key": "ROOM_LANTERN", "group": Group.COMBAT, "color": Color("#ffd166"), "icon": "", "tint": false},
	&"gravedigger": {"key": "ROOM_GRAVEDIGGER", "group": Group.COMBAT, "color": Color("#b8b09a"), "icon": SKULL_ICON, "tint": false},
	&"bounty": {"key": "ROOM_BOUNTY", "group": Group.COMBAT, "color": Color("#f2cf4a"), "icon": CROWN_ICON, "tint": false},
	&"torch_room": {"key": "ROOM_TORCH_ROOM", "group": Group.COMBAT, "color": Color("#ff8a3c"), "icon": "", "tint": false},
	&"elite_nest": {"key": "ROOM_ELITE_NEST", "group": Group.COMBAT, "color": Color("#e0b84a"), "icon": "door:elite_nest", "tint": false},
	# Way-finding (A10): the secret niche, named when its wall breaks.
	SECRET: {"key": "ROOM_SECRET", "group": Group.COMBAT, "color": Color("#c9b8ff"), "icon": "", "tint": false},
	# Room modes v2 (KONZEPT_RAEUME_V2 §2, R3): announced by their RoomIntro, not by show_room_genre;
	# the entries carry the first-time card. Ids and colours as RoomObjective.MODES (Lichtfeuer lifted
	# for the dark card). "Risse schließen" (RoomObjective.RIFTS) uses the entry &"rifts" above until
	# R4b turns the variant into the mode.
	&"escort": {"key": "MODE_ESCORT", "group": Group.COMBAT, "color": Color("#ffd166"), "icon": "mode:escort", "tint": true},
	&"flame": {"key": "MODE_FLAME", "group": Group.COMBAT, "color": Color("#8f78e0"), "icon": "mode:flame", "tint": true},
	&"relic": {"key": "MODE_RELIC", "group": Group.COMBAT, "color": Color("#f2cf4a"), "icon": "mode:relic", "tint": true},
	&"souls": {"key": "MODE_SOULS", "group": Group.COMBAT, "color": Color("#2fb391"), "icon": "mode:souls", "tint": true},
	&"hunt": {"key": "MODE_HUNT", "group": Group.COMBAT, "color": Color("#ff8a3c"), "icon": "mode:hunt", "tint": true},
	&"lightfire": {"key": "MODE_LIGHTFIRE", "group": Group.COMBAT, "color": Color("#a48a85"), "icon": "mode:lightfire", "tint": true},
	&"collapse": {"key": "MODE_COLLAPSE", "group": Group.COMBAT, "color": Color("#8c8f9a"), "icon": "mode:collapse", "tint": true},
}

const TRIAL_GENRES := {
	SpecialTable.TrialKind.GAUNTLET: TRIAL_GAUNTLET,
	SpecialTable.TrialKind.LIGHT_RUN: TRIAL_LIGHT_RUN,
	SpecialTable.TrialKind.CRUMBLE: TRIAL_CRUMBLE,
}


# --- Decision ---

## Facts about a room that decide its genre (see resolve). Reads the room once; works for every
## room type (special content and template are looked up, A7 hooks are duck-typed).
static func describe(room: RoomController) -> Dictionary:
	var info := {
		"campfire": false, "room_type": -1, "special_type": -1, "room_kind": -1, "combat": false,
		"arena": false, "ambush": false, "catacomb": false, "trial_kind": -1, "pact": false,
		"variant": NONE, "wager": false,
	}
	if room == null or not is_instance_valid(room):
		return info
	info["campfire"] = room.is_campfire()
	info["room_type"] = int(room.room_type)
	info["special_type"] = room.special_type
	info["combat"] = room.has_room_kind()
	info["room_kind"] = int(room.room_kind)
	info["arena"] = room.is_arena_room()
	info["ambush"] = room.is_ambush_room()
	var template := RoomTemplate.of(room) if room.has_room_kind() else null
	info["catacomb"] = template != null and template.shape == RoomTemplate.Shape.CATACOMB
	for child in room.get_children():
		if child is TrialContent:
			info["trial_kind"] = int((child as TrialContent).kind)
		elif child is SpecialContent and child.get(&"is_pact") == true:
			info["pact"] = true
	if room.has_method(&"get_variant_id"):
		info["variant"] = StringName(room.call(&"get_variant_id"))
	if room.has_method(&"has_wager_altar"):
		info["wager"] = bool(room.call(&"has_wager_altar"))
	return info


## Genre of a room from describe(); NONE = no banner (normal combat rooms, boss rooms, an ambush
## that has not sprung yet).
static func resolve(info: Dictionary) -> StringName:
	if info.get("campfire", false):
		return CAMPFIRE
	var variant: StringName = info.get("variant", NONE)
	if variant != NONE and TABLE.has(variant):
		return variant
	if info.get("wager", false):
		return WAGER_ALTAR
	var room_type: int = info.get("room_type", -1)
	if room_type == RoomSequence.RoomType.SPECIAL:
		var trial_kind: int = info.get("trial_kind", -1)
		if trial_kind >= 0:
			return TRIAL_GENRES.get(trial_kind, TRIAL_GAUNTLET)
		match int(info.get("special_type", -1)):
			RoomSequence.SpecialType.SHOP:
				return SHOP
			RoomSequence.SpecialType.WEAPON:
				return WEAPON
			RoomSequence.SpecialType.FOUNTAIN:
				return FOUNTAIN
			RoomSequence.SpecialType.UPGRADE:
				return PACT_ALTAR if info.get("pact", false) else UPGRADE_ALTAR
			SpecialTable.TRIAL:
				return TRIAL_GAUNTLET
		return NONE
	if not info.get("combat", false):
		return NONE
	var kind: int = info.get("room_kind", -1)
	if kind == RoomSequence.RoomKind.ARENA and info.get("arena", false):
		# An ambush keeps its secret until the door closes (named by DungeonUI.on_arena_started).
		return NONE if info.get("ambush", false) else ARENA
	if kind == RoomSequence.RoomKind.CHASM:
		return CHASM
	if info.get("catacomb", false):
		return CATACOMB
	return NONE


static func of_room(room: RoomController) -> StringName:
	return resolve(describe(room))


# --- Texts and look ---

static func has_genre(genre: StringName) -> bool:
	return genre != NONE and TABLE.has(genre)


static func get_title(genre: StringName) -> String:
	return DungeonTexts.t(StringName(_key(genre) + "_TITLE")) if has_genre(genre) else ""


## Short banner line. room (optional) fills in details such as the next biome at the campfire.
static func get_subtitle(genre: StringName, room: RoomController = null) -> String:
	if not has_genre(genre):
		return ""
	if genre == CAMPFIRE:
		var next: BiomeData = room.get_next_biome() if room != null and is_instance_valid(room) else null
		if next != null:
			return DungeonTexts.t(&"ROOM_CAMPFIRE_SUB", [next.display_name])
		return DungeonTexts.t(&"ROOM_CAMPFIRE_SUB_PLAIN")
	if get_group(genre) == Group.TRIAL:
		return DungeonTexts.t(&"ROOM_TRIAL_SUB")
	return DungeonTexts.t(StringName(_key(genre) + "_SUB"))


## The first-time explanation (1-2 sentences, D-110).
static func get_intro(genre: StringName) -> String:
	if not has_genre(genre):
		return ""
	match genre:
		CHASM:
			return DungeonTexts.t(&"ROOM_CHASM_INTRO", [ControlsInfo.key_text(ControlsInfo.DASH)])
		CAMPFIRE:
			return DungeonTexts.t(&"ROOM_CAMPFIRE_INTRO" if DungeonManager.CAMPFIRE_EXIT_PORTAL else &"ROOM_CAMPFIRE_INTRO_NO_PORTAL")
	return DungeonTexts.t(StringName(_key(genre) + "_INTRO"))


## Eyebrow over the banner title: "RAUM 7 · KAMPFRAUM", "RAST ZWISCHEN DEN GEBIETEN".
static func get_eyebrow(genre: StringName, room_index: int) -> String:
	if not has_genre(genre):
		return ""
	match get_group(genre):
		Group.SPECIAL:
			return DungeonTexts.t(&"ROOM_EYEBROW_SPECIAL", [room_index])
		Group.TRIAL:
			return DungeonTexts.t(&"ROOM_EYEBROW_TRIAL", [room_index])
		Group.REST:
			return DungeonTexts.t(&"ROOM_EYEBROW_REST")
		Group.WAGER:
			return DungeonTexts.t(&"ROOM_EYEBROW_WAGER", [room_index])
	return DungeonTexts.t(&"ROOM_EYEBROW_COMBAT", [room_index])


static func get_group(genre: StringName) -> Group:
	return (TABLE[genre] as Dictionary).get("group", Group.COMBAT) if has_genre(genre) else Group.COMBAT


static func get_color(genre: StringName) -> Color:
	return (TABLE[genre] as Dictionary).get("color", UiKit.COLOR_GOLD) if has_genre(genre) else UiKit.COLOR_GOLD


## Banner symbol (null if the genre has none yet); tinted symbols are grey art coloured by modulate.
static func get_icon(genre: StringName) -> Texture2D:
	if not has_genre(genre):
		return null
	var spec: String = (TABLE[genre] as Dictionary).get("icon", "")
	if spec.is_empty():
		return null
	if spec.begins_with("door:"):
		return DoorArt.get_symbol(StringName(spec.trim_prefix("door:")))
	if spec.begins_with("mode:"):
		return RoomObjective.get_mode_icon(StringName(spec.trim_prefix("mode:")))
	if spec.begins_with("wager:"):
		if not ResourceLoader.exists(WAGER_ICONS):
			return null
		var atlas := AtlasTexture.new()
		atlas.atlas = load(WAGER_ICONS) as Texture2D
		atlas.region = Rect2(int(spec.trim_prefix("wager:")) * 16, 0, 16, 16)
		return atlas
	return load(spec) as Texture2D if ResourceLoader.exists(spec) else null


static func is_icon_tinted(genre: StringName) -> bool:
	return has_genre(genre) and (TABLE[genre] as Dictionary).get("tint", false)


# --- First time per save ---

static func get_seen_id(genre: StringName) -> StringName:
	return StringName(SEEN_PREFIX + String(genre))


## True while this save has not seen the explanation of the genre.
static func should_explain(genre: StringName) -> bool:
	return has_genre(genre) and not SaveManager.has_seen(get_seen_id(genre))


static func mark_explained(genre: StringName) -> void:
	if has_genre(genre):
		SaveManager.mark_seen(get_seen_id(genre))


static func _key(genre: StringName) -> String:
	return String((TABLE[genre] as Dictionary).get("key", ""))
