extends GutTest
## KF9, optional: CloudSave with the real ApiClient (HTTPRequest) against a running soulwick-api
## with the cloud worlds of KF8. Skipped (pending) unless the environment names one, e.g.
##   SOULWICK_TEST_API=http://localhost:3102
## or when it does not answer. Logs in as a fresh guest (random device id: a new test account every
## run), plays two devices in a test folder (SaveManager.set_storage_root), never the real save, and
## deletes its cloud world at the end.

const ROOT := "user://test_cloud_save_live"

var _api_url := ""
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_api_url = OS.get_environment("SOULWICK_TEST_API")
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.set_storage_root(ROOT)


func after_all() -> void:
	_wipe()
	CloudSave.last_report = {}
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.remove_absolute(root.path_join("saves"))
	DirAccess.make_dir_recursive_absolute(root)


## A fresh device: empty test folder.
func _new_device() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	CloudSave._running_since = 0


func test_two_devices_share_a_world_through_the_api() -> void:
	if _api_url.is_empty():
		pending("SOULWICK_TEST_API not set")
		return
	var api := ApiClient.new()
	api.base_url = _api_url
	add_child_autofree(api)
	var health := await api.get_health()
	if not health.ok:
		pending("API %s not reachable (%s)" % [_api_url, health.describe()])
		return
	var login := await api.login_device("KF9 Test", OnlineConfig.generate_uuid())
	assert_true(login.ok, login.describe())
	if not login.ok:
		return
	api.token = str(login.get_field("token", ""))
	var player_id := str((login.get_field("player", {}) as Dictionary).get("id", ""))
	var cloud := CloudSave.new(api, player_id)

	# Device A: a new world goes up.
	_new_device()
	assert_eq(SaveManager.create_slot(1, "Live"), OK)
	SaveManager.add_permanent_gold(40)
	SaveManager.record_stat_max(&"deepest_room", 12)
	SaveManager.save_game()
	var world_id := SaveManager.get_world_id()
	var device_a := FileAccess.get_file_as_string(SaveManager.slot_path(1))
	var report: Dictionary = await cloud.sync_all()
	assert_eq(report["uploaded"], 1, "device A uploads: %s" % str(report))

	# Device B (new install): the world comes down, then B buys a forge level.
	_new_device()
	report = await cloud.sync_all()
	assert_eq(report["downloaded"], 1, "device B downloads: %s" % str(report))
	assert_eq(SaveManager.get_slot_summary(1)["world_id"], world_id)
	assert_eq(SaveManager.load_slot(1), OK)
	assert_eq(SaveManager.get_permanent_gold(), 40)
	SaveManager.set_meta_level(&"smith_sword", 1)
	SaveManager.try_spend_permanent_gold(30)
	SaveManager.save_game()
	report = await cloud.sync_all()
	assert_eq(report["uploaded"], 1, "device B uploads its change: %s" % str(report))

	# Device A again, offline meanwhile: a deeper record, synced on its old base -> merged.
	_new_device()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveManager.saves_dir))
	var file := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	file.store_string(device_a)
	file.close()
	assert_eq(SaveManager.load_slot(1), OK)
	SaveManager.record_stat_max(&"deepest_room", 33)
	SaveManager.save_game()
	report = await cloud.sync_all()
	assert_eq(report["merged"], 1, "device A merges: %s" % str(report))
	assert_eq(SaveManager.get_stat(&"deepest_room"), 33)
	assert_eq(SaveManager.get_meta_level(&"smith_sword"), 1, "B's forge level")
	assert_eq(SaveManager.get_permanent_gold(), 40, "gold of the state played last (A)")
	var server := await api.request(HTTPClient.METHOD_GET, CloudSave.world_path(world_id))
	assert_true(server.ok, server.describe())
	if server.ok:
		assert_eq(int(server.data["revision"]), 3)
		assert_eq(int(server.data["data"]["stats"]["deepest_room"]), 33)
		assert_eq(int(server.data["data"]["meta_upgrades"]["smith_sword"]), 1)
		assert_eq(int(server.data["backupCount"]), 1, "B's gold is kept as a backup")
	report = await cloud.sync_all()
	assert_eq(report["unchanged"], 1, "nothing left to do")

	var removed := await api.request(HTTPClient.METHOD_DELETE, CloudSave.world_path(world_id) + "?permanent=true")
	assert_true(removed.ok or removed.status == 204, removed.describe())
