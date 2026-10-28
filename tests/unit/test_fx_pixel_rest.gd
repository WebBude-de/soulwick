extends GutTest
## FS2b, D-218 "Nur Pixel-Effekte" for the rest of the game: spells, the wind trail, weapon rings,
## the projectile trail and the UI pieces (vignette, shade, dashed box) draw whole art pixels in hard
## steps; effect sprites fitted to a radius get a whole scale while the hit radius stays exact.

const PIXEL := PixelDraw.WORLD_PIXEL

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_fx_pixel_rest_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _on_grid(value: float, pixel: float) -> bool:
	return is_equal_approx(fposmod(value, pixel), 0.0) or is_equal_approx(fposmod(value, pixel), pixel)


func _assert_rects_on_grid(rects: Array[Rect2], what: String, pixel := PIXEL) -> void:
	assert_gt(rects.size(), 0, "%s draws something" % what)
	for area in rects:
		if not (_on_grid(area.position.x, pixel) and _on_grid(area.position.y, pixel) and _on_grid(area.size.x, pixel) and _on_grid(area.size.y, pixel)):
			fail_test("%s: %s is off the art-pixel grid" % [what, area])
			return
	pass_test("%s: %d rects on the grid" % [what, rects.size()])


## Distinct alpha values of the painted pixels.
func _alphas(image: Image) -> Dictionary:
	var found := {}
	for y in image.get_height():
		for x in image.get_width():
			found[snappedf(image.get_pixel(x, y).a, 0.01)] = true
	return found


# --- Whole sprite scales ---

func test_effect_sprite_scale_rounds_to_a_whole_number() -> void:
	assert_eq(PixelDraw.whole_scale(0.3), 1.0, "at least 1")
	assert_eq(PixelDraw.whole_scale(1.4), 1.0)
	assert_eq(PixelDraw.whole_scale(70.0 / Blast.EXPLOSION_ART_RADIUS), 2.0, "a 70 px blast shows the art at 2x")
	assert_eq(PixelDraw.whole_scale(2.6), 3.0)


func test_blast_art_has_a_whole_scale_and_the_hit_keeps_its_radius() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var blast := Blast.spawn(holder, Vector2(100, 100), 70.0, 1.0)
	blast.target_mask = 0
	await wait_physics_frames(2)
	var found := false
	for child in holder.get_children():
		if child is AnimatedSprite2D:
			found = true
			var sprite := child as AnimatedSprite2D
			assert_eq(sprite.scale.x, roundf(sprite.scale.x), "whole scale: %s" % sprite.scale)
			assert_eq(sprite.scale.x, 2.0)
	assert_true(found, "the explosion art was spawned")


# --- Spells ---

func test_spell_ring_is_a_pixel_ring_that_fades_in_steps() -> void:
	var ring := autofree(SpellRing.new()) as SpellRing
	ring.color = Color(0.4, 0.8, 1.0)
	ring.start_radius = 12.0
	ring.end_radius = 64.0
	var seen := {}
	for age in [0.0, 0.1, 0.2, 0.3, 0.35, 0.39]:
		ring._age = age
		seen[snappedf(ring.get_fade(), 0.001)] = true
		var raster := PixelDraw.Raster.new(Vector2i(160, 160), Vector2(80, 80))
		ring.paint(raster)
		_assert_rects_on_grid(raster.rects, "spell ring at %.2f s" % age)
	assert_lte(seen.size(), SpellRing.FADE_STEPS, "only a few alpha steps: %s" % [seen.keys()])


func test_spark_and_wisp_are_pixel_discs() -> void:
	var spark := autofree(SpellSpark.new()) as SpellSpark
	spark.color = Color(1.0, 0.8, 0.3)
	var raster := PixelDraw.Raster.new(Vector2i(24, 24), Vector2(12, 12))
	spark.paint(raster)
	_assert_rects_on_grid(raster.rects, "spark")
	var wisp := autofree(WillOWisp.new()) as WillOWisp
	wisp.velocity = Vector2(120, 40)
	raster = PixelDraw.Raster.new(Vector2i(48, 48), Vector2(24, 24))
	wisp.paint(raster)
	_assert_rects_on_grid(raster.rects, "wisp")


# --- Talent trail ---

func test_wind_trail_placeholder_is_pixels_on_the_world_grid() -> void:
	var trail := autofree(WindRunnerTrail.create(Vector2(3.3, 5.1), Vector2(151.0, 63.7), null)) as WindRunnerTrail
	var raster := PixelDraw.Raster.new(Vector2i(200, 120), Vector2(20, 20))
	trail.paint(raster, 1.0)
	_assert_rects_on_grid(raster.rects, "wind trail")
	assert_lte(_alphas(raster.image).size(), 4, "empty, band, core and their overlap only")


# --- Weapon rings and the projectile trail ---

func test_ring_wave_now_spawns_the_pixel_ring() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var ring: Variant = RingWave.spawn(holder, Vector2(10, 10), 40.0, Color.WHITE)
	assert_true(ring is PixelRingWave, "RingWave forwards to PixelRingWave")


func test_pixel_trail_is_thin_and_faint_at_its_old_end() -> void:
	var trail := autofree(PixelTrail.new()) as PixelTrail
	trail.width = 8.0
	trail.max_points = 6
	for i in 9:
		trail.add_point(Vector2(10.0 + i * 17.3, 40.0 + i * 3.1))
	assert_eq(trail.get_point_count(), 6, "older points drop off")
	var raster := PixelDraw.Raster.new(Vector2i(200, 80))
	trail.paint(raster)
	_assert_rects_on_grid(raster.rects, "projectile trail")
	assert_lte(_alphas(raster.image).size(), PixelTrail.FADE_STEPS + 1, "hard alpha steps")
	var points := trail.get_points()
	var old_end := Vector2i(points[0])
	var new_end := Vector2i(points[points.size() - 1])
	assert_lt(raster.image.get_pixel(old_end.x, old_end.y).a, raster.image.get_pixel(new_end.x, new_end.y).a, "the newest end is the brightest")
	trail.fade = 0.0
	var gone := PixelDraw.Raster.new(Vector2i(200, 80))
	trail.paint(gone)
	assert_eq(gone.rects.size(), 0, "faded out: nothing drawn")


func test_projectile_trail_is_a_pixel_trail() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var damage := DamageData.new()
	damage.amount = 1.0
	var projectile := Projectile.create(damage, Vector2.RIGHT, 300.0, 200.0, 0)
	projectile.trail_length = 6
	projectile.launch(holder, Vector2(50, 50))
	var trail: PixelTrail = null
	for child in projectile.get_children():
		if child is PixelTrail:
			trail = child
	assert_not_null(trail, "the projectile leaves a PixelTrail, not a smooth Line2D")
	if trail != null:
		assert_eq(trail.max_points, 6)


# --- UI ---

func test_vignette_is_hard_bands_on_the_ui_grid() -> void:
	var pixel := float(UiKit.ART_SCALE)
	var raster := PixelDraw.Raster.new(Vector2i(240, 135))
	var ramp := BossIntroView.vignette_ramp(Color(0.8, 0.2, 0.2))
	PixelDraw.radial_bands(raster, Rect2(0, 0, 240, 135), ramp, BossIntroView.VIGNETTE_STEPS, pixel)
	_assert_rects_on_grid(raster.rects, "vignette", pixel)
	assert_lte(_alphas(raster.image).size(), BossIntroView.VIGNETTE_STEPS + 1, "hard steps only")
	var image := raster.image
	assert_eq(image.get_pixel(120, 67).a, 0.0, "clear in the middle")
	assert_gt(image.get_pixel(1, 1).a, image.get_pixel(120, 2).a, "darkest in the corners")
	assert_gt(image.get_pixel(120, 2).a, 0.0, "a little dark at the edges")


func test_shade_ramp_is_a_few_hard_texels() -> void:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0.9))
	ramp.set_color(1, Color(0, 0, 0, 0.0))
	var texture := PixelDraw.stepped_ramp_texture(ramp, 6)
	assert_eq(texture.get_size(), Vector2(6, 1))
	var image := texture.get_image()
	assert_gt(image.get_pixel(0, 0).a, image.get_pixel(5, 0).a, "dark side first")


func test_dashed_box_frame_is_whole_ui_pixels() -> void:
	var pixel := float(UiKit.ART_SCALE)
	var raster := PixelDraw.Raster.new(Vector2i(90, 45))
	DashedBox.paint_frame(raster, Vector2i(30, 15), pixel)
	_assert_rects_on_grid(raster.rects, "dashed box", pixel)
	assert_gt(raster.image.get_pixel(0, 0).a, 0.0, "a dash starts in the corner")
	assert_eq(raster.image.get_pixel(45, 22).a, 0.0, "the inside stays empty")


# --- Delivered ember golem art (lava impact, lava pool, stomp ring): whole scales ---

func _spawned_art(holder: Node, look: StringName, radius: float) -> AnimatedSprite2D:
	var blast := Blast.spawn(holder, Vector2(200, 200), radius, 1.0)
	blast.target_mask = 0
	blast.look = look
	await wait_physics_frames(2)
	for child in holder.get_children():
		if child is AnimatedSprite2D:
			return child
	return null


func test_lava_impact_and_stomp_ring_art_get_whole_scales() -> void:
	for look: StringName in [Blast.LOOK_LAVA, Blast.LOOK_STOMP]:
		var holder := Node2D.new()
		add_child_autofree(holder)
		var radius := 44.0 if look == Blast.LOOK_LAVA else 150.0
		var sprite: AnimatedSprite2D = await _spawned_art(holder, look, radius)
		assert_not_null(sprite, "%s: the delivered strip is shown" % look)
		if sprite == null:
			continue
		assert_eq(sprite.sprite_frames.get_frame_count(&"default"), 6, "%s: six frames sliced right" % look)
		assert_eq(sprite.scale.x, roundf(sprite.scale.x), "%s: whole scale %s" % [look, sprite.scale])
		var art_radius := Blast.LAVA_IMPACT_ART_RADIUS if look == Blast.LOOK_LAVA else Blast.STOMP_RING_ART_RADIUS
		assert_lte(absf(art_radius * sprite.scale.x - radius), art_radius * 0.5 + 0.01, "%s: drawn near the hit radius" % look)


func test_lava_pool_art_gets_a_whole_scale_and_keeps_its_hit_radius() -> void:
	assert_true(ResourceLoader.exists(LavaPool.ART_PATH), "lava pool art is delivered")
	var holder := Node2D.new()
	add_child_autofree(holder)
	var pool := LavaPool.spawn(holder, Vector2(100, 100), 44.0 * Blast.POOL_RADIUS_SHARE, 2.0, 0.5, PhysicsLayers.PLAYER_HURTBOX, null)
	var sprite: AnimatedSprite2D = null
	for child in pool.get_children():
		if child is AnimatedSprite2D:
			sprite = child
	assert_not_null(sprite, "the delivered pool is shown")
	if sprite != null:
		assert_eq(sprite.sprite_frames.get_frame_count(&"default"), 4)
		assert_eq(sprite.scale.x, 3.0, "a 37 px pool shows the 12.5 texel art at 3x")
	var shape: CollisionShape2D = null
	for child in pool.get_children():
		if child is Hitbox:
			shape = child.get_child(0) as CollisionShape2D
	assert_not_null(shape, "the pool hurts")
	if shape == null:
		return
	assert_almost_eq((shape.shape as CircleShape2D).radius, 44.0 * Blast.POOL_RADIUS_SHARE, 0.001, "the hit area is exact")


func test_lava_ball_art_is_drawn_at_a_whole_scale() -> void:
	assert_true(ResourceLoader.exists(LobShell.ART_PATH), "lava ball art is delivered")
	assert_eq(LobShell.ART_SCALE, roundf(LobShell.ART_SCALE))
	var texture := load(LobShell.ART_PATH) as Texture2D
	assert_eq(texture.get_width() % LobShell.ART_FRAME.x, 0, "whole frames")
