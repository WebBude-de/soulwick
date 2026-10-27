extends GutTest
## Bug reports 17.10.2026 (web build dev.7, rooms 7-30):
##   - #b16194d4 "da bin ich transparent": the walkable band at the top of a lip was closed at the
##     ends of a block; since 22.10.2026 (#db6117ad, "unsichtbare Wand") it is open there again, one
##     rule for every raised mass (RockTerrain.LIP_CAPS);
##   - #5d991188 "unsichtbare Hitbox": the wall beside an entrance gap is a lip like the rest of the
##     wall, a blocked south entrance blocks from the band down, and rock both joined rooms keep takes
##     the lip's collision (PassageSeam);
##   - #5bf2c82e: a room built in stages (paint held back) already knows its cave look, so the cracked
##     wall of a secret niche is the cave rock's crack, not bricks;
##   - #6be25fbd: a campfire built in stages draws the next biome over its own walls (blend layers
##     after the draw layers);
##   - #a1bd7c42: hangings in the side view grow out of the ceiling (their art's rock strip left out).

const HALL: PackedScene = preload("res://dungeon/rooms/combat/combat_hall.tscn")
const CAVE: PackedScene = preload("res://dungeon/rooms/combat/rundhoehle_crypt.tscn")
const CAMPFIRE: PackedScene = preload("res://dungeon/rooms/campfire/campfire_room.tscn")
const DOOR_SCENE: PackedScene = preload("res://dungeon/environment/doors/door.tscn")
const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_walls_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 17
	return context


func test_lip_band_is_open_at_the_ends_of_a_block() -> void:
	# Bug report 22.10.2026 (#db6117ad, "warum ist hier eine unsichtbare Wand"): one rule for every
	# raised mass, the band behind a block is open from the north and from the sides (no caps).
	var floor_mask: Dictionary[Vector2i, bool] = {}
	for y in range(-2, 4):
		for x in range(-3, 4):
			floor_mask[Vector2i(x, y)] = true
	for x in range(-1, 2):
		floor_mask.erase(Vector2i(x, 0))
		floor_mask.erase(Vector2i(x, 1))
	assert_false(RockTerrain.LIP_CAPS, "caps are off")
	for x in range(-1, 2):
		assert_eq(RockTerrain.lip_caps(Vector2i(x, 0), floor_mask), 0, "no cap at %d" % x)
	# The caps stay buildable (LIP_CAPS on): inside the band and the tile.
	var half := RockTerrain.TILE / 2.0
	for cap in [RockTerrain.CAP_LEFT, RockTerrain.CAP_RIGHT]:
		for bits in [0, RockTerrain.CORNER_TL | RockTerrain.CORNER_TR]:
			var polygon := RockTerrain.lip_cap_polygon(bits, cap)
			assert_gt(polygon.size(), 3)
			for point in polygon:
				assert_between(point.y, -half - 0.01, -half + RockTerrain.LIP_WALK + 0.01)
			assert_true(Geometry2D.decompose_polygon_in_convex(polygon).size() == 1, "convex")
	for caps in 4:
		var coords := RockTerrain.solid_coords(5, true, caps)
		assert_true(RockTerrain.is_solid_cell(RockTerrain.SOURCE_GROUND, coords))
		assert_true(RockTerrain.is_lip_coords(coords))
	assert_false(RockTerrain.is_lip_coords(RockTerrain.solid_coords(5)))


func test_a_player_walks_into_a_block_top_from_the_side() -> void:
	var room := HALL.instantiate() as RoomController
	room.setup(3, RoomSequence.RoomType.COMBAT, -1, false, _context())
	add_child_autofree(room)
	await wait_process_frames(2)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	var floor_mask := tiles.get_floor_mask()
	var corridors := tiles.get_door_corridor_tiles()
	var checked := 0
	for cell in tiles.get_used_cells():
		var coords := tiles.get_cell_atlas_coords(cell)
		if not RockTerrain.is_solid_cell(tiles.get_cell_source_id(cell), coords) or not RockTerrain.is_lip_coords(coords):
			continue
		assert_eq(coords.y, RockTerrain.SOLID_LIP_ROW, "%s: no cap" % cell)
		var west_open := floor_mask.has(cell + Vector2i.LEFT) and not corridors.has(cell + Vector2i.LEFT)
		var east_open := floor_mask.has(cell + Vector2i.RIGHT) and not corridors.has(cell + Vector2i.RIGHT)
		if not west_open and not east_open:
			continue
		checked += 1
		# A body moving in from the side in the band gets over the end of the block.
		var side := -1 if west_open else 1
		var body := CharacterBody2D.new()
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		shape.shape = circle
		body.add_child(shape)
		body.collision_mask = tiles.tile_set.get_physics_layer_collision_layer(0)
		var center := tiles.to_global(tiles.map_to_local(cell))
		var band_y := center.y - RoomTiles.TILE_WORLD * 0.5 + RockTerrain.LIP_WALK
		body.global_position = Vector2(center.x + side * RoomTiles.TILE_WORLD, band_y)
		room.add_child(body)
		await wait_physics_frames(1)
		body.move_and_collide(Vector2(-side * RoomTiles.TILE_WORLD * 0.75, 0.0))
		var edge := center.x + side * RoomTiles.TILE_WORLD * 0.5
		assert_lt((body.global_position.x - edge) * side, 0.0, "%s: walked into the band behind the block" % cell)
		body.free()
		if checked >= 3:
			break
	if checked == 0:
		pass_test("no free-standing block in this hall")


func test_the_wall_beside_an_entrance_gap_is_a_lip() -> void:
	var room := HALL.instantiate() as RoomController
	room.setup(3, RoomSequence.RoomType.COMBAT, -1, false, _context())
	add_child_autofree(room)
	await wait_process_frames(2)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	assert_eq(tiles.entrance_side, RoomTiles.DoorSide.SOUTH)
	var door := RoomTiles.door_tile_of(tiles.entrance_side, tiles.entrance_x, tiles.room_size)
	for dx in [-1, 1]:
		var cell := door + Vector2i(dx, 0)
		if not tiles.get_floor_mask().has(cell + Vector2i.UP):
			continue
		var coords := tiles.get_cell_atlas_coords(cell)
		assert_true(RockTerrain.is_lip_coords(coords), "%s beside the gap: a lip, no step along the wall" % cell)
		assert_eq(coords.y - RockTerrain.SOLID_LIP_ROW, 0, "%s: no cap towards the gap" % cell)
	# A blocked south entrance is part of the wall's lip.
	var entrance := Door.entrance_of(room)
	assert_not_null(entrance)
	if entrance != null:
		entrance.block()
		var rect := entrance.get_blocking_rect()
		assert_almost_eq(rect.position.y, RockTerrain.LIP_WALK * SpriteStrip.PIXEL_SCALE, 0.01, "blocks from the band down")
		assert_almost_eq(rect.end.y, RoomTiles.TILE_WORLD, 0.01)
	# An exit gate blocks its whole tile.
	var gate := room.get_exit_doors()[0]
	assert_almost_eq(gate.get_blocking_rect().size.y, RoomTiles.TILE_WORLD, 0.01)


func test_rock_both_rooms_keep_takes_the_lip() -> void:
	var info_room := HALL.instantiate() as RoomController
	var info_tiles := info_room.get_node("Tiles") as RoomTiles
	var size := info_tiles.room_size
	var entrance_x := info_tiles.entrance_x
	var exit_x := info_tiles.exit_x
	info_room.free()
	var lower := HALL.instantiate() as RoomController
	lower.setup(3, RoomSequence.RoomType.COMBAT, -1, false, _context())
	lower.apply_door_plan(Vector2i(ExitRules.SOUTH, entrance_x), [Vector2i(ExitRules.NORTH, exit_x)] as Array[Vector2i])
	add_child_autofree(lower)
	var end := ExitRules.exit_corridor_end(Vector2i.ZERO, size, ExitRules.NORTH, exit_x)
	var upper := HALL.instantiate() as RoomController
	upper.setup(4, RoomSequence.RoomType.COMBAT, -1, false, _context())
	upper.apply_door_plan(Vector2i(ExitRules.SOUTH, entrance_x), [Vector2i(ExitRules.NORTH, exit_x)] as Array[Vector2i])
	upper.position = Vector2(ExitRules.origin_for(end, size, ExitRules.SOUTH, entrance_x)) * RoomTiles.TILE_WORLD
	add_child_autofree(upper)
	await wait_process_frames(2)
	if not lower.tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	PassageSeam.join(lower, upper)
	var lipped := PassageSeam.get_lipped(lower, upper)
	var shift := PassageSeam.origin_of(upper) - PassageSeam.origin_of(lower)
	for cell in lipped:
		assert_true(RockTerrain.is_lip_coords(lower.tiles.get_cell_atlas_coords(cell)), "%s: the lower room collides like the lip" % cell)
		assert_true(RockTerrain.is_lip_coords(upper.tiles.get_cell_atlas_coords(cell - shift)), "%s: lip of the upper room" % cell)
	# Beside the upper room's entrance gap no full block of the lower room is left on its lip row.
	var gap := RoomTiles.door_tile_of(RoomTiles.DoorSide.SOUTH, entrance_x, size)
	for dx in [-1, 1]:
		var in_upper := gap + Vector2i(dx, 0)
		var in_lower := in_upper + shift
		var source := lower.tiles.get_cell_source_id(in_lower)
		var coords := lower.tiles.get_cell_atlas_coords(in_lower)
		if RockTerrain.is_solid_cell(source, coords):
			assert_true(RockTerrain.is_lip_coords(coords), "%s: no invisible block beside the gap" % in_lower)
	PassageSeam.release(upper, [lower])
	assert_true(PassageSeam.get_lipped(lower, upper).is_empty(), "given back on release")


func test_a_held_cave_room_knows_its_look() -> void:
	var room := CAVE.instantiate() as RoomController
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, _context())
	var tiles := room.get_node("Tiles") as RoomTiles
	tiles.hold_paint()
	add_child_autofree(room)
	assert_false(tiles.is_terrain_drawn(), "nothing painted yet")
	if not RockTerrain.ensure_sources(tiles.tile_set):
		pending("no terrain art")
		return
	assert_true(tiles.is_terrain_planned(), "the terrain will be drawn")
	assert_eq(tiles.get_planned_look(), RockTerrain.Look.CAVE)
	assert_true(tiles.is_cave_look(), "doors take the soft style before the paint")
	var site := SecretRules.find_sites(tiles, {})
	if site.is_empty():
		pass_test("no niche site in this cave")
		return
	var niche := SecretNiche.attach(room, site[0], SecretRules.Content.CHEST)
	var crack := niche.get_node("CrackedWall") as Sprite2D
	assert_false(crack.texture.resource_path.ends_with("wall_cracked_crypt.png"), "no brick crack in the cave rock")
	tiles.release_paint()
	assert_true(tiles.is_terrain_drawn())
	assert_eq(tiles.get_look(), tiles.get_planned_look(), "the plan was right")


func test_a_staged_campfire_draws_the_next_biome_over_its_walls() -> void:
	var room := CAMPFIRE.instantiate() as RoomController
	room.setup(15, RoomSequence.RoomType.CAMPFIRE, -1, true, _context())
	room.slot_index = RoomSequence.get_campfire_slot_after(15)
	var tiles := room.get_node("Tiles") as RoomTiles
	tiles.hold_paint()
	add_child_autofree(room)
	await wait_process_frames(1)
	tiles.release_paint()
	await wait_process_frames(1)
	if not tiles.has_biome_blend() or tiles.get_rock_layer() == null:
		pending("no blend or terrain in this build")
		return
	assert_gt(tiles.get_blend_layer().get_index(true), tiles.get_rock_layer().get_index(true), "the next biome's walls over the old ones")


func test_side_hangings_grow_out_of_the_ceiling() -> void:
	# #a1bd7c42: the delivered hangings start with a strip of their own rock; it is left out.
	for kind in ["crystals", "roots"]:
		var path := "res://art/environment/side/hang_%s.png" % kind
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		var rows := SideDecor.rock_rows_of(texture)
		assert_between(rows, 1, SideDecor.HANG_ROCK_ROWS_MAX, "%s: its rock strip is found" % kind)
		var image := texture.get_image()
		var open := 0
		for x in image.get_width():
			open += 1 if image.get_pixel(x, rows).a < 0.5 else 0
		assert_gt(open, 0, "%s: the first row kept is no solid strip" % kind)
