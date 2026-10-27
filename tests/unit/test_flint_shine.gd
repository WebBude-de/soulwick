extends GutTest
## Flint's breathing glow and rising sparks (D-217, FlintShine): the timing of the website
## (wick.css), the nodes at the companion's flame (FlintAura behind, FlintSparks over his sprite),
## the portrait's shine inside the ring, and no sparks on "Lichteffekte: Niedrig".

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_save_path: String
var _old_high := true


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_flint_shine_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_high = LightingQuality.is_high()


func after_each() -> void:
	LightingQuality.set_high(_old_high)


func test_the_glow_breathes_like_the_website() -> void:
	assert_almost_eq(FlintShine.breath(0.0), 0.0, 0.001)
	assert_almost_eq(FlintShine.breath(FlintShine.BREATH_TIME), 1.0, 0.001, "full after 2.4 s")
	assert_almost_eq(FlintShine.breath(FlintShine.BREATH_TIME * 2.0), 0.0, 0.001, "and back (alternate)")
	assert_almost_eq(FlintShine.glow_alpha(0.0), 0.75, 0.001)
	assert_almost_eq(FlintShine.glow_scale(FlintShine.BREATH_TIME), 1.04, 0.001)
	var texture := FlintShine.glow_texture()
	assert_eq(texture.fill, GradientTexture2D.FILL_RADIAL)
	assert_same(FlintShine.glow_texture(), texture, "built once")


func test_sparks_rise_fade_and_take_turns() -> void:
	var sparks := FlintShine.sparks(0.3)
	assert_eq(sparks.size(), FlintShine.SPARK_COUNT)
	var visible := 0
	for spark in sparks:
		assert_lte(spark.y, 0.0, "above the flame")
		assert_between(spark.z, 0.0, 1.0)
		if spark.z > 0.05:
			visible += 1
	assert_gte(visible, 3, "several sparks are in the air at once (staggered)")
	var young := FlintShine.sparks(0.1)[0]
	var older := FlintShine.sparks(1.0)[0]
	assert_lt(older.y, young.y, "a spark climbs")
	assert_lt(FlintShine.sparks(FlintShine.SPARK_LIFE - 0.05)[0].z, 0.1, "and fades out at the top")
	assert_lt(FlintShine.sparks(0.01)[0].z, 0.2, "it fades in at the flame")


func test_no_sparks_on_low_light_effects() -> void:
	LightingQuality.set_high(false)
	assert_false(FlintShine.sparks_on())
	assert_eq(FlintShine.spark_cells(Vector2.ZERO, 1.0, 14.0, 0.5).size(), 0, "Niedrig: no sparks")
	LightingQuality.set_high(true)
	assert_true(FlintShine.sparks_on())
	assert_gt(FlintShine.spark_cells(Vector2.ZERO, 1.0, 14.0, 0.5).size(), 0, "Hoch: sparks")


func test_companion_carries_glow_behind_and_sparks_over_his_flame() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = Vector2(400, 300)
	var flint := FlintCompanion.attach_to(player)
	await wait_physics_frames(2)
	var sprite := flint.get_sprite()
	var aura := flint.get_aura()
	var sparks := flint.get_sparks()
	assert_eq(aura.get_parent(), sprite, "the glow moves, scales and fades with his picture")
	assert_true(aura.show_behind_parent, "behind the figure, light is not painted on it (D-174)")
	assert_eq((aura.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_eq(sparks.get_parent(), sprite)
	assert_false(sparks.show_behind_parent, "sparks fly in front")
	var art := flint.get_art()
	var flame := art.get_anchor(FlintArt.ANCHOR_FLAME, sprite.animation, sprite.frame) - art.pivot
	if sprite.flip_h:
		flame.x = -flame.x
	assert_almost_eq(aura.position, flame, Vector2(0.01, 0.01), "the glow sits on the flame")
	assert_almost_eq(sparks.position, flame, Vector2(0.01, 0.01), "the sparks start at the flame")
	assert_lt(flame.y, -8.0, "the flame is above his head")


func test_his_light_breathes_with_the_glow() -> void:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	var flint := FlintCompanion.attach_to(player)
	await wait_physics_frames(1)
	var aura := flint.get_aura()
	aura.time = 0.0
	flint._update_glow()
	var low := flint.get_glow().radius
	aura.time = FlintShine.BREATH_TIME
	flint._update_glow()
	var high := flint.get_glow().radius
	assert_gt(high, low, "the warm light grows and shrinks with the glow")
	assert_almost_eq(high, FlintCompanion.GLOW_RADIUS * FlintShine.GLOW_SCALE_MAX, 0.01)


func test_portrait_shine_stays_inside_the_ring() -> void:
	LightingQuality.set_high(true)
	var portrait := FlintPortrait.new()
	add_child_autofree(portrait)
	var flame := portrait.get_flame_point()
	assert_true(Rect2(Vector2.ZERO, Vector2(FlintPortraitArt.FRAME_SIZE)).has_point(flame), "on the portrait")
	var center := Vector2(24, 24)
	var seen := 0
	for step in 40:
		for cell in FlintShine.spark_cells(flame, 1.0, FlintPortrait.SPARK_RISE, step * 0.1, center, FlintPortrait.SPARK_CLIP_RADIUS):
			seen += 1
			# The cell and its halo (one pixel around) stay inside the ring's opening (radius 24).
			assert_lt((Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)).distance_to(center), 24.0 - 1.0, "inside the ring")
	assert_gt(seen, 0, "sparks rise in the portrait")
