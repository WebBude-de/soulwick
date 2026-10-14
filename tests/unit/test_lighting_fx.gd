extends GutTest
## L1 "Licht next level": glow halos, flickering/breathing source brightness, coloured flashes,
## biome grading and the light effects quality are optics only. The gameplay decision "is this
## point in the light?" (LightQuery) and the logical vision values never change.

const BIOMES: Array[String] = [
	"res://dungeon/biomes/crypt.tres",
	"res://dungeon/biomes/slime_grotto.tres",
	"res://dungeon/biomes/shadow_realm.tres",
	"res://dungeon/biomes/ember_forge.tres",
]
const CRYPT: BiomeData = preload("res://dungeon/biomes/crypt.tres")

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_lighting_fx_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_phase = GameManager.get_phase()
	LightingQuality.set_high(true)


func after_each() -> void:
	GameManager.set_phase(_old_phase)
	LightingQuality.set_high(true)


func _light(parent: Node, pos: Vector2, radius := 160.0, counts := false) -> LightSource:
	var light := LightSource.new()
	light.radius = radius
	light.counts_as_light = counts
	parent.add_child(light)
	light.global_position = pos
	return light


# --- Gameplay stays the same ---

func test_light_query_ignores_flicker_breath_and_quality() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var torch := _light(root, Vector2(100, 100), 200.0, true)
	torch.flicker = 0.12
	torch.color = LightPalette.WARM
	var crystal := _light(root, Vector2(600, 100), 140.0, true)
	crystal.color = LightPalette.COLD
	var before := LightQuery.source_circles(get_tree())
	var lit_before := LightQuery.is_lit(get_tree(), Vector2(100 + 159, 100), false)
	LightingQuality.set_high(false)
	await wait_process_frames(3)
	assert_eq(LightQuery.source_circles(get_tree()), before, "quality low: same circles")
	LightingQuality.set_high(true)
	await wait_seconds(0.2)
	assert_eq(LightQuery.source_circles(get_tree()), before, "flicker and breath never move the circles")
	assert_eq(LightQuery.is_lit(get_tree(), Vector2(100 + 159, 100), false), lit_before)
	assert_eq(torch.get_lit_radius(), 200.0 * LightSource.DEFAULT_LIT_SHARE)


func test_flashes_never_count_as_light() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var circles := LightQuery.source_circles(get_tree()).size()
	var flash := LightSource.flash(root, Vector2(50, 50), 180.0, 0.3, LightPalette.EMBER, 0.6)
	assert_not_null(flash)
	assert_false(flash.counts_as_light)
	assert_false(flash.is_in_group(LightSource.GAMEPLAY_GROUP))
	assert_eq(flash.get_draw_color(), LightPalette.EMBER, "the flash has the colour of what exploded")
	assert_almost_eq(flash.intensity, 0.6 * GameOptions.get_flash_strength(), 0.001)
	assert_eq(LightQuery.source_circles(get_tree()).size(), circles)


func test_bursts_flash_in_their_colour_only_with_high_quality() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	Burst.spawn(root, Vector2.ZERO, LightPalette.TOXIC, 14)
	assert_eq(_flashes(root).size(), 1, "a hit burst tints the floor for a moment")
	assert_eq((_flashes(root)[0] as LightSource).get_draw_color(), LightPalette.TOXIC)
	Burst.spawn(root, Vector2.ZERO, LightPalette.TOXIC, 3)
	assert_eq(_flashes(root).size(), 1, "tiny bursts (lava drips) stay without light")
	LightingQuality.set_high(false)
	Burst.spawn(root, Vector2.ZERO, LightPalette.TOXIC, 20)
	assert_eq(_flashes(root).size(), 1, "low quality: no burst flashes")
	assert_between(Burst.flash_radius(160.0), Burst.FLASH_RADIUS_MIN, Burst.FLASH_RADIUS_MAX)


func _flashes(root: Node) -> Array:
	return root.get_children().filter(func(n: Node) -> bool: return n is LightSource)


# --- Drawn brightness and halo ---

func test_draw_intensity_stays_in_range() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var fire := _light(root, Vector2.ZERO)
	fire.color = LightPalette.WARM
	fire.flicker = 0.2
	fire.intensity = 0.95
	var soul := _light(root, Vector2.ZERO)
	soul.color = LightPalette.COLD
	var plain := _light(root, Vector2.ZERO)
	plain.color = LightPalette.DANGER
	plain.intensity = 0.4
	for i in 5:
		assert_between(fire.get_draw_intensity(), 0.0, 1.0)
		assert_between(soul.get_draw_intensity(), (1.0 - LightPalette.BREATH_AMPLITUDE) - 0.001, 1.0)
		await wait_process_frames(2)
	assert_eq(plain.get_draw_intensity(), 0.4, "steady lights draw their intensity")


func test_halo_per_family_and_name() -> void:
	assert_gt(LightPalette.halo_for_color(LightPalette.EMBER), LightPalette.halo_for_color(LightPalette.NEUTRAL), "lava glows more than a flash")
	assert_eq(LightPalette.halo_for_color(LightPalette.WARM), LightPalette.HALO_FIRE)
	var root: Node2D = add_child_autofree(Node2D.new())
	var way := _light(root, Vector2.ZERO)
	way.name = "WayLight"
	way.color = LightPalette.GOLD
	assert_eq(way.get_halo(), 0.0, "door light cones draw no blob")
	var custom := _light(root, Vector2.ZERO)
	custom.halo = 0.25
	assert_eq(custom.get_halo(), 0.25, "an explicit halo wins")


func test_biome_torches_light_in_their_flame_colour() -> void:
	var torch := AnimatedProp.new()
	torch.strip = load("res://art/environment/props/torch_green_4f.png")
	var light := LightSource.new()
	torch.add_child(light)
	add_child_autofree(torch)
	assert_eq(light.get_draw_color(), LightPalette.FIRE_GREEN, "green flame, green light")
	assert_true(LightPalette.is_fire(light.get_draw_color()), "and it flickers like fire")
	torch.strip = load("res://art/environment/props/torch_purple_4f.png")
	assert_eq(light.get_draw_color(), LightPalette.FIRE_VIOLET, "a swapped strip changes the light")
	torch.strip = load("res://art/environment/props/torch_4f.png")
	assert_eq(light.get_draw_color(), LightPalette.WARM)


# --- Grading ---

func test_every_biome_has_a_subtle_grade() -> void:
	for path in BIOMES:
		var biome := load(path) as BiomeData
		assert_true(BiomeGrade.TABLE.has(biome.id), "grade for %s" % biome.id)
		var grade := BiomeGrade.for_biome(biome.id)
		assert_between(grade.amount, 0.0, 1.0)
		assert_between(grade.vignette, 0.0, 0.4, "vignette stays soft for a 30-minute session")
		assert_between(grade.mist, 0.0, 0.15)
		for channel in [grade.shadow.r, grade.shadow.g, grade.shadow.b]:
			assert_between(channel, 0.0, 0.25, "shadows are lifted only a little")
	assert_eq(BiomeGrade.neutral().amount, 0.0)
	assert_eq(BiomeGrade.for_village(0.0).amount, 0.0, "village by day: no grade")
	assert_gt(BiomeGrade.for_village(1.0).highlight.r, BiomeGrade.for_village(1.0).highlight.b, "village night: warm lamps")


func test_overlay_grade_follows_biome_and_quality_without_touching_vision() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := VisionOverlay.new()
	add_child_autofree(overlay)
	overlay.set_biome(CRYPT, true)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	assert_almost_eq(overlay.get_grade().vignette, BiomeGrade.for_biome(&"crypt").vignette, 0.0001)
	var radius := overlay.get_current_radius()
	var visual := overlay.get_visual_darkness()
	LightingQuality.set_high(false)
	await wait_process_frames(2)
	assert_eq(overlay.get_grade().amount, 0.0, "low quality: no grading")
	assert_eq(overlay.get_current_radius(), radius, "logical radius unchanged")
	assert_almost_eq(overlay.get_visual_darkness(), visual, 0.0001, "darkness unchanged")


# --- Many lights ---

func test_more_lights_than_the_shader_takes_keep_the_gameplay_lights() -> void:
	var root: Node2D = add_child_autofree(Node2D.new())
	var screen := Vector2(1280, 720)
	var gameplay: Array[LightSource] = []
	for i in VisionOverlay.MAX_LIGHTS + 8:
		var counts := i % 8 == 0
		# Gameplay lights at the screen edge (low score by distance), effects in the middle.
		var pos := Vector2(20.0, 20.0 + i * 4.0) if counts else Vector2(640.0 + i, 360.0)
		var light := _light(root, pos, 120.0, counts)
		if counts:
			gameplay.append(light)
	var picked := VisionOverlay.pick_lights(get_tree().get_nodes_in_group(LightSource.GROUP), Transform2D.IDENTITY, 1.0, screen)
	assert_eq(picked.size(), VisionOverlay.MAX_LIGHTS)
	var picked_lights: Array = picked.map(func(entry: Array) -> LightSource: return entry[0])
	for light in gameplay:
		assert_true(picked_lights.has(light), "gameplay lights are always drawn")


func test_shader_takes_as_many_lights_as_the_overlay_sends() -> void:
	var code := (load("res://components/visual/vision.gdshader") as Shader).code
	assert_true(code.contains("const int MAX_LIGHTS = %d;" % VisionOverlay.MAX_LIGHTS))
