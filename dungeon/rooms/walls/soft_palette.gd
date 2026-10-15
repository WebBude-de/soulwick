class_name SoftPalette
extends RefCounted
## Fits delivered art of the V9 delivery (SPRITES_V9: inner corners, cracked walls, niche, cave
## breach) to the soft rock of the rooms (M1). V9 was drawn in its own soft palette (darker rock top,
## greyer edge band) than the rock sheets the rooms use (rock_blob_crypt_soft and its palette swaps
## by tools/build_tilesets.gd); used as delivered, those pieces would stand out as dark patches.
## Every colour is moved by the offset of its nearest anchor (rock top, edge band light and middle,
## outline, front face and its dark streaks): anchors of the delivered biome set -> anchors of the
## room's rock sheet. Colours far from every anchor (a skull, a candle, a glowing crack) stay.
## Results are cached per file and biome; the delivered files are never written.

const TILES_DIR := "res://art/environment/tiles/"
## Colours further than this from every anchor keep their colour (RGB distance, 0..1.73).
const MAX_ANCHOR_DISTANCE := 0.22

enum Anchor { TOP, BAND_LIGHT, BAND_MIDDLE, OUTLINE, FRONT, FRONT_DARK }

static var _anchors: Dictionary[String, Array] = {}
static var _textures: Dictionary[String, Texture2D] = {}


## The delivered picture at path, recoloured from the V9 palette of from_biome to the room rock of
## to_biome (to_biome = from_biome when empty). Null without the file.
static func texture(path: String, from_biome: StringName, to_biome: StringName = &"") -> Texture2D:
	var target := to_biome if to_biome != &"" else from_biome
	var key := "%s|%s|%s" % [path, from_biome, target]
	if _textures.has(key):
		return _textures[key]
	var image := load_image(path)
	if image == null:
		return null
	var result := ImageTexture.create_from_image(fit(image, from_biome, target))
	_textures[key] = result
	return result


## A copy of image with the V9 colours of from_biome moved onto the room rock of to_biome. Without
## the anchor art of either side the image comes back unchanged.
static func fit(image: Image, from_biome: StringName, to_biome: StringName) -> Image:
	var source := delivered_anchors(from_biome)
	var target := room_anchors(to_biome)
	var result := image.duplicate() as Image
	if source.size() != Anchor.size() or target.size() != Anchor.size():
		return result
	var mapped: Dictionary[Color, Color] = {}
	for y in result.get_height():
		for x in result.get_width():
			var pixel := result.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			var opaque := Color(pixel.r, pixel.g, pixel.b)
			if not mapped.has(opaque):
				mapped[opaque] = _move(opaque, source, target)
			var moved: Color = mapped[opaque]
			result.set_pixel(x, y, Color(moved.r, moved.g, moved.b, pixel.a))
	return result


static func _move(color: Color, source: Array, target: Array) -> Color:
	var best := -1
	var best_distance := MAX_ANCHOR_DISTANCE
	for i in source.size():
		var anchor: Color = source[i]
		var distance := Vector3(color.r - anchor.r, color.g - anchor.g, color.b - anchor.b).length()
		if distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return color
	var from: Color = source[best]
	var to: Color = target[best]
	return Color(clampf(to.r + color.r - from.r, 0.0, 1.0), clampf(to.g + color.g - from.g, 0.0, 1.0), clampf(to.b + color.b - from.b, 0.0, 1.0))


## Anchors of the V9 set of a biome (Anchor order): rock top, band light, band middle and outline
## from rock_blob_<biome>_soft_inner, front and its dark streaks from wall_cracked_<biome>_soft.
static func delivered_anchors(biome_id: StringName) -> Array:
	var key := "v9:%s" % biome_id
	if _anchors.has(key):
		return _anchors[key]
	var result: Array = []
	var inner := load_image(TILES_DIR + "rock_blob_%s_soft_inner.png" % biome_id)
	var cracked := load_image(TILES_DIR + "wall_cracked_%s_soft.png" % biome_id)
	if inner != null and cracked != null:
		var counts := _counts(inner, Rect2i(0, 0, inner.get_width(), mini(inner.get_height(), 96)))
		var top := _most(counts)
		result = [top]
		result.append_array(_bands(counts, top))
		result.append(_darkest(counts))
		var faces := _counts(cracked, Rect2i(0, 16, cracked.get_width(), cracked.get_height() - 16))
		var front := _most(faces)
		faces.erase(front)
		result.append(front)
		result.append(_most(faces))
	_anchors[key] = result
	return result


## Anchors of the rock sheet a room of the biome draws (RockTerrain cave look).
static func room_anchors(biome_id: StringName) -> Array:
	var key := "room:%s" % biome_id
	if _anchors.has(key):
		return _anchors[key]
	var result: Array = []
	var sheet := load_image(String(RockTerrain.art_paths(biome_id, RockTerrain.Look.CAVE)["rock"]))
	if sheet != null:
		var full := RockTerrain.rock_coords(RockTerrain.FULL) * RockTerrain.TILE
		var top := _most(_counts(sheet, Rect2i(full, Vector2i(RockTerrain.TILE, RockTerrain.TILE))))
		var band := RockTerrain.band_colors(sheet)
		var front_at := RockTerrain.front_coords(RockTerrain.Front.MIDDLE) * RockTerrain.TILE
		var faces := _counts(sheet, Rect2i(front_at + Vector2i(0, 4), Vector2i(RockTerrain.TILE, RockTerrain.TILE - 6)))
		var front := _most(faces)
		faces.erase(front)
		result = [top, _opaque(band[0]), _opaque(band[RockTerrain.BAND / 2]), _darkest(_counts(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()))), front, _most(faces)]
	_anchors[key] = result
	return result


static func load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture_file := load(path) as Texture2D
	if texture_file == null:
		return null
	var image := texture_file.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _counts(image: Image, rect: Rect2i) -> Dictionary[Color, int]:
	var counts: Dictionary[Color, int] = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 1.0:
				continue
			counts[pixel] = counts.get(pixel, 0) + 1
	return counts


static func _most(counts: Dictionary[Color, int]) -> Color:
	var best := Color.BLACK
	var best_count := -1
	for color: Color in counts:
		if counts[color] > best_count:
			best_count = counts[color]
			best = color
	return _opaque(best)


## The two most frequent colours clearly lighter than top, the lighter one first (edge band).
static func _bands(counts: Dictionary[Color, int], top: Color) -> Array:
	var light: Dictionary[Color, int] = {}
	for color: Color in counts:
		if color.get_luminance() > top.get_luminance() + 0.12:
			light[color] = counts[color]
	var first := _most(light)
	light.erase(first)
	var second := _most(light) if not light.is_empty() else first
	return [first, second] if first.get_luminance() >= second.get_luminance() else [second, first]


## The darkest colour used more than a few times (the outline).
static func _darkest(counts: Dictionary[Color, int]) -> Color:
	var best := Color.WHITE
	for color: Color in counts:
		if counts[color] >= 20 and color.get_luminance() < best.get_luminance():
			best = color
	return _opaque(best)


static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b)
