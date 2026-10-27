extends GutTest
## Bug reports 22.10.2026 14:29-14:33 (solo runs in the crypt, seeds -7817677183151461459 and
## 7318039169487686574):
##   - #157f21bc, #eeb4fb40: a figure on the ground behind a plateau - the copy of the plateau covers
##     its whole north row while somebody stands behind it (sword tip, Flint and his shadow), only
##     the band otherwise;
##   - #2d4a4686: room modes put nothing on the ground right behind a plateau's north edge (the flame's
##     bonus chest stood on the rim line and seemed to float);
##   - #581b8b3d: the rock copied over the figures (lips, sorted fronts) has no floor in its rounded
##     corners (legs cut off beside a block's corner);
##   - #28fef95b: whatever stands on a plateau sorts after the plateau's copy (a grave in the north
##     row had its stone under the band);
##   - #cab236b0 (not reproduced, the report showed a plateau from before CR6): every plateau shows its
##     stairs or ladder and its chest is reached from the entrance;
##   - #2da96ffa (fixed by D-206 and the low boss frame): test_room_feedback_1022, test_door_frame_rise.

const KREUZGANG := "res://dungeon/rooms/combat/kreuzgang_mirror_crypt.tscn"
const GRUFT := "res://dungeon/rooms/combat/gruft_mirror_crypt.tscn"
const FLAME_ROOM := "res://dungeon/rooms/combat/flamme_schrein_crypt.tscn"
const ASCHEGRUBE := "res://dungeon/rooms/combat/aschegrube_%s.tscn"
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const BIOMES: Array[StringName] = [&"crypt", &"slime_grotto", &"shadow_realm", &"ember_forge"]
const TILESETS: Array[String] = [
	"res://dungeon/environment/dungeon_tileset.tres",
	"res://dungeon/environment/slime_grotto_tileset.tres",
	"res://dungeon/environment/shadow_realm_tileset.tres",
	"res://dungeon/environment/ember_forge_tileset.tres",
]

var _old_save_path: String
var _catalog: RoomCatalog


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_room_feedback_1429_save.cfg"
	_catalog = RoomCatalog.create()


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _context() -> DungeonContext:
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	context.rng.seed = 29
	return context


func _template(path: String) -> RoomController:
	var room := (load(path) as PackedScene).instantiate() as RoomController
	room.setup(7, RoomSequence.RoomType.COMBAT, -1, false, _context())
	var spawner := room.get_node("EnemySpawner") as EnemySpawner
	spawner.biomes = [] as Array[BiomeData]
	spawner.extra_types = [] as Array[EnemyData]
	spawner.enemy_types = [SKELETON] as Array[EnemyData]
	spawner.spawn_weights = [1.0] as Array[float]
	add_child_autofree(room)
	return room


## Every template with height (combat catalog and plan rooms), detached (free them yourself).
func _height_rooms() -> Array[RoomController]:
	var rooms: Array[RoomController] = []
	var entries := _catalog.get_entries()
	entries.append_array(RoomCatalog.load_plans().get_entries())
	for entry in entries:
		var room := entry.scene.instantiate() as RoomController
		if (room.get_node("Tiles") as RoomTiles).has_height():
			rooms.append(room)
		else:
			room.free()
	return rooms


func _north_edges(layout: HeightLayout) -> Array[Vector2i]:
	var north: Array[Vector2i] = []
	for tile: Vector2i in layout.edge_sides:
		if int(layout.edge_sides[tile]) & 1:
			north.append(tile)
	north.sort()
	return north


# --- #157f21bc, #eeb4fb40 ---

func test_a_figure_behind_a_plateau_is_covered_down_to_the_row() -> void:
	var room := _template(KREUZGANG)
	await wait_process_frames(3)
	var tiles := room.tiles
	var layout := tiles.get_height_layout()
	var field := tiles.get_height_field()
	var north := _north_edges(layout)
	assert_gt(north.size(), 3, "the court has a long north edge")
	var tile := north[north.size() / 2]
	var piece := field.get_lip_piece(tile)
	assert_not_null(piece)
	if piece == null:
		return
	assert_almost_eq(piece.region_rect.size.y, HeightField.BAND, 0.01, "nobody behind: only the band")
	var unit := float(tiles.tile_set.tile_size.x)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	var feet := tiles.to_global((Vector2(float(tile.x) + 0.5, float(tile.y))) * unit + Vector2(0.0, HeightField.band_of(unit) * 0.5))
	player.global_position = feet - Player.FEET_OFFSET
	await wait_physics_frames(4)
	assert_eq(HeightRules.level_of(player), HeightRules.GROUND, "in the band: on the ground")
	assert_true(field.is_covered_deep(tile), "somebody behind %s" % tile)
	assert_almost_eq(piece.region_rect.size.y, float(PlateauArt.TILE), 0.01, "the copy covers the whole row (sword, Flint, his shadow)")
	assert_true(field.is_covered_deep(tile + Vector2i.RIGHT), "a sword reaches the tile beside")
	var far := tile + Vector2i(HeightField.BEHIND_REACH + 2, 0)
	if north.has(far):
		assert_false(field.is_covered_deep(far), "farther along the edge only the band")
	# On the plateau he is in front of the copy, which shows only the band again.
	player.global_position = tiles.to_global((Vector2(tile) + Vector2(0.5, 0.75)) * unit) - Player.FEET_OFFSET
	await wait_physics_frames(4)
	assert_eq(HeightRules.level_of(player), HeightRules.PLATEAU)
	assert_false(field.is_covered_deep(tile), "nobody behind any more")
	assert_almost_eq(piece.region_rect.size.y, HeightField.BAND, 0.01)


# --- #2d4a4686 ---

func test_room_modes_leave_the_row_behind_a_plateau_free() -> void:
	var rooms := _height_rooms()
	assert_gt(rooms.size(), 10)
	var checked := 0
	for room in rooms:
		var tiles := room.get_node("Tiles") as RoomTiles
		var layout := tiles.get_height_layout()
		var free: Dictionary[Vector2i, bool] = {}
		for tile: Vector2i in layout.ground:
			free[tile] = true
		HeightRules.keep_feet_free(tiles, free)
		for tile in layout.get_behind_tiles():
			assert_false(layout.get_height_tiles().has(tile), "%s: %s is ground" % [room.name, tile])
			assert_false(free.has(tile), "%s: %s behind a north edge stays free" % [room.name, tile])
			checked += 1
		room.free()
	assert_gt(checked, 20, "rooms with ground behind a plateau")


func test_the_flame_bonus_chest_stands_in_front_of_its_plateau() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()
	var room := _template(FLAME_ROOM)
	await wait_process_frames(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(RoomVariants.attach(room, VariantTable.pick_for(&"flame"), rng), &"flame")
	var mode := CombatVariant.of(room) as FlameMode
	assert_not_null(mode)
	if mode == null:
		return
	var layout := room.tiles.get_height_layout()
	var flame_tile := RoomTiles.local_to_tile(mode.flame.position)
	assert_true(_north_edges(layout).has(flame_tile), "the flame stands in the north row of its plateau")
	# Where FlameMode puts it on success (just below the flame).
	var chests := mode.spawn_bonus_chests(mode.flame.position + Vector2(0, Player.FEET_OFFSET.y + RoomTiles.TILE_WORLD))
	assert_false(chests.is_empty())
	for chest in chests:
		var tile := RoomTiles.local_to_tile(chest.position)
		assert_false(layout.get_behind_tiles().has(tile), "chest at %s not on the rim line behind the plateau" % tile)
		assert_true(layout.ground.has(tile), "chest at %s on the ground" % tile)
		assert_false(layout.get_connector_feet().has(tile), "chest at %s not on the foot of the stairs" % tile)
	RunManager.end_run(RunManager.EndReason.ABORT)


# --- #581b8b3d ---

func test_rock_copies_over_figures_have_no_floor_in_their_corners() -> void:
	var looks := 0
	for path in TILESETS:
		var tileset := load(path) as TileSet
		if not RockTerrain.ensure_sources(tileset):
			continue
		for look: RockTerrain.Look in [RockTerrain.Look.CAVE, RockTerrain.Look.MASONRY]:
			if not RockTerrain.has_look(tileset, look):
				continue
			looks += 1
			var rock := (tileset.get_source(RockTerrain.rock_source(look)) as TileSetAtlasSource).texture.get_image()
			var lip_texture := RockTerrain.lip_texture(tileset, look)
			assert_ne(lip_texture, (tileset.get_source(RockTerrain.rock_source(look)) as TileSetAtlasSource).texture, "%s: an own copy" % path)
			var lip := lip_texture.get_image()
			assert_eq(lip.get_size(), rock.get_size(), "same atlas")
			var cleared := 0
			var changed := 0
			for y in range(0, rock.get_height(), 1):
				for x in range(0, rock.get_width(), 1):
					var a := lip.get_pixel(x, y)
					if a.a < 0.5:
						if rock.get_pixel(x, y).a > 0.5:
							cleared += 1
					elif not a.is_equal_approx(rock.get_pixel(x, y)):
						changed += 1
			assert_gt(cleared, 1000, "%s look %d: the floor in the corners is taken out" % [path, look])
			assert_eq(changed, 0, "%s look %d: the rock itself stays as it is" % [path, look])
	assert_gt(looks, 3, "both looks in the biomes")


func test_beside_a_block_corner_the_rock_copy_is_see_through() -> void:
	var room := _template(GRUFT)
	await wait_process_frames(3)
	var tiles := room.tiles
	if not tiles.is_terrain_drawn():
		pending("no terrain art")
		return
	var lips := tiles.get_lips()
	assert_not_null(lips)
	if lips == null:
		return
	var expected := RockTerrain.lip_texture(tiles.tile_set, tiles.get_look())
	var corners := 0
	for sprite: Sprite2D in lips.get_children():
		assert_eq(sprite.texture, expected, "%s: the floorless rock" % sprite.name)
		var image := sprite.texture.get_image()
		var origin := Vector2i(sprite.region_rect.position)
		# A corner piece of a block (rounded top corner): its outermost corner pixel shows nothing.
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(PlateauArt.TILE - 1, 0)]:
			var rock_pixel := (tiles.tile_set.get_source(RockTerrain.rock_source(tiles.get_look())) as TileSetAtlasSource).texture.get_image().get_pixelv(origin + corner)
			if rock_pixel.a > 0.5 and image.get_pixelv(origin + corner).a < 0.5:
				corners += 1
	assert_gt(corners, 0, "the block's rounded corners are open in the copy")


# --- #28fef95b ---

func test_things_on_a_plateau_sort_after_its_copy() -> void:
	var standing := 0
	for room in _height_rooms():
		var tiles := room.get_node("Tiles") as RoomTiles
		var layout := tiles.get_height_layout()
		var name := room.scene_file_path.get_file()
		var sources := room.get_node_or_null("Sources")
		if sources != null:
			for marker: Node2D in sources.get_children():
				var tile: Vector2i = marker.get_meta(&"tile")
				var kind := SpawnSourceRules.kind_from_id(marker.get_meta(&"source_kind"))
				if not layout.surface.has(tile) or SpawnSource.FLAT_KINDS.has(kind) or SpawnSourceRules.is_wall_kind(kind):
					continue
				var source := SpawnSource.create_floor(kind, marker.position)
				var sort_y := marker.position.y - source.sort_lift()
				source.free()
				standing += 1
				assert_gt(sort_y, HeightField.lip_sort_y(tiles, layout, tile), "%s: %s at %s in front of the plateau's copy" % [name, marker.name, tile])
		for prop in room.get_node("Props").get_children():
			var node := prop as Node2D
			if node == null or (node is CanvasItem and (node as CanvasItem).z_index != 0):
				continue
			var tile := RoomTiles.local_to_tile(node.position - Vector2(0.0, 1.0))
			if layout.surface.has(tile):
				assert_gt(node.position.y, HeightField.lip_sort_y(tiles, layout, tile), "%s: %s at %s in front of the plateau's copy" % [name, node.name, tile])
		room.free()
	assert_gt(standing, 10, "graves on plateaus (crypt)")


# --- #cab236b0 ---

func test_every_plateau_has_its_way_up_and_its_chest_is_reached() -> void:
	for room in _height_rooms():
		var tiles := room.get_node("Tiles") as RoomTiles
		var layout := tiles.get_height_layout()
		var name := room.scene_file_path.get_file()
		for group in layout.components():
			var ways := 0
			for tile: Vector2i in group:
				if layout.is_connector(tile):
					ways += 1
			assert_gt(ways, 0, "%s: plateau at %s has stairs or a ladder" % [name, group[0]])
		for prop in room.get_node("Props").get_children():
			if prop is TreasureChest:
				var tile := RoomTiles.local_to_tile((prop as Node2D).position - Vector2(0.0, 1.0))
				if layout.surface.has(tile):
					assert_true(HeightRules.is_reached_surface(tiles, tile), "%s: chest at %s reached from the entrance" % [name, tile])
		room.free()


func test_the_arena_pit_shows_its_stairs_in_every_biome() -> void:
	for biome in BIOMES:
		var room := _template(ASCHEGRUBE % biome)
		await wait_process_frames(2)
		var layout := room.tiles.get_height_layout()
		assert_false(layout.stairs.is_empty(), "%s: stairs up to the chest" % biome)
		var field := room.tiles.get_height_field()
		for tile: Vector2i in layout.stairs:
			var steps := field.get_node_or_null("Steps_%d_%d" % [tile.x, tile.y]) as Sprite2D
			assert_not_null(steps, "%s: steps drawn at %s" % [biome, tile])
			if steps != null:
				assert_not_null(steps.texture, "%s: steps art" % biome)
				assert_true(steps.is_visible_in_tree())
