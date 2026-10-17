extends GutTest
## Context of a bug report (DevFeedbackContext): the readable German location line (dungeon with
## biome, room type, boss fight and dialog; main menu with online tab and guild page), German texts
## whatever the game language, open dialogs found by their pause reason, the boss of the fight, co-op
## and device info, no room codes in the network snapshot, and the ping copied to coop.

const ENEMY_STUB := """extends Node2D
var data: Resource
var phase := 2
var is_miniboss := false
var health: Node
"""
const DATA_STUB := """extends Resource
var id := &"bone_king"
var display_name := "BIOME_CRYPT"
var is_boss := true
"""
const HEALTH_STUB := """extends Node
func is_dead() -> bool:
	return false
func get_health() -> float:
	return 412.0
func get_max_health() -> float:
	return 900.0
"""

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_dev_feedback_context_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func test_dungeon_location_is_readable_german() -> void:
	var context := {
		"phase": "dungeon",
		"dungeon": {"room_index": 23, "biome_name": "Schleimgrotte", "room_type": "COMBAT_UPGRADE",
			"room_type_name": "Kampf + Upgrade", "genre_name": "Arena"},
		"players": [{"side_view": false}],
		"boss": {"name": "Knochenkönig II", "phase": 2},
		"screen": {"parts": ["Pausemenü"]},
	}
	assert_eq(DevFeedbackContext.describe_location(context),
		"Dungeon · Raum 23 · Schleimgrotte · Kampf + Upgrade · Arena · Bosskampf: Knochenkönig II (Phase 2) · Pausemenü")
	context["boss"] = {"name": "Schleimkönigin", "miniboss": true}
	context["screen"] = {}
	context["players"] = [{"side_view": true}]
	assert_string_ends_with(DevFeedbackContext.describe_location(context), "Seitenansicht · Miniboss: Schleimkönigin")
	assert_does_not_have(DevFeedbackContext.describe_location(context).split(" · "), "COMBAT_UPGRADE", "no enum names")


func test_menu_location_names_the_guild_page() -> void:
	var context := {"phase": "menu", "screen": {"parts": ["Online", "Gilden", "Gildenseite"]}}
	assert_eq(DevFeedbackContext.describe_location(context), "Hauptmenü · Online · Gilden · Gildenseite")
	assert_eq(DevFeedbackContext.describe_location({"phase": "village", "screen": {"parts": ["Schmiede"]}}), "Dorf · Schmiede")
	var long := DevFeedbackContext.describe_location({"phase": "menu", "screen": {"parts": ["x".repeat(300)]}})
	assert_lte(long.length(), 200, "fits the contract (location max 200)")


func test_german_texts_whatever_the_language() -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(DevFeedbackContext.de_text(&"BIOME_SLIME_GROTTO"), "Schleimgrotte")
	assert_eq(DevFeedbackContext.de_text("HUD_ROOM_TYPE_COMBAT_UPGRADE"), "Kampf + Upgrade")
	assert_eq(DevFeedbackContext.de_text("NO_SUCH_KEY_X", "Ersatz"), "Ersatz")
	assert_eq(DevFeedbackContext.de_text("NO_SUCH_KEY_X"), "NO_SUCH_KEY_X")
	TranslationServer.set_locale(old_locale)


func test_online_menu_tab_and_guild_page() -> void:
	var menu := OnlineMenu.new()
	autofree(menu)
	menu.view = OnlineMenu.View.DETAIL
	assert_eq(DevFeedbackContext._online_parts(menu), ["Gilden", "Gildenseite"])
	menu.view = OnlineMenu.View.QUICK
	assert_eq(DevFeedbackContext._online_parts(menu), ["Schnell"])


func test_open_dialog_is_named() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var modal := Modal.create(GameManager.PAUSE_MENU)
	layer.add_child(modal)
	var screen := DevFeedbackContext.screen_info(get_tree(), "dungeon")
	assert_has(screen["parts"], "Pausemenü")
	assert_string_starts_with(str(screen["label"]), "Dungeon · ")
	assert_eq((screen["nodes"] as Array).size(), 1)
	modal.visible = false
	assert_does_not_have(DevFeedbackContext.screen_info(get_tree(), "dungeon")["parts"], "Pausemenü", "hidden dialogs do not count")


func test_boss_of_the_fight() -> void:
	assert_eq(DevFeedbackContext.boss_info(get_tree()), {}, "no boss, no entry")
	var boss := _script(ENEMY_STUB).new() as Node2D
	boss.set(&"data", _script(DATA_STUB).new())
	var health := _script(HEALTH_STUB).new() as Node
	boss.add_child(health)
	boss.set(&"health", health)
	boss.add_to_group(&"enemies")
	add_child_autofree(boss)
	var info := DevFeedbackContext.boss_info(get_tree())
	assert_eq(info["id"], "bone_king")
	assert_eq(info["name"], "Krypta", "German name from the display key")
	assert_eq(info["phase"], 2)
	assert_almost_eq(float(info["hp"]), 412.0, 0.01)
	assert_almost_eq(float(info["hp_max"]), 900.0, 0.01)
	assert_false(info["miniboss"])
	boss.visible = false
	assert_eq(DevFeedbackContext.boss_info(get_tree()), {}, "a hidden boss is not fought")


func test_coop_and_device() -> void:
	var coop := DevFeedbackContext.coop_info(get_tree())
	assert_has(["solo", "local", "host", "client"], coop["role"])
	assert_true(coop.has("players"))
	assert_false(coop["online"], "no lobby room in tests")
	var device := DevFeedbackContext.device_info(get_tree())
	assert_eq(device["platform"], DevFeedbackUpload.platform())
	assert_has(["mouse", "gamepad", "touch"], device["input"])
	assert_true(device.has("ui_zoom"))
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	DevFeedbackContext.note_input(pad)
	assert_eq(DevFeedbackContext._last_input, "gamepad")
	DevFeedbackContext.note_input(InputEventKey.new())
	assert_eq(DevFeedbackContext._last_input, "mouse")


func test_no_room_codes_and_ping_in_coop() -> void:
	var snapshot := {"online": true, "connection": {"role": "host", "room": "ABCD12", "rtt_ms": {"last": 85, "avg": 80}},
		"last_disconnect": {"room": "ABCD12", "code": 4010, "reason": "slow consumer"}}
	var clean: Dictionary = DevFeedbackContext.without_room_codes(snapshot)
	assert_false(JSON.stringify(clean).contains("ABCD12"), "no room code anywhere")
	assert_eq(clean["last_disconnect"]["code"], 4010, "the close code stays")
	assert_eq(snapshot["connection"]["room"], "ABCD12", "the original is not changed")
	var context := {"network": clean, "coop": {"players": 2}}
	DevFeedbackContext.add_ping(context)
	assert_eq(context["coop"]["ping_ms"], 85)


func test_full_context_stays_small() -> void:
	var context := DevFeedbackContext.collect(get_tree())
	for key in ["screen", "coop", "device", "location"]:
		assert_true(context.has(key), "context has %s" % key)
	assert_lte(DevFeedbackUpload.json_bytes(context), DevFeedbackUpload.MAX_CONTEXT_BYTES)


func _script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script
