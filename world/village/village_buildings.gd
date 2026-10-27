class_name VillageBuildings
extends RefCounted
## Facts about the enterable village buildings (D-078, D-087): display name, the one-sentence role
## (the dialog's subtitle), a few short how-to lines, the door prompt, the NPC sprite of the building
## and the door sign. All texts are translation keys (D-111); the getters return them in the current
## language. Also decides whether a building still has to explain itself (the "intro_<id>" flag of
## the world in SaveManager, and the account's Flint flag, VillageTour); since WK9 Flint says the
## explanation (VillageTour.building_explanation), not a card.
## Zuhause (MM1) is the player's own house: no NPC, its door leads inside ("Eintreten", KE8,
## enter_home), where Flint explains the altar.

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
	# KE8: the door leads inside (HOME_INSIDE_TEXTS, enter_home).
	HOME: {
		"name": &"VILLAGE_HOME",
		"role": &"VILLAGE_HOME_INSIDE_ROLE",
		"hints": [&"VILLAGE_HOME_INSIDE_HINT_1", &"VILLAGE_HOME_INSIDE_HINT_2"],
		"prompt": &"VILLAGE_HOME_INSIDE_ENTER",
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


## Door prompt of the open building ("Schmiede betreten", Zuhause: "Eintreten").
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


## True while the building has not explained itself yet: not in this world (old saves count as
## explained, D-087) and not to this account (Flint explained it in another world, WK9).
static func needs_intro(id: StringName) -> bool:
	if not INFO.has(id) or SaveManager.has_seen(get_intro_key(id)):
		return false
	return not AccountSeen.has_seen(VillageTour.account_seen_id(id))


## Stores in this world that the explanation was heard (and saves). False if the world had it.
static func mark_intro_seen(id: StringName) -> bool:
	if not INFO.has(id) or SaveManager.has_seen(get_intro_key(id)):
		return false
	SaveManager.mark_seen(get_intro_key(id))
	SaveManager.save_game()
	return true


# --- KE8: the home's door leads inside (HomeTravel, world/village/home/) ---

## The open door of the home (second state of home.png, same size, warm light in the frame).
const HOME_DOOR_OPEN_ART := "res://art/environment/buildings/home_door_open.png"
## Texts of the home now that its door leads inside (INFO[HOME] uses them).
const HOME_INSIDE_TEXTS := {
	"role": &"VILLAGE_HOME_INSIDE_ROLE",
	"hints": [&"VILLAGE_HOME_INSIDE_HINT_1", &"VILLAGE_HOME_INSIDE_HINT_2"],
	"prompt": &"VILLAGE_HOME_INSIDE_ENTER",
}


## The home's door (Village.enter_building): alone the door opens and the interior loads
## (HomeTravel); in a group session the talent tree opens read-only on the village's dialog layer
## (KE8 Koop-Check: guests never respec). The home counts as explained from now on
## (Flint explains the altar inside, FlintExplanation "flint_home_altar").
static func enter_home(village: Node) -> void:
	mark_intro_seen(HOME)
	if await HomeTravel.enter(village):
		return
	if HomeTravel.is_travelling() or village == null or not village.is_inside_tree():
		return
	var layer: Variant = village.get(&"ui")
	# Read-only in a group session; alone without a WorldController (tools) it stays editable.
	await TalentTreeDialog.open_for_account(layer if layer is Node else village, HomeTravel.can_enter(village))


## Shows the home with its door open (true) or closed; nothing while the art is missing.
static func set_home_door_open(home: Node2D, open: bool) -> void:
	var sprite := home.get_node_or_null(^"Sprite") as Sprite2D if home != null else null
	if sprite == null:
		return
	if not sprite.has_meta(&"closed_texture"):
		sprite.set_meta(&"closed_texture", sprite.texture)
	var texture: Texture2D = sprite.get_meta(&"closed_texture")
	if open and ResourceLoader.exists(HOME_DOOR_OPEN_ART):
		texture = load(HOME_DOOR_OPEN_ART) as Texture2D
	sprite.texture = texture


static func is_home_door_open(home: Node2D) -> bool:
	var sprite := home.get_node_or_null(^"Sprite") as Sprite2D if home != null else null
	return sprite != null and sprite.texture != null and sprite.texture.resource_path == HOME_DOOR_OPEN_ART
