class_name DoorStyle
extends RefCounted
## Look of one door (ROADMAP D1): frame, leaf, torches, light, glow, particles and sound,
## chosen from the biome of the room and the kind of room behind the door. Pure data, no nodes.
## Art files (docs/design/sprites/delivered/SPRITES_V4.md §4) are resolved by DoorArt; until they exist DoorArt paints
## placeholders from the palette fields below.
## One gate per transition (M2, 11_makeover3_komplett.md §11/§12, art/environment/doors/gates.json):
## the leaf of a north exit is a gate flush in the wall line (stone slab sinking into the floor or a
## portcullis rising into the wall, 32x48 = front + half the crown, 0.4 s), framed by an arch in built
## rooms or a cave mouth in caves (apply_room_look). West/east doors keep door_side_<biome>, the boss
## gate keeps its chained double door. Entrances show no leaf at all (DoorView).

const DEFAULT_BIOME := &"crypt"
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]

## Door kinds. Every door is NORMAL except the gate in front of / into a boss room.
const KIND_NORMAL := &"normal"
const KIND_BOSS := &"boss"

## Symbols over doors to special rooms, in the column order of door_special_symbols.png
## (SPRITES_V4 §4). "miniboss" is an optional seventh column (see DoorArt).
const SYMBOLS: Array[StringName] = [&"shop", &"weapon", &"fountain", &"upgrade", &"trial", &"campfire", &"miniboss"]
## Symbols over the two doors of a branch (A10, D-105), in the column order of
## art/environment/rooms/door_branch_symbols_4.png: elite nest (crossed swords), safe way (heart),
## unknown (question mark), ladder (the way down into a side segment, M5; SPRITES_V9 §4).
const BRANCH_SYMBOLS: Array[StringName] = [&"elite_nest", &"safe", &"unknown", &"ladder"]
## V9 sheet with the ladder as the fourth column; the old three-column sheet is the fallback.
const BRANCH_SYMBOLS_PATH := "res://art/environment/rooms/door_branch_symbols_4.png"
const BRANCH_SYMBOLS_OLD_PATH := "res://art/environment/rooms/door_branch_symbols.png"
## V9 mode sheet: the ten modes of door_mode_symbols.png plus the ladder as the eleventh column
## (RoomObjective loads the mode sheet; hook in the M2 report).
const MODE_SYMBOLS_LADDER_PATH := "res://art/environment/doors/door_mode_symbols_11.png"

const ART_DIR := "res://art/environment/doors/"

## Leaf placeholder kinds (what opens): iron-banded wood, vine curtain, rune veil, portcullis,
## chained double door.
const LEAF_WOOD := &"wood"
const LEAF_VINES := &"vines"
const LEAF_VEIL := &"veil"
const LEAF_PORTCULLIS := &"portcullis"
const LEAF_DOUBLE := &"double"

## Gates of a transition (gates.json): stone slab (crypt, shadow realm) or portcullis (grotto, forge,
## every arena). Neutral grey art, tinted per biome (tint).
const GATE_SLAB := &"slab"
const GATE_BARS := &"bars"
const GATE_SIZE := Vector2i(32, 48)
## Four frames in 0.4 s (gates.json: 10 fps).
const GATE_FPS := 10.0
const BIOME_GATES: Dictionary[StringName, StringName] = {
	&"crypt": GATE_SLAB,
	&"slime_grotto": GATE_BARS,
	&"shadow_realm": GATE_SLAB,
	&"ember_forge": GATE_BARS,
}
## Stone grinds, chains rattle; shutting behind the group: the slab lands, the bars rattle down.
const GATE_SOUNDS: Dictionary[StringName, StringName] = {
	GATE_SLAB: &"stone_grind",
	GATE_BARS: &"door_open_gate",
}
const GATE_CLOSE_SOUNDS: Dictionary[StringName, StringName] = {
	GATE_SLAB: &"stone_clank",
	GATE_BARS: &"door_open_gate",
}
## Frame around a north door: arch of the biome (built rooms) or cave mouth (caves, M2 §2.2).
const FRAME_ARCH := &"arch"
const FRAME_CAVE := &"cave"
## cave_mouth_<biome>.png: 64x48, the 32x32 door tile at (16, 16) (cave_mouth_*.json).
const CAVE_FRAME_SIZE := Vector2i(64, 48)
const CAVE_LEAF_OFFSET := Vector2i(16, 16)
## door_frame_<biome>.png: 48x48, door tile at (8, 16); the soft arch door_frame_<biome>_soft.png
## (SPRITES_V9 §2): 64x56, round opening, the crown runs through, door tile at (16, 24).
const ARCH_FRAME_SIZE := Vector2i(48, 48)
const ARCH_LEAF_OFFSET := Vector2i(8, 16)
const SOFT_ARCH_FRAME_SIZE := Vector2i(64, 56)
const SOFT_ARCH_LEAF_OFFSET := Vector2i(16, 24)
## Bug report 17.10.2026 (#67215ac5, "Cutted der Eingang"): M2 keeps exactly one corridor tile, so
## over a north door's tile lies one tile of crown (32 art px) and then the next room's floor. A frame
## reaches at most this many art px above its door tile; a taller one (the boss gate and the V9 soft
## arch, 24: their top touched the crown's edge and looked cut off) is shown lowered: its
## <name>_low.png when delivered (SPRITES_V10 §9), else DoorArt takes rows out of it (lower_rows).
## TESTWERT
const MAX_FRAME_RISE := 16
## Suffix of a delivered low frame (door_frame_boss_low.png, door_frame_<biome>_soft_low.png).
const LOW_SUFFIX := "_low"
## Fallback while a room template has no "cave" field of its own (plan header, M1): these biomes dig
## their combat rooms into the rock (11_makeover3_komplett.md §2.1); crypt halls, boss, rest and
## campfire rooms are built. TESTWERT (design choice until every plan says it)
const CAVE_BIOMES: Array[StringName] = [&"slime_grotto", &"shadow_realm", &"ember_forge"]
## Soft cave palette (M1: crypt_soft and its palette swaps): cave_mouth_<biome>_soft.png when it
## exists (crypt delivered, the others by tools/build_tilesets.gd), else the biome's own mouth.
const SOFT_SUFFIX := "_soft"
## M1's rock terrain: which biomes draw their caves in the soft set (RockTerrain.is_soft). Loaded by
## path, so the door works with or without it.
const ROCK_TERRAIN_PATH := "res://dungeon/rooms/walls/rock_terrain.gd"

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
## The way behind the door (R5, 05_tueren.md): mode of the next room (RoomObjective mode id, its
## symbol replaces symbol) and the colour of the light cone thrown into the room; &"" / transparent
## = none. Set through Door.show_way (DoorSigns), kept when the door is configured again.
var mode: StringName = &""
var way_color := Color(0, 0, 0, 0)

## Frame and leaf in art px; leaf_offset = top-left of the door tile (32x32) inside the frame. A gate
## is taller than its tile and reaches leaf_size.y - 32 px up into the crown.
var frame_size := Vector2i(48, 48)
var leaf_size := GATE_SIZE
var leaf_offset := Vector2i(8, 16)
## The frame is shown lowered (MAX_FRAME_RISE): low_frame = its delivered <name>_low.png is used;
## rise_cut = rows DoorArt takes out of the picture (of the low file, else of the tall one). frame_size
## and leaf_offset are those of the picture as shown.
var low_frame := false
var rise_cut := 0
## Material of the biome's doors: the placeholder of a side leaf and the burst of particles.
var leaf_kind: StringName = LEAF_WOOD
## The gate of a north exit (GATE_SLAB / GATE_BARS); &"" for the boss gate (chained double door).
var gate: StringName = GATE_SLAB
## FRAME_ARCH or FRAME_CAVE (apply_room_look); the boss gate has its own frame.
var frame_kind: StringName = FRAME_ARCH
## Soft palette of the room (M1): cave_mouth_<biome>_soft, door_frame_<biome>_soft and the side
## portcullis door_side_<biome>_bars_4f when they exist (V9), else the biome's own art.
var soft := false
## Speed of the opening animation (gates.json; boss and side leaves: doors.json).
var leaf_fps := GATE_FPS
var side_leaf_fps := 8.0

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
var open_sound: StringName = &"stone_grind"
## West/east doors keep the biome's own leaf and sound (door_side_<biome>).
var side_open_sound: StringName = &"door_open_stone"
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
	style._apply_gate(BIOME_GATES.get(style.biome_id, GATE_SLAB))
	if style.kind == KIND_BOSS:
		style._apply_boss()
	return style


## The wall the door stands in (M2): a cave mouth in rock, an arch in built rooms; the soft crypt
## palette; arenas close their ways with a portcullis. No effect on the boss gate.
func apply_room_look(cave: bool, soft_palette := false, arena := false) -> void:
	if is_boss():
		return
	frame_kind = FRAME_CAVE if cave else FRAME_ARCH
	soft = soft_palette
	if cave:
		frame_size = CAVE_FRAME_SIZE
		leaf_offset = CAVE_LEAF_OFFSET
	elif soft and (DoorArt.has_art(get_frame_path()) or DoorArt.has_art(get_low_frame_path())):
		frame_size = SOFT_ARCH_FRAME_SIZE
		leaf_offset = SOFT_ARCH_LEAF_OFFSET
	else:
		frame_size = ARCH_FRAME_SIZE
		leaf_offset = ARCH_LEAF_OFFSET
	_fit_rise()
	if has_side_bars():
		# The side portcullis rattles like the gate.
		side_open_sound = GATE_SOUNDS[GATE_BARS]
		side_leaf_fps = 8.0
	if arena:
		_apply_gate(GATE_BARS)


## Look of the wall of room (a RoomController; null or anything else: an arch). From the template's
## plan header when it says so ("cave", M1), else by role and biome (CAVE_BIOMES).
static func is_cave_room(room: Node, biome: StringName) -> bool:
	if room == null or not is_instance_valid(room) or not room.has_method(&"is_campfire"):
		return false
	# The plan header "cave" (M1): on the room's tiles, else on its template.
	var tiles := room.get_node_or_null("Tiles")
	if tiles != null and &"cave_mouth" in tiles:
		return bool(tiles.get(&"cave_mouth"))
	var template := RoomTemplate.of(room)
	if template != null and &"cave" in template:
		return bool(template.get(&"cave"))
	if template != null and template.role != RoomTemplate.ROLE_COMBAT and template.role != RoomTemplate.ROLE_MINIBOSS:
		return false
	var type := int(room.get(&"room_type"))
	if type == RoomSequence.RoomType.SPECIAL or type == RoomSequence.RoomType.BOSS or room.call(&"is_campfire"):
		return false
	return CAVE_BIOMES.has(biome)


## Soft palette of a room: the template's "palette" when it has one, a room drawn in M1's cave look
## (RoomTiles.is_cave_look) in a biome RockTerrain draws soft, or a soft tileset.
static func is_soft_room(room: Node, biome: StringName = DEFAULT_BIOME) -> bool:
	if room == null or not is_instance_valid(room) or not room.has_method(&"is_campfire"):
		return false
	var template := RoomTemplate.of(room)
	if template != null and &"palette" in template:
		return String(template.get(&"palette")).contains("soft")
	var tiles := room.get_node_or_null("Tiles") as TileMapLayer
	if tiles != null and tiles.has_method(&"is_cave_look") and tiles.call(&"is_cave_look"):
		var terrain: Script = load(ROCK_TERRAIN_PATH) if ResourceLoader.exists(ROCK_TERRAIN_PATH) else null
		return terrain == null or bool(terrain.call(&"is_soft", biome))
	return tiles != null and tiles.tile_set != null and tiles.tile_set.resource_path.contains("soft")


static func is_arena_room(room: Node) -> bool:
	return room != null and is_instance_valid(room) and &"room_kind" in room \
			and int(room.get(&"room_kind")) == RoomSequence.RoomKind.ARENA


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


func is_gate() -> bool:
	return gate != &""


func is_cave() -> bool:
	return frame_kind == FRAME_CAVE


## Does the door throw a light cone of the way behind it (R5)?
func has_way_light() -> bool:
	return way_color.a > 0.0


## Frame file of this style (may not exist yet): boss gate, cave mouth or arch.
func get_frame_path() -> String:
	if is_boss():
		return ART_DIR + "door_frame_boss.png"
	if is_cave():
		return ART_DIR + "cave_mouth_%s%s.png" % [biome_id, SOFT_SUFFIX if soft else ""]
	return ART_DIR + "door_frame_%s%s.png" % [biome_id, SOFT_SUFFIX if soft else ""]


## The low version of the frame file (MAX_FRAME_RISE, SPRITES_V10 §9); may not exist.
func get_low_frame_path() -> String:
	return get_frame_path().get_basename() + LOW_SUFFIX + ".png"


## The frame file this style shows: the low one when it is used (low_frame), else get_frame_path().
func get_shown_frame_path() -> String:
	return get_low_frame_path() if low_frame else get_frame_path()


## Is the frame shown lower than its file (rows taken out, or the low file)?
func is_lowered() -> bool:
	return low_frame or rise_cut > 0


## This style with the frame as tall as the picture it is made from (before rise_cut rows are taken
## out): the placeholder painters draw at that size. self when nothing is taken out.
func tall() -> DoorStyle:
	if rise_cut <= 0:
		return self
	var copy := DoorStyle.new()
	for property: Dictionary in get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(property["name"], get(property["name"]))
	copy.frame_size.y += rise_cut
	copy.leaf_offset.y += rise_cut
	copy.rise_cut = 0
	return copy


## Lowers a frame that rises more than MAX_FRAME_RISE over its door tile: the delivered low file when
## there is one (its own size, the door tile at the bottom centre), and rows taken out of the picture
## for whatever is still too tall.
func _fit_rise() -> void:
	low_frame = false
	rise_cut = 0
	if leaf_offset.y <= MAX_FRAME_RISE:
		return
	var low_size := DoorArt.art_size(get_low_frame_path())
	if low_size.x >= leaf_size.x and low_size.y >= 32:
		low_frame = true
		leaf_offset = Vector2i(leaf_offset.x + (low_size.x - frame_size.x) / 2, low_size.y - 32)
		frame_size = low_size
	rise_cut = maxi(0, leaf_offset.y - MAX_FRAME_RISE)
	frame_size.y -= rise_cut
	leaf_offset.y -= rise_cut


## Four-frame leaf strip of a north door (frame 1 closed, frame 4 open): the gate (32x48 frames,
## gates.json) or the boss gate's double door (32x32).
func get_leaf_path() -> String:
	if is_boss() or not is_gate():
		return ART_DIR + "door_boss_open_4f.png"
	return ART_DIR + "gate_%s_open_4f.png" % gate


## Leaf of a door in the west or east wall, seen from above (A10, docs/design/sprites/delivered/SPRITES_V7.md): four
## frames of 32x32, drawn for a west wall door (the east one is mirrored).
## Soft rooms: the portcullis across the passage (door_side_<biome>_bars_4f, V9) when it exists.
func get_side_leaf_path() -> String:
	if is_boss():
		return ART_DIR + "door_side_boss_open_4f.png"
	if has_side_bars():
		return get_side_bars_path()
	return ART_DIR + "door_side_%s_open_4f.png" % biome_id


func get_side_bars_path() -> String:
	return ART_DIR + "door_side_%s_bars_4f.png" % biome_id


## Does a side door of this style show the delivered portcullis (soft room, file there)?
func has_side_bars() -> bool:
	return soft and not is_boss() and DoorArt.has_art(get_side_bars_path())


## The branch sign sheet: the V9 sheet with the ladder, else the old one.
static func get_branch_symbols_path() -> String:
	return BRANCH_SYMBOLS_PATH if DoorArt.has_art(BRANCH_SYMBOLS_PATH) else BRANCH_SYMBOLS_OLD_PATH


static func get_symbols_path() -> String:
	return ART_DIR + "door_special_symbols.png"


## Cache key for generated art.
func get_key() -> String:
	var lowered := (LOW_SUFFIX if low_frame else "") + ("_r%d" % rise_cut if rise_cut > 0 else "")
	return "%s_%s_%s_%s%s%s" % [biome_id, kind, frame_kind, gate, SOFT_SUFFIX if soft else "", lowered]


func _apply_gate(gate_kind: StringName) -> void:
	gate = gate_kind
	leaf_size = GATE_SIZE
	leaf_fps = GATE_FPS
	open_sound = GATE_SOUNDS.get(gate_kind, &"stone_grind")
	close_sound = GATE_CLOSE_SOUNDS.get(gate_kind, &"stone_clank")


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
			side_open_sound = &"door_open_vines"
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
			side_open_sound = &"door_open_rune"
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
			side_open_sound = &"door_open_gate"
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
			side_open_sound = &"door_open_stone"
			tint = Color.WHITE


func _apply_boss() -> void:
	frame_size = Vector2i(64, 56)
	leaf_size = Vector2i(32, 32)
	leaf_offset = Vector2i(16, 24)
	leaf_kind = LEAF_DOUBLE
	gate = &""
	frame_kind = FRAME_ARCH
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
	side_open_sound = &"door_boss_unlock"
	close_sound = &"door_boss_close"
	symbol = &""
	_fit_rise()
