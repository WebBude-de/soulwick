class_name BranchRules
extends RefCounted
## Branches (D-105, KONZEPT_RAEUME §7.2): now and then a cleared combat room has two exits with a
## sign over each; both lead to room n+1 (cycle, room number and scaling stay), the contents differ.
## The choice falls when the players walk up to a door; the other way is sealed. Pure rules, no
## nodes: the draw (roll), the door layout (pick_exit_pair) and the group vote (resolve_vote).
##
## - From FROM_ROOM, at most once per five-room cycle, CHANCE of the eligible rooms: normal combat
##   rooms on cycle places 1-3 that are no combat variant themselves (never two variants in a row).
## - Before place 4 (the special room): two special room types to choose from (weighted like the
##   special table, never the previous type, the two differ). Before a combat room: elite nest vs.
##   the safe way, or an unknown combat variant vs. the safe way.
## - Randomness: exactly DRAWS numbers of the dungeon RNG per normal combat room, none otherwise.

const FROM_ROOM := 6
## Share of the eligible combat rooms that branch, at most one per cycle. TESTWERT
const CHANCE := 0.3
## Combat branches: elite nest vs. safe way in this share, unknown variant vs. safe way otherwise.
const ELITE_SHARE := 0.6  # TESTWERT
## Group vote (D-105): with the players split over both doors, the door with more players wins after
## this many seconds; a tie is drawn with the dungeon RNG. TESTWERT
const VOTE_TIMEOUT := 10.0
## Numbers drawn from the dungeon RNG per normal combat room.
const DRAWS := 4

## Test aid (smoke test): >= 0 replaces CHANCE. Never set in the game.
static var chance_override := -1.0


## The two ways of one branch room; empty options = no branch.
class Plan:
	extends RefCounted
	var options: Array[BranchOption] = []

	func is_branch() -> bool:
		return options.size() == 2


static func get_chance() -> float:
	return chance_override if chance_override >= 0.0 else CHANCE


## Cycle (five rooms) of a room number: 0 for rooms 1-5, 1 for 6-10, ...
static func get_cycle(room_index: int) -> int:
	return floori(float(room_index - 1) / RoomSequence.CYCLE_LENGTH)


## May this room branch at all? next_slot_type: type of the slot after it.
static func is_eligible(room_index: int, room_type: int, has_variant: bool, branch_cycle: int) -> bool:
	if room_index < FROM_ROOM or not RoomSequence.is_normal_combat(room_type as RoomSequence.RoomType):
		return false
	return not has_variant and branch_cycle != get_cycle(room_index)


## The draw for one room. branch_cycle: cycle of the last branch (-1 = none yet), previous_special:
## type of the last special room (-1 = none). Draws exactly DRAWS numbers for normal combat rooms.
static func roll(room_index: int, room_type: int, next_slot_type: int, has_variant: bool, branch_cycle: int,
		previous_special: int, special_table: SpecialTable, variant_table: VariantTable, rng: RandomNumberGenerator) -> Plan:
	var plan := Plan.new()
	if rng == null or not RoomSequence.is_normal_combat(room_type as RoomSequence.RoomType):
		return plan
	var chance_roll := rng.randf()
	var kind_roll := rng.randf()
	var first_roll := rng.randf()
	var second_roll := rng.randf()
	if not is_eligible(room_index, room_type, has_variant, branch_cycle) or chance_roll >= get_chance():
		return plan
	if next_slot_type == RoomSequence.RoomType.SPECIAL:
		var pair := pick_special_pair(special_table, previous_special, first_roll, second_roll)
		if pair.size() == 2:
			plan.options.assign([BranchOption.create(BranchOption.Kind.SPECIAL, pair[0]), BranchOption.create(BranchOption.Kind.SPECIAL, pair[1])])
		return plan
	if not RoomSequence.is_normal_combat(next_slot_type as RoomSequence.RoomType):
		return plan
	var other := BranchOption.create(BranchOption.Kind.ELITE_NEST, -1, BranchOption.ELITE_NEST_ID)
	if kind_roll >= ELITE_SHARE and variant_table != null:
		var hidden := variant_table.choose_variant(RoomSequence.get_biome(room_index + 1), first_roll)
		if hidden != VariantTable.NONE:
			other = BranchOption.create(BranchOption.Kind.UNKNOWN, -1, hidden)
	var safe := BranchOption.create(BranchOption.Kind.SAFE)
	# Which door shows which way.
	plan.options.assign([other, safe] if second_roll < 0.5 else [safe, other])
	return plan


## Two different special types, weighted like the special table, never previous. [] if the table
## has fewer than two types with a weight.
static func pick_special_pair(table: SpecialTable, previous: int, first_roll: float, second_roll: float) -> Array[int]:
	var pair: Array[int] = []
	if table == null:
		table = SpecialTable.new()
	var weights := table.get_weights(previous)
	var first := SpecialTable.pick_weighted(weights, first_roll, -1)
	if first < 0 or weights[first] <= 0.0:
		return pair
	weights[first] = 0.0
	var second := SpecialTable.pick_weighted(weights, second_roll, -1)
	if second < 0 or second == first or weights[second] <= 0.0:
		return pair
	pair.append(first)
	pair.append(second)
	return pair


## Two exit doors (Vector2i(side, place)) for a branch room: special ways need the north wall (the
## special templates are entered from the south only), so both doors go north, as far apart as the
## template's north places allow; combat ways take two different walls from sides (allowed exit
## walls, ExitRules), preferring the ones without an estimated long corridor. Empty if the template
## cannot host the branch.
static func pick_exit_pair(tiles: RoomTiles, options: Array[BranchOption], sides: Array[int], estimates: Array[int]) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	var all_combat := true
	for option in options:
		all_combat = all_combat and option.is_combat()
	if all_combat:
		var walls: Array[int] = []
		for i in sides.size():
			if sides[i] == ExitRules.NORTH or (i < estimates.size() and estimates[i] <= ExitRules.MAX_TURN_EXTRA):
				walls.append(sides[i])
		if walls.size() >= 2:
			# A fork: west and east when both are free (entered from the south), else north and
			# the free side wall.
			var chosen: Array[int] = [ExitRules.WEST, ExitRules.EAST]
			if not (walls.has(ExitRules.WEST) and walls.has(ExitRules.EAST)):
				chosen.assign(walls.slice(0, 2))
			for side in chosen:
				var places := tiles.get_door_slots(side)
				pair.append(Vector2i(side, ExitRules.pick_place(places, ExitRules.wall_length(side, tiles.room_size))))
			return pair
	var north := tiles.get_door_slots(ExitRules.NORTH)
	if north.size() < 2:
		return pair
	var best := Vector2i(north[0], north[north.size() - 1])
	if absi(best.y - best.x) < 2:
		return pair
	pair.append(Vector2i(ExitRules.NORTH, best.x))
	pair.append(Vector2i(ExitRules.NORTH, best.y))
	return pair


## Group decision (D-105): counts[i] = living players in front of door i, players = living players.
## All of them at one door -> that door at once; split over the doors -> after VOTE_TIMEOUT seconds
## the door with more players, a tie decided by tie_roll in [0, 1). -1 = no decision yet.
static func resolve_vote(counts: Array[int], players: int, waited: float, tie_roll := 0.0) -> int:
	if players <= 0:
		return -1
	var standing := 0
	for i in counts.size():
		standing += counts[i]
		if counts[i] >= players:
			return i
	if standing < players or waited < VOTE_TIMEOUT:
		return -1
	var best := 0
	var tied: Array[int] = []
	for count in counts:
		best = maxi(best, count)
	for i in counts.size():
		if counts[i] == best:
			tied.append(i)
	return tied[mini(tied.size() - 1, floori(tie_roll * tied.size()))]
