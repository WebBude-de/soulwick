extends GutTest
## Half-high plateaus (D-205, CR6; bug reports #25371167, #276ffad7: "man denkt, man kann aus der Map
## laufen"): the front is HeightField.PLATFORM_HEIGHT (16 art px) high in the upper half of the cliff
## row, the ground in front of it belongs to the room (floor cell, navigation, walkable up to the
## foot of the front), the stairs are two steps of 8 px, plateaus stand free with floor all round,
## pictures from the delivered art or placeholders in the biome's rock colours.

const TILESET_PATH := "res://dungeon/environment/dungeon_tileset.tres"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TEST_SAVE_PATH := "user://test_height_half.cfg"
## World px below the foot of the front where the test player's feet circle (radius 9) stands.
const IN_FRONT := 16.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## 10 x 9 cave room, plateau at columns 5-8, rows 1-3 with floor all round: stairs at (6, 3), ladder
## at (8, 3), cliffs at (5, 3) and (7, 3).
func _room() -> RoomTiles:
	var room := Node2D.new()
	add_child_autofree(room)
	var tiles := RoomTiles.new()
	tiles.name = "Tiles"
	tiles.tile_set = load(TILESET_PATH)
	tiles.scale = Vector2(2, 2)
	tiles.rock_style = RoomTiles.RockStyle.BLOB
	tiles.room_size = Vector2i(10, 9)
	tiles.entrance_x = 2
	tiles.exit_x = 2
	var plateau: Array[Vector2i] = []
	for y in range(1, 4):
		for x in range(5, 9):
			plateau.append(Vector2i(x, y))
	plateau.erase(Vector2i(6, 3))
	plateau.erase(Vector2i(8, 3))
	tiles.plateau_tiles = plateau
	tiles.ladder_tiles = [Vector2i(8, 3)] as Array[Vector2i]
	tiles.stair_tiles = [Vector2i(6, 3)] as Array[Vector2i]
	room.add_child(tiles)
	EnemyNavigation.isolate_room_navigation(tiles)
	return tiles


func _at(tiles: RoomTiles, tile: Vector2i) -> Vector2:
	return tiles.to_global(tiles.map_to_local(tile))


## The foot of the front of a cliff tile (world): the middle of the tile, since the front fills its
## upper half.
func _foot(tiles: RoomTiles, tile: Vector2i) -> Vector2:
	return tiles.to_global(Vector2(float(tile.x) + 0.5, float(tile.y)) * float(tiles.tile_set.tile_size.x) + Vector2(0.0, HeightField.front_of(float(tiles.tile_set.tile_size.y))))


func test_numbers_follow_d205() -> void:
	assert_eq(HeightField.PLATFORM_HEIGHT, 16.0, "half a tile of 32 art px")
	assert_eq(HeightField.BAND, HeightField.PLATFORM_HEIGHT * 0.5, "the band is half the height of the mass, like a rock lip")
	assert_eq(float(RockTerrain.LIP_WALK), RockTerrain.TILE * 0.5, "the rock lip follows the same rule")
	assert_eq(HeightField.front_of(32.0), 16.0)
	assert_eq(HeightField.front_of(64.0), 32.0)
	var stairs := PlateauArt.stairs_texture(&"crypt")
	assert_eq(stairs.get_size(), Vector2(PlateauArt.TILE, HeightField.PLATFORM_HEIGHT), "two steps of 8 px")


func test_the_front_fills_the_upper_half_of_the_cliff_row() -> void:
	var tiles := _room()
	var layout := tiles.get_height_layout()
	var unit := 32.0
	var cliffs := 0
	for rect in HeightField.wall_rects(layout, unit):
		if rect.size.x >= unit and rect.size.y > HeightRules.EDGE_THICKNESS:
			cliffs += 1
			# The collision ends RockTerrain.FRONT_REACH above the foot line (bug report 23.10.2026 #08fe4567).
			assert_almost_eq(rect.size.y, HeightField.front_of(unit) - HeightField.reach_of(unit), 0.001, "front only: %s" % rect)
			assert_almost_eq(fmod(rect.position.y, unit), 0.0, 0.001, "at the top of the cliff row")
	assert_eq(cliffs, 2, "the two cliff tiles, split by the stairs")


func test_ground_walks_up_to_the_foot_of_the_front() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var field := tiles.get_height_field()
	if field == null:
		pending("no terrain art")
		return
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.health.reset(9999.0)
	var in_front := _foot(tiles, Vector2i(7, 3)) + Vector2(0.0, IN_FRONT)
	player.global_position = in_front - Vector2(0, 8)
	await wait_physics_frames(1)
	assert_false(player.test_move(player.global_transform, Vector2(0, -4)), "the lower half of the cliff tile is ground")
	var reach := HeightField.reach_of(float(tiles.tile_set.tile_size.x)) * tiles.global_scale.y
	assert_false(player.test_move(player.global_transform, Vector2(0, -12)), "a figure comes a little closer than the foot line (#08fe4567)")
	assert_true(player.test_move(player.global_transform, Vector2(0, -12 - reach)), "then the front blocks")
	assert_eq(HeightRules.level_at(in_front), HeightRules.GROUND)
	assert_false(field.is_cliff_at(in_front), "no cliff in front of the front")
	assert_true(field.is_cliff_at(_foot(tiles, Vector2i(7, 3)) - Vector2(0, 8)), "the front itself is the cliff")
	# A figure on the plateau walks to the top of the front.
	player.global_position = _at(tiles, Vector2i(7, 2)) - Vector2(0, 8)
	await wait_physics_frames(1)
	assert_eq(HeightRules.level_of(player), HeightRules.PLATEAU)
	assert_false(player.test_move(player.global_transform, Vector2(0, 16)), "the whole surface tile is walkable")
	assert_true(player.test_move(player.global_transform, Vector2(0, 40)), "the front stops it at the edge")


func test_navigation_reaches_the_ground_in_front_of_the_front() -> void:
	var tiles := _room()
	await wait_physics_frames(12)
	if tiles.get_height_field() == null:
		pending("no terrain art")
		return
	var map := tiles.get_navigation_map()
	var in_front := _foot(tiles, Vector2i(5, 3)) + Vector2(0.0, IN_FRONT)
	assert_lt(NavigationServer2D.map_get_closest_point(map, in_front).distance_to(in_front), 1.0, "navigation in front of the front")
	var on_front := _foot(tiles, Vector2i(5, 3)) - Vector2(0, 16)
	assert_gt(NavigationServer2D.map_get_closest_point(map, on_front).distance_to(on_front), 4.0, "none on the front itself")


func test_pictures_of_the_half_high_plateau() -> void:
	var tiles := _room()
	await wait_physics_frames(2)
	var field := tiles.get_height_field()
	if field == null or tiles.get_rock_layer() == null:
		pending("no terrain art")
		return
	var layout := tiles.get_height_layout()
	var fronts := 0
	var steps := 0
	for child in field.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		assert_false(String(sprite.name).begins_with("WallFace"), "no half wall face any more")
		if String(sprite.name).begins_with("FrontShade"):
			continue
		if String(sprite.name).begins_with("Front"):
			fronts += 1
			assert_eq(sprite.texture.get_height(), int(HeightField.PLATFORM_HEIGHT), "half high")
		elif String(sprite.name).begins_with("Steps"):
			steps += 1
	assert_eq(fronts, layout.cliffs.size() + layout.ladders.size(), "a front on every cliff and behind every ladder")
	assert_eq(steps, layout.stairs.size())
	for tile: Vector2i in layout.get_height_tiles():
		assert_eq(tiles.get_rock_layer().get_cell_source_id(tile), -1, "%s is not drawn as rock" % tile)
		assert_eq(tiles.get_cell_source_id(tile), tiles.get_floor_source(), "%s is a floor cell" % tile)
	assert_eq(HeightChecks.problems(tiles.get_parent()), [] as Array[String])


func test_front_pieces_and_placeholders() -> void:
	var pieces := PlateauArt.front_pieces(&"shadow_realm")
	assert_eq(pieces.size(), PlateauArt.FrontPiece.size())
	for piece in pieces:
		assert_eq(piece.get_size(), Vector2(PlateauArt.TILE, HeightField.PLATFORM_HEIGHT))
	var layout := _room().get_height_layout()
	assert_eq(PlateauArt.front_piece_of(layout, Vector2i(5, 3)), PlateauArt.FrontPiece.LEFT, "the row starts at the west cliff")
	assert_eq(PlateauArt.front_piece_of(layout, Vector2i(7, 3)), PlateauArt.FrontPiece.MIDDLE, "stairs and ladder go on beside it")
	assert_eq(PlateauArt.front_piece_of(layout, Vector2i(8, 3)), PlateauArt.FrontPiece.RIGHT)
	if not ResourceLoader.exists(PlateauArt.STAIRS_HALF_ART % "crypt"):
		var image := PlateauArt.stairs_texture(&"crypt").get_image()
		var light: Color = PlateauArt.rock_colors(&"crypt")[SoftPalette.Anchor.BAND_LIGHT]
		var step := int(HeightField.PLATFORM_HEIGHT) / 2
		assert_eq(image.get_pixel(PlateauArt.TILE / 2, 0), light, "the upper tread")
		assert_eq(image.get_pixel(PlateauArt.TILE / 2, step), light, "the lower tread, 8 px below")
	assert_true(PlateauArt.is_front_below(layout, Vector2i(5, 2)), "light edge of the surface towards its front")
	assert_false(PlateauArt.is_front_below(layout, Vector2i(5, 1)))


func test_templates_keep_floor_round_their_plateaus() -> void:
	var entries := RoomCatalog.create().get_entries()
	entries.append_array(RoomCatalog.load_plans().get_entries())
	var checked := 0
	for entry in entries:
		var room := entry.scene.instantiate() as RoomController
		autofree(room)
		var tiles := room.get_node("Tiles") as RoomTiles
		if not tiles.has_height():
			continue
		checked += 1
		var layout := tiles.get_height_layout()
		for tile: Vector2i in layout.get_height_tiles():
			var rock := layout.rock_beside(tile)
			assert_eq(rock, tile, "%s: %s touches rock at %s" % [room.scene_file_path.get_file(), tile, rock])
	assert_gt(checked, 0, "templates with plateaus")
