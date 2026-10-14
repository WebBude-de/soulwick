class_name BiomeGrade
extends RefCounted
## Colour grading of a biome (L1, "Biom-Stimmung"): a split tone drawn by vision.gdshader on top of
## the lit scene. Shadows are lifted a little towards the biome colour, highlights are tinted
## (multiplied with the tint normalised to its brightness, so they shift hue without getting darker),
## a soft vignette sinks the screen edges into the biome darkness and faint mist drifts where light
## falls. Pure optics; LightingQuality low switches it off.
## All numbers are TESTWERTE (L1).

## Biome id -> [shadow lift colour, highlight tint, amount, vignette, mist].
## Krypta cool violet, Schleimgrotte greenish, Schattenreich deep blue-violet, Glutschmiede warm red.
const TABLE := {
	&"crypt": [Color(0.1, 0.065, 0.19), Color(0.94, 0.92, 1.0), 1.0, 0.3, 0.075],
	&"slime_grotto": [Color(0.035, 0.12, 0.085), Color(0.9, 1.0, 0.84), 1.0, 0.26, 0.12],
	&"shadow_realm": [Color(0.075, 0.05, 0.21), Color(0.86, 0.85, 1.0), 1.0, 0.34, 0.1],
	&"ember_forge": [Color(0.17, 0.055, 0.03), Color(1.0, 0.88, 0.74), 1.0, 0.28, 0.06],
}
## Unknown biome (before the first room): a calm neutral dungeon look.
const DEFAULT_ROW := [Color(0.07, 0.06, 0.12), Color(1.0, 1.0, 1.0), 0.8, 0.26, 0.04]
## Village at night (D-107 look, L1 "Dorf wärmer"): blue shadows, warm lamp-lit highlights. The
## evening vignette (world/village/evening_vignette.gdshader) already darkens the edges.
const VILLAGE_NIGHT_ROW := [Color(0.03, 0.05, 0.15), Color(1.0, 0.84, 0.64), 1.0, 0.0, 0.025]

var shadow := Color(0, 0, 0)
var highlight := Color(1, 1, 1)
var amount := 0.0
var vignette := 0.0
var mist := 0.0


static func create(row: Array) -> BiomeGrade:
	var grade := BiomeGrade.new()
	grade.shadow = row[0]
	grade.highlight = row[1]
	grade.amount = float(row[2])
	grade.vignette = float(row[3])
	grade.mist = float(row[4])
	return grade


## No grading at all (menu, village by day, quality low).
static func neutral() -> BiomeGrade:
	return BiomeGrade.new()


static func for_biome(biome_id: StringName) -> BiomeGrade:
	return create(TABLE.get(biome_id, DEFAULT_ROW))


## Village look for a night amount (0 = day: neutral, 1 = full night).
static func for_village(night: float) -> BiomeGrade:
	return neutral().lerp_to(create(VILLAGE_NIGHT_ROW), clampf(night, 0.0, 1.0))


## Blend towards other by t (0 = this, 1 = other); returns a new grade.
func lerp_to(other: BiomeGrade, t: float) -> BiomeGrade:
	var result := BiomeGrade.new()
	result.shadow = shadow.lerp(other.shadow, t)
	result.highlight = highlight.lerp(other.highlight, t)
	result.amount = lerpf(amount, other.amount, t)
	result.vignette = lerpf(vignette, other.vignette, t)
	result.mist = lerpf(mist, other.mist, t)
	return result
