class_name IngredientSet
extends Resource
## Ingredients of one biome (KONZEPT_RAEUME §3.3): which elements the IngredientScatter may put
## into a normal combat room, how likely each one is and how many pieces it places. One .tres per
## biome in dungeon/rooms/ingredients/sets/<biome id>.tres; the biome .tres points to it with the
## metadata entry "ingredient_set" (BiomeData has no field for it yet, see for_biome()).
## All numbers are TESTWERTE; balancing happens in the .tres files without code changes.

## The six ingredients of A3. Arena waves (A5), small abyss holes (A4) and cracked walls (A10)
## come with their packages.
enum Kind { COVER, TRAPS, WALLS, CHOKEPOINTS, LIGHT, EXPLOSIVES }
## Free-standing light of the light islands.
enum LightStyle { CRYSTAL, TORCH_STAND }

const SET_PATH := "res://dungeon/rooms/ingredients/sets/%s.tres"
const DEFAULT_BIOME := &"crypt"
const META_KEY := &"ingredient_set"

@export var biome_id: StringName = DEFAULT_BIOME
## Ingredients per room, inclusive (2-3, never all; KONZEPT_RAEUME §3.3). TESTWERT
@export var count := Vector2i(2, 3)

@export_group("Weights (TESTWERTE)")
@export var cover_weight := 1.0
@export var traps_weight := 1.0
@export var walls_weight := 1.0
@export var chokepoints_weight := 0.8
@export var light_weight := 1.0
## 0 = never in this biome (explosive barrels: crypt and ember forge only).
@export var explosives_weight := 0.0

@export_group("Cover")
## Crates and barrels (Breakable) and rubble (Rubble, solid), picked uniformly per piece.
@export var cover_scenes: Array[PackedScene] = []
## Pieces in one cover group. TESTWERT
@export var cover_pieces := Vector2i(2, 4)
## Tint of the biome-neutral rubble art (SPRITES_V5 §1).
@export var rubble_tint := Color.WHITE

@export_group("Traps")
## The biome's trap (spike trap, toxic puddle, lava crack).
@export var trap_scene: PackedScene
## Tint of the trap (shadow thorns use the purple-tinted spike trap until own art exists).
@export var trap_tint := Color.WHITE
## Traps in one group. TESTWERT
@export var trap_pieces := Vector2i(2, 4)

@export_group("Walls")
## Inner wall or pillar pieces per room. TESTWERT
@export var wall_pieces := Vector2i(1, 3)

@export_group("Light")
@export var light_style: LightStyle = LightStyle.CRYSTAL
## Tint of the crystal / flame (the art is biome-neutral, SPRITES_V5 §1).
@export var light_color := Color(0.7, 0.95, 1.0)
## Light islands per room. TESTWERT
@export var light_pieces := Vector2i(1, 2)
## Chance that the light ingredient also leaves a dark zone in the room. TESTWERT
@export_range(0.0, 1.0) var dark_zone_chance := 0.5

@export_group("Explosives")
@export var explosive_scene: PackedScene
## Explosive barrels per room. TESTWERT
@export var explosive_pieces := Vector2i(1, 3)
## No explosive barrels before this room (gentle start). TESTWERT
@export var explosives_from_room := 3


## Weight of one ingredient in this biome (0 = never).
func get_weight(kind: Kind) -> float:
	match kind:
		Kind.COVER:
			return cover_weight if not cover_scenes.is_empty() else 0.0
		Kind.TRAPS:
			return traps_weight if trap_scene != null else 0.0
		Kind.WALLS:
			return walls_weight
		Kind.CHOKEPOINTS:
			return chokepoints_weight
		Kind.LIGHT:
			return light_weight
		Kind.EXPLOSIVES:
			return explosives_weight if explosive_scene != null else 0.0
	return 0.0


## Set of a biome: the "ingredient_set" metadata of the BiomeData, else the file named after the
## biome id, else the crypt set. Null only if no set exists at all.
static func for_biome(biome: BiomeData) -> IngredientSet:
	if biome != null and biome.has_meta(META_KEY):
		var linked := biome.get_meta(META_KEY) as IngredientSet
		if linked != null:
			return linked
	var biome_id: StringName = biome.id if biome != null else DEFAULT_BIOME
	return load_for_id(biome_id)


static func load_for_id(biome_id: StringName) -> IngredientSet:
	for id: StringName in [biome_id, DEFAULT_BIOME]:
		var path := SET_PATH % id
		if ResourceLoader.exists(path):
			return load(path) as IngredientSet
	return null


static func get_kind_name(kind: int) -> String:
	match kind:
		Kind.COVER:
			return "Deckung"
		Kind.TRAPS:
			return "Fallengruppe"
		Kind.WALLS:
			return "Innenmauern"
		Kind.CHOKEPOINTS:
			return "Engstelle/Nische"
		Kind.LIGHT:
			return "Licht/Dunkel"
		Kind.EXPLOSIVES:
			return "Explosionsfässer"
	return "?"
