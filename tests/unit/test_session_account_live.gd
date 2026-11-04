extends GutTest
## KF6 live test against a running soulwick-api (local platform): signing in with username and
## password (dev seed "lumen"), keeping this test device on the account, the logins, a web login
## request (user code, browser secret only in the url's fragment), securing a fresh guest with a
## password and deleting that guest again. Runs only with SOULWICK_TEST_API (e.g.
## http://localhost:3102); never against the real online.cfg or save (own files, no cloud sync).

const TEST_PATH := "user://test_session_account_live_online.cfg"
const SAVE_PATH := "user://test_session_account_live_save.cfg"
const LUMEN := "lumen"
const LUMEN_PASSWORD := "soulwick-player-local"

var _api_url := ""
var _old_save_path: String


func before_all() -> void:
	_api_url = OS.get_environment("SOULWICK_TEST_API")
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH


func after_all() -> void:
	_remove_files()
	SaveManager.save_path = _old_save_path


func before_each() -> void:
	_remove_files()


func _remove_files() -> void:
	for path in [TEST_PATH, SAVE_PATH, TEST_PATH.get_basename() + OnlineSession.LOGIN_FILE_SUFFIX]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _service() -> AccountService:
	var config := OnlineConfig.new()
	config.path = TEST_PATH
	config.settings_path = TEST_PATH
	config.load_from({"api": _api_url})
	var session := OnlineSession.new(config)
	add_child_autofree(session)
	var service := AccountService.new(session)
	service.web.url_opener = func(_url: String) -> void: pass
	return service


func test_password_sign_in_keeps_the_device() -> void:
	if _api_url.is_empty():
		pending("SOULWICK_TEST_API not set")
		return
	var service := _service()
	await service.refresh()
	if not service.has_password_login():
		pending("the API offers no password login")
		return
	var result: ApiResult = await service.sign_in_with_password("Lumen", LUMEN_PASSWORD)
	assert_true(result.ok, result.describe())
	assert_true(service.session.is_logged_in())
	assert_eq(service.session.login_kind, OnlineSession.LOGIN_DEVICE, "this test device is on the account now")
	assert_eq(service.get_state(), AccountService.State.SECURED)
	assert_eq(service.password_username(), LUMEN)
	var groups := service.login_groups()
	var this_device := false
	for group in groups:
		this_device = this_device or bool(group["this_device"])
	assert_true(this_device, "the device is recognised in the list")
	# Leave lumen as it was: take this test device off again (the password stays).
	var removed: ApiResult = await service.remove_login("device")
	assert_true(removed.ok, removed.describe())


func test_web_login_request_follows_the_contract() -> void:
	if _api_url.is_empty():
		pending("SOULWICK_TEST_API not set")
		return
	var service := _service()
	await service.refresh()
	var opened: Array[String] = []
	service.web.url_opener = func(url: String) -> void: opened.append(url)
	var result: ApiResult = await service.web.start(ApiClient.WEB_SIGN_IN)
	assert_true(result.ok, result.describe())
	assert_eq(service.web.display_code().length(), 7, "user code ABC-DEF")
	assert_false(service.web.url.contains("#"), "the shown page has no fragment")
	assert_eq(opened.size(), 1)
	assert_eq(opened[0].count("#k="), 1)
	assert_eq(await service.web.poll(), WebLoginFlow.Status.WAITING, "pending until the browser signs in")
	service.web.cancel()


func test_a_fresh_guest_is_secured_with_a_password_and_deleted() -> void:
	if _api_url.is_empty():
		pending("SOULWICK_TEST_API not set")
		return
	var service := _service()
	await service.refresh()
	if not service.has_password_login() or not service.session.public_config.get("guestAuth", false):
		pending("the API offers no guest or password login")
		return
	var username := "kf6-test-%d" % (Time.get_ticks_usec() % 1_000_000)
	var saved: ApiResult = await service.save_password_login(username, "kf6-test-password")
	assert_true(saved.ok, saved.describe())
	assert_eq(service.get_state(), AccountService.State.SECURED)
	assert_eq(service.password_username(), username)
	var code: ApiResult = await service.create_deletion_code()
	assert_true(code.ok, code.describe())
	var deleted: ApiResult = await service.delete_account()
	assert_true(deleted.ok, deleted.describe())
	assert_false(service.session.is_logged_in())
