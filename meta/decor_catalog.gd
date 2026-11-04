class_name DecorCatalog
extends RefCounted
## The decoration catalog (WK5, WK7, KONZEPT §8, D-202, D-205): everything that can be bought with
## gold and set in the village (per world) or in the home. One loader reads the delivered JSON files
## (SPRITES_V13 Teil E, no list in code): furniture from art/environment/home/furniture/<group>/
## furniture_<group>.json (names <kind>_<style>_<front|side>), village decoration from
## art/environment/village/deco/<group>/deco_<group>.json and the home's wallpaper and floor styles
## from art/environment/home/home_style_tiles.json. A new group folder or a new JSON entry is in the
## shop on the next start.
## Prices (TESTWERT): a base price per group plus TILE_PRICE per extra tile, times the style factor
## (soul is the noble style and costs more, the collecting incentive). Cosmetic only (D-175, D-176).
## Pictures: the delivered file; a strip-only piece (village water, fire bowl) uses its strip; a
## missing file gets a drawn placeholder of the frame size (SPRITES_V13 Teil C).

const HOME: StringName = &"home"
const VILLAGE: StringName = &"village"
const SPACES: Array[StringName] = [VILLAGE, HOME]
const FURNITURE_DIR := "res://art/environment/home/furniture/"
const DECO_DIR := "res://art/environment/village/deco/"
const STYLE_TILES_PATH := "res://art/environment/home/home_style_tiles.json"
const STYLE_TILES_DIR := "res://art/environment/home/"
## Styles of the furniture in catalog order (SPRITES_V13 Teil E).
const STYLES: Array[String] = ["cozy", "rustic", "soul"]
const SURFACE_GROUP := "surfaces"
## Wallpaper and floor of the home: surface kinds and the id prefix in the save.
const SURFACE_WALL := "wall"
const SURFACE_FLOOR := "floor"
const SURFACE_PREFIX := "home_"
## Group order in the shop (unknown groups follow alphabetically).
const GROUP_ORDER: Array[String] = ["beds", "seating", "tables", "storage", "light", "rugs", "wall", "plants",
	"cozy", "garden", "paths", "lights", "fences", "water", "fun", SURFACE_GROUP]
## TESTWERT: base price per group in gold (a run to room 10 brings 100–150 gold, KONZEPT §5.4).
const GROUP_PRICES := {
	"beds": 90, "seating": 30, "tables": 35, "storage": 40, "light": 35, "rugs": 30, "wall": 25,
	"plants": 20, "cozy": 60, "fun": 40,
	"garden": 15, "paths": 6, "lights": 35, "fences": 8, "water": 70,
	SURFACE_GROUP: 120,
}
const DEFAULT_GROUP_PRICE := 40
## TESTWERT: extra gold per tile beyond the first (big pieces cost more).
const TILE_PRICE := 10
## TESTWERT: style factor; soul (violet and gold, noble) is the collector's style.
const STYLE_FACTORS := {"cozy": 1.0, "rustic": 1.0, "soul": 2.5}
## TESTWERT: light radius in tiles per kind (fireplace: the room's main light, Antwort 20 §1).
const LIGHT_RADIUS_TILES := {"fireplace": 5.0, "stove": 3.0, "lamp_post": 3.0, "fire_bowl": 3.0,
	"torch_post": 2.5, "string_lights": 2.5, "string_lights_posts": 3.0}
const DEFAULT_LIGHT_RADIUS_TILES := 2.0
## TESTWERT: frames per second of animation strips (fireplace 6f, water 4f, flames).
const ANIM_FPS := 8.0
const PLACEHOLDER_FILL := Color("#8a5a34")
const PLACEHOLDER_OUTLINE := Color("#1c1a2b")

static var _items: Dictionary[String, DecorItem] = {}
static var _order: Array[String] = []
static var _textures: Dictionary[String, Texture2D] = {}
static var _loaded := false


## Every item, in shop order (space, group, kind, style).
static func all_items() -> Array[DecorItem]:
	_ensure_loaded()
	var list: Array[DecorItem] = []
	for id in _order:
		list.append(_items[id])
	return list


static func items_for(space: StringName, group := "") -> Array[DecorItem]:
	var list: Array[DecorItem] = []
	for item in all_items():
		if item.space == space and (group.is_empty() or item.group == group):
			list.append(item)
	return list


## Groups of a space in shop order.
static func groups_for(space: StringName) -> Array[String]:
	var groups: Array[String] = []
	for item in all_items():
		if item.space == space and not groups.has(item.group):
			groups.append(item.group)
	return groups


static func has_item(id: String) -> bool:
	_ensure_loaded()
	return _items.has(id)


static func get_item(id: String) -> DecorItem:
	_ensure_loaded()
	return _items.get(id, null)


## TESTWERT: (group price + TILE_PRICE per extra tile) × style factor, rounded to 5 gold.
static func price_for(group: String, footprint: Vector2i, style: String) -> int:
	var base := int(GROUP_PRICES.get(group, DEFAULT_GROUP_PRICE))
	var tiles := maxi(1, footprint.x * maxi(1, footprint.y))
	var raw := float(base + TILE_PRICE * (tiles - 1)) * float(STYLE_FACTORS.get(style, 1.0))
	return maxi(5, int(round(raw / 5.0)) * 5)


static func light_radius_tiles(item: DecorItem) -> float:
	return float(LIGHT_RADIUS_TILES.get(item.kind, DEFAULT_LIGHT_RADIUS_TILES))


## Translated name: "Sessel · Gemütlich" (furniture), "Blumenbeet rot" (village), "Tapete · Seele".
static func display_name(item: DecorItem) -> String:
	if item == null:
		return ""
	var name := _translated(&"DECOR_%s" % item.kind.to_upper(), item.kind.capitalize())
	if item.style.is_empty():
		return name
	return "%s · %s" % [name, style_name(item.style)]


static func style_name(style: String) -> String:
	return _translated(&"DECOR_STYLE_%s" % style.to_upper(), style.capitalize())


static func group_name(group: String) -> String:
	return _translated(&"DECOR_GROUP_%s" % group.to_upper(), group.capitalize())


static func _translated(key: StringName, fallback: String) -> String:
	var text := Loc.t(key)
	return fallback if text == String(key) else text


## The still picture of a view (or the first strip frame), a placeholder when nothing is delivered.
static func texture_for(item: DecorItem, rot := 0) -> Texture2D:
	var file := String(item.spec(rot).get("file", ""))
	var path := item.dir + file
	if not file.is_empty() and ResourceLoader.exists(path):
		return _load(path)
	var strip := strip_texture(item, rot)
	if strip != null:
		return strip
	return _placeholder(item.id + String(item.view_for(rot)), item.frame_size(rot))


## True when the still picture is missing and the strip stands in for it (village water, fire bowl).
static func uses_strip_as_picture(item: DecorItem, rot := 0) -> bool:
	var file := String(item.spec(rot).get("file", ""))
	return (file.is_empty() or not ResourceLoader.exists(item.dir + file)) and strip_texture(item, rot) != null


## The animation strip of a view (null without one or when the file is missing).
static func strip_texture(item: DecorItem, rot := 0) -> Texture2D:
	var file := item.anim_file(rot)
	if file.is_empty() or not ResourceLoader.exists(item.dir + file):
		return null
	return _load(item.dir + file)


## One frame of the picture for the shop (first frame of a strip).
static func preview_texture(item: DecorItem) -> Texture2D:
	if item.is_surface():
		return texture_for(item)
	var texture := texture_for(item)
	if uses_strip_as_picture(item):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2.ZERO, Vector2(item.frame_size()))
		return atlas
	return texture


static func clear_cache() -> void:
	_items.clear()
	_order.clear()
	_textures.clear()
	_loaded = false


# --- Loading ---

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var found: Array[DecorItem] = []
	for group in _sorted_dirs(FURNITURE_DIR):
		found.append_array(_load_furniture_group(group))
	for group in _sorted_dirs(DECO_DIR):
		found.append_array(_load_deco_group(group))
	found.append_array(_load_surfaces())
	found.sort_custom(_before)
	for item in found:
		if _items.has(item.id):
			continue
		_items[item.id] = item
		_order.append(item.id)


static func _before(a: DecorItem, b: DecorItem) -> bool:
	if a.space != b.space:
		return SPACES.find(a.space) < SPACES.find(b.space)
	if a.group != b.group:
		var ia := GROUP_ORDER.find(a.group)
		var ib := GROUP_ORDER.find(b.group)
		ia = ia if ia >= 0 else GROUP_ORDER.size()
		ib = ib if ib >= 0 else GROUP_ORDER.size()
		return ia < ib if ia != ib else a.group < b.group
	if a.kind != b.kind:
		return a.kind < b.kind
	return STYLES.find(a.style) < STYLES.find(b.style)


static func _sorted_dirs(root: String) -> Array[String]:
	var dirs: Array[String] = []
	if DirAccess.dir_exists_absolute(root):
		for name in DirAccess.get_directories_at(root):
			dirs.append(name)
	dirs.sort()
	return dirs


static func _read_items(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data as Dictionary).get("items") is Array:
		push_warning("DecorCatalog: %s has no item list, skipped." % path)
		return []
	return data["items"]


## furniture_<group>.json: one entry per <kind>_<style>_<view>; the views of a kind and style become
## one item.
static func _load_furniture_group(group: String) -> Array[DecorItem]:
	var dir := FURNITURE_DIR + group + "/"
	var regex := RegEx.create_from_string("^(.+)_(%s)_(front|side)$" % "|".join(PackedStringArray(STYLES)))
	var by_id: Dictionary[String, DecorItem] = {}
	var list: Array[DecorItem] = []
	for entry: Variant in _read_items(dir + "furniture_%s.json" % group):
		if not entry is Dictionary or not (entry as Dictionary).has("name"):
			continue
		var found := regex.search(String(entry["name"]))
		if found == null:
			push_warning("DecorCatalog: %s does not follow <kind>_<style>_<view>, skipped." % entry["name"])
			continue
		var id := "%s_%s" % [found.get_string(1), found.get_string(2)]
		var item: DecorItem = by_id.get(id, null)
		if item == null:
			item = DecorItem.new()
			item.id = id
			item.space = HOME
			item.group = group
			item.kind = found.get_string(1)
			item.style = found.get_string(2)
			item.dir = dir
			by_id[id] = item
			list.append(item)
		item.views[StringName(found.get_string(3))] = entry
	for item in list.duplicate():
		if not item.views.has(DecorItem.FRONT):
			push_warning("DecorCatalog: %s has no _front view, skipped." % item.id)
			list.erase(item)
			continue
		item.placement = DecorItem.Placement.WALL if item.footprint().y == 0 else DecorItem.Placement.FLOOR
		item.price = price_for(group, item.footprint(), item.style)
	return list


## deco_<group>.json: one item per entry (front only, no style).
static func _load_deco_group(group: String) -> Array[DecorItem]:
	var dir := DECO_DIR + group + "/"
	var list: Array[DecorItem] = []
	for entry: Variant in _read_items(dir + "deco_%s.json" % group):
		if not entry is Dictionary or not (entry as Dictionary).has("name"):
			continue
		var item := DecorItem.new()
		item.id = String(entry["name"])
		item.space = VILLAGE
		item.group = group
		item.kind = item.id
		item.dir = dir
		item.views[DecorItem.FRONT] = entry
		item.placement = DecorItem.Placement.FLOOR
		item.price = price_for(group, item.footprint(), "")
		list.append(item)
	return list


## home_style_tiles.json: wall_<style> and floor_<style> become "home_wall_<style>" and
## "home_floor_<style>".
static func _load_surfaces() -> Array[DecorItem]:
	var list: Array[DecorItem] = []
	var regex := RegEx.create_from_string("^(%s|%s)_(.+)$" % [SURFACE_WALL, SURFACE_FLOOR])
	for entry: Variant in _read_items(STYLE_TILES_PATH):
		if not entry is Dictionary or not (entry as Dictionary).has("name"):
			continue
		var found := regex.search(String(entry["name"]))
		if found == null:
			continue
		var item := DecorItem.new()
		item.id = SURFACE_PREFIX + String(entry["name"])
		item.space = HOME
		item.group = SURFACE_GROUP
		item.kind = "home_" + found.get_string(1)
		item.style = found.get_string(2)
		item.dir = STYLE_TILES_DIR
		item.views[DecorItem.FRONT] = entry
		item.placement = DecorItem.Placement.SURFACE
		item.price = price_for(SURFACE_GROUP, Vector2i.ONE, item.style)
		list.append(item)
	return list


## Id of a surface item ("home_wall_soul") from its kind and style.
static func surface_id(surface: String, style: String) -> String:
	return "%s%s_%s" % [SURFACE_PREFIX, surface, style]


static func _load(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]


static func _placeholder(key: String, size: Vector2i) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var image := Image.create(maxi(2, size.x), maxi(2, size.y), false, Image.FORMAT_RGBA8)
	image.fill(PLACEHOLDER_FILL)
	for x in image.get_width():
		image.set_pixel(x, 0, PLACEHOLDER_OUTLINE)
		image.set_pixel(x, image.get_height() - 1, PLACEHOLDER_OUTLINE)
	for y in image.get_height():
		image.set_pixel(0, y, PLACEHOLDER_OUTLINE)
		image.set_pixel(image.get_width() - 1, y, PLACEHOLDER_OUTLINE)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture
