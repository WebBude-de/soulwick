extends RefCounted
## Arrows (→ ← ↑ ↓) for Pixelify Sans, which has none: a tiny bitmap font built at runtime in the
## font's own pixel grid (one bitmap pixel = 1/10 em, the stroke of the regular weight), used as a
## fallback font. Without it the desktop borrows a system font and the browser, which has none,
## draws a box (report #f6fe6427: "Schaden 15 [] 16,2" in the forge).
## with_arrows(font) wraps a font so labels can use it; fallback() can also be put into the
## fallbacks of the game font itself (integrator hook, UiKit.FONT), then every text has arrows.
## Preload (no class_name, like the other village helpers): const PixelArrows := preload(…).

## Pixel rows of each arrow ('#' = ink), drawn on the baseline grid of the font: EM pixels per em.
const EM := 10
const GLYPHS := {
	0x2192: ["....#..", ".....#.", "#######", ".....#.", "....#.."],
	0x2190: ["..#....", ".#.....", "#######", ".#.....", "..#...."],
	0x2191: ["..#..", ".#.#.", "#.#.#", "..#..", "..#..", "..#..", "..#.."],
	0x2193: ["..#..", "..#..", "..#..", "..#..", "#.#.#", ".#.#.", "..#.."],
}
## Pixels above the baseline of each arrow's top row: the shaft of → and ← lies on the row of the
## font's hyphen (2-3 px above the baseline), ↑ and ↓ stand on the baseline like capitals.
const TOPS := {0x2192: 5, 0x2190: 5, 0x2191: 7, 0x2193: 7}
## Empty pixels left of each glyph and after it.
const BEARING := 1
## Ascent and descent of the bitmap font (pixels), below Pixelify Sans' 0.92 / 0.28 em, so a line
## with an arrow is exactly as high as one without.
const ASCENT := 9
const DESCENT := 2

static var _font: FontFile = null
static var _wrapped: Dictionary = {}


## The bitmap font with the arrows (built once).
static func fallback() -> FontFile:
	if _font != null:
		return _font
	var size := Vector2i(EM, 0)
	var width := 0
	var height := 0
	for code: int in GLYPHS:
		width += String(GLYPHS[code][0]).length() + 1
		height = maxi(height, GLYPHS[code].size())
	var image := Image.create(width + 1, height + 2, false, Image.FORMAT_RGBA8)
	var font := FontFile.new()
	font.fixed_size = EM
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.set_cache_ascent(0, EM, ASCENT)
	font.set_cache_descent(0, EM, DESCENT)
	var x := 1
	for code: int in GLYPHS:
		var rows: Array = GLYPHS[code]
		var glyph_width := String(rows[0]).length()
		for y in rows.size():
			for column in glyph_width:
				if String(rows[y])[column] == "#":
					image.set_pixel(x + column, 1 + y, Color.WHITE)
		font.set_glyph_advance(0, EM, code, Vector2(glyph_width + 2 * BEARING, 0))
		font.set_glyph_offset(0, size, code, Vector2(BEARING, -int(TOPS[code])))
		font.set_glyph_size(0, size, code, Vector2(glyph_width, rows.size()))
		font.set_glyph_uv_rect(0, size, code, Rect2(x, 1, glyph_width, rows.size()))
		font.set_glyph_texture_idx(0, size, code, 0)
		x += glyph_width + 1
	font.set_texture_image(0, size, 0, image)
	_font = font
	return font


## base with the arrows as fallback (cached per font): for labels that show "15 → 16,2".
static func with_arrows(base: Font) -> FontVariation:
	var key := base.get_instance_id()
	if _wrapped.has(key):
		return _wrapped[key]
	var variation := FontVariation.new()
	variation.base_font = base
	variation.fallbacks = [fallback()]
	_wrapped[key] = variation
	return variation
