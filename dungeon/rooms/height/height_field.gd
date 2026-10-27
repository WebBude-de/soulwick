class_name HeightField
extends Node2D
## The height of one live room (M3, Makeover 3 §8): built by RoomTiles in its layer space (32 art px
## per tile) from its HeightLayout. Holds
##   - the walls of the height (HeightBody "Cliffs", PhysicsLayers.CLIFF): the front of every cliff
##     tile (its upper PLATFORM_HEIGHT less the reach, front_of, reach_of) and a thin wall on every
##     edge between a surface tile and the ground beside it (a pair of one-way walls at a north edge),
##     beside the ground part of a cliff, stairs or ladder (HeightLayout.foot_sides) and on every side
##     of stairs or a ladder towards the ground beside it (HeightLayout.connector_sides); players and
##     enemies stop there, shots and hit areas do not;
##   - the ladder block for enemies (HeightBody "Ladders", PhysicsLayers.LADDER, the front part);
##   - the switch areas on stairs and ladders (HeightConnector: level_changed, ladder slow);
##   - the pictures: surface floor, front, two steps, ladder with its top (PlateauArt).
## Half height (D-205, CR6; bug reports #25371167, #276ffad7: "man denkt, man kann aus der Map
## laufen"): a plateau rises PLATFORM_HEIGHT (half a tile) above the ground. Its front fills the upper
## half of the cliff row, the lower half is ground in front of it (RoomTiles gives it a floor cell
## with navigation): the foot of the front is where a figure on the ground stops, its top where a
## figure on the plateau stops. Stairs are two steps of half that height in the same half; plateaus
## stand free in the room (HeightLayout.problems), so no half wall above them is needed any more.
## The navigation of the surface tiles lies on the room layer itself (RoomTiles), cut off at the
## edges, so enemies walk up and down only over stairs.
## Z order: everything here belongs to the tile layer, drawn below every figure; figures sort by y
## as everywhere, so a figure on the plateau always stands in front of the cliff below it and a
## figure on the ground in front of the cliff it walks along.
## Answers HeightRules: covers(point) and level_at(point) (group HeightRules.FIELDS_GROUP).
## One rule for every raised mass (bug reports 22.10.2026 #784047ba, #81959d11, #bbdc6153: "dort kann
## ich nicht hinter die Wand und mein Schwert ragt oben drauf"): like a rock lip, a plateau's edge to
## the ground in the north lies BAND into its surface tile (band_of), so a figure on
## the ground walks a bit behind the plateau there and counts as on the ground; the band is drawn
## once more in the room's y-sort at its line ("PlateauLips"), over every figure on the ground behind
## it (his feet and what of his weapon lies in the band) and under every figure on the plateau.
## Behind the plateau (bug reports 22.10.2026 #157f21bc "Layer passt immer noch nicht", #eeb4fb40
## "Schatten schaut hier durch"): what of a figure in the band reaches below the band line - a sword
## pointing down, Flint hovering behind his player and Flint's shadow - lay on the surface. While a
## player or an enemy stands in the band of a north edge tile or up to BEHIND_REACH tiles beside it
## (an Area2D per tile, "Behind_x_y"), that tile's copy covers its whole row; otherwise only the band,
## so what lies flat on the plateau (shadows, warnings, flat sources) stays visible.

signal level_changed(body: Node2D, level: int)
signal climbing_changed(player: Player, climbing: bool)

const NAME := "Height"
## The y-sorted copy of the north bands in the room (see the header).
const LIPS_NAME := "PlateauLips"
## Characters sort this far above their feet (RoomTiles.LIP_SORT_FEET, Player.FEET_OFFSET).
const SORT_FEET := 16.0
## Height of a plateau above the ground (art px, 32 per tile): its front and the two steps of its
## stairs (D-205: "nur halbe Höhe: 16 px, Treppe aus zwei Stufen à 8 px"). TESTWERT
const PLATFORM_HEIGHT := 16.0
## Depth of the walk-behind band at a plateau's north edge (art px): half the height of the mass,
## the same rule as a rock lip (RockTerrain.LIP_WALK 16 of a 32 px face). With the half-high front
## (CR6) that is the 8 px it was before; any less would lie inside the surface rim (PlateauArt.RIM)
## and read as a wall again. Figures, chests and sources on the edge row keep the middle of the tile.
## TESTWERT
const BAND := PLATFORM_HEIGHT * 0.5
## A figure in the band of a north edge tile or this many tiles beside it deepens that tile's copy to
## the whole row: a sword reaches about a tile sideways. TESTWERT
const BEHIND_REACH := 1
## The watch area of a north edge tile starts this share of a tile north of it (a figure just north of
## the band whose weapon reaches into the row). TESTWERT
const BEHIND_NORTH := 0.25

var layout: HeightLayout = null
var _tiles: RoomTiles = null
var _connectors: Array[HeightConnector] = []
var _lips: Node2D = null
## North edge tile -> its piece in the y-sorted copy, and the bodies behind it (instance id -> body).
var _lip_pieces: Dictionary[Vector2i, Sprite2D] = {}
var _behind: Dictionary[Vector2i, Dictionary] = {}


## Builds everything for layout on tiles (called by RoomTiles.paint, again after a biome change).
func build(tiles: RoomTiles, height_layout: HeightLayout, biome_id: StringName, look: RockTerrain.Look) -> void:
	name = NAME
	_tiles = tiles
	layout = height_layout
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_connectors.clear()
	_lip_pieces.clear()
	_behind.clear()
	add_to_group(HeightRules.FIELDS_GROUP)
	var unit := float(tiles.tile_set.tile_size.x) if tiles.tile_set != null else float(PlateauArt.TILE)
	_build_art(tiles, biome_id, look, unit)
	var one_way: Array[int] = []
	var rects := wall_rects(layout, unit, one_way)
	add_child(HeightBody.create("Cliffs", PhysicsLayers.CLIFF, rects, one_way))
	var ladder_rects: Array[Rect2] = []
	for tile in _sorted(layout.ladders):
		ladder_rects.append(Rect2(Vector2(tile) * unit, Vector2(unit, front_of(unit))))
	if not ladder_rects.is_empty():
		add_child(HeightBody.create("Ladders", PhysicsLayers.LADDER, ladder_rects))
	for tile in _sorted(layout.stairs) + _sorted(layout.ladders):
		var connector := HeightConnector.new()
		connector.setup(tile, layout.ladders.has(tile), unit)
		connector.level_changed.connect(func(body: Node2D, level: int) -> void: level_changed.emit(body, level))
		connector.climbing_changed.connect(func(player: Player, climbing: bool) -> void: climbing_changed.emit(player, climbing))
		add_child(connector)
		_connectors.append(connector)


## Collision rectangles (layer space) of the height for walkers: the front of every cliff tile
## (front_of less the reach, merged per row) and a thin wall of HeightRules.EDGE_THICKNESS on every
## surface side towards the ground. one_way (optional) gets one HeightBody kind per rect: the north
## edge is two one-way walls (see the north edge below), everything else solid.
## Upper edges (bug reports 23.10.2026 #08fe4567, #019f28b3, "noch 3-4 Pixel weiter nach oben"): a
## figure's body circle sits above its feet, so who walks north stops with his feet well below an
## edge. The cliff's collision ends reach_of() above its foot line, and a figure on the plateau walks
## reach_of() further towards the north edge than a figure on the ground behind it may come from the
## north (RockTerrain.FRONT_REACH, the same for the rock).
static func wall_rects(height_layout: HeightLayout, unit: float, one_way: Array[int] = []) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	one_way.clear()
	var front := front_of(unit)
	var reach := reach_of(unit)
	var cliffs := _sorted(height_layout.cliffs)
	var i := 0
	while i < cliffs.size():
		var start := cliffs[i]
		var length := 1
		while i + length < cliffs.size() and cliffs[i + length] == start + Vector2i(length, 0):
			length += 1
		rects.append(Rect2(Vector2(start) * unit, Vector2(float(length) * unit, front - reach)))
		i += length
	var half := HeightRules.EDGE_THICKNESS * 0.5
	var band := band_of(unit)
	for tile in _sorted(height_layout.edge_sides):
		var sides: int = height_layout.edge_sides[tile]
		var origin := Vector2(tile) * unit
		# An edge to the ground in the north lies band_of() into the tile; the side walls of that tile
		# start there, so the band is open from the north and from the sides (no invisible wall).
		var side_top := band - half if sides & 1 else 0.0
		if sides & 1:
			# Who comes from the north stops at the band line, who walks on the plateau reach further
			# north: one one-way wall for each side.
			_pad(one_way, rects.size())
			rects.append(Rect2(origin + Vector2(0, band - half), Vector2(unit, HeightRules.EDGE_THICKNESS)))
			one_way.append(HeightBody.ONE_WAY_FROM_NORTH)
			rects.append(Rect2(origin + Vector2(0, band - reach - half), Vector2(unit, HeightRules.EDGE_THICKNESS)))
			one_way.append(HeightBody.ONE_WAY_FROM_SOUTH)
		if sides & 2:
			rects.append(Rect2(origin + Vector2(unit - half, side_top), Vector2(HeightRules.EDGE_THICKNESS, unit - side_top)))
		if sides & 4:
			rects.append(Rect2(origin + Vector2(0, unit - half), Vector2(unit, HeightRules.EDGE_THICKNESS)))
		if sides & 8:
			rects.append(Rect2(origin + Vector2(-half, side_top), Vector2(HeightRules.EDGE_THICKNESS, unit - side_top)))
		if sides & 1:
			# The band ends where the surface beside it has none (rock north of it).
			for step: int in [-1, 1]:
				var beside := tile + Vector2i(step, 0)
				if height_layout.surface.has(beside) and not (int(height_layout.edge_sides.get(beside, 0)) & 1):
					var x := unit - half if step > 0 else -half
					rects.append(Rect2(origin + Vector2(x, 0), Vector2(HeightRules.EDGE_THICKNESS, band + half)))
	# Stairs and ladders are closed towards the ground beside them along their front
	# (HeightLayout.connector_sides); below it lies ground like beside them.
	for tile in _sorted(height_layout.connector_sides):
		var sides: int = height_layout.connector_sides[tile]
		var origin := Vector2(tile) * unit
		if sides & 2:
			rects.append(Rect2(origin + Vector2(unit - half, 0), Vector2(HeightRules.EDGE_THICKNESS, front)))
		if sides & 8:
			rects.append(Rect2(origin + Vector2(-half, 0), Vector2(HeightRules.EDGE_THICKNESS, front)))
	# A surface tile beside a cliff, stairs or ladder (HeightLayout.foot_sides, #302ea822): closed
	# along that side where the tile beside it is ground (the lower part); beside a cliff the whole
	# side, its front is solid anyway.
	for tile in _sorted(height_layout.foot_sides):
		var sides: int = height_layout.foot_sides[tile]
		var origin := Vector2(tile) * unit
		for side: int in [2, 8]:
			if not sides & side:
				continue
			var beside := tile + (Vector2i.RIGHT if side == 2 else Vector2i.LEFT)
			var top := 0.0 if height_layout.cliffs.has(beside) else front
			var x := unit - half if side == 2 else -half
			rects.append(Rect2(origin + Vector2(x, top), Vector2(HeightRules.EDGE_THICKNESS, unit - top)))
	_pad(one_way, rects.size())
	return rects


## Fills one_way with solid entries up to count.
static func _pad(one_way: Array[int], count: int) -> void:
	while one_way.size() < count:
		one_way.append(0)


## Depth of the band at a plateau's north edge to the ground (layer px for tiles of unit px, BAND).
static func band_of(unit: float) -> float:
	return BAND * unit / float(PlateauArt.TILE)


## How much closer a figure comes to an upper edge (layer px for tiles of unit px,
## RockTerrain.FRONT_REACH): the foot of a cliff and the north edge seen from the plateau.
static func reach_of(unit: float) -> float:
	return float(RockTerrain.FRONT_REACH) * unit / float(PlateauArt.TILE)


## Height of the front in the cliff row (layer px for tiles of unit px, PLATFORM_HEIGHT): the upper
## part of a cliff, stairs or ladder tile; the rest of the tile is ground in front of it.
static func front_of(unit: float) -> float:
	return PLATFORM_HEIGHT * unit / float(PlateauArt.TILE)


## Is the layer point (tiles' local space) in the band of a surface tile's north edge (on the ground)?
static func in_band(height_layout: HeightLayout, tile: Vector2i, local: Vector2, unit: float) -> bool:
	if height_layout == null or not (int(height_layout.edge_sides.get(tile, 0)) & 1):
		return false
	return local.y - float(tile.y) * unit < band_of(unit)


## Does the world point lie on the floor of this field's room (its floor rectangle)?
func covers(point: Vector2) -> bool:
	if _tiles == null or not is_instance_valid(_tiles):
		return false
	return Rect2i(Vector2i.ZERO, _tiles.room_size).has_point(tile_at(point))


func level_at(point: Vector2) -> int:
	if layout == null:
		return HeightRules.GROUND
	var tile := tile_at(point)
	if in_band(layout, tile, _tiles.to_local(point), _unit()):
		return HeightRules.GROUND
	return layout.level_of(tile)


func _unit() -> float:
	return float(_tiles.tile_set.tile_size.x) if _tiles != null and _tiles.tile_set != null else float(PlateauArt.TILE)


## Does the world point lie in the front of a cliff (not on the ground in front of it)?
func is_cliff_at(point: Vector2) -> bool:
	if layout == null or not layout.cliffs.has(tile_at(point)):
		return false
	return _tiles.to_local(point).y - float(tile_at(point).y) * _unit() < front_of(_unit())


## point moved off the edges of the surface tile it lies on, at least inset (layer px) into the
## tile: inside the navigation of the plateau (RoomTiles cuts it NAV_INSET off every edge). Points
## elsewhere stay unchanged.
func into_surface(point: Vector2, inset: float) -> Vector2:
	if layout == null or _tiles == null or not is_instance_valid(_tiles):
		return point
	var tile := tile_at(point)
	var sides: int = layout.edge_sides.get(tile, 0) | layout.foot_sides.get(tile, 0)
	if sides == 0 or not layout.surface.has(tile):
		return point
	var unit := float(_tiles.tile_set.tile_size.x) if _tiles.tile_set != null else float(PlateauArt.TILE)
	var local := _tiles.to_local(point)
	var low := Vector2(tile) * unit
	var high := low + Vector2.ONE * unit
	if sides & 1:
		local.y = maxf(local.y, low.y + inset + band_of(unit))
	if sides & 2:
		local.x = minf(local.x, high.x - inset)
	if sides & 4:
		local.y = minf(local.y, high.y - inset)
	if sides & 8:
		local.x = maxf(local.x, low.x + inset)
	return _tiles.to_global(local)


func tile_at(point: Vector2) -> Vector2i:
	return _tiles.local_to_map(_tiles.to_local(point))


func get_connectors() -> Array[HeightConnector]:
	return _connectors


## The ladder area a player climbs right now (null = none).
func climbing(player: Player) -> HeightConnector:
	for connector in _connectors:
		if connector.is_climbing(player):
			return connector
	return null


func _build_art(tiles: RoomTiles, biome_id: StringName, look: RockTerrain.Look, unit: float) -> void:
	var fill := PlateauArt.fill_image(tiles.tile_set, look)
	var surface := PlateauArt.surface_texture(layout, fill, "%s|%d" % [biome_id, look], PlateauArt.rim_colors(biome_id), not PlateauArt.has_top_art(biome_id))
	if not surface.is_empty():
		var sprite := Sprite2D.new()
		sprite.name = "Surface"
		sprite.texture = surface["texture"]
		sprite.centered = false
		sprite.position = Vector2(surface["origin"]) * unit / float(PlateauArt.TILE)
		sprite.scale = Vector2.ONE * unit / float(PlateauArt.TILE)
		add_child(sprite)
	_build_lips(tiles, surface, unit)
	_build_fronts(biome_id, unit)
	var stairs := PlateauArt.stairs_texture(biome_id)
	for tile in _sorted(layout.stairs):
		add_child(_tile_sprite("Steps_%d_%d" % [tile.x, tile.y], stairs, Vector2(tile) * unit, unit))
	var ladder := PlateauArt.ladder_texture()
	var top := PlateauArt.ladder_top_texture()
	for tile in _sorted(layout.ladders):
		if ladder != null:
			# The ladder only as high as the front: the lower part of the picture, standing on the ground.
			var piece := _tile_sprite("Ladder", ladder, Vector2(tile) * unit, unit)
			piece.region_enabled = true
			piece.region_rect = Rect2(0.0, float(ladder.get_height()) - PLATFORM_HEIGHT, float(ladder.get_width()), PLATFORM_HEIGHT)
			add_child(piece)
		if top != null:
			# ladder_top hangs over the edge of the surface: its foot on the top of the cliff.
			add_child(_tile_sprite("LadderTop", top, Vector2(tile) * unit - Vector2(0, top.get_height()) * unit / float(PlateauArt.TILE), unit))


## The half-high front on every cliff and ladder tile (PlateauArt.front_pieces: ends where the row
## of the front ends) and the shade it casts on the ground at its foot.
func _build_fronts(biome_id: StringName, unit: float) -> void:
	var pieces := PlateauArt.front_pieces(biome_id)
	var shade := PlateauArt.foot_shade_texture()
	var fronts := _sorted(layout.cliffs) + _sorted(layout.ladders)
	fronts.sort()
	for tile in fronts:
		var at := Vector2(tile) * unit
		add_child(_tile_sprite("Front_%d_%d" % [tile.x, tile.y], pieces[PlateauArt.front_piece_of(layout, tile)], at, unit))
		add_child(_tile_sprite("FrontShade_%d_%d" % [tile.x, tile.y], shade, at + Vector2(0.0, front_of(unit)), unit))


## The band of every north edge once more in the room's y-sort (see the header), sorted at its band
## line. Only the band: what lies flat on the plateau (shadows, warnings, flat sources, all below the
## figures) must stay visible on the rest of the surface. Only inside a room.
func _build_lips(tiles: RoomTiles, surface: Dictionary, unit: float) -> void:
	_drop_lips()
	var room := tiles.get_parent() as Node2D
	if room == null or surface.is_empty() or Engine.is_editor_hint():
		return
	_lips = Node2D.new()
	_lips.name = LIPS_NAME
	_lips.y_sort_enabled = true
	var texture: Texture2D = surface["texture"]
	var origin: Vector2i = surface["origin"]
	var art_scale := unit / float(PlateauArt.TILE)
	for tile in _sorted(layout.edge_sides):
		if not (int(layout.edge_sides[tile]) & 1):
			continue
		var region := Rect2(Vector2(tile) * PlateauArt.TILE - Vector2(origin), Vector2(PlateauArt.TILE, BAND))
		var piece := _lip_piece(tiles, texture, region, tile, art_scale, unit)
		_lips.add_child(piece)
		_lip_pieces[tile] = piece
		add_child(_behind_area(tile, unit))
	_attach_lips.call_deferred()


## The watch area behind a north edge tile (layer space): from BEHIND_NORTH of a tile north of it down
## to the wall that stops figures on the plateau (reach_of() north of the band line), BEHIND_REACH
## tiles wider on both sides. Players and enemies only; nobody on the plateau reaches it.
func _behind_area(tile: Vector2i, unit: float) -> Area2D:
	var area := Area2D.new()
	area.name = "Behind_%d_%d" % [tile.x, tile.y]
	area.collision_layer = 0
	area.collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.ENEMIES
	area.monitorable = false
	var top := float(tile.y) * unit - BEHIND_NORTH * unit
	var bottom := float(tile.y) * unit + band_of(unit) - reach_of(unit) - HeightRules.EDGE_THICKNESS * 0.5
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(1 + 2 * BEHIND_REACH) * unit, bottom - top)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)
	area.position = Vector2((float(tile.x) + 0.5) * unit, (top + bottom) * 0.5)
	_behind[tile] = {}
	area.body_entered.connect(_on_behind_entered.bind(tile))
	area.body_exited.connect(_on_behind_exited.bind(tile))
	return area


func _on_behind_entered(body: Node2D, tile: Vector2i) -> void:
	if _behind.has(tile):
		_behind[tile][body.get_instance_id()] = body
		_show_depth(tile)


func _on_behind_exited(body: Node2D, tile: Vector2i) -> void:
	if _behind.has(tile):
		_behind[tile].erase(body.get_instance_id())
		_show_depth(tile)


## The copy of tile covers its whole row while somebody stands behind it, else only the band.
func _show_depth(tile: Vector2i) -> void:
	var piece := get_lip_piece(tile)
	if piece == null:
		return
	var depth := float(PlateauArt.TILE) if is_covered_deep(tile) else BAND
	piece.region_rect = Rect2(piece.region_rect.position, Vector2(piece.region_rect.size.x, depth))


## Does the copy of the north edge tile cover its whole row right now (somebody behind it)?
func is_covered_deep(tile: Vector2i) -> bool:
	for body: Variant in _behind.get(tile, {}).values():
		if is_instance_valid(body):
			return true
	return false


## The piece of the y-sorted copy at a north edge tile (null elsewhere or before it is built).
func get_lip_piece(tile: Vector2i) -> Sprite2D:
	var piece: Variant = _lip_pieces.get(tile)
	return piece as Sprite2D if is_instance_valid(piece) else null


## Puts the band pieces into the room (deferred from _build_lips, like RoomTiles' rock lips); skipped
## when they were dropped meanwhile. A room whose biome tiles are set right after its first paint
## builds its height twice in one frame: a deferred add_child of the first, already freed pieces
## crashed the engine (headless test runs of ember forge and shadow realm rooms with a plateau).
func _attach_lips() -> void:
	var room := _tiles.get_parent() as Node2D if _tiles != null and is_instance_valid(_tiles) else null
	if room != null and _lips != null and is_instance_valid(_lips) and not _lips.is_inside_tree():
		room.add_child(_lips)


## The band pieces go: at once while they are not in the room yet, else at the end of the frame.
func _drop_lips() -> void:
	if _lips != null and is_instance_valid(_lips):
		if _lips.is_inside_tree():
			_lips.queue_free()
		else:
			_lips.free()
	_lips = null


## Where the copy of the plateau at a surface tile sorts in the room (room-local y): the band line of
## its column's north edge, SORT_FEET up like a character. Whatever stands on the plateau must sort
## below it (later), whatever stands on the ground behind it above (earlier).
static func lip_sort_y(tiles: RoomTiles, height_layout: HeightLayout, tile: Vector2i) -> float:
	var unit := float(tiles.tile_set.tile_size.x) if tiles.tile_set != null else float(PlateauArt.TILE)
	var column_top := tile
	while height_layout.surface.has(column_top + Vector2i.UP):
		column_top += Vector2i.UP
	return tiles.position.y + (float(column_top.y) * unit + band_of(unit)) * tiles.scale.y - SORT_FEET


## One piece of the y-sorted surface: region of texture drawn on tile (layer space), sorted at the
## band line of tile's column.
func _lip_piece(tiles: RoomTiles, texture: Texture2D, region: Rect2, tile: Vector2i, art_scale: float, unit: float) -> Sprite2D:
	var sort_y := lip_sort_y(tiles, layout, tile)
	var piece := Sprite2D.new()
	piece.texture = texture
	piece.region_enabled = true
	piece.region_rect = region
	piece.centered = false
	piece.scale = tiles.scale * art_scale
	piece.modulate = tiles.modulate
	piece.position = Vector2(tiles.position.x + float(tile.x) * unit * tiles.scale.x, sort_y)
	piece.offset = Vector2(0.0, (tiles.position.y + float(tile.y) * unit * tiles.scale.y - sort_y) / piece.scale.y)
	return piece


func get_lips() -> Node2D:
	return _lips


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_drop_lips()


static func _tile_sprite(sprite_name: String, texture: Texture2D, at: Vector2, unit: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = at
	sprite.scale = Vector2.ONE * unit / float(PlateauArt.TILE)
	return sprite


static func _sorted(tiles: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(tiles.keys())
	result.sort()
	return result
