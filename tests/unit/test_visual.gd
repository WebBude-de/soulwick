extends GutTest
## Visual components: rock backdrop around rooms, drop shadows, post-process timing, camera sway,
## ambient particle presets.

const TILESET: TileSet = preload("res://dungeon/environment/dungeon_tileset.tres")


func _make_tiles() -> RoomTiles:
	var tiles := RoomTiles.new()
	tiles.tile_set = TILESET
	tiles.room_size = Vector2i(15, 9)
	tiles.entrance_x = 7
	tiles.exit_x = 7
	add_child_autofree(tiles)
	return tiles


func test_backdrop_surrounds_room_with_rock() -> void:
	var tiles := _make_tiles()
	var backdrop := tiles.get_backdrop()
	assert_not_null(backdrop)
	var outer := tiles.get_backdrop_rect()
	assert_eq(outer.size, Vector2i(15 + 4 + RoomTiles.BACKDROP_MARGIN.x * 2, 9 + 5 + RoomTiles.BACKDROP_MARGIN.y * 2))
	# Corners of the ring are rock; with the terrain (M1) the room's own enclosed rock lies on the
	# backdrop too, under the room's floor and pieces.
	var fill := tiles.get_rock_fill_cell()
	assert_eq(backdrop.get_cell_source_id(outer.position), fill.z)
	assert_eq(backdrop.get_cell_atlas_coords(outer.position), Vector2i(fill.x, fill.y))
	assert_eq(backdrop.get_cell_atlas_coords(outer.end - Vector2i.ONE), Vector2i(fill.x, fill.y))
	assert_eq(backdrop.get_cell_source_id(Vector2i(3, 3)), fill.z if tiles.is_terrain_drawn() else -1)


func test_backdrop_draws_below_room_and_has_no_collision() -> void:
	var tiles := _make_tiles()
	var backdrop := tiles.get_backdrop()
	assert_lt(backdrop.z_index, 0)
	assert_false(backdrop.collision_enabled)
	assert_true(backdrop.use_parent_material)
	assert_not_null(tiles.material)


func test_corridors_stay_floor() -> void:
	var tiles := _make_tiles()
	assert_true(RoomTiles.FLOOR_TILES.has(tiles.get_cell_atlas_coords(Vector2i(7, -3))))
	assert_true(RoomTiles.FLOOR_TILES.has(tiles.get_cell_atlas_coords(Vector2i(7, 10))))


func test_repaint_does_not_duplicate_backdrop() -> void:
	var tiles := _make_tiles()
	var first := tiles.get_backdrop()
	var children := tiles.get_child_count(true)
	tiles.paint()
	assert_same(tiles.get_backdrop(), first)
	assert_eq(tiles.get_child_count(true), children, "backdrop and the terrain layers are reused")


func test_drop_shadow_texture_is_cached_and_sized() -> void:
	var a := DropShadow.make_texture(Vector2i(7, 3))
	var b := DropShadow.make_texture(Vector2i(7, 3))
	assert_same(a, b)
	assert_eq(a.get_size(), Vector2(14, 6))


func test_drop_shadow_attach_scales_with_radius() -> void:
	var body: Node2D = add_child_autofree(Node2D.new())
	var small := DropShadow.attach(body, 8.0, 10.0)
	assert_eq(small.get_parent(), body)
	assert_eq(small.position, Vector2(0, 10))
	assert_lt(small.z_index, 0)
	var small_width := small.texture.get_width()
	small.configure(20.0, 12.0)
	assert_gt(small.texture.get_width(), small_width)
	assert_eq(small.position, Vector2(0, 12))


func test_envelope_fades_in_and_out() -> void:
	assert_eq(PostProcess.envelope(0.0, 0.8), 0.0)
	assert_almost_eq(PostProcess.envelope(0.8, 0.8), 0.0, 0.001)
	assert_almost_eq(PostProcess.envelope(0.5, 0.8), 1.0, 0.001)
	assert_almost_eq(PostProcess.envelope(PostProcess.FADE_OUT * 0.5, 0.8), 0.5, 0.001)


func test_post_process_is_idle_without_effects() -> void:
	var post: PostProcess = add_child_autofree(PostProcess.new())
	post._process(0.016)
	assert_false(post.is_active())
	post.hit_pulse()
	post._process(0.016)
	assert_true(post.is_active())
	post._process(2.0)
	post._process(0.016)
	assert_false(post.is_active())


func test_post_process_stun_and_blind_timers() -> void:
	var post: PostProcess = add_child_autofree(PostProcess.new())
	post.stun(0.8)
	post.blind(4.0)
	post._process(0.3)
	assert_gt(post.get_stun_amount(), 0.9)
	assert_gt(post.get_blind_amount(), 0.9)
	post._process(0.6)
	assert_eq(post.get_stun_amount(), 0.0)
	assert_gt(post.get_blind_amount(), 0.0)
	post.reset()
	assert_eq(post.get_blind_amount(), 0.0)


func test_camera_sway_tilts_then_recovers() -> void:
	var camera: CameraRig = add_child_autofree(CameraRig.new())
	camera.stun_sway(0.8)
	camera._process(0.3)
	assert_gt(absf(camera.rotation), 0.05)
	camera._process(0.6)
	camera._process(0.016)
	assert_eq(camera.rotation, 0.0)
	assert_eq(camera.offset, Vector2.ZERO)


func test_ambient_presets_per_biome() -> void:
	assert_eq(AmbientParticles.preset_for_biome(&"crypt"), AmbientParticles.Preset.DUST)
	assert_eq(AmbientParticles.preset_for_biome(&"ember_forge"), AmbientParticles.Preset.EMBERS)
	assert_eq(AmbientParticles.preset_for_biome(&"unknown"), AmbientParticles.Preset.NONE)
	var particles: AmbientParticles = add_child_autofree(AmbientParticles.new())
	assert_false(particles.emitting)
	particles.set_biome(&"slime_grotto")
	assert_true(particles.emitting)
	particles.set_biome(&"")
	assert_false(particles.emitting)
