class_name SideEnemyKinds
extends RefCounted
## Makes the side enemy of each kind (SV4, D-195) and names its plan character, so plans and the
## segment build every kind the same way on every machine (build order = NetSide index):
##   s slime (hops)       k skeleton (walks)     b bat (arc flight, SideBat)
##   i spike hedgehog (no stomp)                 u shield bearer (stomp or weapon only)
## SideLayout reads all of them, SideSegment._build_enemies calls make(). What each kind accepts:
## SideEnemy.kind_accepts_stomp; nobody is run over (D-216).

const PLAN_CHARS: Dictionary[String, int] = {
	"s": SideEnemy.Kind.SLIME,
	"k": SideEnemy.Kind.SKELETON,
	"b": SideEnemy.Kind.BAT,
	"i": SideEnemy.Kind.SPIKE_HEDGEHOG,
	"u": SideEnemy.Kind.SHIELD_BEARER,
}


## A ready-to-add enemy of kind. rng_seed from the segment's RNG (multiplayer rule); position is
## set by the caller to SideLayout.feet_of(cell) before adding it.
static func make(kind: SideEnemy.Kind, room_index: int, segment: SideSegment, rng_seed: int) -> SideEnemy:
	var enemy: SideEnemy = null
	match kind:
		SideEnemy.Kind.BAT:
			enemy = SideBat.new()
		SideEnemy.Kind.SPIKE_HEDGEHOG:
			enemy = SideSpikeHedgehog.new()
		SideEnemy.Kind.SHIELD_BEARER:
			enemy = SideShieldBearer.new()
		_:
			enemy = SideEnemy.new()
	enemy.setup(kind, room_index, segment, rng_seed)
	return enemy


## Kind for a plan character, -1 if it is no enemy.
static func kind_for_char(character: String) -> int:
	return PLAN_CHARS.get(character, -1)


static func char_for(kind: SideEnemy.Kind) -> String:
	for character: String in PLAN_CHARS:
		if PLAN_CHARS[character] == kind:
			return character
	return ""


## Flies (no floor needed, its path must be air: SideBat.path_cells).
static func is_flying(kind: SideEnemy.Kind) -> bool:
	return kind == SideEnemy.Kind.BAT
