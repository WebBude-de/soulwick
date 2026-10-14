class_name WallArt
extends RefCounted
## Recolours wall art drawn in crypt colours into another biome's wall colours (R1: the break of a
## secret wall, "Bruchkante in Biomfarbe"). The palette comes from the delivered wall autotiles
## (art/environment/tiles/wall_autotile_<biome>.png, 4 x 5 tiles, same layout in every biome): the
## colour at a pixel of the crypt sheet maps to the colour at the same pixel of the biome sheet
## (most frequent pair wins). Any other colour takes the mapping of the nearest crypt colour, alpha
## stays. Optics only; results are cached per biome and texture.

const SHEET_PATH := "res://art/environment/tiles/wall_autotile_%s.png"
const SOURCE_BIOME := &"crypt"

static var _maps: Dictionary = {}
static var _textures: Dictionary = {}


## Are both sheets there (crypt and biome)? Otherwise callers tint instead.
static func has_biome_colors(biome_id: StringName) -> bool:
	return biome_id != SOURCE_BIOME and ResourceLoader.exists(SHEET_PATH % SOURCE_BIOME) and ResourceLoader.exists(SHEET_PATH % biome_id)


## texture recoloured for biome_id (the texture itself for the crypt or without sheets).
static func recolor_texture(texture: Texture2D, biome_id: StringName) -> Texture2D:
	if texture == null or not has_biome_colors(biome_id):
		return texture
	var key := "%s|%s" % [texture.resource_path, biome_id]
	if _textures.has(key):
		return _textures[key]
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var result := ImageTexture.create_from_image(recolor_image(image, biome_id))
	_textures[key] = result
	return result


## A copy of image in the biome's wall colours.
static func recolor_image(image: Image, biome_id: StringName) -> Image:
	var palette := palette_for(biome_id)
	var copy := image.duplicate() as Image
	if palette.is_empty():
		return copy
	var sources: Array = palette.keys()
	var cache := {}
	for y in copy.get_height():
		for x in copy.get_width():
			var pixel := copy.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var opaque := Color(pixel.r, pixel.g, pixel.b)
			var mapped: Color
			if cache.has(opaque):
				mapped = cache[opaque]
			else:
				mapped = palette.get(opaque, palette[_nearest(opaque, sources)])
				cache[opaque] = mapped
			copy.set_pixel(x, y, Color(mapped.r, mapped.g, mapped.b, pixel.a))
	return copy


## Crypt colour -> biome colour from the two autotile sheets (empty without sheets).
static func palette_for(biome_id: StringName) -> Dictionary:
	if _maps.has(biome_id):
		return _maps[biome_id]
	var result := {}
	var source := _load(SHEET_PATH % SOURCE_BIOME)
	var target := _load(SHEET_PATH % biome_id)
	if source != null and target != null and source.get_size() == target.get_size():
		var counts := {}
		for y in source.get_height():
			for x in source.get_width():
				var a := source.get_pixel(x, y)
				var b := target.get_pixel(x, y)
				if a.a <= 0.0 or b.a <= 0.0:
					continue
				var from := Color(a.r, a.g, a.b)
				var to := Color(b.r, b.g, b.b)
				if not counts.has(from):
					counts[from] = {}
				counts[from][to] = int(counts[from].get(to, 0)) + 1
		for from: Color in counts:
			var best := Color.BLACK
			var best_count := -1
			for to: Color in counts[from]:
				if counts[from][to] > best_count:
					best = to
					best_count = counts[from][to]
			result[from] = best
	_maps[biome_id] = result
	return result


static func _nearest(color: Color, sources: Array) -> Color:
	var best: Color = sources[0]
	var best_distance := INF
	for candidate: Color in sources:
		var distance := Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


static func _load(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
