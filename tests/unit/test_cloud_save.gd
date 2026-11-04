extends GutTest
## Cloud sync of the worlds (KF9, D-188, KONZEPT §10) against a fake API that behaves like KF8
## (revisions, 409 revision_conflict with the server state, archive, backups, pending account
## merges): uploads, downloads, merges without a dialog, first sync, free slots, deletions, offline,
## newer versions, a world changed while waiting, the [cloud] state in the save (migration) and the
## slot list. Works only in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_cloud_save"
const PLAYER := "11111111-2222-4333-8444-555555555555"
const OTHER_WORLD := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
const BACKUP_ID := "99999999-8888-4777-8666-555555555555"
const OLD := 1_760_000_000


## Answers like soulwick-api (routes of contracts world.ts), in memory.
class FakeWorldServer extends HttpTransport:
	## lower world id -> {revision, status, data, formatVersion, pendingMerges, backups: {id: data}}
	var worlds: Dictionary = {}
	var requests: Array[String] = []
	var bodies: Array = []
	var offline := false
	## Called before a request is answered (key "PUT /me/worlds/<id>", …): simulates another device.
	var before_answer: Callable = Callable()

	func send(_owner: Node, method: HTTPClient.Method, url: String, _headers: PackedStringArray, body: String, _timeout: float) -> Dictionary:
		if offline:
			return {"status": 0, "body": "", "error": ApiResult.UNREACHABLE}
		var path := url.substr(url.find("/", 8))
		var verb: String = ["GET", "HEAD", "POST", "PUT", "DELETE"][method]
		var key := "%s %s" % [verb, path]
		requests.append(key)
		var parsed: Variant = JSON.parse_string(body) if not body.is_empty() else null
		bodies.append(parsed)
		if before_answer.is_valid():
			before_answer.call(key)
		var parts := path.split("/", false)
		if parts.size() == 2:
			return _answer(200, {"items": _metas("active"), "archived": _metas("archived"), "maxWorlds": 3, "maxDataBytes": 65536})
		var world_id := parts[2].to_lower()
		if parts.size() == 5 and verb == "GET":
			var backups: Dictionary = worlds.get(world_id, {}).get("backups", {})
			if not backups.has(parts[4]):
				return _answer(404, {"error": "backup_not_found"})
			return _answer(200, {"id": parts[4], "worldId": world_id, "data": backups[parts[4]]})
		match verb:
			"GET":
				if not worlds.has(world_id):
					return _answer(404, {"error": "world_not_found"})
				return _answer(200, full(world_id))
			"PUT":
				return _put(world_id, parsed)
			"DELETE":
				if not worlds.has(world_id):
					return _answer(404, {"error": "world_not_found"})
				worlds[world_id]["status"] = "archived"
				return _answer(200, {"world": meta(world_id)})
		return _answer(404, {"error": "not_found"})

	func _put(world_id: String, body: Dictionary) -> Dictionary:
		var base := int(body.get("baseRevision", -1))
		if not worlds.has(world_id):
			if base != 0:
				return _answer(409, {"error": "revision_conflict", "world": null})
		elif int(worlds[world_id]["revision"]) != base:
			return _answer(409, {"error": "revision_conflict", "world": full(world_id)})
		var data: Dictionary = (body["data"] as Dictionary).duplicate(true)
		data.erase("cloud")
		if str(data.get("world", {}).get("id", "")).to_lower() != world_id:
			return _answer(400, {"error": "world_id_mismatch"})
		var created := not worlds.has(world_id)
		var entry: Dictionary = worlds.get(world_id, {"revision": 0, "backups": {}, "pendingMerges": []})
		entry["revision"] = int(entry["revision"]) + 1
		entry["status"] = "active"
		entry["data"] = JSON.parse_string(JSON.stringify(data))
		entry["formatVersion"] = int(body.get("formatVersion", 5))
		entry["summary"] = body.get("summary", {})
		for id: Variant in body.get("resolvedMerges", []):
			(entry["pendingMerges"] as Array).erase(id)
		if body.has("discarded"):
			entry["discarded"] = body["discarded"]
		worlds[world_id] = entry
		return _answer(201 if created else 200, {"world": meta(world_id), "archived": []})

	## Stores a state as if another device had uploaded it.
	func store(config: ConfigFile, revision := 1, status := "active") -> String:
		var data := SaveMerge.to_world_data(config)
		var world_id := String(config.get_value("world", "id")).to_lower()
		worlds[world_id] = {
			"revision": revision, "status": status, "data": JSON.parse_string(JSON.stringify(data)),
			"formatVersion": int(config.get_value("meta", "version", 5)), "pendingMerges": [], "backups": {},
			"summary": {"lastPlayedAt": CloudSave.iso_time(int(config.get_value("profile", "last_played", OLD)))},
		}
		return world_id

	func meta(world_id: String) -> Dictionary:
		var entry: Dictionary = worlds[world_id]
		return {
			"worldId": world_id, "revision": entry["revision"], "status": entry["status"], "source": "upload",
			"formatVersion": entry["formatVersion"], "pendingMerges": entry["pendingMerges"].duplicate(),
			"summary": entry.get("summary", {}),
		}

	func full(world_id: String) -> Dictionary:
		var result := meta(world_id)
		result["data"] = (worlds[world_id]["data"] as Dictionary).duplicate(true)
		return result

	func server_value(world_id: String, section: String, key: String) -> Variant:
		return worlds[world_id.to_lower()]["data"].get(section, {}).get(key, null)

	func _metas(status: String) -> Array:
		var result := []
		for world_id: String in worlds:
			if worlds[world_id]["status"] == status:
				result.append(meta(world_id))
		return result

	func count(prefix: String) -> int:
		var total := 0
		for request in requests:
			if request.begins_with(prefix):
				total += 1
		return total

	func _answer(status: int, body: Variant) -> Dictionary:
		return {"status": status, "body": JSON.stringify(body), "error": "", "headers": PackedStringArray()}


var _server: FakeWorldServer
var _api: ApiClient
var _old_locale: String
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	Loc.apply(&"de")
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path
	SaveManager.set_storage_root(ROOT)


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	CloudSave._running_since = 0
	CloudSave.last_report = {}
	_server = FakeWorldServer.new()
	_api = ApiClient.new()
	_api.base_url = "http://fake"
	_api.token = "test-token"
	_api.transport = _server
	add_child_autofree(_api)


func after_all() -> void:
	TranslationServer.set_locale(_old_locale)
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


func _sync() -> Dictionary:
	return await CloudSave.new(_api, PLAYER).sync_all()


## A fresh world in a slot with some gold, saved (and loaded).
func _world(slot: int, gold := 10) -> String:
	assert_eq(SaveManager.create_slot(slot, "Welt %d" % slot), OK)
	SaveManager.add_permanent_gold(gold)
	SaveManager.save_game()
	return SaveManager.get_world_id()


## The server's copy of a world as a config, changed by another device (played later than now).
func _other_device(world_id: String, changes: Dictionary, played_later := true) -> void:
	var config := SaveMerge.from_world_data(_server.full(world_id.to_lower())["data"])
	for path: String in changes:
		var cut := path.find("/")
		config.set_value(path.left(cut), path.substr(cut + 1), changes[path])
	var played := int(Time.get_unix_time_from_system()) + (100 if played_later else -100000)
	config.set_value("profile", "last_played", played)
	var entry: Dictionary = _server.worlds[world_id.to_lower()]
	entry["data"] = JSON.parse_string(JSON.stringify(SaveMerge.to_world_data(config)))
	entry["revision"] = int(entry["revision"]) + 1


# --- Uploads ---

func test_a_new_local_world_is_uploaded() -> void:
	var world_id := _world(1, 25)
	var report := await _sync()
	assert_true(report["ok"], "sync ok: %s" % report["error"])
	assert_eq(report["uploaded"], 1)
	assert_eq(_server.worlds[world_id]["revision"], 1)
	var body: Dictionary = _server.bodies[_server.requests.find("PUT /me/worlds/%s" % world_id)]
	assert_eq(int(body["baseRevision"]), 0, "new on this account")
	assert_eq(int(body["formatVersion"]), SaveManager.SAVE_VERSION)
	assert_eq(body["data"]["world"]["id"], world_id)
	assert_false(body["data"].has("cloud"), "[cloud] stays on the device")
	assert_eq(body["summary"]["name"], "", "the default name is no own name (contract: \"\" = Welt <n>)")
	assert_true(str(body["summary"]["lastPlayedAt"]).ends_with("Z"))
	assert_eq(int(_server.server_value(world_id, "progress", "permanent_gold")), 25)
	var cloud := SaveManager.get_cloud_state(1)
	assert_eq(cloud["base_revision"], 1)
	assert_eq(cloud["player_id"], PLAYER)
	assert_false(SaveManager.get_slot_summary(1)["cloud_dirty"])


func test_an_unchanged_world_is_not_uploaded_again() -> void:
	_world(1)
	await _sync()
	var report := await _sync()
	assert_eq(report["unchanged"], 1)
	assert_eq(_server.count("PUT"), 1, "only the first sync uploaded")


func test_a_local_change_goes_up_on_its_base_revision() -> void:
	var world_id := _world(1, 10)
	await _sync()
	SaveManager.add_permanent_gold(5)
	SaveManager.save_game()
	assert_true(SaveManager.get_slot_summary(1)["cloud_dirty"], "the card says it is not in the cloud yet")
	var report := await _sync()
	assert_eq(report["uploaded"], 1)
	assert_eq(int(_server.bodies.back()["baseRevision"]), 1)
	assert_eq(_server.worlds[world_id]["revision"], 2)
	assert_eq(int(_server.server_value(world_id, "progress", "permanent_gold")), 15)


func test_saving_without_a_change_is_not_a_change() -> void:
	_world(1)
	await _sync()
	SaveManager.save_game()
	assert_false(SaveManager.get_slot_summary(1)["cloud_dirty"], "last_played alone does not count")


# --- Downloads and merges ---

func test_a_cloud_change_is_downloaded() -> void:
	var world_id := _world(1, 10)
	await _sync()
	_other_device(world_id, {"progress/permanent_gold": 999})
	var report := await _sync()
	assert_eq(report["downloaded"], 1)
	assert_eq(_server.count("PUT"), 1, "nothing new to upload")
	assert_eq(SaveManager.get_permanent_gold(), 999, "the loaded world has it at once")
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 2)
	var file := ConfigFile.new()
	file.load(SaveManager.slot_path(1))
	assert_eq(file.get_value("progress", "permanent_gold"), 999)


func test_changes_on_both_sides_are_merged_without_a_dialog() -> void:
	var world_id := _world(1, 100)
	await _sync()
	_other_device(world_id, {"stats/deepest_room": 40, "progress/permanent_gold": 7}, false)
	SaveManager.set_meta_level(&"smith_sword", 2)
	SaveManager.try_spend_permanent_gold(60)
	SaveManager.save_game()
	var report := await _sync()
	assert_eq(report["merged"], 1)
	assert_eq(SaveManager.get_stat(&"deepest_room"), 40, "record of the other device")
	assert_eq(SaveManager.get_meta_level(&"smith_sword"), 2, "forge level of this device")
	assert_eq(SaveManager.get_permanent_gold(), 40, "gold of the state played last (this one)")
	var body: Dictionary = _server.bodies.back()
	assert_eq(int(body["baseRevision"]), 2)
	assert_eq(body["discarded"], {"side": "server"}, "the server's gold lost: kept as a backup there")
	assert_eq(int(_server.server_value(world_id, "stats", "deepest_room")), 40)
	assert_eq(int(_server.server_value(world_id, "meta_upgrades", "smith_sword")), 2)
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 3)
	assert_false(SaveManager.get_slot_summary(1)["cloud_dirty"])


func test_a_newer_cloud_state_wins_the_last_played_fields() -> void:
	var world_id := _world(1, 100)
	await _sync()
	_other_device(world_id, {"progress/permanent_gold": 3, "world/name": "Andere"})
	SaveManager.set_meta_level(&"lantern", 1)
	_save_keeping_time()
	await _sync()
	assert_eq(SaveManager.get_permanent_gold(), 3)
	assert_eq(SaveManager.get_world_name(), "Andere")
	assert_eq(SaveManager.get_meta_level(&"lantern"), 1)
	var body: Dictionary = _server.bodies.back()
	assert_eq(body["discarded"]["side"], "local", "this device's state is kept as a backup")
	assert_eq(int(body["discarded"]["data"]["progress"]["permanent_gold"]), 100)


func test_a_conflict_merges_again_with_the_new_server_state() -> void:
	var world_id := _world(1, 10)
	await _sync()
	SaveManager.add_stat(&"kills", 3)
	SaveManager.set_meta_level(&"smith_bow", 1)
	SaveManager.save_game()
	var moved := [false]
	_server.before_answer = func(key: String) -> void:
		if key.begins_with("PUT") and not moved[0]:
			moved[0] = true
			_other_device(world_id, {"stats/kills": 500}, false)
	var report := await _sync()
	assert_eq(report["merged"], 1, "merged after the 409")
	assert_eq(_server.count("PUT"), 3, "first upload, refused one, merged one")
	assert_eq(SaveManager.get_stat(&"kills"), 500)
	assert_eq(SaveManager.get_meta_level(&"smith_bow"), 1)
	assert_eq(_server.worlds[world_id]["revision"], 3)
	assert_eq(int(_server.server_value(world_id, "meta_upgrades", "smith_bow")), 1)


func test_first_sync_merges_a_world_the_account_already_has() -> void:
	var world_id := _world(1, 10)
	SaveManager.record_stat_max(&"deepest_room", 5)
	SaveManager.save_game()
	var other := SaveManager.read_world_config(1)
	other.set_value("stats", "deepest_room", 30)
	other.set_value("profile", "last_played", OLD)
	_server.store(other, 4)
	SaveManager.set_meta_level(&"shield_plate", 1)
	SaveManager.save_game()
	var report := await _sync()
	assert_eq(report["merged"], 1)
	assert_eq(int(_server.bodies.back()["baseRevision"]), 4, "never synced here: merged on the server's revision")
	assert_eq(SaveManager.get_stat(&"deepest_room"), 30)
	assert_eq(SaveManager.get_meta_level(&"shield_plate"), 1)
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 5)
	assert_eq(world_id, SaveManager.get_world_id())


func test_a_lower_record_here_just_takes_the_cloud_state() -> void:
	_world(1, 10)
	var other := SaveManager.read_world_config(1)
	other.set_value("stats", "deepest_room", 30)
	other.set_value("profile", "last_played", OLD)
	_server.store(other, 4)
	var report := await _sync()
	assert_eq(report["downloaded"], 1, "the cloud state already has everything of this one")
	assert_eq(_server.count("PUT"), 0)
	assert_eq(SaveManager.get_stat(&"deepest_room"), 30)
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 4)


func test_another_account_counts_as_a_first_sync() -> void:
	var world_id := _world(1, 10)
	await _sync()
	var other_api := CloudSave.new(_api, "22222222-3333-4444-8555-666666666666")
	_server.worlds.clear()
	var report: Dictionary = await other_api.sync_all()
	assert_eq(report["uploaded"], 1, "the world goes into the new account")
	assert_eq(int(_server.bodies.back()["baseRevision"]), 0)
	assert_true(_server.worlds.has(world_id))


func test_pending_account_merges_are_merged_in_and_resolved() -> void:
	var world_id := _world(1, 10)
	await _sync()
	var backup := SaveManager.read_world_config(1)
	backup.set_value("stats", "deepest_room", 70)
	backup.set_value("profile", "last_played", OLD)
	_server.worlds[world_id]["backups"][BACKUP_ID] = JSON.parse_string(JSON.stringify(SaveMerge.to_world_data(backup)))
	_server.worlds[world_id]["pendingMerges"] = [BACKUP_ID]
	var report := await _sync()
	assert_eq(report["merged"], 1)
	assert_eq(_server.bodies.back()["resolvedMerges"], [BACKUP_ID])
	assert_eq(SaveManager.get_stat(&"deepest_room"), 70)
	assert_eq(_server.worlds[world_id]["pendingMerges"], [])


# --- New cloud worlds, deletions ---

func test_a_cloud_world_goes_into_a_free_slot() -> void:
	_world(1)
	_server.store(_cloud_world("Aus der Cloud", 33), 2)
	var report := await _sync()
	assert_eq(report["downloaded"], 1)
	assert_true(SaveManager.has_slot(2))
	var summary := SaveManager.get_slot_summary(2)
	assert_eq(summary["name"], "Aus der Cloud")
	assert_eq(summary["gold"], 33)
	assert_eq(summary["world_id"], OTHER_WORLD)
	assert_eq(summary["cloud_revision"], 2)
	assert_false(summary["cloud_dirty"])
	assert_eq(SaveManager.get_active_slot(), 1, "the loaded world stays loaded")
	assert_eq(CloudSave.report_text(report), "Cloud: 1 Welt gesichert · 1 Welt aus dem Konto geladen")


func test_without_a_free_slot_the_cloud_world_stays_there() -> void:
	for slot in [1, 2, 3]:
		_world(slot)
	_server.store(_cloud_world("Zu viel", 1))
	var report := await _sync()
	assert_eq(report["no_room"], 1)
	assert_eq(report["uploaded"], 3)
	assert_true(CloudSave.report_text(report).contains("1 weitere in der Cloud, kein Platz frei"))


func test_archived_cloud_worlds_are_not_downloaded() -> void:
	_server.store(_cloud_world("Archiv", 1), 1, "archived")
	var report := await _sync()
	assert_eq(report["downloaded"], 0)
	assert_false(SaveManager.has_slot(1))


func test_a_deleted_world_goes_to_the_cloud_archive() -> void:
	var world_id := _world(1)
	_world(2)
	await _sync()
	assert_eq(SaveManager.delete_slot(1), OK)
	assert_eq(SaveManager.get_deleted_world_ids(), PackedStringArray([world_id]))
	await _sync()
	assert_eq(_server.count("DELETE /me/worlds/%s" % world_id), 1)
	assert_eq(_server.worlds[world_id]["status"], "archived")
	assert_true(SaveManager.get_deleted_world_ids().is_empty())
	assert_false(SaveManager.has_slot(1), "not downloaded again")


func test_a_never_synced_deleted_world_sends_nothing() -> void:
	_world(1)
	SaveManager.delete_slot(1)
	assert_true(SaveManager.get_deleted_world_ids().is_empty())


# --- Failures ---

func test_offline_changes_nothing() -> void:
	_world(1, 10)
	var before := FileAccess.get_file_as_string(SaveManager.slot_path(1))
	_server.offline = true
	var report := await _sync()
	assert_false(report["ok"])
	assert_eq(report["error"], ApiResult.UNREACHABLE)
	assert_eq(FileAccess.get_file_as_string(SaveManager.slot_path(1)), before)
	assert_eq(CloudSave.report_text(report), "Cloud: offline – deine Welten bleiben auf dem Gerät")


func test_without_a_login_nothing_is_sent() -> void:
	_api.token = ""
	var report := await _sync()
	assert_eq(report["error"], ApiResult.UNAUTHORIZED)
	assert_true(_server.requests.is_empty())


func test_a_cloud_world_of_a_newer_game_is_left_alone() -> void:
	var world_id := _world(1, 10)
	await _sync()
	_other_device(world_id, {"progress/permanent_gold": 1})
	_server.worlds[world_id]["formatVersion"] = SaveManager.SAVE_VERSION + 1
	_server.worlds[world_id]["data"]["meta"]["version"] = SaveManager.SAVE_VERSION + 1
	var report := await _sync()
	assert_eq(report["newer"], 1)
	assert_eq(SaveManager.get_permanent_gold(), 10)
	assert_true(CloudSave.report_text(report).contains("Spiel-Update"))


func test_a_world_changed_while_waiting_is_not_overwritten() -> void:
	var world_id := _world(1, 10)
	await _sync()
	_other_device(world_id, {"stats/deepest_room": 40}, false)
	SaveManager.set_meta_level(&"lantern", 1)
	SaveManager.save_game()
	_server.before_answer = func(key: String) -> void:
		if key.begins_with("PUT"):
			SaveManager.add_permanent_gold(5)
	var report := await _sync()
	assert_eq(report["busy"], 1)
	assert_eq(SaveManager.get_permanent_gold(), 15, "the player's change while waiting stays")
	assert_eq(SaveManager.get_stat(&"deepest_room"), 0, "not written over it")
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 1, "the old base: next sync merges again")
	_server.before_answer = Callable()
	report = await _sync()
	assert_eq(report["merged"], 1)
	assert_eq(SaveManager.get_stat(&"deepest_room"), 40)
	assert_eq(SaveManager.get_permanent_gold(), 15)
	assert_eq(SaveManager.get_meta_level(&"lantern"), 1)


func test_a_second_sync_does_not_start_while_one_runs() -> void:
	CloudSave._running_since = int(Time.get_unix_time_from_system())
	var report := await _sync()
	assert_eq(report["error"], CloudSave.ALREADY_RUNNING)
	assert_true(_server.requests.is_empty())


func test_automatic_sync_is_off_in_script_runs() -> void:
	assert_false(CloudSave.auto_sync_enabled, "tests and tools never upload a world by themselves")
	assert_false(CloudSave.is_due())


# --- The save: [cloud], export and import (ROADMAP rule 4) ---

func test_v4_world_gets_its_id_once_and_cloud_defaults() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("saves")))
	var file := FileAccess.open(SaveManager.slot_path(2), FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v4_real.cfg"))
	file.close()
	var first := SaveManager.read_world_config(2)
	assert_not_null(first)
	var world_id := String(first.get_value("world", "id"))
	assert_true(SaveManager.is_valid_world_id(world_id))
	assert_eq(String(SaveManager.read_world_config(2).get_value("world", "id")), world_id, "the id is written once")
	assert_true(FileAccess.file_exists(SaveManager.slot_path(2) + ".v4.bak"), "the old file is kept")
	assert_eq(SaveManager.get_cloud_state(2), SaveManager.CLOUD_DEFAULTS, "never synced")


func test_v5_without_cloud_section_loads_as_never_synced() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("saves")))
	var file := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	file.store_string("[meta]\nversion=5\n[progress]\npermanent_gold=4\n[world]\nid=\"%s\"\n" % OTHER_WORLD)
	file.close()
	assert_eq(SaveManager.load_slot(1), OK)
	assert_eq(SaveManager.get_cloud_state(), SaveManager.CLOUD_DEFAULTS)
	SaveManager.save_game()
	var saved := ConfigFile.new()
	saved.load(SaveManager.slot_path(1))
	assert_eq(saved.get_value("cloud", "base_revision"), 0)
	assert_eq(saved.get_value("meta", "version"), SaveManager.SAVE_VERSION, "no new save version")


func test_export_leaves_out_cloud_and_import_keeps_last_played() -> void:
	var world_id := _world(1, 10)
	SaveManager.set_cloud_state({"base_revision": 3, "synced_hash": "x", "player_id": PLAYER, "synced_at": 5})
	var data := SaveManager.export_world()
	assert_false(data.has("cloud"))
	assert_eq(data["world"]["id"], world_id)
	data["progress"]["permanent_gold"] = 77
	data["profile"]["last_played"] = OLD
	assert_eq(SaveManager.import_world(JSON.parse_string(JSON.stringify(data)), 1), OK)
	assert_eq(SaveManager.get_permanent_gold(), 77)
	assert_eq(SaveManager.get_last_played(), OLD, "an imported state is not stamped as played now")
	assert_eq(SaveManager.get_cloud_state(1)["base_revision"], 3, "an empty cloud argument keeps [cloud]")


func test_import_refuses_another_world_and_newer_versions() -> void:
	_world(1)
	var foreign := SaveMerge.to_world_data(_cloud_world("Fremd", 1))
	assert_eq(SaveManager.import_world(foreign, 1), ERR_INVALID_PARAMETER)
	var newer := SaveManager.export_world()
	newer["meta"]["version"] = SaveManager.SAVE_VERSION + 1
	assert_eq(SaveManager.import_world(newer, 1), ERR_FILE_UNRECOGNIZED)
	var broken := SaveManager.export_world()
	broken["progress"]["permanent_gold"] = -5
	assert_eq(SaveManager.import_world(broken, 1), ERR_INVALID_DATA)


# --- The slot list ---

func test_slot_cards_show_the_cloud_state() -> void:
	_world(1)
	_world(2)
	SaveManager.load_slot(1)
	await _sync()
	SaveManager.add_permanent_gold(1)
	SaveManager.save_game()
	var panel := SlotPanel.new()
	add_child_autofree(panel)
	var tag_1 := panel.find_child("CloudTag", true, false) as Label
	assert_not_null(tag_1)
	var texts := PackedStringArray()
	for node in panel.find_children("CloudTag", "Label", true, false):
		texts.append(tr((node as Label).text))
	assert_has(texts, "Cloud: noch offen", "slot 1 changed since the sync")
	assert_has(texts, "in der Cloud", "slot 2 is up to date")
	var line := panel.find_child("CloudLine", true, false) as Label
	assert_true(line.visible)
	assert_eq(line.text, "Cloud: 2 Welten gesichert")


## A v5 world of another device (OTHER_WORLD).
func _cloud_world(world_name: String, gold: int) -> ConfigFile:
	var config := ConfigFile.new()
	# A world of the current version (a downloaded older one is migrated and goes up again once).
	config.parse("[meta]\nversion=%d\n[progress]\npermanent_gold=%d\nunlocked=PackedStringArray()\n[world]\nid=\"%s\"\nname=\"%s\"\n[profile]\ncreated=%d\nlast_played=%d\n[seen]\nall=false\nids=PackedStringArray()\n" % [SaveManager.SAVE_VERSION, gold, OTHER_WORLD, world_name, OLD, OLD])
	return config


## Saves the loaded world without making it the state played last (another device was later).
func _save_keeping_time() -> void:
	var cloud := SaveManager.get_cloud_state()
	SaveManager.set_cloud_state(cloud)
