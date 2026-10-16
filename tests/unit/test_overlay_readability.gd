extends GutTest
## Overlays and the fight (online test 16.10.2026: "Gegner sieht man oft schlecht, weil
## Texteinblendungen davor sind"): banners shrink to a strip while enemies are on screen, overlays
## fade while a body is under them, the status line at the top (show_status_line), the 3-2-1 in the
## top band, teaching cards in the upper left, shorter damage numbers, and the fall / downed
## presentation (D-084). Uses a test save, never the real one.

const TEST_SAVE_PATH := "user://test_overlay_readability.cfg"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy_base.tscn")
const SKELETON: EnemyData = preload("res://enemies/data/skeleton.tres")
const OverlayDodge := preload("res://ui/hints/overlay_dodge.gd")

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


func _ui() -> DungeonUI:
	var ui: DungeonUI = add_child_autofree(DungeonUI.new())
	ui.auto_enemy_hints = false
	ui.show_controls_hint = false
	return ui


## Enemy standing at a screen point (no camera in these tests: world = screen).
func _enemy(pos: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.data = SKELETON
	enemy.position = pos
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	return enemy


func _player(local := true) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = local
	return add_child_autofree(player)


func _kill(player: Player, source: Node = null) -> void:
	var hit := DamageData.new()
	hit.amount = 999.0
	hit.source = source
	player.hurtbox.receive_hit(hit)


# --- Dodge rules ---

func test_dodge_rules() -> void:
	var rect := Rect2(100, 20, 200, 40)
	assert_true(OverlayDodge.is_covering(rect, [Rect2(150, 30, 20, 20)] as Array[Rect2]))
	assert_false(OverlayDodge.is_covering(rect, [Rect2(150, 200, 20, 20)] as Array[Rect2]))
	assert_false(OverlayDodge.is_covering(Rect2(), [Rect2(0, 0, 999, 999)] as Array[Rect2]), "nothing on screen covers nothing")
	var alpha := OverlayDodge.step(1.0, true, 10.0)
	assert_eq(alpha, OverlayDodge.DODGE_ALPHA, "fades down to the dodge alpha, not further")
	assert_eq(OverlayDodge.step(alpha, false, 10.0), 1.0, "and back")


func test_banner_fades_while_an_enemy_is_under_it() -> void:
	# The first frames of a run carry the loading time as delta (tweens would jump to their end).
	await wait_process_frames(3)
	var ui := _ui()
	ui.show_banner("Fackel entzündet", "Noch 2")
	await wait_process_frames(3)
	var banner := ui.get_banner()
	assert_not_null(banner)
	var centre := banner.get_global_rect().get_center()
	_enemy(Vector2(centre.x, banner.get_global_rect().end.y + 10.0))
	await wait_seconds(0.4)
	assert_almost_eq(ui._banner_root.modulate.a, OverlayDodge.DODGE_ALPHA, 0.05, "see-through over the enemy")


func test_dodge_can_be_switched_off() -> void:
	var ui := _ui()
	ui.dodge_overlays = false
	ui.show_banner("Fackel entzündet")
	await wait_process_frames(3)
	var rect := ui.get_banner().get_global_rect()
	_enemy(rect.get_center())
	await wait_seconds(0.3)
	assert_eq(ui._banner_root.modulate.a, 1.0)


# --- Strip or plaque ---

func test_banner_is_a_plaque_without_enemies_on_screen() -> void:
	var ui := _ui()
	ui.show_banner("Raum geschafft!", "Der Weg ist frei")
	var banner := ui.get_banner()
	assert_false(banner.has_meta(&"strip"))
	var title := banner.find_child("Title", true, false) as Label
	assert_eq(title.get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_TITLE_LARGE))


func test_banner_is_a_slim_strip_while_enemies_are_on_screen() -> void:
	var ui := _ui()
	_enemy(Vector2(300, 400))
	await wait_process_frames(2)
	assert_true(ui.is_fight_on_screen())
	ui.show_banner("Fackel entzündet", "Noch 2 Fackeln")
	var banner := ui.get_banner()
	assert_true(banner.has_meta(&"strip"), "no big plaque over a running fight")
	assert_eq(banner.name, &"Banner")
	var title := banner.find_child("Title", true, false) as Label
	assert_eq(title.text, "Fackel entzündet")
	assert_eq(title.get_theme_font_size("font_size"), UiKit.font_px(UiKit.SIZE_CARD_NAME))
	assert_not_null(banner.find_child("Stripe", true, false), "same stripe as the plaque")
	assert_lt(banner.get_combined_minimum_size().y, UiKit.px(20), "one slim line")


func test_an_entry_may_force_the_plaque() -> void:
	var ui := _ui()
	_enemy(Vector2(300, 400))
	await wait_process_frames(2)
	ui._queue_banner({"kind": &"fall", "title": "Du bist gefallen", "compact": false})
	assert_false(ui.get_banner().has_meta(&"strip"))


func test_banners_are_shorter() -> void:
	assert_lte(DungeonUI.BANNER_TIME, 1.8)
	assert_lte(DungeonUI.GENRE_BANNER_TIME, 2.4)
	assert_lt(DungeonUI.STRIP_TIME, DungeonUI.BANNER_TIME)


# --- Status line ---

func test_status_line_shows_renews_and_clears() -> void:
	var ui := _ui()
	assert_eq(ui.get_status_line_text(), "")
	assert_false(ui.get_status_line().visible)
	ui.show_status_line("Warte auf Anna …")
	await wait_process_frames(2)
	var line := ui.get_status_line()
	assert_true(line.visible)
	assert_eq(ui.get_status_line_text(), "Warte auf Anna …")
	assert_true(line.is_in_group(Hud.TOP_CENTER_GROUP), "the room line and coop lines dodge it")
	assert_lt(line.get_global_rect().position.y, UiKit.px(12), "at the top edge")
	var view := ui.get_viewport().get_visible_rect().size
	assert_almost_eq(line.get_global_rect().get_center().x, view.x * 0.5, 2.0, "centred")
	ui.show_status_line("Warte auf Anna …")
	assert_eq(line.modulate.a, 1.0, "the same text again does not pop in again")
	ui.clear_status_line()
	assert_eq(ui.get_status_line_text(), "")
	await wait_seconds(DungeonUI.STATUS_LINE_FADE + 0.15)
	assert_false(line.visible)


func test_status_line_with_duration_goes_away() -> void:
	var ui := _ui()
	ui.show_status_line("Beeil dich!", 0.3, UiKit.COLOR_DANGER)
	await wait_seconds(0.15)
	assert_eq(ui.get_status_line_text(), "Beeil dich!")
	await wait_seconds(0.3)
	assert_eq(ui.get_status_line_text(), "")
	ui.show_status_line("")
	assert_eq(ui.get_status_line_text(), "", "an empty text clears")


func test_status_line_sits_below_the_top_bar_and_banners_below_it() -> void:
	var ui := _ui()
	ui._boss_bar_root.visible = true
	ui.show_status_line("Warte auf Ben …")
	await wait_process_frames(3)
	var bar := ui._boss_bar_root.get_global_rect()
	var line := ui.get_status_line().get_global_rect()
	assert_gte(line.position.y, bar.end.y, "below the boss bar (or the task bar)")
	ui.show_banner("Raum geschafft!")
	await wait_seconds(0.4)
	assert_gte(ui.get_banner().get_global_rect().position.y, line.end.y - 1.0, "the banner goes below the line")


# --- Top band: the 3-2-1 under the banner ---

func test_countdown_sits_in_the_top_band_under_the_banner() -> void:
	var ui := _ui()
	ui.show_banner("Halte die Flamme 40 s", "Bleib im Kreis")
	await wait_seconds(0.4)
	var bottom := ui.get_top_band_bottom()
	assert_gt(bottom, ui.get_banner().get_global_rect().end.y - 1.0)
	var countdown := ui.get_countdown()
	countdown.top_px = bottom
	countdown.show_number(3)
	await wait_process_frames(1)
	var number := countdown.get_number_rect()
	assert_ne(number, Rect2(), "on screen")
	assert_gte(number.position.y + 1.0, ui.get_banner().get_global_rect().end.y, "below the banner")
	var view := ui.get_viewport().get_visible_rect().size
	assert_lt(number.get_center().y, view.y * 0.45, "not in the middle of the playfield")


func test_countdown_without_banner_stays_in_the_upper_third() -> void:
	var ui := _ui()
	var countdown := ui.get_countdown()
	countdown.show_number(2)
	await wait_process_frames(1)
	var view := ui.get_viewport().get_visible_rect().size
	assert_lt(countdown.get_number_rect().get_center().y, view.y * 0.34)
	assert_lt(IntroCountdown.NUMBER_SIZE, 30, "smaller than the old 30 px")


# --- Teaching cards in the upper left ---

func test_enemy_hint_card_sits_on_the_left_edge() -> void:
	var ui := _ui()
	ui.show_hint("Skelett", "Hält Abstand und wirft Knochen.")
	await wait_process_frames(2)
	var card := ui._hint_card as Control
	assert_not_null(card)
	assert_eq(card.name, &"EnemyHint")
	assert_almost_eq(card.position.x, UiKit.px(DungeonUI.HINT_EDGE_MARGIN), 0.5)
	assert_almost_eq(card.position.y, Hud.teaching_card_top(get_tree()), 1.0, "in the upper left")
	var view := ui.get_viewport().get_visible_rect().size
	assert_lt(card.get_global_rect().end.x, view.x * 0.45, "never across the middle")


func test_teaching_cards_start_below_the_top_band() -> void:
	assert_gte(Hud.teaching_card_top(null), UiKit.px(60.0), "a wide banner never reaches the cards")
	var ui := _ui()
	ui._queue_room_intro(RoomGenre.ARENA)
	await wait_process_frames(3)
	var card := ui.get_room_intro_card()
	assert_not_null(card)
	assert_almost_eq(card.position.y, Hud.teaching_card_top(get_tree()), 1.0)


func test_teaching_card_ends_in_the_next_room() -> void:
	var ui := _ui()
	ui.show_hint("Abgrund", "Mit Dash über Löcher springen.")
	await wait_process_frames(2)
	var card := ui._hint_card as Control
	EventBus.room_entered.emit(2)
	await wait_process_frames(2)
	assert_eq(ui._hint_card, card, "too short to be read: it stays")
	card.set_meta(&"shown_ms", Time.get_ticks_msec() - int(DungeonUI.HINT_ROOM_CHANGE_MIN * 1000.0) - 100)
	EventBus.room_entered.emit(3)
	await wait_seconds(0.45)
	assert_false(is_instance_valid(card), "read long enough: it goes with the room")


func test_teaching_cards_step_back_during_a_fight() -> void:
	await wait_process_frames(2)
	var ui := _ui()
	ui.show_hint("Skelett", "Hält Abstand.")
	_enemy(Vector2(900, 600))
	await wait_seconds(0.5)
	assert_almost_eq(ui._hint_root.modulate.a, DungeonUI.CARD_FIGHT_ALPHA, 0.05)


# --- Damage numbers ---

func test_damage_numbers_are_short_and_drift_aside() -> void:
	assert_lte(DamageNumber.LIFETIME, 0.6, "about half as long as the old 1.1 s")
	var offsets: Array[float] = []
	for i in DamageNumber.STAGGER.size():
		offsets.append(DamageNumber.next_stagger())
	assert_true(offsets.has(0.0))
	assert_true(offsets.any(func(x: float) -> bool: return x > 0.0) and offsets.any(func(x: float) -> bool: return x < 0.0), "both sides in turn")


func test_status_literals_are_translated_once_the_key_exists() -> void:
	assert_eq(DamageNumber.status_text("Unbekannt!"), "Unbekannt!")
	var stunned := DamageNumber.status_text("Betäubt!")
	assert_true(stunned == "Betäubt!" or stunned == Loc.t(&"STATUS_STUNNED"), "the literal until the key is in the CSV")


func test_damage_number_is_gone_after_its_lifetime() -> void:
	var parent: Node2D = add_child_autofree(Node2D.new())
	var result := DamageResult.new()
	result.health_damage = 3.0
	DamageNumber.spawn_for_result(parent, Vector2(100, 100), result)
	assert_eq(parent.get_child_count(), 1)
	var number := parent.get_child(0) as DamageNumber
	assert_almost_eq(number.modulate.a, DamageNumber.ALPHA, 0.01, "a little see-through")
	await wait_seconds(DamageNumber.LIFETIME + 0.15)
	assert_false(is_instance_valid(number) and number.is_inside_tree() and not number.is_queued_for_deletion(), "freed")


# --- Falls and downed players (D-084) ---

func test_single_player_fall_names_the_cause() -> void:
	var ui := _ui()
	var player := _player()
	var enemy := _enemy(Vector2(2000, 2000))
	await wait_process_frames(2)
	_kill(player, enemy)
	await wait_process_frames(2)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq((banner.find_child("Title", true, false) as Label).text, DungeonTexts.t(&"RUNEND_DEATH"))
	assert_eq((banner.find_child("Subtitle", true, false) as Label).text, DungeonTexts.t(&"DOWNED_CAUSE", [enemy.get_display_name()]))
	assert_false(banner.has_meta(&"strip"), "important: big and short")
	assert_null(ui.get_downed_panel(), "single player: the run ends, no downed panel")


func test_downed_local_player_gets_the_panel_and_loses_it_when_revived() -> void:
	var ui := _ui()
	var share := [0.0]
	ui.revive_share_provider = func(_p: Player) -> float: return share[0]
	var player := _player()
	var mate := _player(false)
	var enemy := _enemy(Vector2(2000, 2000))
	await wait_process_frames(2)
	_kill(player, enemy)
	await wait_process_frames(2)
	var panel := ui.get_downed_panel()
	assert_not_null(panel, "a mate stands: the player is down, not out")
	assert_eq(panel.get_cause_text(), DungeonTexts.t(&"DOWNED_CAUSE", [enemy.get_display_name()]))
	assert_false(panel.is_reviving())
	assert_eq((ui.get_banner().find_child("Title", true, false) as Label).text, Loc.t(&"NET_DOWNED_TITLE"))
	var view := ui.get_viewport().get_visible_rect().size
	assert_gt(panel.get_global_rect().position.y, view.y * 0.5, "bottom: the top band stays free")
	share[0] = 0.5
	await wait_process_frames(2)
	assert_true(panel.is_reviving(), "the bar runs while a mate helps")
	player.revive(2.0)
	await wait_process_frames(2)
	assert_null(ui.get_downed_panel())
	assert_true(mate.is_alive())


func test_netdungeon_banner_of_the_same_fall_is_not_shown_twice() -> void:
	var ui := _ui()
	var player := _player()
	_player(false)
	await wait_process_frames(2)
	_kill(player)
	await wait_process_frames(2)
	ui.show_banner(Loc.t(&"NET_DOWNED_TITLE"), Loc.t(&"NET_DOWNED_SUB"))
	assert_eq(ui.get_banner_queue_size(), 0)


func test_downed_mate_gets_a_strip_and_a_marker() -> void:
	var ui := _ui()
	_player()
	var mate := _player(false)
	var tag := Label.new()
	tag.name = "NameTag"
	tag.text = "Anna"
	mate.add_child(tag)
	await wait_process_frames(2)
	_kill(mate)
	await wait_process_frames(3)
	var banner := ui.get_banner()
	assert_not_null(banner)
	assert_eq((banner.find_child("Title", true, false) as Label).text, DungeonTexts.t(&"MATE_DOWNED_TITLE", ["Anna"]))
	assert_true(banner.has_meta(&"strip"), "info about a mate: small")
	assert_eq(ui.get_downed_markers().get_target_count(), 1, "where the mate lies")
	assert_null(ui.get_downed_panel())
	mate.revive(2.0)
	await wait_process_frames(2)
	assert_eq(ui.get_downed_markers().get_target_count(), 0)


func test_a_freed_player_drops_out_quietly() -> void:
	# Session end / a mate leaves: the players go before the UI (net smoke: "previously freed").
	var ui := _ui()
	_player()
	var mate := PLAYER_SCENE.instantiate() as Player
	mate.is_local = false
	add_child(mate)
	await wait_process_frames(2)
	_kill(mate)
	mate.free()
	await wait_process_frames(3)
	assert_eq(ui._watched().size(), 1)
	assert_eq(ui.get_downed_markers().get_target_count(), 0)


func test_marker_arrow_sits_on_the_screen_edge_for_a_mate_off_screen() -> void:
	var ui := _ui()
	var markers := ui.get_downed_markers()
	var view := markers.get_view()
	var far := view.get_center() + Vector2(view.size.x * 2.0, 0.0)
	assert_false(markers.is_on_screen(far))
	var edge: Vector2 = markers.edge_point(far)
	assert_true(view.has_point(edge))
	assert_gt(edge.x, view.get_center().x + view.size.x * 0.4, "right edge, towards the mate")
	assert_true(markers.is_on_screen(view.get_center()))


func test_new_texts_have_german() -> void:
	for key: StringName in [&"FALL_ALL_DOWN", &"DOWNED_EYEBROW", &"DOWNED_CAUSE", &"DOWNED_HELP", &"DOWNED_ROOM",
			&"DOWNED_ALL", &"DOWNED_REVIVING", &"MATE_DOWNED_TITLE", &"MATE_DOWNED_NAMELESS", &"MATE_DOWNED_SUB", &"REVIVED_TITLE"]:
		assert_true(DungeonTexts.has_text(key), String(key))
