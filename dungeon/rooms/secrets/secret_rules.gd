class_name SecretRules
extends RefCounted
## Secret niches behind cracked walls (A10, D-105, D-109, D-117): pure rules, no nodes.
##
## - From FROM_ROOM, CHANCE of the normal combat rooms (normal and chasm kind; arenas keep their
##   walls for the wave gates) get a cracked wall. It is no room of its own: a small niche (three
##   tiles in a row) inside solid rock behind a wall front that faces the room - the north wall with
##   the rock ring behind it, or a thick inner wall (the corners of a cross, the cut corner of an L,
##   the catacomb's rock). The front shows the crack (wall_cracked_<biome> replaces a wall front tile,
##   SPRITES_V5 §6). The floor plan of the room stays as it is.
## - Only an explosion opens it (breaks_wall): explosive barrel, a bomber's death, the staff's and
##   the hammer's area hits ("Explosiver Treffer" too). Then the front and the crown above it turn
##   into floor and the niche is open.
## - Behind it: a chest (upgrade choice, D-109), soul crystals, or rarely the wandering merchant
##   (the shop's prices, rarer goods, D-109). Weights are TESTWERTE.
## - Where: find_sites() keeps every front with plain, reachable floor in front of it and solid rock
##   all around the niche (walls stay at least two tiles tall), away from north doors and wall
##   torches; the dungeon RNG picks one. A room plan (R1) may name the places itself (cell 'q',
##   RoomTiles.secret_cracks); then only those count. Fronts holding a fixture of the plan (niche,
##   gate, rift, chains) and their neighbours never crack (RoomTiles.front_fixtures).
## - Randomness: exactly DRAWS numbers of the dungeon RNG per normal combat room, none otherwise.

enum Content { CHEST, CRYSTAL, MERCHANT }

const FROM_ROOM := 6
## "1/8 der Normal- und Abgrundräume ab Raum 6" (D-117). TESTWERT
const CHANCE := 1.0 / 8.0
## Content weights in Content order: chest, soul crystals, wandering merchant (rare). TESTWERTE
const CONTENT_WEIGHTS: Array[float] = [0.55, 0.35, 0.10]
## Soul crystals lying in a niche (for the group). TESTWERT
const CRYSTALS := 2
## The niche: NICHE_WIDTH floor tiles in a row, two rows behind the cracked front (crown between).
const NICHE_WIDTH := 3
## Tiles of the niche on each side of the crack column (NICHE_WIDTH = 2 * NICHE_HALF + 1).
const NICHE_HALF := 1
## A crack in the north wall keeps this many columns from a north door (frame, torches) and from
## the wall torches.
const DOOR_CLEARANCE := 4
const TORCH_CLEARANCE := 2
const DRAWS := 3

## Test aid (smoke test): >= 0 replaces CHANCE. Never set in the game.
static var chance_override := -1.0


## One place of the niche in a room (room tiles).
class Site:
	extends RefCounted
	## Floor tiles of the niche (two rows behind the crack).
	var niche: Array[Vector2i] = []
	## Crown and front that open when the wall breaks (front last).
	var opening: Array[Vector2i] = []
	## The cracked brick front (faces the room).
	var crack := Vector2i.ZERO
	## Floor tile in front of the crack, where the players stand.
	var approach := Vector2i.ZERO

	## Tile the content stands on (middle of the niche).
	func get_content_tile() -> Vector2i:
		return niche[NICHE_HALF]

	## The niche as RoomTiles.niche_rect.
	func get_rect() -> Rect2i:
		return Rect2i(niche[0], Vector2i(NICHE_WIDTH, 1))

	## In the north wall (the niche lies in the rock ring around the room)?
	func is_in_north_wall() -> bool:
		return crack.y == -1

	## Every tile the niche changes or needs free: niche, opening, approach.
	func get_tiles() -> Array[Vector2i]:
		var tiles: Array[Vector2i] = niche.duplicate()
		tiles.append_array(opening)
		tiles.append(approach)
		return tiles

	## Solid tiles around the niche and its opening (they keep the niche sealed and every wall at
	## least two tiles tall).
	func get_enclosure() -> Array[Vector2i]:
		var tiles: Array[Vector2i] = []
		for x in range(crack.x - NICHE_HALF, crack.x + NICHE_HALF + 1):
			tiles.append(Vector2i(x, crack.y - 3))
			tiles.append(Vector2i(x, crack.y - 1))
		tiles.append(Vector2i(crack.x - NICHE_HALF - 1, crack.y - 2))
		tiles.append(Vector2i(crack.x + NICHE_HALF + 1, crack.y - 2))
		tiles.append(Vector2i(crack.x - 1, crack.y))
		tiles.append(Vector2i(crack.x + 1, crack.y))
		return tiles


## Result of one draw.
class Pick:
	extends RefCounted
	var has_secret := false
	var content := Content.CHEST
	## In [0, 1): which of the sites.
	var site_roll := 0.0


static func get_chance() -> float:
	return chance_override if chance_override >= 0.0 else CHANCE


static func is_eligible(room_index: int, room_type: int, room_kind: int) -> bool:
	return room_index >= FROM_ROOM and RoomSequence.is_normal_combat(room_type as RoomSequence.RoomType) \
			and room_kind != RoomSequence.RoomKind.ARENA


## The draw for one room; DRAWS numbers for every normal combat room, none for other rooms.
static func roll(room_index: int, room_type: int, room_kind: int, rng: RandomNumberGenerator) -> Pick:
	var pick := Pick.new()
	if rng == null or not RoomSequence.is_normal_combat(room_type as RoomSequence.RoomType):
		return pick
	var chance_roll := rng.randf()
	var content_roll := rng.randf()
	pick.site_roll = rng.randf()
	pick.has_secret = is_eligible(room_index, room_type, room_kind) and chance_roll < get_chance()
	pick.content = SpecialTable.pick_weighted(CONTENT_WEIGHTS, content_roll, Content.CHEST) as Content
	return pick


## Only an explosion breaks a cracked wall: a hit tagged "explosion" (barrel, bomber, boss slams,
## "Explosiver Treffer") or any area hit (staff impact, hammer slam and quake, nova).
static func breaks_wall(damage: DamageData) -> bool:
	return damage != null and (damage.tags.has(&"explosion") or damage.has_impact_position)


## The niche behind the wall front crack (no checks): crown above it, niche two rows up.
static func site_at(crack: Vector2i) -> Site:
	var site := Site.new()
	site.crack = crack
	for i in NICHE_WIDTH:
		site.niche.append(Vector2i(crack.x - NICHE_HALF + i, crack.y - 2))
	site.opening = [crack + Vector2i.UP, crack]
	site.approach = crack + Vector2i.DOWN
	return site


## Every valid place of the niche, north to south, west to east. forbidden: spawn markers, props,
## door lanes; torch_columns: x of the north wall torches.
static func find_sites(tiles: RoomTiles, forbidden: Dictionary, torch_columns: Array[int] = []) -> Array[Site]:
	var sites: Array[Site] = []
	var size := tiles.room_size
	var floor_rect := Rect2i(Vector2i.ZERO, size)
	var mass := tiles.get_wall_mass()
	var reachable := tiles.get_reachable_tiles(0)
	var open: Dictionary[Vector2i, bool] = {}
	for tile in tiles.get_door_corridor_tiles():
		open[tile] = true
	for tile in tiles.get_extra_floor_tiles():
		open[tile] = true
	# The height (M3) counts as wall mass for the floor rules, but a plateau, its cliff, stairs and
	# ladders are no rock to blow a niche into (bug report 22.10.2026 #f5026f89: the crack sat in a
	# cliff and opened the plateau's chest to the ground).
	var height: Dictionary[Vector2i, bool] = {}
	for list: Array[Vector2i] in [tiles.plateau_tiles, tiles.ladder_tiles, tiles.stair_tiles]:
		for tile in list:
			height[tile] = true
	var door_columns: Array[int] = []
	for exit in tiles.get_exit_doors():
		if exit.x == RoomTiles.DoorSide.NORTH:
			door_columns.append(exit.y)
	var cracks: Array[Vector2i] = []
	for y in range(-1, size.y - 1):
		for x in range(NICHE_HALF + 1, size.x - NICHE_HALF - 1):
			cracks.append(Vector2i(x, y))
	if not tiles.secret_cracks.is_empty():
		cracks = tiles.secret_cracks.duplicate()
	for crack in cracks:
		var x := crack.x
		if x < NICHE_HALF + 1 or x >= size.x - NICHE_HALF - 1 or _beside_fixture(crack, tiles.front_fixtures):
			continue
		var site := site_at(crack)
		var approach := site.approach
		if not floor_rect.has_point(approach) or not reachable.has(approach) or mass.has(approach) or tiles.is_pit(approach) \
				or tiles.is_bridge(approach) or forbidden.has(approach):
			continue
		# A place the plan names keeps its distance by the plan's own rules (generator).
		if site.is_in_north_wall() and tiles.secret_cracks.is_empty() and not _clear_of_doors_and_torches(x, door_columns, torch_columns):
			continue
		var solid := true
		for tile in site.niche + site.opening + site.get_enclosure():
			solid = solid and _is_solid(tile, floor_rect, mass, open) and not height.has(tile)
		if not solid:
			continue
		# Carved niche and later opening keep every wall at least two tiles tall.
		var carved: Dictionary[Vector2i, bool] = {}
		for tile: Vector2i in mass:
			carved[tile] = true
		for tile in site.niche:
			carved.erase(tile)
		if not WallAutotile.is_valid_mass(carved, size):
			continue
		for tile in site.opening:
			carved.erase(tile)
		if WallAutotile.is_valid_mass(carved, size):
			sites.append(site)
	return sites


## One of the sites from site_roll in [0, 1); null if there is none.
static func choose_site(sites: Array[Site], site_roll: float) -> Site:
	if sites.is_empty():
		return null
	return sites[mini(sites.size() - 1, floori(site_roll * sites.size()))]


## Solid: wall mass inside the floor, the painted rock ring outside it (no corridor, no niche floor).
static func _is_solid(tile: Vector2i, floor_rect: Rect2i, mass: Dictionary, open: Dictionary) -> bool:
	if floor_rect.has_point(tile):
		return mass.has(tile)
	# The ring is two tiles wide at the sides, three at the top; the row above a north niche is
	# painted with it (RoomTiles.get_niche_bump).
	return tile.x >= -2 and tile.x <= floor_rect.end.x + 1 and tile.y >= -4 and tile.y <= floor_rect.end.y + 1 \
			and not open.has(tile)


## A front holding a plan fixture or right beside one (niche, gate, rift, torch, chains).
static func _beside_fixture(crack: Vector2i, fixtures: Array[Vector2i]) -> bool:
	for fixture in fixtures:
		if fixture.y == crack.y and absi(fixture.x - crack.x) <= 1:
			return true
	return false


static func _clear_of_doors_and_torches(column: int, door_columns: Array[int], torch_columns: Array[int]) -> bool:
	for door in door_columns:
		if absi(door - column) < DOOR_CLEARANCE:
			return false
	for torch in torch_columns:
		if absi(torch - column) <= TORCH_CLEARANCE:
			return false
	return true
