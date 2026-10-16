class_name RelayProtocol
extends RefCounted
## Wire format of soulwick-relay (D-119, MP2), mirrored from
## soulwick-platform/packages/contracts/src/lobby.ts: control messages are JSON text frames with a
## "type"; game packets are binary frames with a 10-byte little-endian header
## (from:int32, to:int32, channel:uint8, mode:uint8) followed by the untouched Godot packet.
## Keep the constants in step with the contract (PROTOCOL_VERSION lives in OnlineConfig).

const WS_PATH := "/v1"
const MAX_ROOM_PLAYERS := 4
const HOST_PEER_ID := 1
## Target "every peer in the room except the sender"; negative = all except -to.
const TARGET_ALL := 0
## No 0/O, 1/I/L: codes are read aloud and typed from Discord.
const ROOM_CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const HELLO_TIMEOUT_SECONDS := 5

const FRAME_HEADER_BYTES := 10
const OFFSET_FROM := 0
const OFFSET_TO := 4
const OFFSET_CHANNEL := 8
const OFFSET_MODE := 9

## Godot's TransferMode values equal the relay's (0 unreliable, 1 unreliable ordered, 2 reliable).
const MODE_UNRELIABLE := 0
const MODE_UNRELIABLE_ORDERED := 1
const MODE_RELIABLE := 2

## WebSocket close codes of the relay (RELAY_CLOSE_CODES). -1 = closed without a close frame
## (connection cut: deploy behind the proxy, WLAN gone, Cloudflare).
const CLOSE_ABNORMAL := -1
const CLOSE_SHUTDOWN := 1001
const CLOSE_TIMEOUT := 4000
const CLOSE_UNAUTHORIZED := 4001
const CLOSE_BANNED := 4003
const CLOSE_VERSION_MISMATCH := 4006
const CLOSE_RATE_LIMITED := 4008
const CLOSE_SLOW_CONSUMER := 4010

## RoomClosedReason values.
const CLOSED_LEFT := "left"
const CLOSED_HOST_LEFT := "host_left"
const CLOSED_EXPIRED := "expired"
const CLOSED_KICKED := "kicked"
const CLOSED_SHUTDOWN := "shutdown"
const CLOSED_BY_ADMIN := "closed_by_admin"

## Session end reasons of the game itself when the socket closes in a room (LobbyClient shows
## LOBBY_ERR_<REASON>): the relay's close code says why (end_reason_for_close).
const END_DISCONNECTED := "disconnected"
const END_TIMEOUT := "timeout"
const END_SLOW_CONSUMER := "slow_consumer"
const END_RATE_LIMITED := "rate_limited"
const END_BANNED := "banned"

## TESTWERT: seconds between the game's own heartbeat pings once welcomed (the relay answers pong).
## Keeps the line busy through menus and loading screens (Cloudflare drops after 100 s silence)
## and measures the round trip.
const HEARTBEAT_SECONDS := 20.0
## TESTWERT: no data at all from the relay for this long = the connection is dead (the relay pings
## every 15 s and answers every heartbeat). Catches half-open connections the OS does not notice.
const SILENCE_TIMEOUT_SECONDS := 50.0

## Error codes of the relay contract (RelayErrorCode); unknown ones are passed on unchanged.
const ERROR_CODES: Array[String] = [
	"unauthorized", "hello_required", "banned", "version_mismatch", "invalid_message",
	"room_not_found", "room_full", "room_started", "not_guild_member", "already_in_room", "kicked",
	"not_in_room", "not_host", "peer_not_found", "invalid_target", "api_unavailable",
	"rate_limited", "frame_too_large", "internal", "room_not_started",
]

## RunEndReason of end_run/run_ended: exit portal, everybody down, given up.
const RUN_END_PORTAL := "portal"
const RUN_END_WIPED := "wiped"
const RUN_END_ABANDONED := "abandoned"


## Binary game frame: header + data.
static func encode_frame(from: int, to: int, channel: int, mode: int, data: PackedByteArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(FRAME_HEADER_BYTES)
	bytes.encode_s32(OFFSET_FROM, from)
	bytes.encode_s32(OFFSET_TO, to)
	bytes.encode_u8(OFFSET_CHANNEL, channel & 0xff)
	bytes.encode_u8(OFFSET_MODE, mode & 0xff)
	bytes.append_array(data)
	return bytes


## {from, to, channel, mode, data} or {} for frames shorter than the header.
static func decode_frame(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < FRAME_HEADER_BYTES:
		return {}
	return {
		"from": bytes.decode_s32(OFFSET_FROM),
		"to": bytes.decode_s32(OFFSET_TO),
		"channel": bytes.decode_u8(OFFSET_CHANNEL),
		"mode": bytes.decode_u8(OFFSET_MODE),
		"data": bytes.slice(FRAME_HEADER_BYTES),
	}


## Room code from user input: upper case, without spaces and characters outside the alphabet.
static func normalize_code(text: String) -> String:
	var result := ""
	for character in text.strip_edges().to_upper():
		if ROOM_CODE_ALPHABET.contains(character):
			result += character
	return result.left(ROOM_CODE_LENGTH)


static func is_valid_code(text: String) -> bool:
	return text.length() == ROOM_CODE_LENGTH and normalize_code(text) == text


## Relay URL with the /v1 path (a bare ws://host:port gets it appended).
static func with_ws_path(url: String) -> String:
	var trimmed := url.strip_edges().trim_suffix("/")
	var scheme_end := trimmed.find("://")
	var has_path := scheme_end >= 0 and trimmed.find("/", scheme_end + 3) >= 0
	return trimmed if has_path else trimmed + WS_PATH


## Godot resolves "localhost" to ::1 first and then never reaches a relay that listens on IPv4
## only (the relay's default RELAY_HOST 0.0.0.0): local URLs use 127.0.0.1 instead.
static func prefer_ipv4_loopback(url: String) -> String:
	for scheme in ["ws://", "wss://"]:
		if url.begins_with(scheme + "localhost:") or url.begins_with(scheme + "localhost/") or url == scheme + "localhost":
			return scheme + "127.0.0.1" + url.substr(scheme.length() + "localhost".length())
	return url


static func hello(token: String, protocol_version: int, game_version: String, platform: String) -> Dictionary:
	return {"type": "hello", "token": token, "protocolVersion": protocol_version, "gameVersion": game_version, "platform": platform}


static func create(mode: String, guild_id := "") -> Dictionary:
	var message := {"type": "create", "mode": mode}
	if mode == "guild" and not guild_id.is_empty():
		message["guildId"] = guild_id
	return message


static func join(code: String) -> Dictionary:
	return {"type": "join", "code": code}


## Application heartbeat; the relay answers {"type": "pong", "t": t}.
static func ping(t: int) -> Dictionary:
	return {"type": "ping", "t": t}


## Why a session ends when the relay connection closes while in a room.
static func end_reason_for_close(code: int) -> String:
	match code:
		CLOSE_SHUTDOWN:
			return CLOSED_SHUTDOWN
		CLOSE_TIMEOUT:
			return END_TIMEOUT
		CLOSE_SLOW_CONSUMER:
			return END_SLOW_CONSUMER
		CLOSE_RATE_LIMITED:
			return END_RATE_LIMITED
		CLOSE_BANNED:
			return END_BANNED
	return END_DISCONNECTED


## Host only: the run is over, the room goes back to the lobby (joins and start work again).
static func end_run(reason := "") -> Dictionary:
	var message := {"type": "end_run"}
	if reason in [RUN_END_PORTAL, RUN_END_WIPED, RUN_END_ABANDONED]:
		message["reason"] = reason
	return message
