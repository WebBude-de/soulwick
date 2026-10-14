extends GutTest
## R7 evening light (06_dorf.md, D-107): a soft vignette at the screen edges instead of an even
## veil, warm glow halfway through the dusk, lit windows and night-only lights that follow the
## darkness the VisionOverlay carries. Pure optics; uses a test folder for the save.

const ROOT := "user://test_village_evening"
const VILLAGE_SCENE := "res://world/village/village.tscn"

var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()


func after_each() -> void:
	GameManager.clear_pause_reasons()


func after_all() -> void:
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _village() -> Village:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	return village


func test_vignette_follows_the_night() -> void:
	assert_eq(VillageEvening.edge_for_night(0.0), 0.0, "day: no vignette")
	assert_almost_eq(VillageEvening.edge_for_night(1.0), VillageEvening.EDGE_AMOUNT, 0.0001)
	assert_lt(VillageEvening.edge_for_night(0.5), VillageEvening.edge_for_night(1.0))
	assert_eq(VillageEvening.warmth_for_night(0.0), 0.0, "no warm glow by day")
	assert_almost_eq(VillageEvening.warmth_for_night(1.0), 0.0, 0.0001, "nor in full night")
	assert_almost_eq(VillageEvening.warmth_for_night(0.5), VillageEvening.DUSK_WARMTH, 0.0001, "strongest at dusk")


func test_night_from_the_overlay_darkness() -> void:
	assert_eq(VillageDaylight.night_from_darkness(0.0), 0.0)
	assert_almost_eq(VillageDaylight.night_from_darkness(VillageDaylight.NIGHT_DARKNESS), 1.0, 0.0001)
	assert_almost_eq(VillageDaylight.night_from_darkness(VillageDaylight.NIGHT_DARKNESS * 0.5), 0.5, 0.0001)
	assert_eq(VillageDaylight.night_from_darkness(5.0), 1.0, "clamped")


func test_windows_glow_and_light_at_night_only() -> void:
	var village := _village()
	var evening := village.get_evening()
	assert_not_null(evening)
	var glows := village.find_children("WindowGlow", "Sprite2D", true, false)
	assert_gte(glows.size(), 5, "houses and buildings with glass get lit windows")
	var lights := village.find_children("WindowLight", "", true, false)
	assert_eq(lights.size(), glows.size(), "one window light per building")
	evening.night_override = 0.0
	await wait_process_frames(2)
	assert_eq((glows[0] as CanvasItem).modulate.a, 0.0, "dark windows by day")
	assert_eq((lights[0] as LightSource).intensity, 0.0)
	evening.night_override = 1.0
	await wait_process_frames(2)
	assert_eq((glows[0] as CanvasItem).modulate.a, 1.0, "lit in the night")
	assert_almost_eq((lights[0] as LightSource).intensity, VillageEvening.WINDOW_LIGHT_INTENSITY, 0.0001)
	assert_almost_eq(evening.get_night(), 1.0, 0.0001)


func test_vignette_sits_below_the_overlay_and_the_ui() -> void:
	var village := _village()
	var layer := village.get_evening().get_node("EveningLayer") as CanvasLayer
	assert_not_null(layer)
	assert_lt(layer.layer, 2, "below the VisionOverlay (layer 2) and every UI layer")
	assert_gt(layer.layer, 0, "above the world")
	village.get_evening().night_override = 0.0
	await wait_process_frames(2)
	assert_false((layer.get_node("Vignette") as CanvasItem).visible, "nothing drawn by day")
	village.get_evening().night_override = 0.8
	await wait_process_frames(2)
	assert_true((layer.get_node("Vignette") as CanvasItem).visible)


func test_glass_detection() -> void:
	assert_true(VillagePlaceholders.is_glass(Color("#8fc4ec")), "light blue pane")
	assert_false(VillagePlaceholders.is_glass(Color("#4a6a9a")), "darker blue roof")
	assert_false(VillagePlaceholders.is_glass(Color("#d9b48a")), "plaster wall")
	var forge := load("res://art/environment/buildings/forge.png") as Texture2D
	var glow := VillagePlaceholders.window_glow(forge)
	assert_not_null(glow["texture"])
	assert_gt((glow["centres"] as Array).size(), 0)
