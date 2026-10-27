class_name TalentTree
extends Resource
## The talent catalog (KONZEPT §6.1, D-194): three paths of four ranks; a rank opens once enough
## points sit in the lower ranks of the same path (rank_thresholds: 0/3/7/11, TESTWERT). Data in
## talents/talent_tree.tres; the same tree serves the solo character and later the guild character
## (MP8b) – only the TalentState differs.

const DEFAULT_PATH := "res://talents/talent_tree.tres"

## Points needed in the lower ranks of a path to open rank 1..4 (index = rank - 1). TESTWERT.
@export var rank_thresholds: Array[int] = [0, 3, 7, 11]
@export var talents: Array[TalentDef] = []

static var _default: TalentTree = null


## The tree of the game, loaded once.
static func get_default() -> TalentTree:
	if _default == null:
		_default = load(DEFAULT_PATH) as TalentTree
	return _default


func get_talent(id: StringName) -> TalentDef:
	for talent in talents:
		if talent != null and talent.id == id:
			return talent
	return null


func has_talent(id: StringName) -> bool:
	return get_talent(id) != null


## Talents of one path in catalog order (rank by rank).
func get_path_talents(talent_path: StringName) -> Array[TalentDef]:
	var result: Array[TalentDef] = []
	for talent in talents:
		if talent != null and talent.path == talent_path:
			result.append(talent)
	return result


func get_rank_talents(talent_path: StringName, rank: int) -> Array[TalentDef]:
	var result: Array[TalentDef] = []
	for talent in get_path_talents(talent_path):
		if talent.rank == rank:
			result.append(talent)
	return result


## Points in lower ranks of the same path that open rank (1 → 0).
func get_rank_threshold(rank: int) -> int:
	var index := clampi(rank, TalentDef.MIN_RANK, TalentDef.MAX_RANK) - 1
	return rank_thresholds[index] if index < rank_thresholds.size() else 0


## Talent that unlocks spell, null if none does.
func get_spell_talent(spell: StringName) -> TalentDef:
	for talent in talents:
		if talent != null and talent.unlocks_spell() and talent.spell == spell:
			return talent
	return null


## All spell ids the tree can unlock, in catalog order.
func get_spells() -> Array[StringName]:
	var result: Array[StringName] = []
	for talent in talents:
		if talent != null and talent.unlocks_spell():
			result.append(talent.spell)
	return result


## Points to fill the whole tree.
func get_total_cost() -> int:
	var total := 0
	for talent in talents:
		if talent != null:
			total += talent.max_level
	return total
