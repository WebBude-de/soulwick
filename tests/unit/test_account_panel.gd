extends GutTest
## KF6: the account panel (AccountPanel) and its entry in the options ("Konto" on the action line).
## Views per state (no account, guest, secured, signed out), the ways to sign in, the browser code
## without the browser secret on screen, username and password, the merge question, logins with
## "Trennen", cloud worlds with backups and archive, deleting with the deletion code; keyboard,
## gamepad (focus frame, fields open the on-screen keyboard) and touch (X closes). Fake API, no
## network; the real online.cfg and save are never touched.

const TEST_PATH := "user://test_account_panel_online.cfg"
const SAVE_PATH := "user://test_account_panel_save.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const OWN_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"
const BROWSER_SECRET := "browser-secret-do-not-show-0123456789"
const WORLD_ID := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
const OLD_WORLD_ID := "cccccccc-bbbb-4ccc-8ddd-eeeeeeeeeeee"

const FakeTransport := preload("res://tests/unit/test_session_account.gd").FakeTransport
const PadKeyboard := preload("res://ui/widgets/pad_keyboard.gd")
const MobileUi := preload("res://ui/menus/mobile_ui.gd")

var _fake
var _client: ApiClient
var _session: OnlineSession
var _old_locale: String
var _old_save_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	SaveManager.load_game()


func before_each() -> void:
	_remove_files()
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	_fake = FakeTransport.new()
	_client = ApiClient.new()
	_client.transport = _fake
	_client.base_url = "http://api.test"
	add_child_autofree(_client)
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": "http://api.test"})
	_session = OnlineSession.new(config)
	_session.api = _client
	_session.public_config = {"apiVersion": "1.1.0", "loginMethods": ["device", "password", "google", "discord"]}
	add_child_autofree(_session)


func after_each() -> void:
	var open := AccountPanel.get_open()
	if open != null:
		open.finish()
	var keyboard := PadKeyboard.get_open()
	if keyboard != null:
		keyboard.finish()
	MobileUi.touch_override = -1
	InputDevice.shared().set_kind(InputDevice.Kind.KEYBOARD_MOUSE)
	await wait_process_frames(2)


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	_remove_files()
	SaveManager.save_path = _old_save_path
	SaveManager.load_game()


func _remove_files() -> void:
	for path in [TEST_PATH, SAVE_PATH, TEST_PATH.get_basename() + OnlineSession.LOGIN_FILE_SUFFIX]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _log_in() -> void:
	_session.token = TOKEN
	_session.token_expires_at = 4_000_000_000
	_session.player = {"id": OWN_ID, "name": "Lumen", "createdAt": "2026-10-01T10:00:00.000Z", "guild": null, "guilds": [], "level": 7}
	_session.state = OnlineSession.State.ONLINE
	_client.token = TOKEN


func _identities(providers: Array) -> Dictionary:
	var items := []
	for provider: String in providers:
		items.append({"id": "00000000-0000-4000-8000-%012d" % items.size(), "provider": provider,
				"maskedId": "***" + (_session.config.get_device_id().right(4) if provider == "device" else "0001"),
				"label": "lumen" if provider == "password" else null, "createdAt": "2026-10-01T10:00:00.000Z", "lastUsedAt": "2026-10-01T10:00:00.000Z"})
	return {"items": items}


func _worlds() -> Dictionary:
	var summary := {"name": "Kerzenhain", "deepestRoom": 12, "forgeLevel": 4, "forgeMax": 20, "playTimeSeconds": 7300, "lastPlayedAt": "2026-11-02T18:00:00Z"}
	return {"items": [{"worldId": WORLD_ID, "revision": 3, "status": "active", "backupCount": 1, "summary": summary, "pendingMerges": []}],
			"archived": [{"worldId": OLD_WORLD_ID, "revision": 1, "status": "archived", "backupCount": 0, "expiresAt": CloudSave.iso_time(int(Time.get_unix_time_from_system()) + 12 * 86400 - 60),
				"summary": {"name": "", "deepestRoom": 3, "forgeLevel": 0, "forgeMax": 20, "playTimeSeconds": 600, "lastPlayedAt": "2026-10-02T18:00:00Z"}, "pendingMerges": []}],
			"maxWorlds": 3, "maxDataBytes": 65536}


## A panel on its own layer, its first refresh finished.
func _open() -> AccountPanel:
	var host := Control.new()
	add_child_autofree(host)
	var panel := AccountPanel.open_for(host, _session)
	panel.input_guard = 0.0
	panel.pad_accept_guard = 0.0
	panel.service.web.url_opener = func(_url: String) -> void: pass
	await _settle(panel)
	return panel


func _settle(panel: AccountPanel, frames := 4) -> void:
	for i in frames:
		await wait_process_frames(1)
		if not panel.service.is_busy():
			break
	await wait_process_frames(2)


func _texts(panel: AccountPanel) -> String:
	var parts := PackedStringArray()
	for node in panel.frame.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	for node in panel.frame.find_children("*", "Button", true, false):
		parts.append((node as Button).text)
	for node in panel.frame.find_children("*", "LineEdit", true, false):
		parts.append((node as LineEdit).text)
	return " | ".join(parts)


func _press(panel: AccountPanel, button_name: String) -> void:
	var button := panel.find_button(button_name)
	assert_not_null(button, "button %s in: %s" % [button_name, _texts(panel)])
	if button != null:
		assert_false(button.disabled, "%s enabled" % button_name)
		button.pressed.emit()
	await _settle(panel)


func _web_answers() -> void:
	var expires := CloudSave.iso_time(int(Time.get_unix_time_from_system()) + 600)
	_fake.answer("POST /auth/web-login", 201, {ApiClient.WEB_CODE: "ABCDEFGH", ApiClient.WEB_USER_CODE: "KMN-PQR", ApiClient.WEB_POLL_SECRET: "poll-secret-0123456789",
			ApiClient.WEB_BROWSER_SECRET: BROWSER_SECRET, ApiClient.WEB_URL: "https://playsoulwick.test/login/ABCDEFGH#k=" + BROWSER_SECRET,
			ApiClient.WEB_EXPIRES_AT: expires, ApiClient.WEB_POLL_INTERVAL: 30})


# --- Entry in the options ---

func test_options_have_the_account_entry_on_the_action_line() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	await wait_process_frames(2)
	assert_not_null(view.get_account_button(), "Konto next to Zurücksetzen")
	assert_eq(view.get_account_button().text, "OPTIONS_ACCOUNT")
	view.select_row(OptionsView.Row.RESET)
	view.handle_input(MenuInput.key_event(KEY_LEFT))
	assert_true(view.is_account_picked(), "← picks Konto")
	view.handle_input(MenuInput.key_event(KEY_RIGHT))
	assert_false(view.is_account_picked(), "→ back to Zurücksetzen")
	view.handle_input(MenuInput.key_event(KEY_LEFT))
	view.handle_input(MenuInput.key_event(KEY_ENTER))
	await wait_process_frames(2)
	var panel := AccountPanel.get_open()
	assert_not_null(panel, "Enter opens the account panel")
	assert_false(view.is_confirming_reset(), "not the reset question")
	view.handle_input(MenuInput.key_event(KEY_DOWN))
	assert_eq(view.get_row(), OptionsView.Row.TABS, "the options still work after it (host forwards keys)")


func test_enter_on_the_reset_row_still_asks_to_reset() -> void:
	var view := OptionsView.new()
	add_child_autofree(view)
	await wait_process_frames(2)
	view.select_row(OptionsView.Row.RESET)
	view.handle_input(MenuInput.key_event(KEY_ENTER))
	assert_true(view.is_confirming_reset())
	assert_null(AccountPanel.get_open())
	view.cancel_reset()


func test_the_panel_swallows_keys_and_esc_closes_it() -> void:
	var panel := await _open()
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	assert_true(AccountPanel.is_swallowed(key), "Q does not reach the options under it")
	assert_true(AccountPanel.is_swallowed(MenuInput.pad_button_event(JOY_BUTTON_LEFT_SHOULDER)), "nor LB")
	assert_false(AccountPanel.is_swallowed(InputEventMouseMotion.new()), "the mouse hits the dim")
	assert_eq(panel.get_parent().name, "AccountPanelLayer")
	assert_eq(panel.get_parent().get_index(), panel.get_tree().root.get_child_count() - 1, "last child of the root: reads keys first")
	panel._unhandled_input(MenuInput.key_event(KEY_ESCAPE))
	await wait_process_frames(2)
	assert_null(AccountPanel.get_open(), "Esc on the overview closes")


func test_closing_the_opener_closes_the_panel() -> void:
	var host := Control.new()
	add_child(host)
	var panel := AccountPanel.open_for(host, _session)
	await wait_process_frames(1)
	host.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(panel) and not panel.is_queued_for_deletion())


# --- Views per state ---

func test_without_account_it_offers_secure_and_sign_in_and_never_logs_in() -> void:
	var panel := await _open()
	assert_eq(panel.service.get_state(), AccountService.State.NONE)
	assert_not_null(panel.find_button("Secure"))
	assert_not_null(panel.find_button("SignIn"))
	assert_eq(_fake.last("POST /auth/device"), {}, "opening creates no account (D-224)")
	await _press(panel, "SignIn")
	assert_eq(panel.view, AccountPanel.View.METHODS)
	assert_not_null(panel.find_button("WebMethod"))
	assert_not_null(panel.find_button("PasswordMethod"))
	panel._unhandled_input(MenuInput.key_event(KEY_ESCAPE))
	await _settle(panel)
	assert_eq(panel.view, AccountPanel.View.MAIN, "Esc goes one step back")


func test_browser_view_shows_the_code_but_never_the_secret() -> void:
	var panel := await _open()
	var opened: Array[String] = []
	panel.service.web.url_opener = func(url: String) -> void: opened.append(url)
	await _press(panel, "SignIn")
	_web_answers()
	await _press(panel, "WebMethod")
	await _settle(panel, 6)
	assert_eq(panel.view, AccountPanel.View.WEB)
	var texts := _texts(panel)
	assert_string_contains(texts, "KMN-PQR", "the user code to type")
	assert_false(texts.contains(BROWSER_SECRET), "the browser secret is never on screen")
	assert_false(texts.contains("ABCDEFGH") or texts.contains("ABCD-EFGH"), "nor the request code")
	assert_eq(opened.size(), 1)
	assert_eq(opened[0].count("#k="), 1, "the fragment once")
	assert_string_ends_with(opened[0], "#k=" + BROWSER_SECRET)
	assert_not_null(panel.find_button("Reopen"))
	assert_not_null(panel.find_button("CopyLink"))
	await _press(panel, "Cancel")
	assert_eq(panel.service.web.status, WebLoginFlow.Status.CANCELLED)
	assert_eq(panel.view, AccountPanel.View.METHODS)


func test_browser_view_names_confirm_and_expiry() -> void:
	var panel := await _open()
	await _press(panel, "SignIn")
	_web_answers()
	await _press(panel, "WebMethod")
	await _settle(panel, 6)
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "awaiting_confirm"})
	await panel.service.web.poll()
	await _settle(panel)
	assert_string_contains(_texts(panel), "Im Browser bestätigen")
	_fake.answer("POST /auth/web-login/poll", 200, {"status": "expired"})
	await panel.service.web.poll()
	await _settle(panel)
	assert_string_contains(_texts(panel), "abgelaufen")
	assert_not_null(panel.find_button("Retry"), "a new code")


func test_password_sign_in_with_wrong_and_right_password() -> void:
	var panel := await _open()
	await _press(panel, "SignIn")
	await _press(panel, "PasswordMethod")
	assert_eq(panel.view, AccountPanel.View.PASSWORD)
	assert_true(panel.get_password_edit().secret, "the password is hidden")
	panel.get_username_edit().text = "lumen"
	panel.get_password_edit().text = "falsch-falsch"
	_fake.answer("POST /auth/password", 401, {"error": "invalid_credentials"})
	await _press(panel, "Submit")
	await _settle(panel)
	assert_string_contains(_texts(panel), "stimmt nicht")
	assert_eq(panel.view, AccountPanel.View.PASSWORD, "stays to try again")
	panel.get_password_edit().text = "soulwick-player-local"
	_fake.answer("POST /auth/password", 200, {"token": "fresh", "expiresAt": "2099-01-01T00:00:00.000Z",
			"player": {"id": OWN_ID, "name": "Lumen", "createdAt": "2026-10-01T10:00:00.000Z", "level": 7}})
	_fake.answer("POST /me/logins", 200, {"token": "fresh-device", "expiresAt": "2099-01-01T00:00:00.000Z", "merged": false, "removedPlayerId": null,
			"player": {"id": OWN_ID, "name": "Lumen", "createdAt": "2026-10-01T10:00:00.000Z", "level": 7}, "identities": _identities(["password", "device"]).items})
	_fake.answer("GET /me/identities", 200, _identities(["password", "device"]))
	await _press(panel, "Submit")
	await _settle(panel, 10)
	assert_eq(panel.view, AccountPanel.View.MAIN)
	assert_eq(panel.service.get_state(), AccountService.State.SECURED)
	assert_string_contains(_texts(panel), "Angemeldet als Lumen")


func test_merge_question_after_a_sign_in() -> void:
	_log_in()
	var panel := await _open()
	panel.service.merge_offer = {"remaining": {"name": "Lumen", "level": 9, "runCount": 40, "worlds": 2, "guilds": []},
			"removed": {"name": "Gast", "level": 2, "runCount": 3, "worlds": 1, "guilds": []}}
	panel.show_view(AccountPanel.View.MERGE)
	await _settle(panel)
	var texts := _texts(panel)
	assert_string_contains(texts, "Level 9")
	assert_string_contains(texts, "bleibt")
	await _press(panel, "NotNow")
	assert_eq(panel.view, AccountPanel.View.MAIN)
	assert_eq(_session.login_kind, OnlineSession.LOGIN_ACCOUNT)


func test_secured_account_lists_logins_and_removes_one_after_a_question() -> void:
	_log_in()
	_fake.answer("GET /me/identities", 200, _identities(["device", "discord", "password"]))
	_fake.answer("GET /me/worlds", 200, _worlds())
	var panel := await _open()
	assert_eq(panel.service.get_state(), AccountService.State.SECURED)
	var texts := _texts(panel)
	assert_string_contains(texts, "Discord")
	assert_string_contains(texts, "lumen")
	assert_string_contains(texts, "auch dieses")
	assert_string_contains(texts, "1 in der Cloud · 1 im Archiv")
	_fake.answer("DELETE /me/identities/discord", 200, _identities(["device", "password"]))
	await _press(panel, "Remove_discord")
	assert_eq(panel.view, AccountPanel.View.CONFIRM, "asks first")
	await _press(panel, "Confirm")
	await _settle(panel)
	assert_eq(panel.view, AccountPanel.View.MAIN)
	assert_null(panel.find_button("Remove_discord"))
	assert_string_contains(_texts(panel), "Getrennt")


func test_guest_account_asks_to_secure() -> void:
	_log_in()
	_fake.answer("GET /me/identities", 200, _identities(["device"]))
	var panel := await _open()
	assert_eq(panel.service.get_state(), AccountService.State.GUEST)
	assert_string_contains(_texts(panel), "nicht gesichert")
	assert_not_null(panel.find_button("Secure"))
	assert_null(panel.find_button("Remove_device"), "the last login cannot go")


func test_signed_out_offers_sign_in_or_guest() -> void:
	_session.set_login_kind(OnlineSession.LOGIN_ACCOUNT)
	var panel := await _open()
	assert_eq(panel.service.get_state(), AccountService.State.SIGNED_OUT)
	assert_string_contains(_texts(panel), "abgelaufen")
	await _press(panel, "AsGuest")
	assert_eq(_session.login_kind, OnlineSession.LOGIN_DEVICE)
	assert_eq(panel.service.get_state(), AccountService.State.NONE)


func test_cloud_worlds_backups_and_archive() -> void:
	_log_in()
	_fake.answer("GET /me/identities", 200, _identities(["device", "discord"]))
	_fake.answer("GET /me/worlds", 200, _worlds())
	var panel := await _open()
	_fake.answer("GET /me/worlds", 200, _worlds())
	await _press(panel, "Worlds")
	assert_eq(panel.view, AccountPanel.View.WORLDS)
	var texts := _texts(panel)
	assert_string_contains(texts, "Kerzenhain")
	assert_string_contains(texts, "Raum 12 · Schmiede 4/20 · 2 Std.")
	assert_string_contains(texts, "Wird in 12 Tagen gelöscht")
	assert_not_null(panel.find_button("Unarchive_" + OLD_WORLD_ID))
	_fake.answer("GET /me/worlds/%s/backups" % WORLD_ID, 200, {"items": [{"id": "99999999-8888-4777-8666-555555555555", "worldId": WORLD_ID,
			"reason": "merge", "createdAt": "2026-11-01T12:00:00Z", "summary": {"deepestRoom": 10, "forgeLevel": 3, "forgeMax": 20, "playTimeSeconds": 3600}}]})
	await _press(panel, "Backups_" + WORLD_ID)
	assert_eq(panel.view, AccountPanel.View.BACKUPS)
	assert_string_contains(_texts(panel), "älterer Stand")
	await _press(panel, "Restore_99999999-8888-4777-8666-555555555555")
	assert_eq(panel.view, AccountPanel.View.CONFIRM, "restoring asks first")
	panel._unhandled_input(MenuInput.key_event(KEY_ESCAPE))
	await _settle(panel)
	assert_eq(panel.view, AccountPanel.View.BACKUPS, "Esc back to the backups")


func test_world_limit_view_offers_the_active_worlds() -> void:
	_log_in()
	var panel := await _open()
	panel.service.limit_offer = {"world_id": OLD_WORLD_ID, "backup_id": "", "items": _worlds()["items"]}
	panel.show_view(AccountPanel.View.LIMIT)
	await _settle(panel)
	assert_not_null(panel.find_button("Archive_" + WORLD_ID))
	_fake.answer("POST /me/worlds/%s/unarchive" % OLD_WORLD_ID, 409, {"error": "world_limit_reached", "items": []})
	await _press(panel, "Archive_" + WORLD_ID)
	await _settle(panel, 6)
	assert_eq(_fake.last("POST /me/worlds/%s/unarchive" % OLD_WORLD_ID).body, {"archiveWorldId": WORLD_ID})


func test_delete_view_with_deletion_code_and_question() -> void:
	_log_in()
	_fake.answer("GET /me/identities", 200, _identities(["device", "discord"]))
	var panel := await _open()
	await _press(panel, "Delete")
	assert_eq(panel.view, AccountPanel.View.DELETE)
	assert_string_contains(_texts(panel), "/delete-account")
	_fake.answer("POST /me/deletion-code", 201, {"code": "QRSTUVWX", "expiresAt": "2099-01-01T00:00:00.000Z"})
	await _press(panel, "DeleteCode")
	await _settle(panel)
	assert_string_contains(_texts(panel), "QRST-UVWX")
	await _press(panel, "DeleteNow")
	assert_eq(panel.view, AccountPanel.View.CONFIRM)
	_fake.answer("DELETE /me", 204, null)
	await _press(panel, "Confirm")
	await _settle(panel, 6)
	assert_eq(panel.view, AccountPanel.View.MAIN)
	assert_false(_session.is_logged_in())
	assert_string_contains(_texts(panel), "gelöscht")


# --- Gamepad and touch ---

func test_gamepad_reaches_the_fields_and_opens_the_keyboard() -> void:
	InputDevice.shared().set_kind(InputDevice.Kind.GAMEPAD)
	var panel := await _open()
	assert_not_null(panel.get_focused_button(), "the frame starts on a button")
	assert_eq(String(panel.get_focused_button().name), "Secure", "the default one")
	await _press(panel, "SignIn")
	await _press(panel, "PasswordMethod")
	var field := panel.find_button("FieldUsername")
	assert_true(panel.focus_targets().has(field), "the field is a gamepad target")
	panel.focus_button(field)
	panel.press_focused()
	await wait_process_frames(2)
	assert_not_null(PadKeyboard.get_open(), "A on a field opens the on-screen keyboard")
	assert_eq(PadKeyboard.get_open().get(&"field"), panel.get_username_edit())


func test_touch_has_the_x_to_close() -> void:
	MobileUi.touch_override = 1
	var panel := await _open()
	assert_true(panel.has_close_button())
	panel.request_close()
	await wait_process_frames(2)
	assert_null(AccountPanel.get_open())


func test_texts_follow_the_language() -> void:
	var panel := await _open()
	assert_string_contains(_texts(panel), "Konto sichern")
	Loc.apply(&"en")
	await wait_process_frames(3)
	assert_string_contains(_texts(panel), "Secure account")
	Loc.apply(&"de")
	await wait_process_frames(2)


func test_error_texts_cover_the_api_codes() -> void:
	for code in ["unreachable", "invalid_credentials", "username_taken", "rate_limited", "banned", "merge_blocked_banned",
			"account_gone", "provider_error", "cancelled", "email_unavailable", "last_identity", "signed_out"]:
		var text := AccountPanel.error_text(code)
		assert_false(text.contains("ACCOUNT_"), "%s has a text: %s" % [code, text])
	assert_string_contains(AccountPanel.error_text("something_new"), "something_new", "unknown codes still say something")
