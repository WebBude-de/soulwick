class_name AbyssFace
extends RefCounted
## The rock face under the north edge of an abyss in a terrain room (playtest 15.10.2026, notes 2, 3
## and 6: "the north edge where you can fall is odd", a wall front seemed to stand over the abyss
## with a dark strip below it). The face is no wall front any more: it hangs below the abyss's own
## rim (the same wavy edge as its other sides, so all four sides of a hole match), starts a little
## darker than the rock and sinks into the void of the abyss over the tile, without an end piece,
## rounded corners or a line at its foot. Where the abyss ends to the west or east its side rim runs
## up to the north rim, the face only fills the void between them.
## One picture per abyss piece (AbyssAutotile mask and inner corners), drawn over that piece by
## RoomTiles: the face is laid only on the void pixels of the piece. Where it ends beside abyss
## without a face (an inner corner of the abyss, the face of a deeper part begins), it fades out to
## the side instead of ending in a hard edge (playtest 15.10.2026, note 16). Optics only, cached per
## biome.

## Brightness of the face just under the rim (share of the void mixed in) and how fast it sinks into
## the void (share of the tile height where it is gone); alpha fades over the last part (TESTWERTE,
## look).
const START_DARK := 0.3
const GONE_AT := 0.85
const FADE_FROM := 0.7
## A pixel of the abyss piece belongs to the void up to this much above the void's luminance (the
## rim is far lighter, its dark dither counts as void).
const VOID_MARGIN := 0.1
## Width (art px) over which a face fades out at an end beside abyss without a face (TESTWERT, look).
const SIDE_FADE := 12.0

static var _textures: Dictionary[String, Texture2D] = {}
## The abyss art of a tileset as an image, by the texture's RID: get_image() reads the atlas back from
## the GPU, once per sheet instead of once per face piece (feedback 16.10.2026, the first rooms of a
## biome hitched).
static var _arts: Dictionary[RID, Image] = {}


## Face over the abyss piece (mask, corners) of tileset (biome rock face, biome abyss art); null
## without the art.
static func texture_for(tileset: TileSet, biome_id: StringName, mask: int, corners: int, fade_left := false, fade_right := false) -> Texture2D:
	var key := "%s|%d|%d|%s|%s" % [biome_id, mask, corners, fade_left, fade_right]
	if _textures.has(key):
		return _textures[key]
	var face := RockTerrain.face_image(biome_id)
	var art := _abyss_art(tileset)
	if face == null or art == null:
		return null
	var image := build(face, art, mask, corners, fade_left, fade_right)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## The face picture (32 x 32) for one abyss piece from the rock face and the delivered abyss art.
static func build(face: Image, art: Image, mask: int, corners: int, fade_left := false, fade_right := false) -> Image:
	var tile := AbyssAutotile.TILE
	var piece := AbyssRims.make_piece(art, mask, corners)
	var void_tile := art.get_region(Rect2i(AbyssAutotile.ART_VOID[0] * tile, Vector2i(tile, tile)))
	var void_color := _most_common(void_tile)
	var limit := void_color.get_luminance() + VOID_MARGIN
	var image := Image.create_empty(tile, tile, false, Image.FORMAT_RGBA8)
	for x in tile:
		# The face starts under the rim of this column.
		var top := 0
		while top < tile and piece.get_pixel(x, top).get_luminance() > limit:
			top += 1
		for y in range(top, tile):
			var pixel := piece.get_pixel(x, y)
			if pixel.get_luminance() > limit:
				continue
			var t := float(y - top) / float(maxi(1, tile - top))
			var dark := clampf(START_DARK + (1.0 - START_DARK) * t / GONE_AT, 0.0, 1.0)
			var color := face.get_pixel(x, y).lerp(void_color, dark)
			color.a = 1.0 - smoothstep(FADE_FROM, 1.0, t)
			if fade_left:
				color.a *= smoothstep(0.0, 1.0, (x + 0.5) / SIDE_FADE)
			if fade_right:
				color.a *= smoothstep(0.0, 1.0, (tile - x - 0.5) / SIDE_FADE)
			image.set_pixel(x, y, color)
	return image


static func _abyss_art(tileset: TileSet) -> Image:
	if tileset == null or not tileset.has_source(AbyssAutotile.ART_SOURCE_ID):
		return null
	var source := tileset.get_source(AbyssAutotile.ART_SOURCE_ID) as TileSetAtlasSource
	if source == null or source.texture == null:
		return null
	var key := source.texture.get_rid()
	if _arts.has(key):
		return _arts[key]
	var image := source.texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	_arts[key] = image
	return image


static func _most_common(image: Image) -> Color:
	var counts: Dictionary[Color, int] = {}
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			counts[pixel] = counts.get(pixel, 0) + 1
	var best := Color.BLACK
	var best_count := -1
	for color: Color in counts:
		if counts[color] > best_count:
			best = color
			best_count = counts[color]
	return best
