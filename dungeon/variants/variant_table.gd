class_name VariantTable
extends Resource
## Mode table of the normal combat rooms (places 1-3 of the cycle, RAEUME §4, D-120):
## minigame (ModeRegistry), wager altar or a plain fight. The chances live in variant_table.tres,
## the modes and their weights in ModeRegistry (one line per mode). Randomness only through the RNG
## handed in (the dungeon RNG).
##
## From room from_room (cycle 2) mode_chance of the combat rooms become a minigame, at most
## max_per_cycle per cycle (five rooms), never the same mode twice in a row and no mode twice in one
## cycle. A mode is available from its first room (ModeRegistry from_room); a mode the run has not
## seen yet comes first (new modes one by one, KONZEPT §4), then they mix. Of the other combat rooms
## wager_chance get a wager altar behind the entrance (D-104). The arena stays a room kind of its own:
## a minigame room is fought as a normal room (the DungeonManager forces RoomKind.NORMAL).
## roll() draws exactly three numbers for every normal combat room, also before from_room, and none
## for other room types, so the dungeon RNG stays in step whatever comes out. The pick names the mode
## and its plan mode (Pick.plan_mode), so the DungeonManager draws a plan made for it.
## The table keeps a short history (cycle, modes of the cycle, last mode, modes seen); load_default()
## hands out a fresh copy per run.

const DEFAULT_PATH := "res://dungeon/variants/variant_table.tres"
const NONE := &""

## First room with minigames and wager altars (cycle 1 stays plain, RAEUME §4).
@export var from_room := 6
## Share of the combat rooms that become a minigame (D-120: 30-40 %). TESTWERT
@export_range(0.0, 1.0) var variant_chance := 0.35
## At most this many minigames per cycle (RAEUME §4). TESTWERT
@export var max_per_cycle := 2
## Share of the other combat rooms with a wager altar (D-104). TESTWERT
@export_range(0.0, 1.0) var wager_chance := 0.12
## Modes of the draw and their weights, parallel arrays. Empty in the .tres: filled from
## ModeRegistry (tools may overwrite them for a measurement, e.g. balance_sim vt.only).
@export var variant_ids: Array[StringName] = []
@export var variant_weights: Array[float] = []
## Biome a mode is bound to (RoomSequence.Biome value), -1 = every biome; parallel to variant_ids.
@export var variant_biomes: Array[int] = []
## Several biomes for one mode: bit mask of 1 << RoomSequence.Biome, parallel to variant_ids.
## 0 or missing = variant_biomes decides.
@export var variant_biome_masks: Array[int] = []
## First room per mode, parallel to variant_ids (0 or missing = from_room).
@export var variant_from_rooms: Array[int] = []

## History of the run (not saved): cycle of the last roll, modes drawn in it, the last mode drawn
## and every mode drawn so far.
var _cycle := -1
var _in_cycle: Array[StringName] = []
var _last_mode: StringName = NONE
var _seen: Array[StringName] = []


## Result of one draw.
class Pick:
	extends RefCounted
	var variant_id: StringName = &""
	## RoomTemplate.mode of the plan to draw for the mode (&"" = any combat plan).
	var plan_mode: StringName = &""
	var wager := false

	func has_variant() -> bool:
		return variant_id != &""

	func is_empty() -> bool:
		return variant_id == &"" and not wager


func _init() -> void:
	_fill_from_registry()


## A fresh table for one run (its own history); the shared .tres stays untouched.
static func load_default() -> VariantTable:
	var shared := load(DEFAULT_PATH) as VariantTable
	if shared == null:
		return null
	var table := shared.duplicate() as VariantTable
	if table.variant_ids.is_empty():
		table._fill_from_registry()
	return table


## A pick for a known mode (a branch way that hides it, tools): mode and its plan mode.
static func pick_for(mode_id: StringName) -> Pick:
	var pick := Pick.new()
	pick.variant_id = mode_id
	pick.plan_mode = ModeRegistry.get_plan_mode(mode_id)
	return pick


## Cycle of five rooms (cycle 0 = rooms 1-5), the same count as BranchRules.get_cycle.
static func get_cycle(room_index: int) -> int:
	return floori(float(room_index - 1) / RoomSequence.CYCLE_LENGTH)


## Minigame or wager altar (or nothing) for one room. previous_variant: mode of the combat room right
## before this one (&"" if that one was none or not a combat room) - never the same mode twice.
func roll(room_index: int, room_type: RoomSequence.RoomType, previous_variant: StringName, rng: RandomNumberGenerator) -> Pick:
	var pick := Pick.new()
	if rng == null or not RoomSequence.is_normal_combat(room_type):
		return pick
	var variant_roll := rng.randf()
	var choice_roll := rng.randf()
	var wager_roll := rng.randf()
	if room_index < from_room:
		return pick
	var cycle := get_cycle(room_index)
	if cycle != _cycle:
		_cycle = cycle
		_in_cycle.clear()
	if _in_cycle.size() < max_per_cycle and variant_roll < variant_chance:
		var exclude: Array[StringName] = _in_cycle.duplicate()
		for id: StringName in [previous_variant, _last_mode]:
			if id != NONE and not exclude.has(id):
				exclude.append(id)
		var id := choose_variant(RoomSequence.get_biome(room_index), choice_roll, room_index, exclude)
		if id != NONE:
			pick.variant_id = id
			pick.plan_mode = ModeRegistry.get_plan_mode(id)
			note_drawn(room_index, id)
	if not pick.has_variant():
		pick.wager = wager_roll < wager_chance
	return pick


## Records a mode that a room got (roll() does it itself; a branch way that forces a hidden mode
## may call it too).
func note_drawn(room_index: int, id: StringName) -> void:
	if id == NONE:
		return
	var cycle := get_cycle(room_index)
	if cycle != _cycle:
		_cycle = cycle
		_in_cycle.clear()
	if not _in_cycle.has(id):
		_in_cycle.append(id)
	_last_mode = id
	if not _seen.has(id):
		_seen.append(id)


## The history as a value (the DungeonManager builds both ways of a branch and keeps the draw state
## of the way that is not taken out of the stream, R5): restore_history() puts it back.
func save_history() -> Dictionary:
	return {"cycle": _cycle, "in_cycle": _in_cycle.duplicate(), "last": _last_mode, "seen": _seen.duplicate()}


func restore_history(state: Dictionary) -> void:
	if state.is_empty():
		return
	_cycle = int(state.get("cycle", -1))
	_in_cycle.assign(state.get("in_cycle", []))
	_last_mode = StringName(state.get("last", NONE))
	_seen.assign(state.get("seen", []))


## Forgets the history (a new run with the same table, tests).
func reset_history() -> void:
	_cycle = -1
	_in_cycle.clear()
	_last_mode = NONE
	_seen.clear()


func get_modes_in_cycle() -> Array[StringName]:
	return _in_cycle.duplicate()


func get_last_mode() -> StringName:
	return _last_mode


func has_seen(id: StringName) -> bool:
	return _seen.has(id)


## Weighted choice among the modes allowed in a biome and room; value in [0, 1). Modes the run has
## not seen yet come first (one new mode at a time). room_index 0 = no room filter. &"" if none.
func choose_variant(biome: int, value: float, room_index := 0, exclude: Array[StringName] = []) -> StringName:
	var ids: Array[StringName] = []
	for id in get_allowed(biome, room_index):
		if not exclude.has(id):
			ids.append(id)
	var fresh: Array[StringName] = []
	for id in ids:
		if not _seen.has(id):
			fresh.append(id)
	if not fresh.is_empty() and room_index > 0:
		ids = fresh
	return _weighted(ids, value)


## Modes with a positive weight that may appear in the biome and (room_index > 0) in that room.
func get_allowed(biome: int, room_index := 0) -> Array[StringName]:
	var allowed: Array[StringName] = []
	for i in variant_ids.size():
		if is_allowed_in(i, biome) and get_weight(variant_ids[i]) > 0.0 and (room_index <= 0 or room_index >= get_from_room(i)):
			allowed.append(variant_ids[i])
	return allowed


## Biome filter of the mode at index i: its mask if it has one, else its single biome (-1 = all).
func is_allowed_in(index: int, biome: int) -> bool:
	var mask := variant_biome_masks[index] if index < variant_biome_masks.size() else 0
	if mask > 0:
		return biome >= 0 and (mask & (1 << biome)) != 0
	var bound := variant_biomes[index] if index < variant_biomes.size() else -1
	return bound < 0 or bound == biome


## First room of the mode at index i.
func get_from_room(index: int) -> int:
	var first := variant_from_rooms[index] if index < variant_from_rooms.size() else 0
	return maxi(from_room, first)


## Bit mask for variant_biome_masks from a list of RoomSequence.Biome values.
static func biome_mask(biomes: Array[int]) -> int:
	var mask := 0
	for biome in biomes:
		mask |= 1 << biome
	return mask


func get_weight(variant_id: StringName) -> float:
	var index := variant_ids.find(variant_id)
	if index < 0 or index >= variant_weights.size():
		return 0.0
	return maxf(0.0, variant_weights[index])


func _weighted(ids: Array[StringName], value: float) -> StringName:
	if ids.is_empty():
		return NONE
	var total := 0.0
	for id in ids:
		total += get_weight(id)
	if total <= 0.0:
		return NONE
	var rest := value * total
	for id in ids:
		rest -= get_weight(id)
		if rest < 0.0:
			return id
	return ids[ids.size() - 1]


## The modes of ModeRegistry as the parallel arrays of the draw.
func _fill_from_registry() -> void:
	var ids: Array[StringName] = []
	var weights: Array[float] = []
	var biomes: Array[int] = []
	var masks: Array[int] = []
	var firsts: Array[int] = []
	for id in ModeRegistry.get_ids():
		ids.append(id)
		weights.append(ModeRegistry.get_weight(id))
		biomes.append(-1)
		masks.append(ModeRegistry.get_biome_mask(id))
		firsts.append(ModeRegistry.get_from_room(id))
	variant_ids = ids
	variant_weights = weights
	variant_biomes = biomes
	variant_biome_masks = masks
	variant_from_rooms = firsts
