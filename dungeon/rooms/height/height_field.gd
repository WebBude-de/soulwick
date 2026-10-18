class_name HeightField
extends Node2D
## The height of one live room (M3, Makeover 3 §8): built by RoomTiles in its layer space (32 art px
## per tile) from its HeightLayout. Holds
##   - the walls of the height (HeightBody "Cliffs", PhysicsLayers.CLIFF): a rectangle on every
##     cliff tile and a thin wall on every edge between a surface tile and the ground beside it;
##     players and enemies stop there, shots and hit areas do not;
##   - the ladder block for enemies (HeightBody "Ladders", PhysicsLayers.LADDER);
##   - the switch areas on stairs and ladders (HeightConnector: level_changed, ladder slow);
##   - the pictures: surface floor (PlateauArt), steps on the stairs, ladder with its top.
## The navigation of the surface tiles lies on the room layer itself (RoomTiles), cut off at the
## edges, so enemies walk up and down only over stairs.
## Z order: everything here belongs to the tile layer, drawn below every figure; figures sort by y
## as everywhere, so a figure on the plateau always stands in front of the cliff below it and a
## figure on the ground in front of the cliff it walks along.
## Answers HeightRules: covers(point) and level_at(point) (group HeightRules.FIELDS_GROUP).

signal level_changed(body: Node2D, level: int)
signal climbing_changed(player: Player, climbing: bool)

const NAME := "Height"

var layout: HeightLayout = null
var _tiles: RoomTiles = null
var _connectors: Array[HeightConnector] = []


## Builds everything for layout on tiles (called by RoomTiles.paint, again after a biome change).
func build(tiles: RoomTiles, height_layout: HeightLayout, biome_id: StringName, look: RockTerrain.Look) -> void:
	name = NAME
	_tiles = tiles
	layout = height_layout
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_connectors.clear()
	add_to_group(HeightRules.FIELDS_GROUP)
	var unit := float(tiles.tile_set.tile_size.x) if tiles.tile_set != null else float(PlateauArt.TILE)
	_build_art(tiles, biome_id, look, unit)
	add_child(HeightBody.create("Cliffs", PhysicsLayers.CLIFF, wall_rects(layout, unit)))
	var ladder_rects: Array[Rect2] = []
	for tile in _sorted(layout.ladders):
		ladder_rects.append(Rect2(Vector2(tile) * unit, Vector2.ONE * unit))
	if not ladder_rects.is_empty():
		add_child(HeightBody.create("Ladders", PhysicsLayers.LADDER, ladder_rects))
	for tile in _sorted(layout.stairs) + _sorted(layout.ladders):
		var connector := HeightConnector.new()
		connector.setup(tile, layout.ladders.has(tile), unit)
		connector.level_changed.connect(func(body: Node2D, level: int) -> void: level_changed.emit(body, level))
		connector.climbing_changed.connect(func(player: Player, climbing: bool) -> void: climbing_changed.emit(player, climbing))
		add_child(connector)
		_connectors.append(connector)


## Collision rectangles (layer space) of the height for walkers: every cliff tile (merged per row)
## and a thin wall of HeightRules.EDGE_THICKNESS on every surface side towards the ground.
static func wall_rects(height_layout: HeightLayout, unit: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var cliffs := _sorted(height_layout.cliffs)
	var i := 0
	while i < cliffs.size():
		var start := cliffs[i]
		var length := 1
		while i + length < cliffs.size() and cliffs[i + length] == start + Vector2i(length, 0):
			length += 1
		rects.append(Rect2(Vector2(start) * unit, Vector2(length, 1) * unit))
		i += length
	var half := HeightRules.EDGE_THICKNESS * 0.5
	for tile in _sorted(height_layout.edge_sides):
		var sides: int = height_layout.edge_sides[tile]
		var origin := Vector2(tile) * unit
		if sides & 1:
			rects.append(Rect2(origin + Vector2(0, -half), Vector2(unit, HeightRules.EDGE_THICKNESS)))
		if sides & 2:
			rects.append(Rect2(origin + Vector2(unit - half, 0), Vector2(HeightRules.EDGE_THICKNESS, unit)))
		if sides & 4:
			rects.append(Rect2(origin + Vector2(0, unit - half), Vector2(unit, HeightRules.EDGE_THICKNESS)))
		if sides & 8:
			rects.append(Rect2(origin + Vector2(-half, 0), Vector2(HeightRules.EDGE_THICKNESS, unit)))
	return rects


## Does the world point lie on the floor of this field's room (its floor rectangle)?
func covers(point: Vector2) -> bool:
	if _tiles == null or not is_instance_valid(_tiles):
		return false
	return Rect2i(Vector2i.ZERO, _tiles.room_size).has_point(tile_at(point))


func level_at(point: Vector2) -> int:
	return layout.level_of(tile_at(point)) if layout != null else HeightRules.GROUND


func is_cliff_at(point: Vector2) -> bool:
	return layout != null and layout.cliffs.has(tile_at(point))


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
	var surface := PlateauArt.surface_texture(layout, fill, "%s|%d" % [biome_id, look], PlateauArt.rim_colors(biome_id))
	if not surface.is_empty():
		var sprite := Sprite2D.new()
		sprite.name = "Surface"
		sprite.texture = surface["texture"]
		sprite.centered = false
		sprite.position = Vector2(surface["origin"]) * unit / float(PlateauArt.TILE)
		sprite.scale = Vector2.ONE * unit / float(PlateauArt.TILE)
		add_child(sprite)
	var stairs := PlateauArt.stairs_texture(biome_id)
	for tile in _sorted(layout.stairs):
		if stairs != null:
			add_child(_tile_sprite("Steps", stairs, Vector2(tile) * unit, unit))
	var ladder := PlateauArt.ladder_texture()
	var top := PlateauArt.ladder_top_texture()
	for tile in _sorted(layout.ladders):
		if ladder != null:
			add_child(_tile_sprite("Ladder", ladder, Vector2(tile) * unit, unit))
		if top != null:
			# ladder_top hangs over the edge of the surface: its foot on the top of the cliff.
			add_child(_tile_sprite("LadderTop", top, Vector2(tile) * unit - Vector2(0, top.get_height()) * unit / float(PlateauArt.TILE), unit))


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
