class_name TalentTreeEdit
extends RefCounted
## One visit at the candle altar (KE8, KONZEPT §6.1, D-196): the stored distribution (saved) and the
## working copy the player changes (working). Setting points is free; points taken back below the
## stored level cost Seelenkristalle (TalentState.respec_cost of TalentState.refunded_points), paid
## from the world being played when the player confirms (apply). Pure rules without UI; the view
## (TalentTreeDialog) only shows what this says. Read-only visits (co-op guests, D-078/KE8 Koop-Check)
## refuse every change.
## Storage, wallet and the account level are replaceable callables, so tests never touch a real file
## (defaults: AccountTalents on AccountProgress.current(), SaveManager's permanent crystals).

signal changed

## What a node of the tree looks like (KE8: aus / verfügbar / gesetzt; the capstone frame is
## TalentDef.is_capstone on top of these).
enum NodeState { LOCKED, AVAILABLE, TAKEN, FULL }

## Why a point cannot be set or taken back (empty reason = it can).
enum Reason { NONE, READ_ONLY, LOCKED, NO_POINTS, FULL, EMPTY, HOLDS_HIGHER }

var tree: TalentTree = null
var saved: TalentState = null
var working: TalentState = null
## Talent points of the account level (TalentState.points_for_level).
var available_points := 0
## false: only look (co-op guests); every change is refused.
var editable := true
## () -> int: Seelenkristalle of the world being played.
var crystals_source: Callable = func() -> int: return SaveManager.get_permanent_crystals()
## (amount: int) -> bool: takes the fee; false when it cannot.
var spend_crystals: Callable = func(amount: int) -> bool: return TalentTreeEdit._spend_from_save(amount)
## (amount: int) -> void: gives the fee back when storing failed.
var refund_crystals: Callable = func(amount: int) -> void: SaveManager.add_permanent_crystals(amount)
## (state: TalentState) -> Error: stores the distribution of the account.
var store: Callable = func(state: TalentState) -> Error: return AccountTalents.save_state(state)


## A visit for this machine's account (AccountTalents, D-152: one character per account).
static func for_account(can_edit := true, progress: AccountProgress = null) -> TalentTreeEdit:
	var account := progress if progress != null else AccountProgress.current()
	var points := TalentState.points_for_level(account.get_level())
	return create(AccountTalents.load_state(account), points, can_edit)


## A visit on a given distribution (tests, the guild character later, MP8b).
static func create(state: TalentState, points: int, can_edit := true, catalog: TalentTree = null) -> TalentTreeEdit:
	var edit := TalentTreeEdit.new()
	edit.tree = catalog if catalog != null else TalentTree.get_default()
	edit.available_points = maxi(0, points)
	edit.saved = (state if state != null else TalentState.new()).sanitized(edit.available_points, edit.tree)
	edit.working = edit.saved.duplicate_state()
	edit.editable = can_edit
	return edit


# --- Points ---

func get_free_points() -> int:
	return maxi(0, available_points - working.get_spent_points())


func get_level(id: StringName) -> int:
	return working.get_level(id)


func can_raise(id: StringName) -> bool:
	return raise_reason(id) == Reason.NONE


func can_lower(id: StringName) -> bool:
	return lower_reason(id) == Reason.NONE


func raise_reason(id: StringName) -> Reason:
	var talent := tree.get_talent(id)
	if not editable:
		return Reason.READ_ONLY
	if talent == null:
		return Reason.LOCKED
	if working.get_level(id) >= talent.max_level:
		return Reason.FULL
	if not working.is_rank_open(talent.path, talent.rank, tree):
		return Reason.LOCKED
	if get_free_points() <= 0:
		return Reason.NO_POINTS
	return Reason.NONE


func lower_reason(id: StringName) -> Reason:
	if not editable:
		return Reason.READ_ONLY
	if working.get_level(id) <= 0:
		return Reason.EMPTY
	if not working.can_lower(id, tree):
		return Reason.HOLDS_HIGHER
	return Reason.NONE


## One point more (free). A spell talent puts its spell into the first empty slot.
func raise(id: StringName) -> bool:
	if not can_raise(id):
		return false
	working.raise(id, available_points, tree)
	var talent := tree.get_talent(id)
	if talent != null and talent.unlocks_spell() and working.get_level(id) == 1:
		_auto_equip(talent.spell)
	changed.emit()
	return true


## One point back; what it costs is charged on apply().
func lower(id: StringName) -> bool:
	if not can_lower(id):
		return false
	working.lower(id, tree)
	changed.emit()
	return true


## Points (or 0) a talent of rank needs in its path before it opens.
func get_rank_threshold(rank: int) -> int:
	return tree.get_rank_threshold(rank)


func is_rank_open(talent_path: StringName, rank: int) -> bool:
	return working.is_rank_open(talent_path, rank, tree)


func get_path_points(talent_path: StringName) -> int:
	return working.get_path_points(talent_path, tree)


func get_node_state(id: StringName) -> NodeState:
	var talent := tree.get_talent(id)
	if talent == null:
		return NodeState.LOCKED
	var level := working.get_level(id)
	if level >= talent.max_level:
		return NodeState.FULL
	if level > 0:
		return NodeState.TAKEN
	if working.is_rank_open(talent.path, talent.rank, tree):
		return NodeState.AVAILABLE
	return NodeState.LOCKED


# --- Spells ---

func get_spell_slots() -> int:
	return working.get_spell_slots(tree)


func get_unlocked_spells() -> Array[StringName]:
	return working.get_unlocked_spells(tree)


func get_equipped_spell(slot: int) -> StringName:
	return working.get_equipped_spell(slot)


func equip_spell(spell: StringName, slot: int) -> bool:
	if not editable or not working.equip_spell(spell, slot, tree):
		return false
	changed.emit()
	return true


func unequip_spell(slot: int) -> bool:
	if not editable or working.get_equipped_spell(slot) == &"":
		return false
	working.unequip_spell(slot)
	changed.emit()
	return true


func _auto_equip(spell: StringName) -> void:
	for slot in working.get_spell_slots(tree):
		if working.get_equipped_spell(slot) == &"":
			working.equip_spell(spell, slot, tree)
			return


# --- Respec and storing ---

## Something differs from the stored distribution.
func is_dirty() -> bool:
	return working.to_dict() != saved.to_dict()


## Points taken back below the stored levels (raising elsewhere does not offset it, D-196).
func get_refunded_points() -> int:
	return TalentState.refunded_points(saved, working)


## Seelenkristalle the confirm costs (0 = free).
func get_cost() -> int:
	return TalentState.respec_cost(get_refunded_points())


func get_crystals() -> int:
	return int(crystals_source.call()) if crystals_source.is_valid() else 0


func can_afford() -> bool:
	return get_cost() <= get_crystals()


func can_apply() -> bool:
	return editable and is_dirty() and can_afford()


## Pays the fee and stores the working copy. True when stored (or nothing to store).
func apply() -> bool:
	if not is_dirty():
		return true
	if not editable or not can_afford():
		return false
	var cost := get_cost()
	if cost > 0 and not bool(spend_crystals.call(cost)):
		return false
	var error: Error = store.call(working.duplicate_state())
	if error != OK:
		if cost > 0:
			refund_crystals.call(cost)
		push_warning("TalentTreeEdit: storing the talents failed (%s); nothing was charged." % error_string(error))
		return false
	saved = working.duplicate_state()
	changed.emit()
	return true


## Back to the stored distribution.
func discard() -> void:
	if not is_dirty():
		return
	working = saved.duplicate_state()
	changed.emit()


static func _spend_from_save(amount: int) -> bool:
	if not SaveManager.try_spend_permanent_crystals(amount):
		return false
	SaveManager.save_game()
	return true
