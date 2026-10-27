class_name TalentState
extends RefCounted
## How one player distributed their talent points (KONZEPT §6.1, D-194): the level of each talent
## and the equipped spells. State of a player (D-088), never of a session: the solo character takes
## it from the account, the guild character later from the server (MP8b); the lobby message carries
## to_dict() so the host can resolve everyone's effects (TalentEffects). Pure data and rules, no
## node and no save access: the owner stores to_dict() where it belongs (AccountProgress, KE1).
## Rules: every level costs one point; spent points never exceed the available points; a talent of
## rank r needs TalentTree.get_rank_threshold(r) points in the lower ranks of its path. Setting
## points is free, taking them back costs Seelenkristalle (respec_cost, D-196).

const VERSION := 1
## D-196 (TESTWERT): taking points back costs 10 % of them in Seelenkristalle, rounded up, at least 1.
const RESPEC_COST_PERCENT := 10
const RESPEC_MIN_COST := 1
## The first spell (Lichtblitz) opens the spell slot (KONZEPT §6.1).
const SPELL_SLOT_OPENER: StringName = &"light_flash"

## Talent id -> level (1..max_level); talents without points are not listed.
var levels: Dictionary[StringName, int] = {}
## Equipped spell ids, index = spell slot (at most get_spell_slots()).
var equipped_spells: Array[StringName] = []


# --- Points ---

## Talent points of an account or guild level (KONZEPT §4: level 2 gives the first, one per level).
static func points_for_level(level: int) -> int:
	return maxi(0, level - 1)


## Seelenkristalle for taking refunded_points back (D-196): 10 %, rounded up, at least 1; 0 for none.
static func respec_cost(refunded_points: int) -> int:
	if refunded_points <= 0:
		return 0
	return maxi(RESPEC_MIN_COST, ceili(refunded_points * RESPEC_COST_PERCENT / 100.0))


## Points taken back between two distributions (raising elsewhere does not offset it): what the
## altar charges for when the player confirms after (KE8).
static func refunded_points(before: TalentState, after: TalentState) -> int:
	var refunded := 0
	for id in before.levels:
		refunded += maxi(0, before.get_level(id) - after.get_level(id))
	return refunded


func get_level(id: StringName) -> int:
	return levels.get(id, 0)


func get_spent_points() -> int:
	var total := 0
	for id in levels:
		total += levels[id]
	return total


func get_path_points(talent_path: StringName, tree: TalentTree = null) -> int:
	return _points_below_rank(_tree(tree), talent_path, TalentDef.MAX_RANK + 1)


## Rank of a path is open: enough points in its lower ranks (0/3/7/11, TalentTree.rank_thresholds).
func is_rank_open(talent_path: StringName, rank: int, tree: TalentTree = null) -> bool:
	var catalog := _tree(tree)
	return _points_below_rank(catalog, talent_path, rank) >= catalog.get_rank_threshold(rank)


func can_raise(id: StringName, available_points: int, tree: TalentTree = null) -> bool:
	var catalog := _tree(tree)
	var talent := catalog.get_talent(id)
	if talent == null or get_level(id) >= talent.max_level:
		return false
	if get_spent_points() >= available_points:
		return false
	return is_rank_open(talent.path, talent.rank, catalog)


## Sets one more point into a talent (free). False if it is full, closed or no point is left.
func raise(id: StringName, available_points: int, tree: TalentTree = null) -> bool:
	if not can_raise(id, available_points, tree):
		return false
	levels[id] = get_level(id) + 1
	return true


## Takes one point back, unless a higher rank of the same path would then stand on too few points.
## The crystals are charged on confirm (respec_cost of refunded_points), not here.
func can_lower(id: StringName, tree: TalentTree = null) -> bool:
	if get_level(id) <= 0:
		return false
	var catalog := _tree(tree)
	var talent := catalog.get_talent(id)
	if talent == null:
		return true
	var trial := duplicate_state()
	trial._set_level(id, get_level(id) - 1)
	return trial._ranks_hold(catalog, talent.path)


func lower(id: StringName, tree: TalentTree = null) -> bool:
	if not can_lower(id, tree):
		return false
	_set_level(id, get_level(id) - 1)
	_drop_locked_spells(_tree(tree))
	return true


## Takes every point back (full respec); costs respec_cost(get_spent_points()).
func clear() -> void:
	levels.clear()
	equipped_spells.clear()


# --- Spells ---

## Spells unlocked by the talents taken, in catalog order.
func get_unlocked_spells(tree: TalentTree = null) -> Array[StringName]:
	var result: Array[StringName] = []
	for talent in _tree(tree).talents:
		if talent != null and talent.unlocks_spell() and get_level(talent.id) > 0:
			result.append(talent.spell)
	return result


## Spell slots: the slot opens with Lichtblitz (KONZEPT §6.1), the soul capstone adds the second.
func get_spell_slots(tree: TalentTree = null) -> int:
	var catalog := _tree(tree)
	var slots := 0
	for talent in catalog.talents:
		if talent == null or get_level(talent.id) <= 0:
			continue
		if talent.effect == TalentDef.Effect.SPELL_SLOTS:
			slots += roundi(talent.value) * get_level(talent.id)
		elif talent.unlocks_spell() and talent.spell == SPELL_SLOT_OPENER:
			slots += 1
	return slots


func can_equip_spell(spell: StringName, slot: int, tree: TalentTree = null) -> bool:
	return slot >= 0 and slot < get_spell_slots(tree) and get_unlocked_spells(tree).has(spell)


## Puts spell into slot (at the altar, KE8); a spell sits in one slot at most.
func equip_spell(spell: StringName, slot: int, tree: TalentTree = null) -> bool:
	if not can_equip_spell(spell, slot, tree):
		return false
	var old_slot := equipped_spells.find(spell)
	if old_slot >= 0:
		equipped_spells[old_slot] = &""
	while equipped_spells.size() <= slot:
		equipped_spells.append(&"")
	equipped_spells[slot] = spell
	_trim_spells()
	return true


func unequip_spell(slot: int) -> void:
	if slot >= 0 and slot < equipped_spells.size():
		equipped_spells[slot] = &""
		_trim_spells()


func get_equipped_spell(slot: int) -> StringName:
	return equipped_spells[slot] if slot >= 0 and slot < equipped_spells.size() else &""


# --- Checks ---

## Problems of this distribution (empty = valid): unknown talents, too many levels, more points
## than available, ranks without enough points below, spells that are locked or have no slot.
func validate(available_points: int, tree: TalentTree = null) -> Array[String]:
	var catalog := _tree(tree)
	var problems: Array[String] = []
	for id in levels:
		var talent := catalog.get_talent(id)
		if talent == null:
			problems.append("unknown talent %s" % id)
		elif levels[id] < 1 or levels[id] > talent.max_level:
			problems.append("talent %s at level %d of %d" % [id, levels[id], talent.max_level])
	if get_spent_points() > available_points:
		problems.append("%d points spent, %d available" % [get_spent_points(), available_points])
	for talent_path in TalentDef.PATHS:
		if not _ranks_hold(catalog, talent_path):
			problems.append("path %s: a rank stands on too few points" % talent_path)
	var unlocked := get_unlocked_spells(catalog)
	var slots := get_spell_slots(catalog)
	for slot in equipped_spells.size():
		var spell := equipped_spells[slot]
		if spell == &"":
			continue
		if slot >= slots:
			problems.append("spell %s in slot %d of %d" % [spell, slot, slots])
		elif not unlocked.has(spell):
			problems.append("spell %s is locked" % spell)
	return problems


func is_valid(available_points: int, tree: TalentTree = null) -> bool:
	return validate(available_points, tree).is_empty()


## A valid copy for untrusted input (an old save, a lobby message): unknown talents dropped, levels
## clamped, talents standing on too few points in their path dropped, then points taken back from
## the highest ranks (soul before ember before wind on a tie) until the budget holds; locked or
## slotless spells are unequipped. A valid state comes back unchanged.
func sanitized(available_points: int, tree: TalentTree = null) -> TalentState:
	var catalog := _tree(tree)
	var copy := TalentState.new()
	for talent in catalog.talents:
		if talent != null and get_level(talent.id) > 0:
			copy.levels[talent.id] = mini(get_level(talent.id), talent.max_level)
	var order := _highest_rank_first(catalog)
	while not copy._all_ranks_hold(catalog):
		for talent in order:
			if copy.get_level(talent.id) > 0 and copy._points_below_rank(catalog, talent.path, talent.rank) < catalog.get_rank_threshold(talent.rank):
				copy._set_level(talent.id, 0)
				break
	var budget := maxi(0, available_points)
	while copy.get_spent_points() > budget:
		for talent in order:
			if copy.get_level(talent.id) > 0:
				copy._set_level(talent.id, copy.get_level(talent.id) - 1)
				break
	copy.equipped_spells = equipped_spells.duplicate()
	copy._drop_locked_spells(catalog)
	return copy


# --- Copy and storage ---

func duplicate_state() -> TalentState:
	var copy := TalentState.new()
	copy.levels = levels.duplicate()
	copy.equipped_spells = equipped_spells.duplicate()
	return copy


## Plain dictionary for the save (AccountProgress, KE1), the server (MP8b) and the lobby message.
func to_dict() -> Dictionary:
	var talent_levels := {}
	for id in levels:
		talent_levels[String(id)] = levels[id]
	var spells: Array[String] = []
	for spell in equipped_spells:
		spells.append(String(spell))
	return {"version": VERSION, "talents": talent_levels, "spells": spells}


## Reads to_dict() output; tolerant of missing or wrongly typed entries (never fails). Does not check
## the rules: call sanitized() with the available points for anything that comes from outside.
static func from_dict(data: Variant) -> TalentState:
	var state := TalentState.new()
	if not (data is Dictionary):
		return state
	var talent_levels: Variant = data.get("talents", {})
	if talent_levels is Dictionary:
		for key: Variant in talent_levels:
			var level: Variant = talent_levels[key]
			if (key is String or key is StringName) and (level is int or level is float) and int(level) > 0:
				state.levels[StringName(key)] = int(level)
	var spells: Variant = data.get("spells", [])
	if spells is Array:
		for spell: Variant in spells:
			state.equipped_spells.append(StringName(spell) if (spell is String or spell is StringName) else &"")
		state._trim_spells()
	return state


# --- Internals ---

static func _tree(tree: TalentTree) -> TalentTree:
	return tree if tree != null else TalentTree.get_default()


func _set_level(id: StringName, level: int) -> void:
	if level <= 0:
		levels.erase(id)
	else:
		levels[id] = level


## Points in ranks below rank of one path (only talents the tree knows count).
func _points_below_rank(tree: TalentTree, talent_path: StringName, rank: int) -> int:
	var total := 0
	for talent in tree.get_path_talents(talent_path):
		if talent.rank < rank:
			total += get_level(talent.id)
	return total


## Every taken talent of the path stands on enough points in the ranks below it.
func _ranks_hold(tree: TalentTree, talent_path: StringName) -> bool:
	for talent in tree.get_path_talents(talent_path):
		if get_level(talent.id) > 0 and _points_below_rank(tree, talent_path, talent.rank) < tree.get_rank_threshold(talent.rank):
			return false
	return true


## Catalog talents from rank 4 down to rank 1, later catalog entries first within a rank. Taking a
## point from the first taken talent of this order never breaks a rank threshold.
static func _highest_rank_first(tree: TalentTree) -> Array[TalentDef]:
	var order: Array[TalentDef] = []
	for rank in range(TalentDef.MAX_RANK, TalentDef.MIN_RANK - 1, -1):
		for index in range(tree.talents.size() - 1, -1, -1):
			var talent := tree.talents[index]
			if talent != null and talent.rank == rank:
				order.append(talent)
	return order


func _all_ranks_hold(tree: TalentTree) -> bool:
	for talent_path in TalentDef.PATHS:
		if not _ranks_hold(tree, talent_path):
			return false
	return true


## Unequips spells that are no longer unlocked or lost their slot.
func _drop_locked_spells(tree: TalentTree) -> void:
	var unlocked := get_unlocked_spells(tree)
	var slots := get_spell_slots(tree)
	for slot in equipped_spells.size():
		if slot >= slots or not unlocked.has(equipped_spells[slot]):
			equipped_spells[slot] = &""
	_trim_spells()


func _trim_spells() -> void:
	while not equipped_spells.is_empty() and equipped_spells[-1] == &"":
		equipped_spells.pop_back()
