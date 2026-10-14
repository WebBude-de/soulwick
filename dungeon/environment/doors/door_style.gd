class_name DoorStyle
extends RefCounted
## Look of one door (ROADMAP_AUSBAU D1): frame, leaf, torches, light, glow, particles and sound,
## chosen from the biome of the room and the kind of room behind the door. Pure data, no nodes.
## Art files (docs/SPRITES_V4.md §4) are resolved by DoorArt; until they exist DoorArt paints
## placeholders from the palette fields below.

const DEFAULT_BIOME := &"crypt"
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]

## Door kinds. Every door is NORMAL except the gate in front of / into a boss room.
const KIND_NORMAL := &"normal"
const KIND_BOSS := &"boss"

## Symbols over doors to special rooms, in the column order of door_special_symbols.png
## (SPRITES_V4 §4). "miniboss" is an optional seventh column (see DoorArt).
const SYMBOLS: Array[StringName] = [&"shop", &"weapon", &"fountain", &"upgrade", &"trial", &"campfire", &"miniboss"]
## Symbols over the two doors of a branch (A10, D-105), in the column order of
## art/environment/rooms/door_branch_symbols.png: elite nest (crossed swords), safe way (heart),
## unknown (question mark).
const BRANCH_SYMBOLS: Array[StringName] = [&"elite_nest", &"safe", &"unknown"]
const BRANCH_SYMBOLS_PATH := "res://art/environment/rooms/door_branch_symbols.png"

const ART_DIR := "res://art/environment/doors/"

## Leaf placeholder kinds (what opens): iron-banded wood, vine curtain, rune veil, portcullis,
## chained double door.
const LEAF_WOOD := &"wood"
const LEAF_VINES := &"vines"
const LEAF_VEIL := &"veil"
const LEAF_PORTCULLIS := &"portcullis"
const LEAF_DOUBLE := &"double"

## Glow overlay behaviour (DoorFx): none, slow pulse (runes), flicker (embers), threat (boss gate,
## strong pulse while closed, gone once open).
const GLOW_NONE := &"none"
const GLOW_PULSE := &"pulse"
const GLOW_FLICKER := &"flicker"
const GLOW_THREAT := &"threat"

## Torches beside the frame: wall torches or braziers standing at the wall foot.
const TORCH_WALL := &"wall"
const TORCH_BRAZIER := &"brazier"

const TORCH_STRIPS := {
	&"crypt": "res://art/environment/props/torch_4f.png",
	&"slime_grotto": "res://art/environment/props/torch_green_4f.png",
	&"shadow_realm": "res://art/environment/props/torch_purple_4f.png",
	&"ember_forge": "res://art/environment/props/brazier_4f.png",
}

var biome_id: StringName = DEFAULT_BIOME
var kind: StringName = KIND_NORMAL
## Symbol id from SYMBOLS or &"" for none.
var symbol: StringName = &""

## Frame and leaf in art px; leaf_offset = top-left of the leaf inside the frame.
var frame_size := Vector2i(48, 48)
var leaf_size := Vector2i(32, 32)
var leaf_offset := Vector2i(8, 16)
var leaf_kind: StringName = LEAF_WOOD
## Speed of the opening animation (art/environment/doors/doors.json).
var leaf_fps := 8.0

## Placeholder palette (docs/HANDOUT.md).
var stone_light := Color("8f88ad")
var stone_mid := Color("6b6584")
var stone_dark := Color("4a4560")
var accent := Color("e9e4d2")
## Colour of the glow overlay (runes, embers, boss threat).
var glow_color := Color("ff8a3c")
var glow_mode: StringName = GLOW_NONE
## Modulate for delivered biome-neutral art (boss frame, symbols); placeholders are painted in colour.
var tint := Color.WHITE

var torch_strip_path := ""
var torch_mode: StringName = TORCH_WALL

## Open effects. Particle colour of the burst, light flash radius in world px.
var particle_color := Color("b9b3c9")
var particle_speed := 120.0
var flash_radius := 150.0
var open_sound: StringName = &"door_open_stone"
## Played when the door shuts behind the player; &"" = silent (as before D1).
var close_sound: StringName = &""


## Style for a door in a room of biome_id that leads into a room of the given kind.
## Unknown biome ids fall back to the crypt, unknown kinds to a normal door.
static func for_door(biome: StringName, door_kind: StringName = KIND_NORMAL, door_symbol: StringName = &"") -> DoorStyle:
	var style := DoorStyle.new()
	style.biome_id = biome if BIOMES.has(biome) else DEFAULT_BIOME
	style.kind = KIND_BOSS if door_kind == KIND_BOSS else KIND_NORMAL
	style.symbol = door_symbol if SYMBOLS.has(door_symbol) or BRANCH_SYMBOLS.has(door_symbol) else &""
	style._apply_biome()
	if style.kind == KIND_BOSS:
		style._apply_boss()
	return style


## Door kind for a door into a room of this RoomSequence.RoomType.
static func kind_for_room(room_type: int) -> StringName:
	return KIND_BOSS if room_type == RoomSequence.RoomType.BOSS else KIND_NORMAL


## Symbol for a door into a room of this RoomSequence.RoomType (special_type = its SpecialType,
## -1 otherwise). Matched by enum key name, so later types (TRIAL, CAMPFIRE, ...) work as soon as
## the enum has them.
static func symbol_for_room(room_type: int, special_type: int = -1) -> StringName:
	if room_type == RoomSequence.RoomType.SPECIAL:
		return _symbol_from_key(RoomSequence.SpecialType.find_key(special_type))
	return _symbol_from_key(RoomSequence.RoomType.find_key(room_type))


static func _symbol_from_key(key: Variant) -> StringName:
	if not key is String:
		return &""
	var id := StringName((key as String).to_lower())
	return id if SYMBOLS.has(id) else &""


## Column of a symbol in door_special_symbols.png, -1 for none (and for branch symbols).
static func symbol_index(symbol_id: StringName) -> int:
	return SYMBOLS.find(symbol_id)


## Column of a branch symbol in door_branch_symbols.png, -1 for none.
static func branch_symbol_index(symbol_id: StringName) -> int:
	return BRANCH_SYMBOLS.find(symbol_id)


static func is_branch_symbol(symbol_id: StringName) -> bool:
	return BRANCH_SYMBOLS.has(symbol_id)


func is_boss() -> bool:
	return kind == KIND_BOSS


## Frame file of this style (may not exist yet).
func get_frame_path() -> String:
	return ART_DIR + ("door_frame_boss.png" if is_boss() else "door_frame_%s.png" % biome_id)


## Four-frame leaf strip (frame 1 closed, frame 4 open).
func get_leaf_path() -> String:
	return ART_DIR + ("door_boss_open_4f.png" if is_boss() else "door_%s_open_4f.png" % biome_id)


## Leaf of a door in the west or east wall, seen from above (A10, docs/SPRITES_V7_A10.md): four
## frames of 32x32, drawn for a west wall door (the east one is mirrored).
func get_side_leaf_path() -> String:
	return ART_DIR + ("door_side_boss_open_4f.png" if is_boss() else "door_side_%s_open_4f.png" % biome_id)


static func get_symbols_path() -> String:
	return ART_DIR + "door_special_symbols.png"


## Cache key for generated art.
func get_key() -> String:
	return "%s_%s" % [biome_id, kind]


func _apply_biome() -> void:
	torch_strip_path = TORCH_STRIPS.get(biome_id, TORCH_STRIPS[DEFAULT_BIOME])
	match biome_id:
		&"slime_grotto":
			stone_light = Color("6f8f84")
			stone_mid = Color("4f6b64")
			stone_dark = Color("2c4038")
			accent = Color("6fbf5a")
			glow_color = Color("7ff0c8")
			glow_mode = GLOW_PULSE
			leaf_kind = LEAF_VINES
			particle_color = Color("8fdc6a")
			particle_speed = 80.0
			open_sound = &"door_open_vines"
			tint = Color("bfe8c8")
		&"shadow_realm":
			stone_light = Color("5d577a")
			stone_mid = Color("3b3150")
			stone_dark = Color("1e1830")
			accent = Color("a66ef0")
			glow_color = Color("a66ef0")
			glow_mode = GLOW_PULSE
			leaf_kind = LEAF_VEIL
			particle_color = Color("dcbcff")
			particle_speed = 90.0
			open_sound = &"door_open_rune"
			tint = Color("cdb8f0")
		&"ember_forge":
			stone_light = Color("8c8f9a")
			stone_mid = Color("5a5f6a")
			stone_dark = Color("3f3737")
			accent = Color("c6ccd6")
			glow_color = Color("ff8a3c")
			glow_mode = GLOW_FLICKER
			leaf_kind = LEAF_PORTCULLIS
			torch_mode = TORCH_BRAZIER
			particle_color = Color("ffd166")
			particle_speed = 190.0
			open_sound = &"door_open_gate"
			tint = Color("f0c4a8")
		_:
			stone_light = Color("8f88ad")
			stone_mid = Color("6b6584")
			stone_dark = Color("4a4560")
			accent = Color("e9e4d2")
			glow_color = Color("e9e4d2")
			glow_mode = GLOW_NONE
			leaf_kind = LEAF_WOOD
			particle_color = Color("b9b3c9")
			particle_speed = 110.0
			open_sound = &"door_open_stone"
			tint = Color.WHITE


func _apply_boss() -> void:
	frame_size = Vector2i(64, 56)
	leaf_offset = Vector2i(16, 24)
	leaf_kind = LEAF_DOUBLE
	leaf_fps = 6.0
	# Threatening red glow while closed, whatever the biome (skull eyes, seam, chains).
	glow_color = Color("e0463a")
	glow_mode = GLOW_THREAT
	# The gate carries its own torch holders; braziers would not fit on the pillars.
	torch_mode = TORCH_WALL
	if biome_id == &"ember_forge":
		torch_strip_path = TORCH_STRIPS[&"crypt"]
	particle_speed = 170.0
	flash_radius = 230.0
	open_sound = &"door_boss_unlock"
	close_sound = &"door_boss_close"
	symbol = &""
