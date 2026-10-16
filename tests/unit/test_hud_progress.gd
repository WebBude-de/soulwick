extends GutTest
## P1-6 (launch review 16.10.2026): the HUD shows the progress to the boss instead of "Zyklus":
## one pip per room of the biome with symbols for special rooms, minibosses and the boss, and
## "Boss in N Räumen" (in the boss room "Boss!"). Uses a test save, never the real one.

const BiomeProgressScript := preload("res://ui/hud/biome_progress.gd")
const TEST_SAVE_PATH := "user://test_hud_progress.cfg"

var _old_save_path: String
var _old_locale: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	_old_locale = TranslationServer.get_locale()
	SaveManager.save_path = TEST_SAVE_PATH
	SaveManager.load_game()


func after_each() -> void:
	TranslationServer.set_locale("de")


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func _hud(room: int) -> Hud:
	var hud: Hud = add_child_autofree(Hud.new())
	hud.set_dungeon_mode(true)
	hud._on_room_changed(room)
	return hud


func test_rooms_until_the_boss() -> void:
	assert_eq(BiomeProgressScript.rooms_until_boss(1), 14)
	assert_eq(BiomeProgressScript.rooms_until_boss(7), 8)
	assert_eq(BiomeProgressScript.rooms_until_boss(14), 1)
	assert_eq(BiomeProgressScript.rooms_until_boss(15), 0, "the boss room itself")
	assert_eq(BiomeProgressScript.rooms_until_boss(16), 14, "next biome")
	assert_eq(BiomeProgressScript.first_room_of_biome(15), 1)
	assert_eq(BiomeProgressScript.first_room_of_biome(16), 16)


func test_pips_follow_the_room_sequence() -> void:
	var hud := _hud(7)
	var pips := hud._biome_progress
	var kinds := pips.get_kinds()
	assert_eq(kinds.size(), RoomSequence.BOSS_INTERVAL, "one pip per room of the biome")
	for i in kinds.size():
		assert_eq(kinds[i], BiomeProgressScript.kind_for(RoomSequence.get_room_type(i + 1)), "pip %d" % (i + 1))
	assert_eq(kinds[3], BiomeProgressScript.Kind.SPECIAL)
	assert_eq(kinds[4], BiomeProgressScript.Kind.MINIBOSS)
	assert_eq(kinds[14], BiomeProgressScript.Kind.BOSS)
	assert_eq(pips.get_current_index(), 6, "room 7 is the seventh pip")
	assert_gt(pips.get_combined_minimum_size().x, 0.0)
	hud._on_room_changed(22)
	assert_eq(pips.get_current_index(), 6, "room 22 is the seventh room of biome 2")


func test_detail_line_counts_down_to_the_boss_instead_of_cycles() -> void:
	TranslationServer.set_locale("de")
	var hud := _hud(7)
	var text := hud._room_detail.text
	assert_string_contains(text, "Boss in 8")
	assert_string_contains(text, Hud.room_type_name(RoomSequence.RoomType.COMBAT))
	assert_false(text.contains("Zyklus"), text)
	hud._on_room_changed(14)
	assert_string_contains(hud._room_detail.text, "nächsten Raum")
	hud._on_room_changed(15)
	assert_eq(hud._room_detail.text, "Boss!")
	TranslationServer.set_locale("en")
	hud._on_room_changed(7)
	assert_string_contains(hud._room_detail.text, "Boss in 8 rooms")
	assert_false(hud._room_detail.text.contains("Cycle"))


func test_mode_and_heal_lines_stay() -> void:
	var hud := _hud(7)
	hud.set_room_mode("Arena")
	assert_true(hud._room_detail.text.ends_with("Arena"), hud._room_detail.text)
	hud.set_heal_countdown(2)
	assert_eq(hud._room_detail.text.split("\n").size(), 2, "heal countdown on its own line")


func test_campfire_completes_the_biome() -> void:
	var hud := _hud(15)
	hud.set_campfire(true, "Schleimgrotte")
	assert_eq(hud._biome_progress.get_current_index(), -1, "all pips done")
	assert_false(hud._room_detail.text.contains("Boss"), hud._room_detail.text)
	hud.set_campfire(false)
	# set_campfire redraws with RunManager's room; the dungeon pushes the next room right after.
	hud._on_room_changed(16)
	assert_eq(hud._biome_progress.get_current_index(), 0, "next biome starts at its first pip")


func test_room_box_stays_in_the_top_right_corner_with_touch() -> void:
	# The touch buttons for overview and pause sit at the top centre (TouchOverlay).
	var hud := _hud(7)
	hud.set_touch_mode(true)
	await wait_process_frames(2)
	var view := hud._root.get_viewport_rect().size
	var rect: Rect2 = hud._room_box.get_global_rect()
	assert_gt(rect.position.x, view.x * 0.6, "right of the top centre buttons")
	assert_lt(rect.end.y, view.y * 0.25, "small at the top")
	hud.set_touch_mode(false)
