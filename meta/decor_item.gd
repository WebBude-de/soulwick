class_name DecorItem
extends RefCounted
## One thing from the decoration catalog (WK5 village decoration, WK7 furniture, D-202, D-205): a
## kind in one style (e.g. "armchair_cozy" with its _front and _side view) or a village decoration
## ("flower_bed_red"), or a wallpaper or floor style of the home (SURFACE). Built by DecorCatalog
## from the delivered JSON files (SPRITES_V13 Teil E), never listed in code.
## Rotation (rot 0..3): 0 front, 1 side, 2 front mirrored, 3 side mirrored; without a _side view
## only 0 and 2 (the opposite side is the mirrored picture, as the briefing says). Footprints are in
## tiles (wide × deep); wall pieces have depth 0 and hang on the back wall of the home.

const FRONT := &"front"
const SIDE := &"side"
## Kind of placement: on the floor (FLOOR), on the back wall (WALL) or a whole surface of the home
## (SURFACE: wallpaper or floor style, chosen instead of placed).
enum Placement { FLOOR, WALL, SURFACE }

## Stable id in the save ("armchair_cozy", "flower_bed_red", "home_wall_soul").
var id := ""
## DecorCatalog.HOME or DecorCatalog.VILLAGE.
var space: StringName = &""
## Group of the delivery ("seating", "garden", "surfaces").
var group := ""
## Kind without style ("armchair"), the display name comes from it.
var kind := ""
## "cozy", "rustic", "soul" or "" (village decoration has no style).
var style := ""
var placement := Placement.FLOOR
## Gold price (DecorCatalog.price_for, TESTWERT).
var price := 0
## view (FRONT/SIDE) -> spec from the JSON (file, frame_size, pivot, footprint, blocks, light, anim).
var views: Dictionary = {}
## Folder of the files (res://…/<group>/).
var dir := ""


func has_side() -> bool:
	return views.has(SIDE)


## Rotations this item has (4 with a side view, 2 without; surfaces 1).
func rotation_count() -> int:
	if placement == Placement.SURFACE:
		return 1
	return 4 if has_side() else 2


## The next rotation after rot (wraps).
func next_rotation(rot: int) -> int:
	if rotation_count() <= 1:
		return 0
	if has_side():
		return (rot + 1) % 4
	return 2 if rot < 2 else 0


func normalized_rotation(rot: int) -> int:
	var count := rotation_count()
	if count <= 1:
		return 0
	rot = posmod(rot, 4)
	if not has_side() and rot % 2 == 1:
		rot -= 1
	return rot


func view_for(rot: int) -> StringName:
	return SIDE if has_side() and normalized_rotation(rot) % 2 == 1 else FRONT


func is_flipped(rot: int) -> bool:
	return normalized_rotation(rot) >= 2


func spec(rot := 0) -> Dictionary:
	return views.get(view_for(rot), views.get(FRONT, {}))


## Tiles wide × deep for rot (the side view's own footprint; wall pieces have depth 0).
func footprint(rot := 0) -> Vector2i:
	var size: Array = spec(rot).get("footprint", [1, 1])
	return Vector2i(maxi(1, int(size[0])), maxi(0, int(size[1])))


func frame_size(rot := 0) -> Vector2i:
	var size: Array = spec(rot).get("frame_size", [32, 32])
	return Vector2i(int(size[0]), int(size[1]))


## Pivot in frame px (bottom centre in the delivery).
func pivot(rot := 0) -> Vector2:
	var point: Array = spec(rot).get("pivot", [16, 31])
	return Vector2(float(point[0]), float(point[1]))


## Blocks walking (collision over the footprint).
func blocks() -> bool:
	return placement == Placement.FLOOR and bool(spec().get("blocks", false))


## Lies flat on the ground under the players (rugs, paving): its own layer, may lie under furniture.
func is_flat() -> bool:
	return bool(spec().get("flat", false)) or (group == "rugs" and not blocks())


func is_wall() -> bool:
	return placement == Placement.WALL


func is_surface() -> bool:
	return placement == Placement.SURFACE


## {"at": Vector2 (frame px), "color": Color} or {} without light.
func light() -> Dictionary:
	var data: Variant = spec().get("light", null)
	if not data is Dictionary or not (data as Dictionary).has("at"):
		return {}
	var at: Array = data["at"]
	return {"at": Vector2(float(at[0]), float(at[1])), "color": Color.from_string(String(data.get("color", "#ffd166")), Color("#ffd166"))}


## File name of the animation strip (overlay over the picture, or the picture itself when the
## still file is missing), "" without one.
func anim_file(rot := 0) -> String:
	return String(spec(rot).get("anim", ""))


## Frames of a strip from its name (<name>_<n>f.png), 1 without the suffix.
static func frames_of(file: String) -> int:
	var regex := RegEx.create_from_string("_(\\d+)f\\.png$")
	var found := regex.search(file)
	return maxi(1, int(found.get_string(1))) if found != null else 1
