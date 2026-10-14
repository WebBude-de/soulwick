class_name DoorSigns
extends RefCounted
## Door recognition (R5, KONZEPT_RAEUME_V2 §1.2, docs/design/claude_design_antwort/05_tueren.md): what
## an exit door tells about the room behind it. The DungeonManager calls show_way() once the next
## room is prepared (it lies built and dark behind the door): the door then shows the mode symbol of
## that room over the arch and throws a light cone in the mode colour into the room.
##   - Clearing room (Säubern): no symbol, light in the biome colour.
##   - Mode rooms (arena, minigames, elite nest): mode symbol and mode colour (RoomObjective.MODES).
##   - Special and rest rooms, the campfire: their own sign (door_special_symbols), gold light.
##   - Miniboss: its skull sign, red light. Boss: the boss gate, red light.
## Pure decision, no nodes of its own: the door draws (Door.show_way, DoorView).
##
## The mode of a prepared room is read, in this order, from: a get_mode_id() method of the room or a
## "mode_id" metadata (for modes that are not a CombatVariant), its RoomObjective, its mode or combat
## variant (RoomVariants.get_variant_id: R4 mode ids directly, old A7/A9 variants mapped onto their
## v2 mode), the arena flag. All of them are known when the room is prepared.

## Old combat variants (A7/A9) and the v2 mode they became (KONZEPT_RAEUME_V2 §2, "Gestrichen oder
## umgebaut"). The gravedigger is an enemy trait now: plain clearing room.
## Values are RoomObjective mode ids.
const VARIANT_MODES: Dictionary[StringName, StringName] = {
	&"soul_flame": &"flame",
	&"bounty": &"hunt",
	&"lantern": &"relic",
	&"torch_room": &"lightfire",
	&"stone_guardian": &"lightfire",
}
const META_MODE := &"mode_id"
## Light of special and rest rooms (07_ui.md gold) and of the dangerous ones (boss, miniboss).
const SPECIAL_COLOR := Color("f2cf4a")
const DANGER_COLOR := Color("e0463a")
## Biome colour of a clearing room's light (05_tueren.md "Säubern Biomfarbe"). TESTWERTE
const BIOME_COLORS: Dictionary[StringName, Color] = {
	&"crypt": Color("d8cfb4"),
	&"slime_grotto": Color("7ff0c8"),
	&"shadow_realm": Color("a66ef0"),
	&"ember_forge": Color("ff8a3c"),
}


## Mode id of a prepared room (RoomObjective mode id), &"" for a plain clearing room and rooms
## without a mode (special, miniboss, boss, campfire).
static func mode_of(room: Node) -> StringName:
	if room == null or not is_instance_valid(room):
		return &""
	if room.has_method(&"get_mode_id"):
		var own := StringName(room.call(&"get_mode_id"))
		if own != &"":
			return own
	if room.has_meta(META_MODE):
		var tagged := StringName(room.get_meta(META_MODE))
		if tagged != &"":
			return tagged
	var objective: RoomObjective = RoomObjective.of_room(room)
	if objective != null:
		return objective.mode_id
	# R4: the room's mode is its variant id; older variants map onto their v2 mode.
	var variant := RoomVariants.get_variant_id(room)
	if RoomObjective.has_mode(variant):
		return variant
	if VARIANT_MODES.has(variant):
		return VARIANT_MODES[variant]
	if room.has_method(&"is_arena_room") and room.call(&"is_arena_room"):
		return RoomObjective.ARENA
	return &""


## Colour of the light cone of a door with this style leading to a room of this mode.
static func way_color(style: DoorStyle, mode: StringName) -> Color:
	if style == null:
		return SPECIAL_COLOR
	if style.is_boss():
		return DANGER_COLOR
	if RoomObjective.has_mode(mode):
		return RoomObjective.get_mode_color(mode)
	if style.symbol == &"miniboss":
		return DANGER_COLOR
	if DoorStyle.SYMBOLS.has(style.symbol):
		return SPECIAL_COLOR
	return BIOME_COLORS.get(style.biome_id, BIOME_COLORS[DoorStyle.DEFAULT_BIOME])


## Mode shown over a door: the room's mode; the safe way of a branch stays a plain fight (heart
## sign), a hidden variant keeps its question mark when it has no v2 mode.
static func mode_for_way(room: Node, option: BranchOption = null) -> StringName:
	if option != null and option.kind == BranchOption.Kind.SAFE:
		return &""
	return mode_of(room)


## Lets door show what waits behind it in room (prepared, built and dark). option: the branch way
## of this door (null for a normal exit).
static func show_way(door: Door, room: Node, option: BranchOption = null) -> void:
	if door == null or not is_instance_valid(door) or door.is_entrance:
		return
	var mode := mode_for_way(room, option)
	door.show_way(mode, way_color(door.get_style(), mode))
