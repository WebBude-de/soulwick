extends GutTest
## Room genres (D-110, UX2): rooms with gameplay of their own get a banner, normal combat rooms
## none; Flint explains a room type the first time per account (D-211/WK11, RoomFlint; no card),
## never pauses. Banners queue instead of overwriting each other.
## Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_room_genre.cfg"

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = TEST_SAVE_PATH


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.load_game()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _info(overrides: Dictionary) -> Dictionary:
	var info := {
		"campfire": false, "room_type": RoomSequence.RoomType.COMBAT, "special_type": -1,
		"room_kind": RoomSequence.RoomKind.NORMAL, "combat": true, "arena": false, "ambush": false,
		"catacomb": false, "trial_kind": -1, "pact": false, "variant": RoomGenre.NONE, "wager": false,
	}
	info.merge(overrides, true)
	return info


func _special(special_type: int, extra := {}) -> Dictionary:
	var overrides := {"room_type": RoomSequence.RoomType.SPECIAL, "special_type": special_type, "combat": false, "room_kind": -1}
	overrides.merge(extra, true)
	return _info(overrides)


func _ui() -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	return ui


# --- Which room is which genre ---

func test_normal_combat_rooms_have_no_genre() -> void:
	assert_eq(RoomGenre.resolve(_info({})), RoomGenre.NONE, "normal room, every shape")
	assert_eq(RoomGenre.resolve(_info({"room_type": RoomSequence.RoomType.COMBAT_UPGRADE})), RoomGenre.NONE)
	assert_eq(RoomGenre.resolve(_info({"room_kind": RoomSequence.RoomKind.ARENA})), RoomGenre.NONE,
		"an arena template before room 6 plays as a normal room")
	for room_type in [RoomSequence.RoomType.BOSS, RoomSequence.RoomType.MINIBOSS]:
		assert_eq(RoomGenre.resolve(_info({"room_type": room_type, "combat": false})), RoomGenre.NONE, "bosses have their own intro")
	assert_eq(RoomGenre.resolve({}), RoomGenre.NONE)


func test_combat_genres() -> void:
	assert_eq(RoomGenre.resolve(_info({"room_kind": RoomSequence.RoomKind.ARENA, "arena": true})), RoomGenre.ARENA)
	assert_false(RoomGenre.TABLE.has(&"ambush"), "no ambush genre any more (D-120, R8)")
	assert_eq(RoomGenre.resolve(_info({"room_kind": RoomSequence.RoomKind.CHASM})), RoomGenre.CHASM)
	assert_eq(RoomGenre.resolve(_info({"catacomb": true})), RoomGenre.CATACOMB)
	assert_eq(RoomGenre.resolve(_info({"variant": &"flame"})), &"flame", "room modes via get_variant_id (R4)")
	assert_eq(RoomGenre.resolve(_info({"variant": &"rifts"})), &"rifts")
	assert_eq(RoomGenre.resolve(_info({"variant": &"soul_flame"})), RoomGenre.NONE, "the old variants are gone")
	assert_eq(RoomGenre.resolve(_info({"variant": &"unknown_variant"})), RoomGenre.NONE)
	assert_eq(RoomGenre.resolve(_info({"wager": true})), RoomGenre.WAGER_ALTAR)


func test_special_genres() -> void:
	assert_eq(RoomGenre.resolve(_special(RoomSequence.SpecialType.SHOP)), RoomGenre.SHOP)
	assert_eq(RoomGenre.resolve(_special(RoomSequence.SpecialType.WEAPON)), RoomGenre.WEAPON)
	assert_eq(RoomGenre.resolve(_special(RoomSequence.SpecialType.FOUNTAIN)), RoomGenre.FOUNTAIN)
	assert_eq(RoomGenre.resolve(_special(RoomSequence.SpecialType.UPGRADE)), RoomGenre.UPGRADE_ALTAR)
	assert_eq(RoomGenre.resolve(_special(RoomSequence.SpecialType.UPGRADE, {"pact": true})), RoomGenre.PACT_ALTAR)
	assert_eq(RoomGenre.resolve(_special(SpecialTable.TRIAL, {"trial_kind": SpecialTable.TrialKind.LIGHT_RUN})), RoomGenre.TRIAL_LIGHT_RUN)
	assert_eq(RoomGenre.resolve(_special(SpecialTable.TRIAL, {"trial_kind": SpecialTable.TrialKind.GAUNTLET})), RoomGenre.TRIAL_GAUNTLET)
	assert_eq(RoomGenre.resolve(_special(SpecialTable.TRIAL)), RoomGenre.TRIAL_GAUNTLET, "trial before its course is known")
	assert_eq(RoomGenre.resolve(_info({"campfire": true, "room_type": RoomSequence.RoomType.CAMPFIRE, "combat": false})), RoomGenre.CAMPFIRE)


func test_a_bare_room_controller_is_unnamed() -> void:
	var room: RoomController = autofree(RoomController.new())
	assert_eq(RoomGenre.of_room(room), RoomGenre.NONE)
	assert_eq(RoomGenre.of_room(null), RoomGenre.NONE)
	var ui := _ui()
	assert_eq(ui.show_room_genre(room), RoomGenre.NONE)
	assert_null(ui.get_banner(), "normal room: no banner")


func test_special_rooms_are_named_once_their_content_is_built() -> void:
	var ui := _ui()
	var room: RoomController = autofree(RoomController.new())
	room.room_type = RoomSequence.RoomType.SPECIAL
	room.special_type = RoomSequence.SpecialType.SHOP
	assert_eq(ui.show_room_genre(room), RoomGenre.SHOP)
	assert_null(ui.get_banner(), "the content (pact altar, kind of trial) is built in activate() first")
	await wait_physics_frames(1)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq((banner.find_child("Title", true, false) as Label).text, "Händler")
	ui.show_room_genre(room)
	await wait_physics_frames(1)
	assert_eq(ui.get_banner_queue_size(), 0, "named once")


func test_every_genre_has_texts_and_a_colour() -> void:
	for genre: StringName in RoomGenre.TABLE:
		for text in [RoomGenre.get_title(genre), RoomGenre.get_subtitle(genre), RoomGenre.get_intro(genre), RoomGenre.get_eyebrow(genre, 7)]:
			assert_false(text.is_empty(), "%s has every text" % genre)
			assert_false(text.begins_with("ROOM_"), "%s: '%s' is not a raw key" % [genre, text])
		assert_lt(RoomGenre.get_intro(genre).count(". ") + 1, 6, "%s: a short explanation" % genre)
	assert_eq(RoomGenre.get_title(RoomGenre.ARENA), "Arena")
	assert_not_null(RoomGenre.get_icon(RoomGenre.ARENA), "arena: mode symbol")
	assert_not_null(RoomGenre.get_icon(RoomGenre.SHOP), "special rooms: door symbol")


# --- Banner and Flint's explanation ---

## A local player whose Flint keeps its seen flags in seen (no real account).
func _learner(seen: Dictionary) -> FlintGuide:
	var player := add_child_autofree(preload("res://player/player.tscn").instantiate()) as Player
	var guide := FlintGuide.for_player(player)
	guide.shows_view = false
	guide.has_seen = func(id: StringName) -> bool: return seen.has(id)
	guide.mark_seen = func(id: StringName) -> void: seen[id] = true
	return guide


func test_genre_banner_without_a_card() -> void:
	var ui := _ui()
	ui.show_genre(RoomGenre.ARENA)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq(banner.name, &"GenreBanner")
	assert_eq((banner.find_child("Title", true, false) as Label).text, "Arena")
	assert_null(ui._hint_card, "no explanation card any more (D-211)")
	assert_false(GameManager.is_game_paused(), "never pauses")


func test_an_arena_started_unannounced_is_named_once() -> void:
	var ui := _ui()
	var room: RoomController = autofree(RoomController.new())
	ui.on_arena_started(room, true)
	var title := ui.get_banner().find_child("Title", true, false) as Label
	assert_eq(title.text, "Arena", "the old ambush flag changes nothing (D-120)")
	ui.on_arena_started(room, false)
	assert_eq(ui.get_banner_queue_size(), 0, "a room is named once")


func test_flint_explains_a_new_room_type_once_per_account() -> void:
	var seen: Dictionary = {}
	var guide := _learner(seen)
	RoomFlint.set_known(guide.player, [])
	RoomFlint.explain_in_scripts = true
	var ui := _ui()
	ui.show_genre(RoomGenre.SHOP)
	assert_true(guide.is_known(RoomFlint.seen_id(RoomGenre.SHOP)), "Flint explains the shop")
	assert_null(ui._hint_card, "no card beside him")
	assert_true(SaveManager.has_seen(RoomGenre.get_seen_id(RoomGenre.SHOP)), "the save keeps its flag (ChasmRules)")
	guide.skip()
	await wait_seconds(FlintGuideRules.FLY_BACK_TIME + 0.2)
	assert_true(seen.has(RoomFlint.seen_id(RoomGenre.SHOP)), "seen for the account")
	RoomFlint.set_known(guide.player, ["shop"])
	assert_false(ui._explain_genre(RoomGenre.SHOP), "known: not again")
	RoomFlint.explain_in_scripts = false


func test_an_old_save_that_saw_the_card_still_hears_flint_once() -> void:
	RoomGenre.mark_explained(RoomGenre.FOUNTAIN)
	assert_false(RoomGenre.should_explain(RoomGenre.FOUNTAIN), "the old card was seen")
	var seen: Dictionary = {}
	var guide := _learner(seen)
	RoomFlint.set_known(guide.player, [])
	RoomFlint.explain_in_scripts = true
	_ui().show_genre(RoomGenre.FOUNTAIN)
	assert_true(guide.is_known(RoomFlint.seen_id(RoomGenre.FOUNTAIN)), "Flint's own flag counts (flint_room_*)")
	RoomFlint.explain_in_scripts = false


# --- Banner queue ---

func test_banners_queue_instead_of_overwriting() -> void:
	var ui := _ui()
	ui.show_banner("Boss besiegt!", "Der Weg ist frei")
	ui.show_banner("Neu im Dorf", "Goldgier")
	assert_eq(ui.get_banner_queue_size(), 1, "the second banner waits")
	var first := ui.get_banner()
	assert_eq((first.find_child("Title", true, false) as Label).text, "Boss besiegt!")
	await wait_seconds(DungeonUI.BANNER_MIN_TIME + 0.2)
	assert_eq(ui.get_banner_queue_size(), 0)
	assert_eq((ui.get_banner().find_child("Title", true, false) as Label).text, "Neu im Dorf")


func test_genre_banner_replaces_the_plain_banner_of_the_same_room() -> void:
	var ui := _ui()
	ui.show_banner("Lagerfeuer", "Rast vor: Schleimgrotte")
	ui.show_genre(RoomGenre.CAMPFIRE)
	assert_eq(ui.get_banner().name, &"GenreBanner", "no 'Lagerfeuer' twice in a row")
	assert_eq(ui.get_banner_queue_size(), 0)
