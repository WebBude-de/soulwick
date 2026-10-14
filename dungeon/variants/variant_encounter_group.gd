class_name VariantEncounterGroup
extends EncounterGroup
## Encounter rules of a variant room: the room's own group (theme, quiet room, A3) with a variant's
## changes on top - fewer enemies in the first wave (rifts bring the rest) or more of one type
## (gravedigger: skeletons). The spawner reads it like any EncounterGroup (filter_table is
## overridden), so nothing in EnemySpawner changes.

## Instance id of the variant that built this group (it shapes the room only once).
var owner_id := 0
## The room's group before the variant (null = default rules).
var base: EncounterGroup = null
## Enemy id -> weight factor in the biome table.
var weight_factors: Dictionary[StringName, float] = {}


## Wraps base (may be null) for a variant: count multiplied by count_multiplier, weights of the
## given ids multiplied by their factor. Elite and type rules stay those of base.
static func wrap(source: EncounterGroup, owner: Object, count_multiplier: float, factors: Dictionary[StringName, float] = {}) -> VariantEncounterGroup:
	var group := VariantEncounterGroup.new()
	group.owner_id = owner.get_instance_id() if owner != null else 0
	group.base = source
	if source != null:
		group.id = source.id
		group.attack_kind = source.attack_kind
		group.tags = source.tags.duplicate()
		group.count_range = source.count_range
		group.count_factor = source.count_factor
		group.health_factor = source.health_factor
		group.allow_elites = source.allow_elites
		group.allow_extra_types = source.allow_extra_types
	group.count_factor *= count_multiplier
	group.weight_factors = factors.duplicate()
	return group


func filter_table(types: Array[EnemyData], weights: Array[float]) -> Array:
	var table: Array = base.filter_table(types, weights) if base != null else super.filter_table(types, weights)
	if weight_factors.is_empty():
		return table
	var kept_types: Array[EnemyData] = table[0]
	var kept_weights: Array[float] = table[1]
	var shaped: Array[float] = []
	for i in kept_types.size():
		var weight: float = kept_weights[i] if i < kept_weights.size() else 1.0
		var data := kept_types[i]
		if data != null and weight_factors.has(data.id):
			weight *= weight_factors[data.id]
		shaped.append(weight)
	return [kept_types, shaped]
