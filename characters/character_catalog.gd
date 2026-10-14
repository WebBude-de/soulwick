class_name CharacterCatalog
extends RefCounted
## All playable characters (MM1). A new character = a CharacterData .tres in res://characters/ plus
## one line in PATHS. The first entry is the default for saves without a character.

const DEFAULT_ID := &"hero"
const PATHS: Array[String] = [
	"res://characters/hero.tres",
]

static var _cache: Array[CharacterData] = []


static func all() -> Array[CharacterData]:
	if _cache.is_empty():
		for path in PATHS:
			var data := load(path) as CharacterData
			if data != null:
				_cache.append(data)
	return _cache


## The character with id, or the default one for unknown ids (old saves, removed characters).
static func get_character(id: StringName) -> CharacterData:
	var characters := all()
	for data in characters:
		if data.id == id:
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


## Character of the loaded save (SaveManager profile).
static func get_active() -> CharacterData:
	return get_character(SaveManager.get_character_id())


## Hook for player.gd (integrator): recolour the player sprite with the loaded save's character
## and clothing colour. One line in Player._ready(): CharacterCatalog.apply_active(_sprite)
static func apply_active(sprite: AnimatedSprite2D) -> void:
	var data := get_active()
	if data != null:
		data.apply_to(sprite, SaveManager.get_character_color())
