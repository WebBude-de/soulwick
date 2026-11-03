class_name CloudSave
extends RefCounted
## Cloud sync of the local worlds (KF9, D-188, KONZEPT §10; contract world.ts of soulwick-platform,
## routes of KF8). Offline first: the game always plays from its local files; sync_all() matches
## them with the account's cloud worlds by world id ([world] id, v5), without a dialog:
## - a world only here is uploaded, a cloud world only there is downloaded into a free slot (active
##   ones, most recently played first; without a free slot it stays in the cloud);
## - a world changed only here is uploaded on its base revision, one changed only in the cloud is
##   downloaded; changed on both sides (or met for the first time on this account) both states are
##   merged by SaveMerge and the result goes up and down; the state whose "last played" fields lost
##   stays on the server as a backup (`discarded`, 30 days);
## - a stale base (409 revision_conflict) merges again with the server state of the answer;
## - pending account merges (pendingMerges) are merged in and reported as resolved;
## - worlds deleted here go to the cloud archive (SaveManager.get_deleted_world_ids).
## [cloud] of every world keeps the base revision, the content hash of the last sync and the account
## (SaveManager.CLOUD_DEFAULTS). The loaded world is never overwritten during a run or when it changed
## while the sync was waiting for the server; that world is synced next time.
## Uses ApiClient.request() only (bearer token of the session). When to sync (login, village, run end,
## closing; never in a run) is up to the caller; see the KF9 hooks. Every failure only shows in the
## report: the game stays playable without a server.

## Emitted when sync_all() is done (also when it failed), with its report.
signal finished(report: Dictionary)

const WORLDS_PATH := "/me/worlds"
## contracts WORLD_MAX_DATA_BYTES (TESTWERT on the server, D-188).
const MAX_DATA_BYTES := 65536
## TESTWERT: merges and uploads per world when the server state keeps moving (409).
const MAX_ATTEMPTS := 3
## TESTWERT: automatic syncs (menu, village) at most this often; explicit ones always run.
const MIN_INTERVAL_SECONDS := 60
## A sync that has not finished after this long (the scene with the client was freed) no longer
## blocks the next one.
const STALE_SECONDS := 120
const CONFLICT := "revision_conflict"
const NOT_FOUND := "world_not_found"

## What happened to one world.
const UPLOADED := "uploaded"
const DOWNLOADED := "downloaded"
const MERGED := "merged"
const UNCHANGED := "unchanged"
const FAILED := "failed"
const NEWER := "newer_version"
const TOO_LARGE := "too_large"
## The loaded world changed while waiting (or a run started): next time.
const BUSY := "busy"
## Report error of a sync that did not start because another one is running.
const ALREADY_RUNNING := "already_running"

## Automatic syncs (slot panel, hooks) only in the real game: script runs (tests, tools) never upload
## a world unless they switch it on with their own fake API.
static var auto_sync_enabled := not PlayerProfile.is_script_run()
## Report of the last finished sync of this game ({} = none yet), for menus.
static var last_report: Dictionary = {}
## Unix seconds the running sync started (0 = none).
static var _running_since := 0
## The running sync, kept alive while it waits for the server (its caller may be gone by then).
static var _active: CloudSave = null

var api: ApiClient = null
## Account the worlds are synced with (PlayerSelf.id); stored in [cloud] player_id.
var player_id := ""


func _init(client: ApiClient = null, account_id := "") -> void:
	api = client
	player_id = account_id


## A sync for the session's account, or null while not logged in.
static func for_session(session: OnlineSession) -> CloudSave:
	if session == null or not session.is_logged_in() or session.api == null:
		return null
	return CloudSave.new(session.api, session.get_player_id())


## True while a sync runs in this game.
static func is_running() -> bool:
	return _running_since > 0 and _now() - _running_since < STALE_SECONDS


## True if an automatic sync is due (none ran in the last MIN_INTERVAL_SECONDS).
static func is_due() -> bool:
	return auto_sync_enabled and not is_running() and _now() - int(last_report.get("finished_at", 0)) >= MIN_INTERVAL_SECONDS


## Matches all local worlds with the cloud (coroutine). Report: {ok, error, uploaded, downloaded,
## merged, unchanged, failed, no_room, newer, worlds: {world_id: status}, finished_at}.
func sync_all() -> Dictionary:
	var report := new_report()
	if api == null or api.token.is_empty() or player_id.is_empty():
		report["error"] = ApiResult.UNAUTHORIZED
		return _finish(report)
	if is_running():
		report["error"] = ALREADY_RUNNING
		return report
	_running_since = _now()
	_active = self
	await _send_deletions()
	var list := await api.request(HTTPClient.METHOD_GET, WORLDS_PATH)
	if not list.ok or not (list.data is Dictionary):
		report["error"] = list.error if not list.ok else ApiResult.BAD_RESPONSE
		return _finish(report)
	var metas := {}
	for key in ["archived", "items"]:
		var entries: Variant = list.data.get(key, [])
		if entries is Array:
			for meta: Variant in entries:
				if meta is Dictionary:
					metas[str(meta.get("worldId", "")).to_lower()] = meta
	var local_ids := {}
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if not SaveManager.has_slot(slot):
			continue
		var config := SaveManager.read_world_config(slot)
		if config == null:
			continue
		var world_id := String(config.get_value("world", "id", "")).to_lower()
		local_ids[world_id] = true
		_count(report, world_id, await _sync_slot(slot, metas.get(world_id, {})))
	await _download_new(list.data.get("items", []), local_ids, report)
	report["ok"] = report["failed"] == 0
	return _finish(report)


## The account's cloud copy of a world goes to the archive (restorable 30 days); ok also when it is
## not there (404).
func archive_world(world_id: String) -> ApiResult:
	var result := await api.request(HTTPClient.METHOD_DELETE, world_path(world_id))
	if not result.ok and result.error == NOT_FOUND:
		return ApiResult.success(404, null)
	return result


static func world_path(world_id: String, suffix := "") -> String:
	return "%s/%s%s" % [WORLDS_PATH, world_id.uri_encode(), suffix]


static func new_report() -> Dictionary:
	return {
		"ok": false, "error": "", "uploaded": 0, "downloaded": 0, "merged": 0, "unchanged": 0,
		"failed": 0, "no_room": 0, "newer": 0, "busy": 0, "worlds": {}, "finished_at": 0,
	}


## The body of an upload without baseRevision (WorldState): blob, summary, versions, platform.
static func world_state(config: ConfigFile, data: Dictionary) -> Dictionary:
	return {
		"formatVersion": int(config.get_value("meta", "version", SaveManager.SAVE_VERSION)),
		"gameVersion": OnlineConfig.get_game_version(),
		"platform": OnlineConfig.get_platform(),
		"summary": summary_of(config),
		"data": data,
	}


## WorldSummary of a world: name, record, forge x/y, play time, last played (ISO).
static func summary_of(config: ConfigFile) -> Dictionary:
	var world_name := ""
	var stored: Variant = config.get_value("world", "name", "")
	if typeof(stored) == TYPE_STRING:
		for i in String(stored).length():
			var code := String(stored).unicode_at(i)
			if code >= 32 and code != 127:
				world_name += String(stored)[i]
	var play_time: Variant = config.get_value("stats", "play_time", 0)
	var last_played: Variant = config.get_value("profile", "last_played", 0)
	var played_at := int(last_played) if typeof(last_played) == TYPE_INT and last_played > 0 else _now()
	return {
		"name": world_name.strip_edges().left(32).strip_edges(),
		"deepestRoom": clampi(_int(config.get_value("stats", "deepest_room", 0)), 0, 100000),
		"forgeLevel": clampi(SaveSlots.forge_progress(config), 0, 1000),
		"forgeMax": clampi(SaveSlots.forge_max_level(), 0, 1000),
		"playTimeSeconds": clampi(int(play_time) if typeof(play_time) in [TYPE_INT, TYPE_FLOAT] else 0, 0, 10 * 365 * 86400),
		"lastPlayedAt": iso_time(played_at),
	}


## Unix seconds as ISO 8601 in UTC ("2026-11-03T14:05:00Z").
static func iso_time(unix_time: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_time) + "Z"


## One line for menus: what the last sync did ("Cloud: 1 Welt gesichert · 1 Welt geladen").
static func report_text(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var error := str(report.get("error", ""))
	if error == ApiResult.UNAUTHORIZED:
		return Loc.t(&"CLOUD_SYNC_LOGGED_OUT")
	if not error.is_empty():
		return Loc.t(&"CLOUD_SYNC_OFFLINE")
	var parts := PackedStringArray()
	var saved := int(report.get("uploaded", 0)) + int(report.get("merged", 0))
	if saved > 0:
		parts.append(Loc.t(&"CLOUD_SYNC_SAVED_ONE") if saved == 1 else Loc.t(&"CLOUD_SYNC_SAVED_MANY", [saved]))
	var loaded := int(report.get("downloaded", 0))
	if loaded > 0:
		parts.append(Loc.t(&"CLOUD_SYNC_LOADED_ONE") if loaded == 1 else Loc.t(&"CLOUD_SYNC_LOADED_MANY", [loaded]))
	if int(report.get("no_room", 0)) > 0:
		parts.append(Loc.t(&"CLOUD_SYNC_NO_ROOM", [int(report.get("no_room", 0))]))
	if int(report.get("newer", 0)) > 0:
		parts.append(Loc.t(&"CLOUD_SYNC_NEWER", [int(report.get("newer", 0))]))
	var open := int(report.get("failed", 0)) + int(report.get("busy", 0))
	if open > 0:
		parts.append(Loc.t(&"CLOUD_SYNC_OPEN", [open]))
	if parts.is_empty():
		return Loc.t(&"CLOUD_SYNC_UP_TO_DATE")
	return Loc.t(&"CLOUD_SYNC_LINE", [" · ".join(parts)])


# --- One world ---

## Syncs the world of one slot with its cloud meta ({} = not in the cloud). Returns the status.
func _sync_slot(slot: int, meta: Dictionary) -> String:
	var config := SaveManager.read_world_config(slot)
	if config == null:
		return FAILED
	var cloud := SaveManager.cloud_state_of(config)
	var same_account: bool = cloud["player_id"] == player_id
	var data := SaveMerge.to_world_data(config)
	var dirty: bool = not same_account or SaveMerge.content_hash(data) != cloud["synced_hash"]
	if meta.is_empty():
		return await _upload(slot, config, data, 0, {}, [], 1)
	if int(meta.get("formatVersion", 0)) > SaveManager.SAVE_VERSION:
		return NEWER
	var revision := int(meta.get("revision", 0))
	var pending: Variant = meta.get("pendingMerges", [])
	var has_pending := pending is Array and not (pending as Array).is_empty()
	if same_account and int(cloud["base_revision"]) == revision and not has_pending:
		if not dirty:
			return UNCHANGED
		return await _upload(slot, config, data, revision, {}, [], 1)
	return await _merge_with_server(slot, null, 1)


## PUT of a state that is already the local one (nothing to write back but [cloud]).
func _upload(slot: int, config: ConfigFile, data: Dictionary, base: int, discarded: Dictionary, resolved: Array, attempt: int) -> String:
	if SaveMerge.data_size(data) > MAX_DATA_BYTES:
		push_warning("CloudSave: world in slot %d is larger than %d bytes, not uploaded." % [slot, MAX_DATA_BYTES])
		return TOO_LARGE
	var world_id := String(config.get_value("world", "id", ""))
	var result := await _put(world_id, config, data, base, discarded, resolved)
	if result.ok:
		SaveManager.set_cloud_state(_cloud_after(result, SaveMerge.content_hash(data)), slot)
		return UPLOADED
	return await _after_failed_put(slot, result, attempt)


## Merges the slot's world with the server state (fetched when world is null), uploads the result if
## it differs from the server state and writes it here.
func _merge_with_server(slot: int, world: Variant, attempt: int) -> String:
	var local := SaveManager.read_world_config(slot)
	if local == null:
		return FAILED
	var world_id := String(local.get_value("world", "id", ""))
	if world == null:
		var fetched := await api.request(HTTPClient.METHOD_GET, world_path(world_id))
		if not fetched.ok and fetched.error == NOT_FOUND:
			return await _upload(slot, local, SaveMerge.to_world_data(local), 0, {}, [], attempt)
		if not fetched.ok or not (fetched.data is Dictionary):
			return FAILED
		world = fetched.data
		# The world may have moved while waiting.
		local = SaveManager.read_world_config(slot)
		if local == null:
			return FAILED
	var server := await _server_state(world)
	if server.is_empty():
		return FAILED
	var server_config: ConfigFile = server["config"]
	if int(server_config.get_value("meta", "version", 0)) > SaveManager.SAVE_VERSION:
		return NEWER
	var revision := int(world.get("revision", 0))
	var local_data := SaveMerge.to_world_data(local)
	var local_hash := SaveMerge.content_hash(local_data)
	var merge := SaveMerge.merge(local, server_config)
	if not merge["ok"]:
		push_warning("CloudSave: world in slot %d not merged (%s)." % [slot, merge["error"]])
		return NEWER if merge["error"] == "newer_version" else FAILED
	var merged: ConfigFile = merge["config"]
	var merged_data := SaveMerge.to_world_data(merged)
	var merged_hash := SaveMerge.content_hash(merged_data)
	var resolved: Array = server["resolved"]
	if merged_hash == server["hash"] and resolved.is_empty():
		# The cloud already has everything of this state: take it as it is.
		var cloud := _cloud_state(revision, merged_hash)
		if merged_hash == local_hash:
			SaveManager.set_cloud_state(cloud, slot)
			return UNCHANGED
		return DOWNLOADED if _write_back(slot, merged_data, cloud, local_hash) else BUSY
	if SaveMerge.data_size(merged_data) > MAX_DATA_BYTES:
		return TOO_LARGE
	var discarded := {}
	if merge["loser_lost"]:
		if merge["winner"] == SaveMerge.LOCAL:
			discarded = {"side": "server"}
		else:
			discarded = world_state(local, local_data)
			discarded["side"] = "local"
	var result := await _put(world_id, merged, merged_data, revision, discarded, resolved)
	if not result.ok:
		return await _after_failed_put(slot, result, attempt)
	var after := _cloud_after(result, merged_hash)
	if merged_hash == local_hash:
		SaveManager.set_cloud_state(after, slot)
		return UPLOADED
	# Not written back (changed here meanwhile): [cloud] keeps the old base, so the next sync merges again.
	return MERGED if _write_back(slot, merged_data, after, local_hash) else BUSY


## 409: merge again with the server state of the answer (null = gone: upload as new); other errors fail.
func _after_failed_put(slot: int, result: ApiResult, attempt: int) -> String:
	if result.error != CONFLICT or attempt >= MAX_ATTEMPTS:
		push_warning("CloudSave: upload of slot %d failed (%s)." % [slot, result.describe()])
		return FAILED
	var world: Variant = result.get_field("world")
	if world is Dictionary:
		return await _merge_with_server(slot, world, attempt + 1)
	var config := SaveManager.read_world_config(slot)
	if config == null:
		return FAILED
	return await _upload(slot, config, SaveMerge.to_world_data(config), 0, {}, [], attempt + 1)


## The server state of a CloudWorld with its pending account merges merged in:
## {config, hash (of the server's own state), resolved (backup ids merged in)}; {} if unreadable.
func _server_state(world: Dictionary) -> Dictionary:
	var data: Variant = world.get("data", null)
	if not (data is Dictionary):
		return {}
	var config := SaveMerge.from_world_data(data)
	var state := {"config": config, "hash": SaveMerge.content_hash(SaveMerge.to_world_data(config)), "resolved": []}
	var pending: Variant = world.get("pendingMerges", [])
	if not (pending is Array):
		return state
	var world_id := str(world.get("worldId", config.get_value("world", "id", "")))
	for backup_id: Variant in pending:
		var backup := await api.request(HTTPClient.METHOD_GET, world_path(world_id, "/backups/%s" % str(backup_id).uri_encode()))
		if not backup.ok or not (backup.data is Dictionary) or not (backup.data.get("data") is Dictionary):
			continue
		var other := SaveMerge.from_world_data(backup.data["data"])
		var merged := SaveMerge.merge(state["config"], other)
		if merged["ok"]:
			state["config"] = merged["config"]
			(state["resolved"] as Array).append(str(backup_id))
	return state


func _put(world_id: String, config: ConfigFile, data: Dictionary, base: int, discarded: Dictionary, resolved: Array) -> ApiResult:
	var body := world_state(config, data)
	body["baseRevision"] = base
	if not discarded.is_empty():
		body["discarded"] = discarded
	if not resolved.is_empty():
		body["resolvedMerges"] = resolved
	return await api.request(HTTPClient.METHOD_PUT, world_path(world_id), body)


## Writes a state into a slot unless that world changed since the sync read it (expected_hash) or a
## run is going on in it. Returns true if written.
func _write_back(slot: int, data: Dictionary, cloud: Dictionary, expected_hash: String) -> bool:
	if SaveManager.get_active_slot() == slot and RunManager.is_run_active():
		return false
	var current := SaveManager.read_world_config(slot)
	var current_hash := SaveMerge.content_hash(SaveMerge.to_world_data(current)) if current != null else ""
	if current_hash != expected_hash:
		return false
	return SaveManager.import_world(data, slot, cloud, expected_hash.is_empty()) == OK


# --- New cloud worlds and deleted ones ---

## Active cloud worlds that are not on this device go into free slots (most recently played first).
func _download_new(items: Variant, local_ids: Dictionary, report: Dictionary) -> void:
	if not (items is Array):
		return
	var deleted := SaveManager.get_deleted_world_ids()
	var sorted: Array = (items as Array).filter(func(meta: Variant) -> bool: return meta is Dictionary)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("summary", {}).get("lastPlayedAt", "")) > str(b.get("summary", {}).get("lastPlayedAt", "")))
	for meta: Dictionary in sorted:
		var world_id := str(meta.get("worldId", "")).to_lower()
		if world_id.is_empty() or local_ids.has(world_id) or deleted.has(world_id):
			continue
		if int(meta.get("formatVersion", 0)) > SaveManager.SAVE_VERSION:
			_count(report, world_id, NEWER)
			continue
		var slot := SaveManager.get_free_slot()
		if slot == 0:
			report["no_room"] += 1
			continue
		_count(report, world_id, await _download(slot, world_id))


func _download(slot: int, world_id: String) -> String:
	var fetched := await api.request(HTTPClient.METHOD_GET, world_path(world_id))
	if not fetched.ok or not (fetched.data is Dictionary):
		return FAILED
	var server := await _server_state(fetched.data)
	if server.is_empty():
		return FAILED
	var config: ConfigFile = server["config"]
	var data := SaveMerge.to_world_data(config)
	var revision := int(fetched.data.get("revision", 0))
	var hash := SaveMerge.content_hash(data)
	var cloud := _cloud_state(revision, hash)
	if not (server["resolved"] as Array).is_empty():
		var result := await _put(world_id, config, data, revision, {}, server["resolved"])
		if not result.ok:
			return FAILED
		cloud = _cloud_after(result, hash)
	if SaveManager.has_slot(slot):
		return BUSY
	return DOWNLOADED if _write_back(slot, data, cloud, "") else FAILED


## Worlds deleted on this device go to the cloud archive; sent ones are forgotten.
func _send_deletions() -> void:
	for world_id in SaveManager.get_deleted_world_ids():
		var result := await archive_world(world_id)
		if result.ok:
			SaveManager.forget_deleted_world(world_id)


# --- Helpers ---

func _cloud_state(revision: int, hash: String) -> Dictionary:
	return {"base_revision": revision, "synced_hash": hash, "player_id": player_id, "synced_at": _now()}


## [cloud] after a successful PUT (PutWorldResponse.world.revision).
func _cloud_after(result: ApiResult, hash: String) -> Dictionary:
	var world: Variant = result.get_field("world")
	var revision := int(world.get("revision", 0)) if world is Dictionary else 0
	return _cloud_state(revision, hash)


func _finish(report: Dictionary) -> Dictionary:
	report["finished_at"] = _now()
	_running_since = 0
	if _active == self:
		_active = null
	last_report = report
	finished.emit(report)
	return report


static func _count(report: Dictionary, world_id: String, status: String) -> void:
	(report["worlds"] as Dictionary)[world_id] = status
	match status:
		UPLOADED:
			report["uploaded"] += 1
		DOWNLOADED:
			report["downloaded"] += 1
		MERGED:
			report["merged"] += 1
		UNCHANGED:
			report["unchanged"] += 1
		NEWER:
			report["newer"] += 1
		BUSY:
			report["busy"] += 1
		_:
			report["failed"] += 1


static func _int(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0


static func _now() -> int:
	return int(Time.get_unix_time_from_system())
