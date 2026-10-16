class_name GuildDirectory
extends RefCounted
## The player's guilds for the online menu (D-147, contracts guild.ts, API 1.1.0): the list
## (GET /me/guilds -> MyGuildList), one guild in detail (GET /guilds/:id -> GuildDetail), found,
## join by invite code, leave, remove a member, new invite code. Rights (platform P-031): founder
## everything, officer sees and renews the invite code and removes plain members, member reads and
## leaves. Open guild rooms (GET /guilds/:id/rooms -> GuildRoomList) are loaded quietly (no busy
## state, changed only when the list differs), so the menu can poll them while a guild is open; an
## API without the route (404) hides the list for good, joining by room code always works.
## Every call goes through OnlineSession.call_api (login first, one new login after a
## 401) and only changes the state here; the menu listens to changed/action_finished. RefCounted on
## purpose: a call that is still running when the menu closes finishes here without touching it.
## Failures never throw: the error code stays in list_error or comes with action_finished, the
## single player game is not affected.

## Something of the state changed (list, a detail, busy).
signal changed
## A call ended. action: one of the ACTION_* names; info: e.g. {guild_id, name, player_id}.
signal action_finished(action: StringName, result: ApiResult, info: Dictionary)

## TESTWERT (D-147): a player is in at most this many guilds.
const MAX_GUILDS_PER_PLAYER := 5
## TESTWERT (D-080): members per guild (contracts MAX_GUILD_MEMBERS).
const MAX_GUILD_MEMBERS := 30
## GuildName / GuildTag / InviteCode of contracts common.ts.
const NAME_MIN := 3
const NAME_MAX := 32
const TAG_MIN := 2
const TAG_MAX := 5
const INVITE_MIN := 6
const INVITE_MAX := 16

const ROLE_FOUNDER := "founder"
const ROLE_OFFICER := "officer"
const ROLE_MEMBER := "member"

const ACTION_LIST: StringName = &"list"
const ACTION_DETAIL: StringName = &"detail"
const ACTION_CREATE: StringName = &"create"
const ACTION_JOIN: StringName = &"join"
const ACTION_LEAVE: StringName = &"leave"
const ACTION_REMOVE: StringName = &"remove"
const ACTION_ROTATE: StringName = &"rotate"
const ACTION_ROLE: StringName = &"role"
const ACTION_ROOMS: StringName = &"rooms"

## Local validation errors (texts GUILD_ERR_*).
const ERROR_NAME_INVALID := "name_invalid"
const ERROR_TAG_INVALID := "tag_invalid"
const ERROR_CODE_INVALID := "code_invalid"

var session: OnlineSession = null
## Finds the session on the first call when none was given (the menu does not log in or create one
## just by opening). Callable() -> OnlineSession.
var session_provider: Callable = Callable()
## Guild summaries (normalised, see normalize_summary), in the API's order (oldest membership first).
var guilds: Array[Dictionary] = []
## MAX_GUILDS_PER_PLAYER of the API (MyGuildList.maxGuilds), the local TESTWERT until it answered.
var max_guilds := MAX_GUILDS_PER_PLAYER
## The list was loaded at least once (successfully).
var loaded := false
## Error code of the last failed list load ("" if none).
var list_error := ""
## Guild id -> normalised guild (normalize_guild) of the last GET /guilds/:id.
var details: Dictionary = {}
## Calls running right now.
var running := 0
## Guild id -> open rooms of that guild (normalize_room, oldest first) of the last
## GET /guilds/:id/rooms; no entry until it answered.
var rooms: Dictionary = {}
## false once the API answered 404 for the rooms route (older API): the menu hides the list.
var rooms_supported := true
## Room loads running right now (not counted in running: they never block the menu).
var rooms_running := 0


func _init(online_session: OnlineSession = null) -> void:
	session = online_session


func is_busy() -> bool:
	return running > 0


## The player's account id ("" while offline).
func get_own_player_id() -> String:
	return session.get_player_id() if session != null and is_instance_valid(session) else ""


func find_summary(guild_id: String) -> Dictionary:
	for guild in guilds:
		if str(guild.get("id", "")) == guild_id:
			return guild
	return {}


func get_detail(guild_id: String) -> Dictionary:
	return details.get(guild_id, {})


## The player's role in a guild: from the detail (members, role) or the list, "" if unknown.
func get_own_role(guild_id: String) -> String:
	var detail := get_detail(guild_id)
	if not str(detail.get("role", "")).is_empty():
		return str(detail.role)
	var own_id := get_own_player_id()
	for member: Dictionary in detail.get("members", []):
		if str(member.get("playerId", "")) == own_id and not own_id.is_empty():
			return str(member.get("role", ""))
	return str(find_summary(guild_id).get("role", ""))


func is_at_limit() -> bool:
	return guilds.size() >= max_guilds


## Open rooms of a guild (normalize_room), [] if none or not loaded.
func get_rooms(guild_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(rooms.get(guild_id, []))
	return result


## true once GET /guilds/:id/rooms answered for this guild (the list may be empty).
func has_rooms(guild_id: String) -> bool:
	return rooms.has(guild_id)


# --- Calls (coroutines; callers may ignore the result and listen to the signals) ---

func refresh() -> ApiResult:
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.get_my_guilds())
	if result.ok:
		guilds = parse_guild_list(result.data)
		if result.data is Dictionary and result.data.get("maxGuilds", null) != null:
			max_guilds = maxi(1, int(result.data.maxGuilds))
		loaded = true
		list_error = ""
		# Details of guilds the player is no longer in are dropped.
		for id: String in details.keys():
			if find_summary(id).is_empty():
				details.erase(id)
	else:
		list_error = result.error
	_finish(ACTION_LIST, result, {})
	return result


func load_guild(guild_id: String) -> ApiResult:
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.get_guild(guild_id))
	if result.ok and result.data is Dictionary:
		var guild := normalize_guild(result.data)
		# Older answers without progress: the treasury comes from GET /guilds/:id/progress.
		if not (result.data as Dictionary).has("progress"):
			var progress := await _call(func(api: ApiClient) -> ApiResult: return await api.get_guild_progress(guild_id))
			if progress.ok and progress.data is Dictionary:
				guild["treasury"] = int(progress.data.get("treasury", 0))
		details[guild_id] = guild
		_update_summary(guild)
	elif _is_gone(result):
		_forget(guild_id)
	_finish(ACTION_DETAIL, result, {"guild_id": guild_id})
	return result


## Open rooms of a guild. Quiet: no busy state; changed only when the list differs. 404 (API without
## the route) switches the list off (rooms_supported); other failures drop the guild's list.
func load_rooms(guild_id: String) -> ApiResult:
	if not rooms_supported or guild_id.is_empty():
		return ApiResult.failure(ApiResult.UNREACHABLE, "Guild rooms not supported")
	rooms_running += 1
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.get_guild_rooms(guild_id), false)
	rooms_running = maxi(0, rooms_running - 1)
	var had := rooms.has(guild_id)
	var before: Array = rooms.get(guild_id, [])
	if result.ok:
		rooms[guild_id] = parse_room_list(result.data)
	else:
		if result.status == 404:
			rooms_supported = false
		rooms.erase(guild_id)
	action_finished.emit(ACTION_ROOMS, result, {"guild_id": guild_id})
	var now: Array = rooms.get(guild_id, [])
	if had != rooms.has(guild_id) or str(before) != str(now) or not rooms_supported:
		changed.emit()
	return result


func create_guild(guild_name: String, tag: String) -> ApiResult:
	var clean_name := guild_name.strip_edges()
	var clean_tag := normalize_tag(tag)
	var result: ApiResult
	if not is_valid_name(clean_name):
		result = ApiResult.failure(ERROR_NAME_INVALID)
	elif not is_valid_tag(clean_tag):
		result = ApiResult.failure(ERROR_TAG_INVALID)
	else:
		result = await _call(func(api: ApiClient) -> ApiResult: return await api.create_guild(clean_name, clean_tag))
	var info := {"name": clean_name, "tag": clean_tag}
	if result.ok and result.data is Dictionary:
		_accept_guild(result.data, info)
	_finish(ACTION_CREATE, result, info)
	if result.ok:
		refresh()
	return result


func join_guild(invite_code: String) -> ApiResult:
	var code := normalize_invite_code(invite_code)
	var result: ApiResult
	if not is_valid_invite_code(code):
		result = ApiResult.failure(ERROR_CODE_INVALID)
	else:
		result = await _call(func(api: ApiClient) -> ApiResult: return await api.join_guild(code))
	var info := {"code": code}
	if result.ok and result.data is Dictionary:
		_accept_guild(result.data, info)
	_finish(ACTION_JOIN, result, info)
	if result.ok:
		refresh()
	return result


func leave_guild(guild_id: String) -> ApiResult:
	var guild_name := str(find_summary(guild_id).get("name", ""))
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.leave_guild(guild_id))
	if result.ok or result.error == ApiResult.NOT_MEMBER:
		_forget(guild_id)
	# LeaveGuildResponse: the last member disbands the guild.
	var disbanded: bool = result.ok and result.get_field("disbanded", false) == true
	_finish(ACTION_LEAVE, result, {"guild_id": guild_id, "name": guild_name, "disbanded": disbanded})
	return result


func remove_member(guild_id: String, player_id: String) -> ApiResult:
	var member_name := ""
	for member: Dictionary in get_detail(guild_id).get("members", []):
		if str(member.get("playerId", "")) == player_id:
			member_name = str(member.get("name", ""))
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.remove_guild_member(guild_id, player_id))
	if result.ok and result.data is Dictionary and (result.data as Dictionary).has("members"):
		# 200 GuildDetail: the guild as it is now.
		var guild := normalize_guild(result.data)
		details[guild_id] = guild
		_update_summary(guild)
	elif result.ok and details.has(guild_id):
		var detail: Dictionary = details[guild_id]
		var members: Array = detail.get("members", [])
		detail["members"] = members.filter(func(member: Variant) -> bool: return member is Dictionary and str(member.get("playerId", "")) != player_id)
		detail["memberCount"] = (detail["members"] as Array).size()
		_update_summary(detail)
	_finish(ACTION_REMOVE, result, {"guild_id": guild_id, "player_id": player_id, "name": member_name})
	return result


## Founder only: makes a member officer (role "officer") or an officer a plain member again.
func set_member_role(guild_id: String, player_id: String, role: String) -> ApiResult:
	var member_name := ""
	for member: Dictionary in get_detail(guild_id).get("members", []):
		if str(member.get("playerId", "")) == player_id:
			member_name = str(member.get("name", ""))
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.set_guild_member_role(guild_id, player_id, role))
	if result.ok and result.data is Dictionary and (result.data as Dictionary).has("members"):
		var guild := normalize_guild(result.data)
		details[guild_id] = guild
		_update_summary(guild)
	_finish(ACTION_ROLE, result, {"guild_id": guild_id, "player_id": player_id, "name": member_name, "role": role})
	return result


func rotate_invite_code(guild_id: String) -> ApiResult:
	var result := await _call(func(api: ApiClient) -> ApiResult: return await api.rotate_guild_invite_code(guild_id))
	if result.ok and details.has(guild_id):
		var code: Variant = result.get_field("inviteCode", null)
		if code != null:
			details[guild_id]["inviteCode"] = str(code)
	_finish(ACTION_ROTATE, result, {"guild_id": guild_id})
	return result


# --- Parsing (static, tests) ---

## Guild list of GET /me/guilds: MyGuildList {items, maxGuilds} (a plain list is read too);
## entries normalised, broken ones skipped.
static func parse_guild_list(data: Variant) -> Array[Dictionary]:
	var raw: Variant = data
	if data is Dictionary:
		raw = data.get("items", data.get("guilds", []))
	var result: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary and not str(entry.get("id", "")).is_empty():
				result.append(normalize_summary(entry))
	return result


## {id, name, tag, role, memberCount, maxMembers, treasury} of a GuildSummary or a GuildDetail
## (the API calls the own role myRole).
static func normalize_summary(entry: Dictionary) -> Dictionary:
	var members: Variant = entry.get("members", null)
	var count := int(entry.get("memberCount", (members as Array).size() if members is Array else 0))
	var role: Variant = entry.get("myRole", entry.get("role", null))
	var progress: Variant = entry.get("progress", null)
	return {
		"id": str(entry.get("id", "")),
		"name": str(entry.get("name", "")),
		"tag": str(entry.get("tag", "")),
		"role": str(role) if role != null else "",
		"memberCount": count,
		"maxMembers": int(entry.get("maxMembers", MAX_GUILD_MEMBERS)),
		"treasury": int(progress.get("treasury", 0)) if progress is Dictionary else int(entry.get("treasury", 0)),
	}


## A guild of GET /guilds/:id (OwnGuild): the summary plus inviteCode ("" if hidden for the role),
## members (playerId, name, role) and the treasury of its progress.
static func normalize_guild(entry: Dictionary) -> Dictionary:
	var guild := normalize_summary(entry)
	var code: Variant = entry.get("inviteCode", null)
	guild["inviteCode"] = str(code) if code != null else ""
	guild["founderId"] = str(entry.get("founderId", "")) if entry.get("founderId", null) != null else ""
	var members: Array[Dictionary] = []
	for member: Variant in entry.get("members", []):
		if member is Dictionary:
			members.append({
				"playerId": str(member.get("playerId", "")),
				"name": str(member.get("name", "")) if member.get("name", null) != null else "?",
				"role": str(member.get("role", ROLE_MEMBER)),
				"joinedAt": str(member.get("joinedAt", "")) if member.get("joinedAt", null) != null else "",
			})
	guild["members"] = members
	if entry.has("members"):
		guild["memberCount"] = int(entry.get("memberCount", members.size()))
	return guild


## Open rooms of GET /guilds/:id/rooms: GuildRoomList {time, relayAvailable, rooms} (a plain list
## or {rooms} without the rest are read too). relayAvailable false = no list. Entries without a
## valid room code are skipped.
static func parse_room_list(data: Variant) -> Array[Dictionary]:
	var raw: Variant = data
	if data is Dictionary:
		if data.get("relayAvailable", true) == false:
			return []
		raw = data.get("rooms", data.get("items", []))
	var result: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				var room := normalize_room(entry)
				if RelayProtocol.is_valid_code(str(room.code)):
					result.append(room)
	return result


## {code, hostName, hostPlayerId, players, maxPlayers, started, gameVersion, createdAt} of a GuildRoom
## (contracts guild.ts: playerCount and a players array; "players" as a number is read too).
## hostName "" if unknown.
static func normalize_room(entry: Dictionary) -> Dictionary:
	var players: Variant = entry.get("players", null)
	var count := int(entry.get("playerCount", players.size() if players is Array else (int(players) if players is float or players is int else 0)))
	var host_name: Variant = entry.get("hostName", null)
	if host_name == null and players is Array:
		for player: Variant in players:
			if player is Dictionary and player.get("host", false) == true:
				host_name = player.get("name", null)
	return {
		"code": RelayProtocol.normalize_code(str(entry.get("code", ""))),
		"hostName": str(host_name) if host_name != null else "",
		"hostPlayerId": str(entry.get("hostPlayerId", "")) if entry.get("hostPlayerId", null) != null else "",
		"players": count,
		"maxPlayers": int(entry.get("maxPlayers", RelayProtocol.MAX_ROOM_PLAYERS)),
		"started": entry.get("started", false) == true,
		"gameVersion": str(entry.get("gameVersion", "")) if entry.get("gameVersion", null) != null else "",
		"createdAt": str(entry.get("createdAt", "")) if entry.get("createdAt", null) != null else "",
	}


## Founders and officers see the invite code, renew it and remove members.
static func can_manage(role: String) -> bool:
	return role == ROLE_FOUNDER or role == ROLE_OFFICER


## Whether own_role may remove a member with member_role (the API has the last word): the founder
## everybody but himself, officers only plain members.
static func can_remove(own_role: String, member_role: String) -> bool:
	match own_role:
		ROLE_FOUNDER:
			return member_role != ROLE_FOUNDER
		ROLE_OFFICER:
			return member_role == ROLE_MEMBER
	return false


## Only the founder names officers and takes the rank back (platform P-031).
static func can_change_role(own_role: String, member_role: String) -> bool:
	return own_role == ROLE_FOUNDER and (member_role == ROLE_OFFICER or member_role == ROLE_MEMBER)


## Translation key of a role (GUILD_ROLE_FOUNDER …).
static func role_key(role: String) -> StringName:
	return StringName("GUILD_ROLE_%s" % (role if not role.is_empty() else ROLE_MEMBER).to_upper())


static func is_valid_name(text: String) -> bool:
	var clean := text.strip_edges()
	if clean.length() < NAME_MIN or clean.length() > NAME_MAX:
		return false
	return RegEx.create_from_string("^[\\p{L}\\p{N} _.'-]+$").search(clean) != null


## Upper case, letters and digits only, at most TAG_MAX.
static func normalize_tag(text: String) -> String:
	return _alnum_upper(text).left(TAG_MAX)


static func is_valid_tag(text: String) -> bool:
	return text.length() >= TAG_MIN and text.length() <= TAG_MAX and normalize_tag(text) == text


## Upper case, letters and digits only (spaces and dashes from Discord are dropped), at most
## INVITE_MAX.
static func normalize_invite_code(text: String) -> String:
	return _alnum_upper(text).left(INVITE_MAX)


static func is_valid_invite_code(text: String) -> bool:
	return text.length() >= INVITE_MIN and text.length() <= INVITE_MAX and normalize_invite_code(text) == text


## Translated sentence for an error code of a guild call: GUILD_ERR_<CODE>, else the lobby's texts
## (server unreachable, banned, update needed …), else a generic one with the code.
static func error_text(code: String) -> String:
	var lookup := code
	match code:
		ApiResult.UNREACHABLE, ApiResult.TIMEOUT:
			lookup = LobbyClient.ERROR_API_UNREACHABLE
		"http_404", "not_found", "not_in_guild", "guild_not_found":
			lookup = "not_found"
		"validation_failed":
			lookup = "validation_error"
	var key := StringName("GUILD_ERR_%s" % lookup.to_upper())
	var args: Array = []
	if lookup == ApiResult.GUILD_LIMIT_REACHED:
		args = [MAX_GUILDS_PER_PLAYER]
	elif lookup == ApiResult.GUILD_FULL:
		args = [MAX_GUILD_MEMBERS]
	if Loc.has_key(key):
		return Loc.t(key, args)
	return LobbyClient.error_text(lookup)


## Short date of an ISO time ("2026-10-15T10:00:00.000Z"): "15.10.2026" in German, "2026-10-15"
## otherwise; "" if it is not a date.
static func format_date(iso: String, locale := "") -> String:
	var parts := iso.left(10).split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return ""
	var lang := (locale if not locale.is_empty() else TranslationServer.get_locale()).left(2)
	if lang == "de":
		return "%s.%s.%s" % [parts[2], parts[1], parts[0]]
	return iso.left(10)


static func _alnum_upper(text: String) -> String:
	var result := ""
	for character in text.to_upper():
		if (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
			result += character
	return result


# --- Internals ---

## busy: counts in running and emits changed (the menu shows "Einen Moment …" and blocks buttons).
func _call(fn: Callable, busy := true) -> ApiResult:
	if (session == null or not is_instance_valid(session)) and session_provider.is_valid():
		session = session_provider.call()
	if session == null or not is_instance_valid(session) or not session.is_inside_tree():
		return ApiResult.failure(ApiResult.UNREACHABLE, "No online session")
	if busy:
		running += 1
		changed.emit()
	var result: ApiResult = await session.call_api(fn)
	if busy:
		running = maxi(0, running - 1)
	return result


func _finish(action: StringName, result: ApiResult, info: Dictionary) -> void:
	action_finished.emit(action, result, info)
	changed.emit()


## A created or joined guild: into the details and (until the list is read again) the list.
func _accept_guild(data: Dictionary, info: Dictionary) -> void:
	var guild := normalize_guild(data)
	if guild.id.is_empty():
		return
	if str(guild.role).is_empty():
		var own_id := get_own_player_id()
		for member: Dictionary in guild.members:
			if member.playerId == own_id and not own_id.is_empty():
				guild["role"] = member.role
	details[guild.id] = guild
	info["guild_id"] = guild.id
	info["name"] = guild.name
	if find_summary(guild.id).is_empty():
		guilds.append(normalize_summary(guild))
	else:
		_update_summary(guild)


func _update_summary(guild: Dictionary) -> void:
	for i in guilds.size():
		if guilds[i].id == guild.get("id", ""):
			var summary := normalize_summary(guild)
			if str(summary.role).is_empty():
				summary["role"] = guilds[i].role
			guilds[i] = summary


func _forget(guild_id: String) -> void:
	details.erase(guild_id)
	rooms.erase(guild_id)
	var kept: Array[Dictionary] = []
	for guild in guilds:
		if guild.id != guild_id:
			kept.append(guild)
	guilds = kept


## The guild is gone for this player (left, removed, disbanded).
func _is_gone(result: ApiResult) -> bool:
	return result.error == ApiResult.NOT_MEMBER or result.status == 404
