class_name TalentTreeArt
extends RefCounted
## Pictures of the talent tree view (SPRITES_V13 §B5, art/ui/talents/): node frames for the four
## states (aus, verfügbar, gesetzt, Schlussstein), the glow strip of a full node, the path symbols
## and the candle branches (8×8, tile vertically). Talent icons come from TalentDef.get_icon(). A
## missing file gets a drawn placeholder in the path colour, so the view always works.

const DIR := "res://art/ui/talents/"
const NODE_SIZE := 22
const PATH_ICON_SIZE := 24
const BRANCH_SIZE := 8
const GLOW_FRAMES := 4
const GLOW_FPS := 6.0
## Path colours (Mockup 14: Wind türkis, Glut orange, Seele violett; the altar's candles).
const PATH_COLORS := {
	TalentDef.PATH_WIND: Color("#5ee6b8"),
	TalentDef.PATH_EMBER: Color("#ff8a3c"),
	TalentDef.PATH_SOUL: Color("#a66ef0"),
}
const LOCKED_COLOR := Color("#5d577a")
const OUTLINE := Color("#1c1a2b")

static var _cache: Dictionary[String, Texture2D] = {}


static func path_color(talent_path: StringName) -> Color:
	return PATH_COLORS.get(talent_path, UiKit.COLOR_GOLD)


## Node frame for a state; capstone nodes use the gold frame once they are open.
static func node_frame(state: TalentTreeEdit.NodeState, capstone: bool) -> Texture2D:
	if state == TalentTreeEdit.NodeState.LOCKED:
		return _texture("node_locked", func() -> Image: return _ring_image(LOCKED_COLOR, false))
	if capstone:
		return _texture("node_capstone", func() -> Image: return _ring_image(UiKit.COLOR_GOLD, true))
	if state == TalentTreeEdit.NodeState.AVAILABLE:
		return _texture("node_available", func() -> Image: return _ring_image(UiKit.COLOR_TEXT_SOFT, false))
	return _texture("node_taken", func() -> Image: return _ring_image(PATH_COLORS[TalentDef.PATH_EMBER], true))


## Frame index of the glow strip for a time (s); the strip itself via glow_strip().
static func glow_frame(time: float) -> int:
	return int(floor(time * GLOW_FPS)) % GLOW_FRAMES


## The 4-frame glow of a full node (null while missing: the view draws the plain taken frame).
static func glow_strip() -> Texture2D:
	var path := DIR + "node_taken_glow_4f.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func path_icon(talent_path: StringName) -> Texture2D:
	var art := "path_" + String(talent_path)
	return _texture(art, func() -> Image: return _flame_image(path_color(talent_path), PATH_ICON_SIZE))


## Vertical branch tile (8×8) of a path.
static func branch(talent_path: StringName) -> Texture2D:
	var art := "branch_" + String(talent_path)
	return _texture(art, func() -> Image: return _branch_image(path_color(talent_path)))


## Icon of a talent node: the delivered talent icon, the spell symbol, else a drawn flame.
static func talent_icon(talent: TalentDef) -> Texture2D:
	var icon := talent.get_icon() if talent != null else null
	if icon != null:
		return icon
	var key := "icon_" + (String(talent.path) if talent != null else "none")
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_flame_image(path_color(talent.path if talent != null else &""), 16))
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()


static func _texture(art_name: String, placeholder: Callable) -> Texture2D:
	if _cache.has(art_name):
		return _cache[art_name]
	var path := DIR + art_name + ".png"
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture == null:
		texture = ImageTexture.create_from_image(placeholder.call() as Image)
	_cache[art_name] = texture
	return texture


## 22×22 ring with a dark inside; filled rings get a soft inner tint.
static func _ring_image(color: Color, filled: bool) -> Image:
	var image := Image.create(NODE_SIZE, NODE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(NODE_SIZE - 1, NODE_SIZE - 1) * 0.5
	for y in NODE_SIZE:
		for x in NODE_SIZE:
			var d := Vector2(x, y).distance_to(centre)
			if d <= 10.5 and d > 9.0:
				image.set_pixel(x, y, color)
			elif d <= 9.0 and d > 8.0:
				image.set_pixel(x, y, OUTLINE)
			elif d <= 8.0:
				image.set_pixel(x, y, Color(color.darkened(0.7), 1.0) if filled else Color("#221f33"))
	return image


## Small flame in a colour (path symbol and icon placeholder).
static func _flame_image(color: Color, size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre_x := (size - 1) * 0.5
	for y in size:
		var t := float(y) / float(size - 1)
		var half := sin(t * PI * 0.85) * size * 0.3
		for x in size:
			var dx := absf(x - centre_x)
			if t > 0.15 and dx <= half:
				image.set_pixel(x, y, color.lightened(0.5) if dx < half * 0.4 and t > 0.5 else color)
	return image


static func _branch_image(color: Color) -> Image:
	var image := Image.create(BRANCH_SIZE, BRANCH_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in BRANCH_SIZE:
		image.set_pixel(3, y, color)
		image.set_pixel(4, y, color.darkened(0.3))
	return image
