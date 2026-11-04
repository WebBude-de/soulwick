extends GutTest
## KF6: backups and archive of the cloud worlds from the account panel (KF8 routes, contract
## world.ts): a restored backup replaces the local world of the same id, an archived world comes back
## into a free slot (and is no longer "deleted here"), no free slot keeps it in the cloud, three
## active worlds answer 409 world_limit_reached until one goes to the archive, never during a run in
## that slot. Works only in a test folder (SaveManager.set_storage_root), never on the real save.

const ROOT := "user://test_cloud_save_backups"
const PLAYER := "11111111-2222-4333-8444-555555555555"
const BACKUP_ID := "99999999-8888-4777-8666-555555555555"

const FakeTransport := preload("res://tests/unit/test_session_account.gd").FakeTransport

var _fake
var _api: ApiClient
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
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
	_fake = FakeTransport.new()
	_api = ApiClient.new()
	_api.base_url = "http://fake"
	_api.token = "test-token"
	_api.transport = _fake
	add_child_autofree(_api)


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


func _cloud() -> CloudSave:
	return CloudSave.new(_api, PLAYER)


func _world(slot: int, gold: int) -> String:
	assert_eq(SaveManager.create_slot(slot, "Welt %d" % slot), OK)
	SaveManager.add_permanent_gold(gold)
	SaveManager.save_game()
	return SaveManager.get_world_id()


## A CloudWorld answer with the world of slot as data (gold changed to gold).
func _cloud_world(slot: int, gold: int, revision := 5) -> Dictionary:
	var config := SaveManager.read_world_config(slot)
	config.set_value("progress", "permanent_gold", gold)
	var world_id := String(config.get_value("world", "id"))
	return {"worldId": world_id, "revision": revision, "status": "active", "source": "restore",
			"formatVersion": int(config.get_value("meta", "version")), "pendingMerges": [],
			"data": JSON.parse_string(JSON.stringify(SaveMerge.to_world_data(config)))}


func test_a_restored_backup_replaces_the_local_world() -> void:
	var world_id := _world(1, 40)
	var answer := _cloud_world(1, 7)
	SaveManager.add_permanent_gold(10)
	SaveManager.save_game()
	_fake.answer("POST /me/worlds/%s/backups/%s/restore" % [world_id, BACKUP_ID], 200, {"world": answer, "archived": []})
	var result: ApiResult = await _cloud().restore_backup(world_id, BACKUP_ID)
	assert_true(result.ok, result.describe())
	assert_eq(result.get_field("applied"), CloudSave.DOWNLOADED)
	assert_eq(SaveManager.get_permanent_gold(), 7, "the loaded world is the backup now")
	var cloud := SaveManager.get_cloud_state(1)
	assert_eq(cloud["base_revision"], 5)
	assert_eq(cloud["player_id"], PLAYER)
	assert_eq(_fake.last("POST /me/worlds/%s/backups/%s/restore" % [world_id, BACKUP_ID]).body, {}, "no archive wish")


func test_an_unarchived_world_comes_into_a_free_slot() -> void:
	var world_id := _world(1, 12)
	var answer := _cloud_world(1, 12, 3)
	SaveManager.set_cloud_state({"base_revision": 3, "synced_hash": "x", "player_id": PLAYER, "synced_at": 1}, 1)
	assert_eq(SaveManager.delete_slot(1), OK)
	assert_eq(SaveManager.get_deleted_world_ids(), PackedStringArray([world_id]), "deleted here, archived in the cloud")
	_fake.answer("POST /me/worlds/%s/unarchive" % world_id, 200, {"world": answer, "archived": []})
	var result: ApiResult = await _cloud().unarchive_world(world_id)
	assert_eq(result.get_field("applied"), CloudSave.DOWNLOADED)
	assert_eq(CloudSave.slot_of_world(world_id), 1)
	assert_true(SaveManager.get_deleted_world_ids().is_empty(), "the next sync does not archive it again")


func test_no_free_slot_keeps_the_world_in_the_cloud() -> void:
	_world(1, 1)
	var answer := _cloud_world(1, 1)
	answer["worldId"] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	answer["data"]["world"]["id"] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	_world(2, 2)
	_world(3, 3)
	assert_eq(_cloud().apply_cloud_world(answer), CloudSave.NO_ROOM)


func test_a_newer_world_is_not_written() -> void:
	_world(1, 1)
	var answer := _cloud_world(1, 1)
	answer["formatVersion"] = SaveManager.SAVE_VERSION + 1
	assert_eq(_cloud().apply_cloud_world(answer), CloudSave.NEWER)


func test_world_limit_names_the_active_worlds_and_takes_the_choice() -> void:
	var world_id := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	var keep := "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	_fake.answer("POST /me/worlds/%s/unarchive" % world_id, 409, {"error": "world_limit_reached", "items": [{"worldId": keep}]})
	var limited: ApiResult = await _cloud().unarchive_world(world_id)
	assert_eq(limited.error, CloudSave.LIMIT_REACHED)
	assert_eq((limited.data["items"] as Array).size(), 1)
	_fake.answer("POST /me/worlds/%s/unarchive" % world_id, 409, {"error": "world_limit_reached", "items": []})
	await _cloud().unarchive_world(world_id, keep)
	assert_eq(_fake.last("POST /me/worlds/%s/unarchive" % world_id).body, {"archiveWorldId": keep})


func test_lists_use_the_kf8_routes() -> void:
	_fake.answer("GET /me/worlds", 200, {"items": [], "archived": [], "maxWorlds": 3, "maxDataBytes": 65536})
	_fake.answer("GET /me/worlds/abc/backups", 200, {"items": []})
	assert_true((await _cloud().list_worlds()).ok)
	assert_true((await _cloud().list_backups("abc")).ok)


func test_restore_through_the_service_syncs_first_and_reloads_the_list() -> void:
	var world_id := _world(1, 40)
	var answer := _cloud_world(1, 9)
	var config := OnlineConfig.new()
	config.path = ROOT.path_join("online.cfg")
	config.settings_path = config.path
	config.load_from({"api": "http://fake"})
	var session := OnlineSession.new(config)
	session.api = _api
	add_child_autofree(session)
	session.token = "test-token"
	session.token_expires_at = 4_000_000_000
	session.player = {"id": PLAYER, "name": "Lumen"}
	session.state = OnlineSession.State.ONLINE
	var service := AccountService.new(session)
	_fake.answer("POST /me/worlds/%s/backups/%s/restore" % [world_id, BACKUP_ID], 200, {"world": answer, "archived": []})
	_fake.answer("GET /me/worlds", 200, {"items": [{"worldId": world_id}], "archived": [], "maxWorlds": 3, "maxDataBytes": 65536})
	var result: ApiResult = await service.restore_backup(world_id, BACKUP_ID)
	assert_true(result.ok, result.describe())
	assert_eq(SaveManager.get_permanent_gold(), 9)
	assert_eq((service.worlds.get("items", []) as Array).size(), 1, "list loaded again")
