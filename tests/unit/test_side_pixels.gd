extends GutTest
## Pixel art and jump feel of the side view (FS1, D-218): SidePixels draws lines, rings, discs and
## polygons only as rects on the art-pixel grid (2 px), fades in steps; platform pictures are lifted
## onto their collision top (the player stood 6-8 px above the moving platform), the guide line of a
## moving platform travels with it; the dust effects are pixel clumps that free themselves; squash
## and stretch run on a spring and are shown in whole art-pixel steps.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const STEP := 1.0 / 60.0

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_pixels_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func after_each() -> void:
	HitStop.reset()
	await wait_process_frames(1)


func _segment(plan_id: StringName, rng_seed := 7) -> SideSegment:
	var segment := SideSegment.new()
	segment.setup(SidePlans.build(plan_id), 1, null, rng_seed)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	return segment


func _assert_on_grid(rects: Array[Rect2], what: String) -> void:
	assert_gt(rects.size(), 0, "%s draws something" % what)
	for area in rects:
		if not SidePixels.is_on_grid(area):
			fail_test("%s: %s is off the art-pixel grid" % [what, area])
			return
	pass_test("%s: %d rects on the grid" % [what, rects.size()])


# --- SidePixels ---

func test_shapes_are_rects_on_the_art_pixel_grid() -> void:
	_assert_on_grid(SidePixels.line_rects(Vector2(3.3, 7.9), Vector2(41.0, 19.2)), "a slanted line")
	_assert_on_grid(SidePixels.line_rects(Vector2(10, 10), Vector2(13, 60), 2), "a steep thick line")
	_assert_on_grid(SidePixels.ring_rects(Vector2(5.5, -3.1), 13.0), "a ring")
	_assert_on_grid(SidePixels.ring_rects(Vector2.ZERO, 30.0, 1, 0.35), "a flat ring")
	_assert_on_grid(SidePixels.ring_rects(Vector2(1, 1), 9.0, 0), "a disc")
	_assert_on_grid(SidePixels.polygon_rects(PackedVector2Array([Vector2(0.4, 0), Vector2(21, 3.3), Vector2(7, 30.7)])), "a triangle")
	assert_eq(SidePixels.line_rects(Vector2(0, 0), Vector2(40, 0)).size(), 1, "a straight run is one rect")
	var steep := SidePixels.line_rects(Vector2(0, 0), Vector2(10, 40))
	var first: Rect2 = steep[0]
	var last: Rect2 = steep[steep.size() - 1]
	assert_true(first.has_point(Vector2(1, 1)), "the line starts at a")
	assert_true(last.has_point(Vector2(11, 41)), "and ends at b")
	assert_eq(SidePixels.snap(Vector2(5.9, -0.5)), Vector2(4, -2))


func test_fades_go_in_hard_steps() -> void:
	var seen := {}
	for i in 21:
		seen[snappedf(SidePixels.fade(0.9, i / 20.0), 0.001)] = true
	assert_lte(seen.size(), SidePixels.FADE_STEPS + 1, "only a few alpha steps (%s)" % [seen.keys()])
	assert_eq(SidePixels.fade(0.9, 0.0), 0.9)
	assert_eq(SidePixels.fade(0.9, 1.0), 0.0)


func test_surface_row_finds_the_slab_under_rivets() -> void:
	var image := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	image.set_pixel(3, 0, Color.WHITE)
	image.set_pixel(3, 1, Color.WHITE)
	image.set_pixel(4, 1, Color.WHITE)
	for y in range(2, 5):
		for x in 8:
			image.set_pixel(x, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	assert_eq(SidePixels.surface_row(texture, Rect2i(0, 0, 8, 6)), 2, "rivets above the slab do not count")
	assert_eq(SidePixels.surface_row(null, Rect2i(0, 0, 8, 6), 3), 3, "fallback without a picture")


# --- Platforms: the feet stand on the drawn slab ---

func test_moving_platform_art_starts_at_the_collision_top() -> void:
	var segment := _segment(&"crypt_gauntlet")
	var mover := segment.get_movers()[0]
	var texture := load(SideMover.ART_PATH % &"crypt") as Texture2D
	var row := SidePixels.surface_row(texture, Rect2i(SideMover.PIECE, 0, SideMover.PIECE, texture.get_height()))
	assert_eq(row, 3, "the delivered crypt platform has rivets in rows 0-2")
	assert_eq(mover.get_art_lift(), row * float(SpriteStrip.PIXEL_SCALE), "the picture is lifted by them")
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	player.side_motion.place_at(mover.top_center_at(mover.clock) + Vector2(0, -4))
	for i in 20:
		await wait_physics_frames(1)
		player._physics_process(STEP)
		if player.side_motion.is_on_floor():
			break
	assert_true(player.side_motion.is_on_floor(), "stands on the platform")
	var slab_top := mover.global_position.y - mover.get_art_lift() + row * SpriteStrip.PIXEL_SCALE
	assert_almost_eq(player.get_feet_position().y, slab_top, 2.0, "the feet are on the drawn slab, not above it")
	segment.remove_players()


func test_tilting_platform_and_bridge_art_sit_on_their_top() -> void:
	var tilt := SideTilt.new()
	tilt.cells = 2
	add_child_autofree(tilt)
	var tilt_art := tilt.get_node("Pieces/Art") as Sprite2D
	var tilt_row := SidePixels.surface_row(tilt_art.texture, Rect2i(Vector2i.ZERO, SideTilt.ART_FRAME))
	var tilt_top := tilt_art.position.y - SideTilt.ART_FRAME.y * 0.5 * SpriteStrip.PIXEL_SCALE + tilt_row * SpriteStrip.PIXEL_SCALE
	assert_eq(tilt_top, 0.0, "tilting platform: slab at the collision top")
	var bridge := SideBridge.new()
	add_child_autofree(bridge)
	var bridge_art := bridge.get_node("Pieces/Art") as Sprite2D
	var frame := Vector2i(bridge_art.texture.get_width() / SideBridge.ART_FRAMES, bridge_art.texture.get_height())
	var bridge_row := SidePixels.surface_row(bridge_art.texture, Rect2i(Vector2i.ZERO, frame))
	assert_eq(bridge_art.position.y + bridge_row * SpriteStrip.PIXEL_SCALE, 0.0, "bridge: planks at the collision top")


func test_guide_line_travels_with_the_platform() -> void:
	var segment := _segment(&"crypt_gauntlet")
	var mover := segment.get_movers()[0]
	await wait_process_frames(1)
	var track := segment.get_node_or_null(NodePath("Track"))
	if track == null:
		for child in segment.get_children():
			if child.name.begins_with("Track"):
				track = child
	assert_not_null(track, "the guide line is in the segment")
	var seen := {}
	for time in [0.0, 0.7, 1.4, 2.1, 2.8, 3.5]:
		mover.apply_clock(time)
		seen[track.get(&"travel_px")] = true
	assert_gt(seen.size(), 1, "the dashes move with the platform")


# --- Dust ---

func test_every_dust_kind_is_pixel_clumps_and_frees_itself() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	for kind: int in SideDust.Kind.values():
		var dust := SideDust.spawn(holder, Vector2(10.7, 11.3), kind, 0.8, -1.0, Color(1, 0.8, 0.3))
		assert_not_null(dust, "dust %d" % kind)
		if dust is SideDust:
			assert_eq(dust.global_position, SidePixels.snap(Vector2(10.7, 11.3)), "on the grid")
			assert_eq(dust.color, Color(1, 0.8, 0.3), "tinted")
			if kind != SideDust.Kind.RING:
				assert_gt((dust as SideDust).get_clumps().size(), 0)
	await wait_seconds(0.55)
	var left := 0
	for child in holder.get_children():
		if child is SideDust:
			left += 1
	assert_eq(left, 0, "drawn dust is gone after its lifetime")


func test_puff_kicks_more_dust_against_the_run() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var puff := SideDust.spawn(holder, Vector2.ZERO, SideDust.Kind.PUFF, 0.4, 1.0) as SideDust
	var back := 0.0
	var front := 0.0
	for clump in puff.get_clumps():
		if clump.velocity.x < 0.0:
			back += -clump.velocity.x
		else:
			front += clump.velocity.x
	assert_gt(back, front, "running right: the puff flies left")


# --- Jump feel (look only) ---

func test_shown_stretch_moves_in_art_pixel_steps_and_the_air_shapes_the_body() -> void:
	var shown := SidePlayerFx.shown_stretch(Vector2(0.777, 1.234))
	assert_almost_eq(fposmod(shown.y * SidePlayerFx.SCALE_STEPS, 1.0), 0.0, 0.0001)
	assert_almost_eq(fposmod(shown.x * SidePlayerFx.SCALE_STEPS, 1.0), 0.0, 0.0001)
	assert_eq(SidePlayerFx.air_shape(true, -500.0), Vector2.ONE, "round on the ground")
	assert_gt(SidePlayerFx.air_shape(false, -SideRules.JUMP_VELOCITY).y, 1.05, "long while rising")
	assert_lt(SidePlayerFx.air_shape(false, 0.0).y, 1.0, "a little round at the apex")
	assert_gt(SidePlayerFx.air_shape(false, SideRules.MAX_FALL_SPEED).y, 1.0, "long again while falling")


func test_squash_springs_back_through_a_stretch() -> void:
	var segment := _segment(&"crypt_gauntlet")
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	var fx := segment.get_fx(player)
	fx.set_process(false)
	player.side_motion.place_at(segment.to_global(SideLayout.feet_of(segment.layout.start)))
	for i in 30:
		await wait_physics_frames(1)
		player._physics_process(STEP)
		if player.side_motion.is_on_floor():
			break
	assert_true(player.side_motion.is_on_floor())
	player.side_motion.landed.emit(player, SideRules.MAX_FALL_SPEED)
	assert_gt(fx.get_stretch().x, 1.2, "squashed at a hard landing")
	var tallest := 0.0
	for i in 60:
		fx._process(STEP)
		tallest = maxf(tallest, fx.get_stretch().y)
	assert_gt(tallest, 1.0, "the spring overshoots into a short stretch")
	assert_almost_eq(fx.get_stretch().y, 1.0, 0.02, "and settles round")
	segment.remove_players()
