class_name BranchOption
extends RefCounted
## One of the two ways of a branch (D-105, D-117): what waits in room n+1 behind its
## door and the sign over the door. Both ways lead to room n+1; cycle, room number and scaling stay.

enum Kind {
	## Normal combat room without variant or wager altar ("sicherer Weg", heart sign).
	SAFE,
	## Elite nest (D-101, D-117): only reachable through a branch (crossed swords).
	ELITE_NEST,
	## A random combat variant, drawn in advance and hidden behind the question mark.
	UNKNOWN,
	## A special room of a given type (before place 4 of the cycle); its own sign (shop, trial, ...).
	SPECIAL,
	## Ladder way (M5, D-144): the way runs through a side segment with coins and the chest, room
	## n+1 behind it is a plain fight like the safe way (ladder sign). Stands in for the safe way.
	LADDER,
}

## Variant id of the elite nest (EliteNestVariant.ID). Kept here, so the branch rules need not load
## the variant scripts (CombatVariant and its subclasses load each other).
const ELITE_NEST_ID := &"elite_nest"

var kind := Kind.SAFE
## SpecialType of a SPECIAL option, -1 otherwise.
var special_type := -1
## Variant of the next room: &"elite_nest" for ELITE_NEST, the hidden variant of UNKNOWN, &"" else.
var variant_id: StringName = &""


static func create(option_kind: Kind, special := -1, variant: StringName = &"") -> BranchOption:
	var option := BranchOption.new()
	option.kind = option_kind
	option.special_type = special
	option.variant_id = variant
	return option


## Sign over the door: a branch sign (DoorStyle.BRANCH_SYMBOLS) for combat ways; special rooms show
## their own sign through the door's destination (&"" here).
func get_symbol() -> StringName:
	match kind:
		Kind.ELITE_NEST:
			return &"elite_nest"
		Kind.UNKNOWN:
			return &"unknown"
		Kind.SAFE:
			return &"safe"
		Kind.LADDER:
			return &"ladder"
	return &""


## Room type of room n+1 behind this door, given the type the slot has anyway.
func get_room_type(slot_type: int) -> int:
	return RoomSequence.RoomType.SPECIAL if kind == Kind.SPECIAL else slot_type


## The way runs through a side segment (M5): DungeonManager plans it as the ladder way.
func is_ladder() -> bool:
	return kind == Kind.LADDER


func is_combat() -> bool:
	return kind != Kind.SPECIAL


## Combat ways force the variant of the next room: none (safe, ladder), elite nest or the hidden variant.
func forces_variant() -> bool:
	return kind != Kind.SPECIAL


## Log name of the way (smoke test); the player only sees the door sign (DoorStyle.BRANCH_SYMBOLS).
func describe() -> String:
	match kind:
		Kind.ELITE_NEST:
			return "Elite-Nest"
		Kind.UNKNOWN:
			return "Unbekannt (%s)" % variant_id
		Kind.SPECIAL:
			return SpecialTable.get_type_name(special_type)
		Kind.LADDER:
			return "Leiter-Weg"
	return "Sicherer Weg"
