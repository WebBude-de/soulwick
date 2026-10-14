extends GutTest
## R6 lighting: the drawn look (LightingProfile, LightPalette, VisionOverlay) lifts the darkness and
## colours the lights, but never changes the gameplay light decision (LightQuery).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const CRYPT: BiomeData = preload("res://dungeon/biomes/crypt.tres")

var _old_save_path: String
var _old_phase: GameManager.Phase


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_lighting_save.cfg"


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.save_path))
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_old_phase = GameManager.get_phase()
	LightingProfile.set_brightness(0.0)


func after_each() -> void:
	GameManager.set_phase(_old_phase)
	LightingProfile.set_brightness(0.0)


# --- Profile (pure) ---

func test_dungeon_darkness_is_capped_to_the_biome_ambient() -> void:
	var ambient := LightingProfile.biome_ambient(&"crypt")
	assert_between(ambient, 0.45, 0.6, "about half of the environment stays visible")
	assert_almost_eq(LightingProfile.visual_darkness(0.97, ambient), ambient, 0.0001)


func test_bright_rooms_keep_their_own_darkness() -> void:
	# Special rooms (0.2) and the village clock stay as the room code sets them.
	assert_almost_eq(LightingProfile.visual_darkness(0.2, LightingProfile.DEEP_AMBIENT), 0.2, 0.0001)
	assert_almost_eq(LightingProfile.visual_darkness(0.6, LightingProfile.neutral().ambient), 0.6, 0.0001)


func test_light_run_goes_deep_when_the_special_room_turns_dark() -> void:
	var profile := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.SPECIAL)
	assert_almost_eq(LightingProfile.visual_darkness(0.2, profile.ambient), 0.2, 0.0001, "before the run")
	assert_almost_eq(LightingProfile.visual_darkness(0.97, profile.ambient), LightingProfile.DEEP_AMBIENT, 0.0001, "during the run")
	assert_eq(profile.player_radius_scale, 1.0, "drawn circle = gameplay circle")


func test_dark_variants_stay_almost_dark_with_true_circles() -> void:
	for variant in [&"stone_guardian", &"torch_room", &"lantern"]:
		var profile := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT, 0, variant)
		assert_almost_eq(profile.ambient, LightingProfile.DEEP_AMBIENT, 0.0001, String(variant))
		assert_eq(profile.player_radius_scale, 1.0, String(variant))
		assert_eq(profile.source_radius_scale, 1.0, String(variant))
		assert_almost_eq(profile.get_softness(), LightingProfile.SOFTNESS_PX, 0.0001, "same soft edge as LightQuery assumes")


func test_room_kinds() -> void:
	var normal := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT)
	var boss := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.BOSS)
	var campfire := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.CAMPFIRE)
	var dark := LightingProfile.for_situation(&"crypt", RoomSequence.RoomType.COMBAT, 0, &"", true)
	assert_lt(boss.ambient, normal.ambient, "the boss stays visible")
	assert_lt(campfire.ambient, normal.ambient, "the campfire is calm and lit")
	assert_gt(dark.ambient, normal.ambient, "a dark room is darker")
	assert_gt(normal.player_radius_scale, 1.0, "the drawn circle is wider than the gameplay one")
	# About 5 tiles (64 px) to the half-light point of the drawn circle.
	var drawn := DungeonManager.VISION_RADIUS * normal.player_radius_scale
	var half_light := drawn - normal.get_softness() * 0.5
	assert_between(half_light, 4.5 * 64.0, 5.5 * 64.0)


func test_brightness_option_shifts_the_ambient_within_limits() -> void:
	var ambient := LightingProfile.biome_ambient(&"crypt")
	LightingProfile.set_brightness(1.0)
	assert_lt(LightingProfile.visual_darkness(0.97, ambient), ambient)
	LightingProfile.set_brightness(-1.0)
	assert_gt(LightingProfile.visual_darkness(0.97, ambient), ambient)
	assert_lte(LightingProfile.visual_darkness(0.97, ambient), LightingProfile.MAX_AMBIENT)
	assert_eq(LightingProfile.apply_brightness(1.0, -1.0), 1.0, "neutral stays neutral")


# --- Palette ---

func test_explicit_colour_wins() -> void:
	var light := LightSource.new()
	light.color = LightPalette.COLD
	assert_eq(light.get_draw_color(), LightPalette.COLD)
	light.free()


func test_colour_from_node_name_and_owner_class() -> void:
	var threat := LightSource.new()
	threat.name = "ThreatLight"
	assert_eq(LightPalette.resolve(threat), LightPalette.DANGER)
	threat.free()
	var torch := RoomTorch.new()
	var light := LightSource.new()
	torch.add_child(light)
	assert_eq(LightPalette.resolve(light), LightPalette.WARM, "torches are warm")
	torch.free()
	var flame := SoulFlame.new()
	var cold := LightSource.new()
	flame.add_child(cold)
	assert_eq(LightPalette.resolve(cold), LightPalette.COLD, "the soul flame is a goal")
	flame.free()


func test_crystal_island_is_cold_torch_island_warm() -> void:
	var crystal := LightIsland.create(IngredientSet.LightStyle.CRYSTAL, Color.WHITE)
	assert_eq(crystal.light.get_draw_color(), LightPalette.COLD)
	crystal.free()
	var stand := LightIsland.create(IngredientSet.LightStyle.TORCH_STAND, Color.WHITE)
	assert_eq(stand.light.get_draw_color(), LightPalette.WARM)
	stand.free()


func test_base_class_lookup() -> void:
	var script := GDScript.new()
	script.source_code = "extends RoomTorch\n"
	script.reload()
	var node := Node2D.new()
	node.set_script(script)
	assert_eq(LightPalette.color_for_class_of(node), LightPalette.WARM)
	node.free()


func test_unknown_owner_is_neutral() -> void:
	var holder := Node2D.new()
	var light := LightSource.new()
	holder.add_child(light)
	assert_eq(LightPalette.resolve(light), LightPalette.NEUTRAL)
	holder.free()


# --- Overlay: optics never change the gameplay radius ---

func _overlay() -> VisionOverlay:
	var overlay := VisionOverlay.new()
	add_child_autofree(overlay)
	return overlay


func test_overlay_draws_wider_but_reports_the_logical_radius() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := _overlay()
	overlay.set_biome(CRYPT, true)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	assert_eq(overlay.get_current_radius(), DungeonManager.VISION_RADIUS, "gameplay radius unchanged")
	assert_almost_eq(overlay.get_visual_radius(), DungeonManager.VISION_RADIUS * LightingProfile.PLAYER_RADIUS_SCALE, 0.01)
	assert_almost_eq(overlay.get_visual_darkness(), LightingProfile.biome_ambient(&"crypt"), 0.0001)
	overlay.set_lighting(LightingProfile.deep(), true)
	assert_almost_eq(overlay.get_visual_radius(), DungeonManager.VISION_RADIUS, 0.01, "deep rooms draw the true circle")
	assert_almost_eq(overlay.get_visual_darkness(), LightingProfile.DEEP_AMBIENT, 0.0001)


func test_overlay_is_neutral_outside_the_dungeon() -> void:
	GameManager.set_phase(GameManager.Phase.VILLAGE)
	var overlay := _overlay()
	overlay.set_biome(CRYPT, true)
	overlay.set_vision(VillageDaylight.NIGHT_DARKNESS, VillageDaylight.VISION_RADIUS, true)
	assert_almost_eq(overlay.get_visual_darkness(), VillageDaylight.NIGHT_DARKNESS, 0.0001, "village keeps its clock")
	assert_almost_eq(overlay.get_visual_radius(), VillageDaylight.VISION_RADIUS, 0.01)


func test_light_query_gets_the_logical_player_radius() -> void:
	GameManager.set_phase(GameManager.Phase.DUNGEON)
	var overlay := _overlay()
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	overlay.bind_player(player)
	overlay.set_biome(CRYPT, true)
	overlay.set_vision(DungeonManager.DUNGEON_DARKNESS, DungeonManager.VISION_RADIUS, true)
	await wait_process_frames(3)
	assert_almost_eq(LightQuery.get_player_radius(player), DungeonManager.VISION_RADIUS, 0.5,
			"LightQuery sees the logical circle, not the drawn one")
	assert_gt(overlay.get_visual_radius(), LightQuery.get_player_radius(player))
