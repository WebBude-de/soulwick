class_name VillageBuildings
extends RefCounted
## Facts about the enterable village buildings (D-078, D-087): display name, the one-sentence role
## (shown on first entry and permanently as dialog subtitle), a few short how-to lines for the
## first-entry explanation, the door prompt, the NPC sprite of the building and the door sign.
## All texts are translation keys (D-111); the getters return them in the current language. Also decides whether a
## building still has to explain itself; the "seen" flags are stored by SaveManager.
## Zuhause (MM1) is the player's own house: no NPC (the explanation shows the player's character),
## its door opens the wardrobe ("Umkleiden").

const FORGE: StringName = &"forge"
const TRADER: StringName = &"trader"
const CHRONICLE: StringName = &"chronicle"
const GUILD: StringName = &"guild"
const HOME: StringName = &"home"
## The four D-087 buildings with an NPC.
const ORDER: Array[StringName] = [FORGE, TRADER, CHRONICLE, GUILD]
## Every building with a door dialog.
const ALL: Array[StringName] = [FORGE, TRADER, CHRONICLE, GUILD, HOME]

## Seen-flag prefix in the save ([seen] ids), e.g. "intro_forge".
const INTRO_PREFIX := "intro_"

## "role" is the exact sentence from D-087. "hints" explain how the building works with facts from
## existing decisions (payout D-039, crystals D-078, multiplayer D-078/D-081).
const INFO := {
	FORGE: {
		"name": &"VILLAGE_FORGE",
		"role": &"VILLAGE_FORGE_ROLE",
		"hints": [&"VILLAGE_FORGE_HINT_1", &"VILLAGE_FORGE_HINT_2"],
		"prompt": &"VILLAGE_FORGE_ENTER",
		"npc_frames": "res://art/characters/npcs/smith_frames.tres",
		"sign": "res://art/ui/sign_forge.png",
	},
	TRADER: {
		"name": &"VILLAGE_TRADER",
		"role": &"VILLAGE_TRADER_ROLE",
		"hints": [&"VILLAGE_TRADER_HINT_1", &"VILLAGE_TRADER_HINT_2"],
		"prompt": &"VILLAGE_TRADER_ENTER",
		"npc_frames": "res://art/characters/npcs/trader_frames.tres",
		"sign": "res://art/ui/sign_trading.png",
	},
	CHRONICLE: {
		"name": &"VILLAGE_CHRONICLE",
		"role": &"VILLAGE_CHRONICLE_ROLE",
		"hints": [&"VILLAGE_CHRONICLE_HINT_1"],
		"prompt": &"VILLAGE_CHRONICLE_ENTER",
		"npc_frames": "res://art/characters/npcs/chronicler_frames.tres",
		"sign": "res://art/ui/sign_chronicle.png",
	},
	GUILD: {
		"name": &"VILLAGE_GUILD",
		"role": &"VILLAGE_GUILD_ROLE",
		"hints": [&"VILLAGE_GUILD_HINT_1", &"VILLAGE_GUILD_HINT_2"],
		"prompt": &"VILLAGE_GUILD_ENTER",
		"npc_frames": "res://art/characters/npcs/guild_master_frames.tres",
		"sign": "res://art/ui/sign_guild.png",
	},
	# MM1: texts by Claude (not part of D-087); the sign is still missing (SPRITES_V3, placeholder).
	HOME: {
		"name": &"VILLAGE_HOME",
		"role": &"VILLAGE_HOME_ROLE",
		"hints": [&"VILLAGE_HOME_HINT_1", &"VILLAGE_HOME_HINT_2"],
		"prompt": &"VILLAGE_HOME_ENTER",
		"npc_frames": "",
		"sign": "res://art/ui/sign_home.png",
	},
}
## Dungeon entrance in the village (not a building with a dialog): caption and door prompt.
const DUNGEON_NAME: StringName = &"VILLAGE_DUNGEON"
const DUNGEON_PROMPT: StringName = &"VILLAGE_DUNGEON_ENTER"


static func has_building(id: StringName) -> bool:
	return INFO.has(id)


static func get_display_name(id: StringName) -> String:
	return Loc.t(INFO[id]["name"]) if INFO.has(id) else String(id)


## The one-sentence role from D-087 (empty for unknown ids).
static func get_role(id: StringName) -> String:
	return Loc.t(INFO[id]["role"]) if INFO.has(id) else ""


static func get_hints(id: StringName) -> Array[String]:
	var result: Array[String] = []
	if INFO.has(id):
		for hint: StringName in INFO[id]["hints"]:
			result.append(Loc.t(hint))
	return result


## Translation key of the building name (for Labels that translate by themselves, e.g. the caption).
static func get_name_key(id: StringName) -> StringName:
	return INFO[id]["name"] if INFO.has(id) else StringName(id)


## Door prompt of the open building ("Schmiede betreten", Zuhause: "Umkleiden").
static func get_prompt(id: StringName) -> String:
	return Loc.t(INFO[id]["prompt"]) if INFO.has(id) else ""


## NPC of the building; null for Zuhause (no NPC) or missing art.
static func get_npc_frames(id: StringName) -> SpriteFrames:
	if not INFO.has(id) or String(INFO[id]["npc_frames"]).is_empty() or not ResourceLoader.exists(INFO[id]["npc_frames"]):
		return null
	return load(INFO[id]["npc_frames"]) as SpriteFrames


## Door sign art; null while the file is missing (the village then shows a placeholder).
static func get_sign_texture(id: StringName) -> Texture2D:
	if not INFO.has(id) or not ResourceLoader.exists(INFO[id]["sign"]):
		return null
	return load(INFO[id]["sign"]) as Texture2D


# --- First-entry explanation (D-087) ---

static func get_intro_key(id: StringName) -> StringName:
	return StringName(INTRO_PREFIX + String(id))


## True while the building has not explained itself yet.
static func needs_intro(id: StringName) -> bool:
	return INFO.has(id) and not SaveManager.has_seen(get_intro_key(id))


## Stores that the explanation was shown (and saves). Returns false if it was already seen.
static func mark_intro_seen(id: StringName) -> bool:
	if not needs_intro(id):
		return false
	SaveManager.mark_seen(get_intro_key(id))
	SaveManager.save_game()
	return true
