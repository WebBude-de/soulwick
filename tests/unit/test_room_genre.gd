extends GutTest
## Room genres (D-110, UX2): rooms with gameplay of their own get a banner, normal combat rooms
## none; the explanation card comes once per save ("room_intro_<genre>"), never pauses, and only
## one teaching card is on screen at a time. Banners queue instead of overwriting each other.
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
	assert_eq(RoomGenre.resolve(_info({"room_kind": RoomSequence.RoomKind.ARENA, "arena": true, "ambush": true})), RoomGenre.NONE,
		"an ambush looks empty on entry")
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
	assert_null(ui.get_room_intro_card())


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
	assert_eq(RoomGenre.get_title(RoomGenre.AMBUSH), "Hinterhalt!")
	assert_not_null(RoomGenre.get_icon(RoomGenre.ARENA), "arena: wave_banner_icon")
	assert_not_null(RoomGenre.get_icon(RoomGenre.SHOP), "special rooms: door symbol")


# --- Banner and first-time card ---

func test_genre_banner_and_card_once_per_save() -> void:
	var ui := _ui()
	assert_true(RoomGenre.should_explain(RoomGenre.ARENA))
	ui.show_genre(RoomGenre.ARENA)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq(banner.name, &"GenreBanner")
	assert_eq((banner.find_child("Title", true, false) as Label).text, "Arena")
	var card := ui.get_room_intro_card()
	assert_not_null(card, "first arena of this save: explanation")
	assert_eq(card.genre, RoomGenre.ARENA)
	assert_true(SaveManager.has_seen(&"room_intro_arena"))
	assert_false(GameManager.is_game_paused(), "never pauses")
	card.finish()
	await wait_physics_frames(1)
	ui.show_genre(RoomGenre.ARENA)
	assert_null(ui.get_room_intro_card(), "second arena: banner only")
	var other := _ui()
	other.show_genre(RoomGenre.ARENA)
	assert_null(other.get_room_intro_card(), "seen is stored in the save, not in the UI")
	other.show_genre(RoomGenre.SHOP)
	assert_not_null(other.get_room_intro_card(), "every genre has its own card")


func test_ambush_is_named_when_it_springs() -> void:
	var ui := _ui()
	var room: RoomController = autofree(RoomController.new())
	ui.on_arena_started(room, true)
	var title := ui.get_banner().find_child("Title", true, false) as Label
	assert_eq(title.text, "Hinterhalt!")
	assert_eq(ui.get_room_intro_card().genre, RoomGenre.AMBUSH)
	ui.on_arena_started(room, true)
	assert_eq(ui.get_banner_queue_size(), 0, "a room is named once")


func test_intro_card_never_shares_the_screen_with_other_cards() -> void:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	await wait_physics_frames(1)
	var controls := ui.get_controls_hint()
	assert_not_null(controls, "fresh save: controls card")
	ui.show_hint("Slime", "Der rote Kreis zeigt, wo er gleich zuschlägt.")
	assert_false(controls.visible, "the controls card steps aside for the enemy card")
	assert_eq(controls.process_mode, Node.PROCESS_MODE_DISABLED, "and keeps its place in the steps")
	ui.show_genre(RoomGenre.SHOP)
	assert_null(ui.get_room_intro_card(), "the room card waits for the enemy card")
	ui._hint_card.queue_free()
	ui._show_next_hint()
	assert_not_null(ui.get_room_intro_card(), "then the room card")
	assert_false(controls.visible)
	ui.get_room_intro_card().finish()
	await wait_physics_frames(1)
	assert_true(controls.visible, "the controls card comes back")
	assert_eq(controls.process_mode, Node.PROCESS_MODE_PAUSABLE)


func test_intro_duration_grows_with_the_text() -> void:
	assert_eq(RoomIntroCard.duration_for("kurz"), RoomIntroCard.MIN_TIME)
	assert_eq(RoomIntroCard.duration_for("x".repeat(1000)), RoomIntroCard.MAX_TIME)
	var long_text := RoomGenre.get_intro(RoomGenre.TRIAL_GAUNTLET)
	assert_gt(RoomIntroCard.duration_for(long_text), RoomIntroCard.duration_for(RoomGenre.get_intro(RoomGenre.FOUNTAIN)))


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
