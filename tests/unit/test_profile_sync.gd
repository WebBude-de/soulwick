extends GutTest
## D-152 online: the account profile at login and on change (OnlineSession against a fake HTTP
## layer, no network). The login sends name and look; the server's profile wins when nothing changed
## here; changes go up with PATCH /me; a refused name change (429 name_change_limited) keeps the
## server's name, sends the look alone and tells when the name can change again. Test files only.

const ONLINE_PATH := "user://test_profile_sync_online.cfg"
const PROFILE_PATH := "user://test_profile_sync_profile.cfg"
const TOKEN := "session-token.c2lnbmF0dXJl"
const PLAYER_ID := "6f1c3a52-6a0e-4a3b-9a55-1c2d3e4f5a6b"


## Answers from a queue keyed by "METHOD path" (PATCH included); records every request.
class FakeTransport extends HttpTransport:
	var answers: Dictionary = {}
	var requests: Array[Dictionary] = []

	func send(_owner: Node, method: HTTPClient.Method, url: String, headers: PackedStringArray, body: String, timeout: float) -> Dictionary:
		var path := url.substr(url.find("/", 8))
		var names := {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST", HTTPClient.METHOD_PATCH: "PATCH", HTTPClient.METHOD_DELETE: "DELETE"}
		var key := "%s %s" % [names.get(method, str(method)), path]
		requests.append({"key": key, "url": url, "headers": headers, "body": body, "timeout": timeout})
		var queue: Array = answers.get(key, [])
		if queue.is_empty():
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		return queue.pop_front()

	func answer(key: String, status: int, body: Variant, headers := PackedStringArray()) -> void:
		if not answers.has(key):
			answers[key] = []
		answers[key].append({"status": status, "body": JSON.stringify(body) if body != null else "", "error": "", "headers": headers})

	func bodies(key: String) -> Array:
		var result := []
		for request in requests:
			if request.key == key:
				result.append(JSON.parse_string(request.body))
		return result


var _fake: FakeTransport
var _old_sync := true
var _old_locale := ""


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	_old_sync = OnlineSession.profile_sync_enabled
	OnlineSession.profile_sync_enabled = true
	PlayerProfile.path_override = PROFILE_PATH


func before_each() -> void:
	for path in [ONLINE_PATH, PROFILE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	PlayerProfile.reset()
	_fake = FakeTransport.new()


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
	OnlineSession.profile_sync_enabled = _old_sync
	for path in [ONLINE_PATH, PROFILE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	PlayerProfile.path_override = ""
	PlayerProfile.reset()


func _self(player_name: String, appearance: Variant = null) -> Dictionary:
	return {"id": PLAYER_ID, "name": player_name, "steamId": null, "createdAt": "2026-10-16T10:00:00.000Z", "guild": null, "guilds": [], "appearance": appearance}


func _session(server_self: Dictionary) -> OnlineSession:
	_fake.answer("POST /auth/device", 200, {"token": TOKEN, "expiresAt": "2099-01-01T00:00:00.000Z", "player": server_self})
	_fake.answer("GET /public/config", 200, {"apiVersion": "1.1.0", "minGameVersion": null, "protocolVersion": 1, "relayUrl": null})
	var config := OnlineConfig.new()
	config.path = ONLINE_PATH
	config.settings_path = ONLINE_PATH
	config.load_from({"api": "http://api.test"})
	var client := ApiClient.new()
	client.transport = _fake
	client.base_url = "http://api.test"
	var session := OnlineSession.new(config)
	session.api = client
	add_child_autofree(session)
	return session


func _set_up(player_name: String, look: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.current()
	profile.complete_setup(player_name, look)
	return profile


func test_login_sends_name_and_look_of_the_profile() -> void:
	var look := PlayerLook.default_look(&"frost")
	_set_up("Lumen", look)
	var session := _session(_self("Lumen", look))
	_fake.answer("PATCH /me", 200, _self("Lumen", look))
	assert_true((await session.ensure_login()).ok)
	var login: Dictionary = _fake.bodies("POST /auth/device")[0]
	assert_eq(login.get("name"), "Lumen")
	assert_eq(PlayerLook.normalize(login.get("appearance")), look, "the look goes along (used when the account is created)")
	assert_eq(PlayerProfile.current().synced_player_id, PLAYER_ID)


func test_without_a_profile_the_server_profile_is_taken() -> void:
	var server_look := PlayerLook.default_look(&"moss")
	var session := _session(_self("Docht", server_look))
	assert_true((await session.ensure_login()).ok)
	assert_false(_fake.bodies("POST /auth/device")[0].has("appearance"), "nothing chosen yet: no look sent")
	var profile := PlayerProfile.current()
	assert_false(profile.needs_setup(), "the account already has a profile")
	assert_eq(profile.player_name, "Docht")
	assert_eq(profile.look, server_look)
	assert_eq(_fake.bodies("PATCH /me").size(), 0)


func test_server_wins_when_nothing_changed_here() -> void:
	var profile := _set_up("Kerze", PlayerLook.default_look())
	profile.mark_synced(PLAYER_ID, true, true)
	var server_look := PlayerLook.default_look(&"ember")
	var session := _session(_self("Glut", server_look))
	assert_true((await session.ensure_login()).ok)
	assert_eq(PlayerProfile.current().player_name, "Glut", "changed on another device")
	assert_eq(PlayerProfile.current().look, server_look)
	assert_eq(_fake.bodies("PATCH /me").size(), 0, "nothing sent")


func test_local_changes_go_up_with_patch_me() -> void:
	var profile := _set_up("Kerze", PlayerLook.default_look())
	profile.mark_synced(PLAYER_ID, true, true)
	profile.set_player_name("Flamme")
	var session := _session(_self("Kerze", PlayerLook.default_look()))
	_fake.answer("PATCH /me", 200, _self("Flamme", PlayerLook.default_look()))
	assert_true((await session.ensure_login()).ok)
	var patches := _fake.bodies("PATCH /me")
	assert_eq(patches.size(), 1)
	assert_eq(patches[0], {"name": "Flamme"}, "only what changed")
	assert_false(PlayerProfile.current().name_dirty)
	assert_eq(session.get_player_name(), "Flamme", "PlayerSelf of the answer")
	# A look change in the lobby.
	PlayerProfile.current().set_color(PlayerLook.OUTFIT, 4)
	_fake.answer("PATCH /me", 200, _self("Flamme", PlayerProfile.current().look))
	var result := await session.push_profile()
	assert_true(result.ok, result.describe())
	assert_eq(_fake.bodies("PATCH /me")[1].keys(), ["appearance"])
	assert_eq(OnlineSession.profile_hint(result), "")
	assert_false(PlayerProfile.current().look_dirty)


func test_name_change_limit_keeps_the_server_name_and_sends_the_look_alone() -> void:
	var profile := _set_up("Kerze", PlayerLook.default_look())
	profile.mark_synced(PLAYER_ID, true, true)
	var session := _session(_self("Kerze", PlayerLook.default_look()))
	assert_true((await session.ensure_login()).ok)
	profile = PlayerProfile.current()
	profile.set_player_name("Neuer Name")
	profile.set_color(PlayerLook.HAIR, 2)
	_fake.answer("PATCH /me", 429, {"error": "name_change_limited", "message": "Too many name changes", "retryAfter": 7000},
			PackedStringArray(["Retry-After: 7000"]))
	_fake.answer("PATCH /me", 200, _self("Kerze", profile.look))
	var result := await session.push_profile()
	assert_false(result.ok)
	assert_eq(result.error, OnlineSession.NAME_CHANGE_LIMITED)
	var patches := _fake.bodies("PATCH /me")
	assert_eq(patches.size(), 2, "refused, then the look alone")
	assert_true(patches[0].has("name") and patches[0].has("appearance"))
	assert_eq(patches[1].keys(), ["appearance"])
	assert_eq(profile.player_name, "Kerze", "the server's name stays")
	assert_false(profile.name_dirty or profile.look_dirty)
	assert_eq(PlayerLook.get_index(profile.look, PlayerLook.HAIR), 2, "the look is kept and sent")
	Loc.apply(&"de")
	assert_eq(OnlineSession.profile_hint(result), "Namen kannst du in 2 h wieder ändern.")
	# Asking again within the limit sends nothing for the name.
	profile.set_player_name("Noch einer")
	var again := await session.push_profile()
	assert_eq(again.error, OnlineSession.NAME_CHANGE_LIMITED)
	assert_eq(_fake.bodies("PATCH /me").size(), 2, "no request while the limit is known")
	assert_eq(profile.player_name, "Kerze")


func test_hints_for_the_player() -> void:
	Loc.apply(&"de")
	var limited := ApiResult.failure(OnlineSession.NAME_CHANGE_LIMITED, "", 429, {"retryAfter": 120})
	assert_eq(OnlineSession.profile_hint(limited), "Namen kannst du in 2 min wieder ändern.", "seconds from the body")
	assert_eq(OnlineSession.profile_hint(ApiResult.failure(OnlineSession.VALIDATION_ERROR, "", 400)), "Diesen Namen nimmt der Server nicht an.")
	assert_string_contains(OnlineSession.profile_hint(ApiResult.failure(ApiResult.UNREACHABLE)), "nächsten Anmeldung")
