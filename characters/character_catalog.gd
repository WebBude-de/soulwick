class_name CharacterCatalog
extends RefCounted
## All playable figures (MM1, D-152: wick, ember, moss, frost = contracts PlayerCharacter). A new
## figure = a CharacterData .tres in res://characters/ plus one line in PATHS (and the id in
## PlayerLook.CHARACTERS and the contracts). The first entry is the default.
## The figure of this player comes from the account profile (PlayerProfile), not from a save slot.

const DEFAULT_ID := PlayerLook.DEFAULT_CHARACTER
const PATHS: Array[String] = [
	"res://characters/wick.tres",
	"res://characters/ember.tres",
	"res://characters/moss.tres",
	"res://characters/frost.tres",
]

static var _cache: Array[CharacterData] = []


static func all() -> Array[CharacterData]:
	if _cache.is_empty():
		for path in PATHS:
			var data := load(path) as CharacterData
			if data != null:
				_cache.append(data)
	return _cache


## The figure with id (old ids such as "hero" are mapped), or the default one for unknown ids.
static func get_character(id: StringName) -> CharacterData:
	var characters := all()
	var wanted: StringName = PlayerLook.LEGACY_IDS.get(id, id)
	for data in characters:
		if data.id == wanted:
			return data
	for data in characters:
		if data.id == DEFAULT_ID:
			return data
	return characters[0] if not characters.is_empty() else null


static func has_character(id: StringName) -> bool:
	for data in all():
		if data.id == id:
			return true
	return false


## Figure of this player's profile.
static func get_active() -> CharacterData:
	return get_character(PlayerLook.get_character(PlayerProfile.current().look))


## Hook for player.gd: the player sprite in the profile's figure and colours (D-152).
static func apply_active(sprite: AnimatedSprite2D) -> void:
	PlayerLook.apply(sprite, PlayerProfile.current().look)
