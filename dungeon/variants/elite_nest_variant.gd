class_name EliteNestVariant
extends CombatVariant
## Variant "Elite-Nest" (KONZEPT_RAEUME §4.8, D-101, D-105): only reachable through a branch, never
## drawn by the variant table. Few but strong enemies: 2-3 elites, or one champion with a small
## escort. Clearing the room is the success (no own failure): a bonus chest with an upgrade choice
## (D-109) and double soul crystals (NEST_CRYSTALS, twice a champion's).
## The variant table belongs to A9: attach() hangs the variant on without a registration in
## CombatVariant.create (hook for the integrator in the A10 report).

const ID := BranchOption.ELITE_NEST_ID
## Enemies of each wave: elites (inclusive range) or the champion with its escort. TESTWERTE
const ELITE_COUNT := Vector2i(2, 3)
const CHAMPION_ESCORT := Vector2i(1, 2)
## Share of the nests with one champion instead of elites. TESTWERT
const CHAMPION_CHANCE := 0.35
## Soul crystals for clearing the nest, for the group ("doppelte Kristalle": a champion gives 1). TESTWERT
const NEST_CRYSTALS := 2
## Gold of a nest elite is multiplied like any elite's (EnemySpawner.ELITE_GOLD_MULTIPLIER).
const ELITE_KINDS: Array[Enemy.Elite] = [Enemy.Elite.SWIFT, Enemy.Elite.ARMORED, Enemy.Elite.VOLATILE]

var champion_mode := false
var champion: Enemy = null

var _center := Vector2.ZERO


## Hangs an elite nest onto a prepared normal combat room (like CombatVariant.attach_to). rng_seed: one
## number of the dungeon RNG, drawn by the caller in any case. null if the room cannot take it.
static func attach(target: RoomController, rng_seed: int) -> EliteNestVariant:
	if target == null or not is_instance_valid(target) or not target.has_room_kind() or CombatVariant.of(target) != null:
		return null
	var variant := EliteNestVariant.new()
	variant.variant_id = ID
	variant.room = target
	variant.context = target.context
	variant._rng.seed = rng_seed
	variant._free = VariantSpots.free_tiles(target)
	variant.name = NODE_NAME
	variant.y_sort_enabled = true
	target.add_child(variant)
	variant._connect_room()
	variant._on_attach()
	return variant


func _on_attach() -> void:
	champion_mode = _rng.randf() < CHAMPION_CHANCE
	# The chest stands near the middle of the floor (room-local, on a free tile).
	_center = room.tiles.get_floor_rect().get_center()


## Fixed small waves: 2-3 elites, or the champion and 1-2 escorts. The spawner's own elite roll is
## off, the nest makes its enemies itself (_on_enemy_added).
func _shape_group(group: EncounterGroup) -> EncounterGroup:
	var shaped := VariantEncounterGroup.wrap(group, self, 1.0)
	shaped.count_range = (Vector2i(1, 0) + CHAMPION_ESCORT) if champion_mode else ELITE_COUNT
	shaped.count_factor = 1.0
	shaped.health_factor = 1.0
	shaped.allow_elites = false
	return shaped


## Every enemy of the nest is an elite; in champion mode the first one is the champion instead.
## Runs before the enemy's _ready (child_entered_tree), so scaling and traits apply cleanly.
func _on_enemy_added(enemy: Enemy) -> void:
	if enemy.data == null or enemy.data.is_boss or enemy.is_miniboss:
		return
	if champion_mode:
		if champion == null:
			champion = enemy
			enemy.apply_scaling(room.room_index, true)
			enemy.make_elite(ELITE_KINDS[_rng.randi_range(0, ELITE_KINDS.size() - 1)])
			enemy.set_boss_tier(RoomSequence.get_boss_tier(room.room_index))
			enemy.gold_drop *= EnemySpawner.ELITE_GOLD_MULTIPLIER * 2
		return
	if enemy.elite == Enemy.Elite.NONE:
		enemy.make_elite(ELITE_KINDS[_rng.randi_range(0, ELITE_KINDS.size() - 1)])
		enemy.gold_drop *= EnemySpawner.ELITE_GOLD_MULTIPLIER


func _is_bonus_met() -> bool:
	return true


func _on_finish() -> void:
	if bonus != Bonus.ACHIEVED:
		return
	RunManager.add_run_crystals(NEST_CRYSTALS)
	show_banner(DungeonTexts.t(&"BRANCH_NEST_CLEARED"), DungeonTexts.t(&"BRANCH_NEST_CLEARED_SUB", [NEST_CRYSTALS]), BONUS_COLOR)
	spawn_bonus_chests(_center)
