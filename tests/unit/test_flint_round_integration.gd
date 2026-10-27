extends GutTest
## Flint round (D-211, D-212), integrated: the light circle sits at the player (picture and rules),
## Flint's flame only glows (never counts as light), stone guardians freeze next to the player in a
## dark Lichtfeuer hall, the cracked wall, chasm and side view hints come from Flint, a new room type
## has no card any more, and the side view camera keeps the way above the bottom quarter.
## Uses a test save; Flint's seen flags are this test's (never the account's).

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const GUARDIAN_SCENE: PackedScene = preload("res://enemies/variants/stone_guardian.tscn")
const GUARDIAN_DATA: EnemyData = preload("res://enemies/data/stone_guardian.tres")
const TEST_SAVE_PATH := "user://test_flint_round_integration.cfg"
const DT := 1.0 / 60.0
## Drawn radius of a dark Lichtfeuer hall in the shadow realm (lit 94 px, the smoke test's hang).
const DARK_DRAWN := 169.0

var _old_save_path: String
var _seen: Dictionary = {}


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()
	_seen.clear()
	RunManager.end_run(RunManager.EndReason.ABORT)
	RunManager.start_run()


func after_each() -> void:
	RoomFlint.explain_in_scripts = false
	HitStop.reset()
	await wait_process_frames(1)


func after_all() -> void:
	RunManager.end_run(RunManager.EndReason.ABORT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


## A local player with Flint whose guide keeps its seen flags in _seen.
func _player(at := Vector2(400, 300), drawn_radius := 300.0) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.global_position = at
	player.set_physics_process(false)
	LightQuery.set_player_radius(player, drawn_radius)
	var guide := FlintGuide.for_player(player)
	guide.shows_view = false
	guide.has_seen = func(id: StringName) -> bool: return _seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: _seen[id] = true
	return player


func _flint(player: Player) -> FlintCompanion:
	var flint := FlintCompanion.attach_to(player)
	flint.set_process(false)
	for i in 30:
		flint._process(DT)
	return flint


func _ui() -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	return ui


# --- D-212: the light circle ---

func test_the_light_circle_is_centred_on_the_player() -> void:
	var player := _player()
	var flint := _flint(player)
	assert_gt(flint.get_light_center().distance_to(player.global_position), 10.0, "Flint hovers beside him")
	var circles := LightQuery.player_circles(get_tree())
	assert_eq(circles.size(), 1)
	assert_eq(Vector2(circles[0].x, circles[0].y), player.global_position, "rules: at the figure")
	assert_eq(LightQuery.get_player_light_center(player), player.global_position, "picture: at the figure")


func test_flints_glow_never_counts_as_light() -> void:
	var player := _player(Vector2(400, 300), 80.0)
	var flint := _flint(player)
	var glow := flint.get_glow()
	assert_not_null(glow)
	assert_true(glow.is_lit(), "it glows")
	assert_false(glow.counts_as_light)
	var flame := flint.get_light_center()
	assert_gt(flame.distance_to(player.global_position), LightQuery.player_lit_radius(80.0), "the flame lies outside the tiny circle")
	assert_false(LightQuery.is_lit(get_tree(), flame), "the glow at the flame is no light for rules")


func test_stone_guardians_freeze_next_to_the_player_in_a_dark_lightfire_hall() -> void:
	var player := _player(Vector2(400, 300), DARK_DRAWN)
	_flint(player)
	var lit := LightQuery.player_lit_radius(DARK_DRAWN)
	for side: float in [-1.0, 1.0]:
		var guardian := GUARDIAN_SCENE.instantiate() as StoneGuardian
		guardian.data = GUARDIAN_DATA
		guardian.apply_scaling(8, false)
		add_child_autofree(guardian)
		guardian.global_position = player.global_position + Vector2(side * (lit - 10.0), 0)
		guardian.set_physics_process(false)
		guardian.player_light_counts = LightfireRules.PLAYER_LIGHT_HOLDS_GUARDIANS
		guardian.activate()
		assert_true(guardian.is_in_light(), "side %d: in the player's own circle" % side)
		guardian.step_light(LightfireRules.GUARDIAN_THAW_DELAY + 0.01, guardian.is_in_light())
		assert_true(guardian.is_frozen(), "side %d: frozen beside the player" % side)


# --- D-211: hints from Flint ---

func test_the_cracked_wall_hint_comes_from_flint() -> void:
	var player := _player()
	var ui := _ui()
	# DungeonUI picks up the players on its next frame.
	await wait_process_frames(1)
	var manager: DungeonManager = autofree(DungeonManager.new())
	manager.ui = ui
	manager._on_secret_tapped(null)
	assert_true(FlintGuide.of(player).is_known(FlintControls.SECRET_WALL), "Flint says it")
	assert_null(ui._hint_card, "no card")
	assert_true(SaveManager.has_seen(DungeonManager.SECRET_HINT_ID), "the save keeps its flag")


func test_the_chasm_hint_comes_from_flint() -> void:
	var player := _player()
	var ui := _ui()
	await wait_process_frames(1)
	assert_true(ui.show_flint_hint(FlintControls.CHASM))
	assert_true(FlintGuide.of(player).is_known(FlintControls.CHASM))
	assert_null(ui._hint_card, "no card")
	var source := FileAccess.get_file_as_string("res://dungeon/dungeon_manager.gd")
	assert_true(source.contains("ui.show_flint_hint(FlintControls.CHASM)"), "DungeonManager asks Flint")
	assert_false(source.contains("ui.show_hint(hint"), "no chasm card any more")


func test_the_side_view_keys_come_from_flint_not_the_banner() -> void:
	var player := _player(Vector2(100, 100))
	var world := Node2D.new()
	add_child_autofree(world)
	var group: Array[Player] = [player]
	var transit := SideTransit.start(world, group, SidePlans.build(&"crypt_steps"), 1, null, 5, func(_g: Array) -> void: pass)
	await wait_seconds(SideRules.FADE_TIME + SideRules.BANNER_TIME + 0.3)
	assert_true(FlintGuide.of(player).is_known(FlintControls.SIDE_VIEW), "Flint explains jump and dash")
	assert_false(player.is_input_locked(), "the banner is short and gone")
	if is_instance_valid(transit) and transit.segment != null:
		transit.segment.finish()
	await wait_seconds(SideRules.FADE_TIME * 2.0 + 0.4)


func test_a_new_room_type_has_no_card_any_more() -> void:
	var player := _player()
	RoomFlint.set_known(player, [])
	RoomFlint.explain_in_scripts = true
	var ui := _ui()
	ui.show_genre(RoomGenre.UPGRADE_ALTAR)
	assert_true(FlintGuide.of(player).is_known(RoomFlint.seen_id(RoomGenre.UPGRADE_ALTAR)), "Flint explains it")
	assert_null(ui._hint_card, "no card")
	assert_false(ResourceLoader.exists("res://ui/hints/room_intro_card.gd"), "the card is gone")
	assert_false(ui.has_method(&"get_room_intro_card"))


# --- Side view camera ---

func test_side_camera_keeps_the_way_above_the_bottom_quarter() -> void:
	var segment := SideSegment.new()
	segment.setup(SidePlans.build(&"crypt_steps"), 1, null, 7)
	add_child_autofree(segment)
	segment.global_position = SideSegment.WORLD_ORIGIN
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	segment.add_player(player)
	segment.make_camera_current()
	var camera := segment.camera
	camera.snap()
	var view := camera.get_viewport_rect().size / camera.zoom
	# The view leans up as far as it may (a climb ahead): the feet must still stay high enough.
	camera._look_y = -view.y * SideCamera.WAY_LOOK_MAX
	var targets: Array[Player] = [player]
	var desired := camera._desired(targets)
	var share := (player.get_feet_position().y - (desired.y - view.y * 0.5)) / view.y
	assert_lte(share, SideCamera.MAX_FEET_SCREEN_SHARE + 0.01, "feet at %.0f %% of the view" % (share * 100.0))
	assert_almost_eq(SideCamera.lowest_feet_y(100.0, 400.0), 100.0 + 400.0 * 0.25, 0.01)
	segment.remove_players()
