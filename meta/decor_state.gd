class_name DecorState
extends RefCounted
## What the player owns and where it stands (WK5, WK7): bought decoration (id -> count, the
## "Lager" is owned minus placed), the placements of the village (per world, the world's save) and of
## the home, and the home's wallpaper and floor style. Stored by SaveManager ([decor_owned],
## [decor_placed], [decor]; save v6, merge rules in SaveMerge), read and changed only here.
## A placement is "id:col:row:rot" (tiles of the space's grid, see DecorGrid; rot see DecorItem);
## unknown ids (an item the catalog no longer has) stay in the save untouched and are not shown.
## Buying needs gold (DecorCatalog prices, TESTWERT); placing takes one from the Lager, putting
## away gives it back. Only static functions (D-044); the grid rules (where a piece may stand) are
## DecorGrid's.
## Koop: in a group session only the host's state counts (snapshot() for the guests, view only).

const VILLAGE: StringName = &"village"
const HOME: StringName = &"home"
const SETTING_WALL := "home_wall"
const SETTING_FLOOR := "home_floor"
const SETTINGS: Array[String] = [SETTING_WALL, SETTING_FLOOR]
## The home's starting furniture (D-205 "eingerichtet, aber basic cozy", Antwort 20 §1) as catalog
## pieces of the cozy style: owned from the start (they can be put away and moved like bought ones).
## Grid of the home: 15×9 tiles, floor rows 2..8, back wall row 1 (HomeLayout).
const STARTER_HOME: Array[String] = [
	"bed_single_cozy:1:2:0",
	"nightstand_cozy:3:2:0",
	"floor_lamp_cozy:0:2:0",
	"fireplace_cozy:11:2:0",
	"pet_basket_medium_cozy:11:3:0",
	"armchair_cozy:13:4:3",
	"rug_round_cozy:8:4:0",
	"shelf_full_cozy:8:2:0",
	"chest_cozy:5:6:0",
	"plant_large_cozy:14:7:0",
	"picture_village_cozy:6:1:0",
]


## One placement as {id, cell, rot}; {} when the text is not a placement.
static func parse(entry: String) -> Dictionary:
	var parts := entry.split(":")
	if parts.size() != 4 or parts[0].is_empty() or not parts[1].is_valid_int() or not parts[2].is_valid_int() \
			or not parts[3].is_valid_int():
		return {}
	return {"id": parts[0], "cell": Vector2i(int(parts[1]), int(parts[2])), "rot": posmod(int(parts[3]), 4)}


static func format(id: String, cell: Vector2i, rot: int) -> String:
	return "%s:%d:%d:%d" % [id, cell.x, cell.y, posmod(rot, 4)]


## Placements of a space as {id, cell, rot, index} (index in the saved list), invalid entries left out.
static func placements(space: StringName) -> Array[Dictionary]:
	return parse_list(SaveManager.get_decor_placements(space))


static func parse_list(list: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in list.size():
		var entry := parse(list[index])
		if entry.is_empty():
			continue
		entry["index"] = index
		result.append(entry)
	return result


## Number of an item standing in all spaces.
static func placed_count(id: String) -> int:
	var count := 0
	for space in DecorCatalog.SPACES:
		for entry in SaveManager.get_decor_placements(space):
			if entry.begins_with(id + ":"):
				count += 1
	return count


static func owned_count(id: String) -> int:
	return SaveManager.get_decor_owned(id)


## In the Lager: owned, not placed.
static func stored_count(id: String) -> int:
	return maxi(0, owned_count(id) - placed_count(id))


## Ids with something in the Lager of a space, in catalog order.
static func stored_ids(space: StringName) -> Array[String]:
	var ids: Array[String] = []
	for item in DecorCatalog.items_for(space):
		if not item.is_surface() and stored_count(item.id) > 0:
			ids.append(item.id)
	return ids


static func can_buy(id: String) -> bool:
	var item := DecorCatalog.get_item(id)
	if item == null:
		return false
	if item.is_surface() and owned_count(id) > 0:
		return false
	return SaveManager.get_permanent_gold() >= item.price


## Gold still missing for an item (0 = affordable).
static func gold_missing(id: String) -> int:
	var item := DecorCatalog.get_item(id)
	return maxi(0, item.price - SaveManager.get_permanent_gold()) if item != null else 0


## Buys one piece into the Lager (a surface once). False without the gold.
static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var item := DecorCatalog.get_item(id)
	if not SaveManager.try_spend_permanent_gold(item.price):
		return false
	SaveManager.set_decor_owned(id, owned_count(id) + 1)
	SaveManager.save_game()
	return true


## Puts a piece from the Lager at cell (the caller checked the grid). False with an empty Lager.
static func place(space: StringName, id: String, cell: Vector2i, rot: int) -> bool:
	if stored_count(id) <= 0:
		return false
	var list := SaveManager.get_decor_placements(space)
	list.append(format(id, cell, rot))
	SaveManager.set_decor_placements(space, list)
	SaveManager.save_game()
	return true


## Moves or turns the placement at index (index of placements()).
static func move(space: StringName, index: int, cell: Vector2i, rot: int) -> bool:
	var list := SaveManager.get_decor_placements(space)
	if index < 0 or index >= list.size():
		return false
	var entry := parse(list[index])
	if entry.is_empty():
		return false
	list[index] = format(entry["id"], cell, rot)
	SaveManager.set_decor_placements(space, list)
	SaveManager.save_game()
	return true


## Puts the placement at index back into the Lager.
static func remove(space: StringName, index: int) -> bool:
	var list := SaveManager.get_decor_placements(space)
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	SaveManager.set_decor_placements(space, list)
	SaveManager.save_game()
	return true


## Style of a home surface (SETTING_WALL/SETTING_FLOOR): "" = the original room, else a style.
static func surface_style(setting: String) -> String:
	return SaveManager.get_decor_setting(setting)


## Puts up an owned wallpaper or floor (style "" = back to the original room).
static func set_surface_style(setting: String, style: String) -> bool:
	if not SETTINGS.has(setting):
		return false
	if not style.is_empty():
		if owned_count(DecorCatalog.surface_id(setting.trim_prefix("home_"), style)) <= 0:
			return false
	SaveManager.set_decor_setting(setting, style)
	SaveManager.save_game()
	return true


## The setting a surface item changes (SETTING_WALL or SETTING_FLOOR).
static func setting_of(item: DecorItem) -> String:
	return SETTING_WALL if item.kind == "home_" + DecorCatalog.SURFACE_WALL else SETTING_FLOOR


## Collection: different catalog items owned / all items (of a space, or all with &"").
static func collection(space: StringName = &"") -> Vector2i:
	var owned := 0
	var total := 0
	for item in DecorCatalog.all_items():
		if space != &"" and item.space != space:
			continue
		total += 1
		if owned_count(item.id) > 0:
			owned += 1
	return Vector2i(owned, total)


## Owned of one style (cozy, rustic, soul) / all of that style.
static func style_collection(style: String) -> Vector2i:
	var owned := 0
	var total := 0
	for item in DecorCatalog.all_items():
		if item.style != style:
			continue
		total += 1
		if owned_count(item.id) > 0:
			owned += 1
	return Vector2i(owned, total)


## Owned starter set (id -> count) of STARTER_HOME.
static func starter_owned() -> Dictionary[String, int]:
	var owned: Dictionary[String, int] = {}
	for entry in STARTER_HOME:
		var parsed := parse(entry)
		var id := String(parsed["id"])
		owned[id] = int(owned.get(id, 0)) + 1
	return owned


## Village decoration and home of this world as one small dictionary (KONZEPT §8 "Dorf besuchen",
## the host's village for guests): placements per space and the home's surfaces, no free text.
static func snapshot() -> Dictionary:
	return {
		"village": Array(SaveManager.get_decor_placements(VILLAGE)),
		"home": Array(SaveManager.get_decor_placements(HOME)),
		SETTING_WALL: surface_style(SETTING_WALL),
		SETTING_FLOOR: surface_style(SETTING_FLOOR),
	}


## Placements of a space from a snapshot (only valid "id:col:row:rot" entries of known items).
static func snapshot_placements(data: Dictionary, space: StringName) -> PackedStringArray:
	var list := PackedStringArray()
	var raw: Variant = data.get(String(space), [])
	if not (raw is Array or raw is PackedStringArray):
		return list
	for entry: Variant in raw:
		if typeof(entry) == TYPE_STRING and not parse(entry).is_empty() and DecorCatalog.has_item(String(parse(entry)["id"])):
			list.append(entry)
	return list
