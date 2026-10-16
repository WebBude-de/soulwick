class_name NetDiagnostics
extends RefCounted
## Network diagnostics of one relay connection (online test 16.10.2026: music stutter on both
## machines, then a client was thrown out). One instance per RelayPeer.open; the newest one is
## "current" for the static helpers, so the F9 bug report (ui/dev/dev_feedback.gd) and the lobby can
## read it without a node: NetDiagnostics.snapshot() is a compact Dictionary (rates per second,
## totals, round trip, buffers, longest frame hitch, last disconnect with close code and reason).
## - Rates: WebSocket frames, logical game packets (a bundle carries several) and bytes per second
##   in both directions; "rate" is the last full second, "peak" the busiest second of the session.
## - Frame hitches: the gap between two polls of the peer (the multiplayer polls every frame). A gap
##   of HITCH_MSEC or more counts, LOG_HITCH_MSEC or more is logged with the current numbers.
## - Disconnects: note_disconnect stores the reason in the static last_disconnect, which outlives the
##   session (the report after being thrown out still has it) and is logged once.
## SOULWICK_NET_STATS=<seconds> (environment) logs one summary line per interval while in a room
## (tools, test evenings); off by default.

## TESTWERT: frame gap (ms) that counts as a hitch, and the one that is logged at once.
const HITCH_MSEC := 250
const LOG_HITCH_MSEC := 1000
## Length of one rate bucket.
const WINDOW_MSEC := 1000
## Keys of the per-second counters.
const RATE_KEYS: Array[String] = ["frames_out", "packets_out", "bytes_out", "frames_in", "packets_in", "bytes_in"]

## The diagnostics of the newest connection (weak: a freed peer leaves nothing behind).
static var _current: WeakRef = null
## The last disconnect of any session on this machine ({} before the first).
static var last_disconnect: Dictionary = {}

var role := ""
var room_code := ""
var opened_msec := 0
## Totals since open.
var totals := {
	"frames_out": 0, "packets_out": 0, "bytes_out": 0,
	"frames_in": 0, "packets_in": 0, "bytes_in": 0,
	"bundles_out": 0, "bundles_in": 0,
	"dropped_out": 0, "dropped_in": 0, "send_errors": 0,
	"relay_errors": 0, "hitches": 0,
}
## Error codes of the relay ({code: count}), e.g. rate_limited, frame_too_large.
var relay_errors: Dictionary = {}
## Last full second and the busiest second (per key).
var rate: Dictionary = {}
var peak: Dictionary = {}
var rtt_last := -1
var rtt_min := -1
var rtt_max := -1
## Smoothed round trip (ms), -1 before the first pong.
var rtt_avg := -1.0
var outbound_buffered := 0
var outbound_buffered_max := 0
var incoming_queue_max := 0
var largest_frame_out := 0
var largest_frame_in := 0
var longest_hitch_msec := 0
var last_hitch_msec := 0
var last_hitch_at := ""
## Bundling to the remote peers is on (both sides speak it, RelayPeer).
var bundling := false

var _bucket: Dictionary = {}
var _bucket_start := 0
var _last_poll_usec := 0
var _log_every_msec := 0
var _next_log_msec := 0


func _init(now_msec := -1) -> void:
	opened_msec = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	_bucket_start = opened_msec
	for key in RATE_KEYS:
		_bucket[key] = 0
		rate[key] = 0
		peak[key] = 0
	var every := OS.get_environment("SOULWICK_NET_STATS")
	if not every.is_empty():
		_log_every_msec = int(maxf(1.0, every.to_float()) * 1000.0)
		_next_log_msec = opened_msec + _log_every_msec


## Makes this the diagnostics the static helpers read.
func make_current() -> void:
	_current = weakref(self)


static func current() -> NetDiagnostics:
	return _current.get_ref() as NetDiagnostics if _current != null else null


# --- Counting (RelayPeer) ---

func note_sent(frame_bytes: int, packets := 1, bundled := false) -> void:
	totals.frames_out += 1
	totals.packets_out += packets
	totals.bytes_out += frame_bytes
	_bucket.frames_out += 1
	_bucket.packets_out += packets
	_bucket.bytes_out += frame_bytes
	largest_frame_out = maxi(largest_frame_out, frame_bytes)
	if bundled:
		totals.bundles_out += 1


func note_received(frame_bytes: int, packets := 1, bundled := false) -> void:
	totals.frames_in += 1
	totals.packets_in += packets
	totals.bytes_in += frame_bytes
	_bucket.frames_in += 1
	_bucket.packets_in += packets
	_bucket.bytes_in += frame_bytes
	largest_frame_in = maxi(largest_frame_in, frame_bytes)
	if bundled:
		totals.bundles_in += 1


## An unreliable packet not sent (own send buffer too full) or dropped from an old backlog.
func note_dropped(outgoing: bool, count := 1) -> void:
	totals["dropped_out" if outgoing else "dropped_in"] += count


func note_send_error() -> void:
	totals.send_errors += 1


func note_relay_error(code: String) -> void:
	totals.relay_errors += 1
	relay_errors[code] = int(relay_errors.get(code, 0)) + 1


func note_rtt(msec: int) -> void:
	rtt_last = msec
	rtt_min = msec if rtt_min < 0 else mini(rtt_min, msec)
	rtt_max = maxi(rtt_max, msec)
	rtt_avg = float(msec) if rtt_avg < 0.0 else lerpf(rtt_avg, float(msec), 0.2)


func note_buffers(outbound: int, incoming_queue: int) -> void:
	outbound_buffered = outbound
	outbound_buffered_max = maxi(outbound_buffered_max, outbound)
	incoming_queue_max = maxi(incoming_queue_max, incoming_queue)


## Called on every poll: frame hitches, the rate buckets and the optional periodic log line.
## Returns the gap since the previous poll in ms (0 on the first).
func note_poll(now_msec: int, now_usec := -1) -> int:
	var usec := now_usec if now_usec >= 0 else Time.get_ticks_usec()
	var gap := 0
	if _last_poll_usec > 0:
		gap = int((usec - _last_poll_usec) / 1000)
		if gap >= HITCH_MSEC:
			totals.hitches += 1
			last_hitch_msec = gap
			last_hitch_at = Time.get_datetime_string_from_system()
			longest_hitch_msec = maxi(longest_hitch_msec, gap)
			if gap >= LOG_HITCH_MSEC:
				push_warning("NetDiagnostics: frame hitch of %d ms in room %s. %s" % [gap, room_code, summary_line()])
	_last_poll_usec = usec
	_roll(now_msec)
	if _log_every_msec > 0 and now_msec >= _next_log_msec:
		_next_log_msec = now_msec + _log_every_msec
		print("[net] ", summary_line())
	return gap


## Forget the poll time (the owner stops polling for a while on purpose, e.g. a scene change).
func reset_poll_clock() -> void:
	_last_poll_usec = 0


func _roll(now_msec: int) -> void:
	if now_msec - _bucket_start < WINDOW_MSEC:
		return
	var seconds := float(now_msec - _bucket_start) / 1000.0
	for key in RATE_KEYS:
		# A hitch spreads its bucket over the whole gap (no fake peak after a long frame).
		var value := int(round(float(_bucket[key]) / maxf(1.0, seconds)))
		rate[key] = value
		peak[key] = maxi(int(peak[key]), value)
		_bucket[key] = 0
	_bucket_start = now_msec


func note_disconnect(code: int, reason: String, end_reason: String, silence_seconds: float, now_msec := -1) -> void:
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	last_disconnect = {
		"at": Time.get_datetime_string_from_system(),
		"role": role,
		"room": room_code,
		"code": code,
		"reason": reason,
		"end_reason": end_reason,
		"silence_s": snappedf(silence_seconds, 0.1),
		"session_s": snappedf(float(now - opened_msec) / 1000.0, 0.1),
		"rtt_ms": rtt_last,
		"longest_hitch_ms": longest_hitch_msec,
		"last_hitch_ms": last_hitch_msec,
		"outbound_buffered_max": outbound_buffered_max,
		"relay_errors": relay_errors.duplicate(),
	}


# --- Reading ---

## Compact copy of the counters (JSON-friendly).
func to_dict(now_msec := -1) -> Dictionary:
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return {
		"role": role,
		"room": room_code,
		"session_s": snappedf(float(now - opened_msec) / 1000.0, 0.1),
		"bundling": bundling,
		"rtt_ms": {"last": rtt_last, "avg": int(round(rtt_avg)), "min": rtt_min, "max": rtt_max},
		"rate": rate.duplicate(),
		"peak": peak.duplicate(),
		"totals": totals.duplicate(),
		"relay_errors": relay_errors.duplicate(),
		"outbound_buffered": outbound_buffered,
		"outbound_buffered_max": outbound_buffered_max,
		"incoming_queue_max": incoming_queue_max,
		"largest_frame": {"out": largest_frame_out, "in": largest_frame_in},
		"hitch_ms": {"longest": longest_hitch_msec, "last": last_hitch_msec, "count": totals.hitches, "last_at": last_hitch_at},
	}


## Counters to compare a later state with (since()).
func mark(now_msec := -1) -> Dictionary:
	var copy := totals.duplicate()
	copy["msec"] = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return copy


## Averages per second between mark and now: frames, packets and bytes in both directions.
func since(start: Dictionary, now_msec := -1) -> Dictionary:
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var seconds := maxf(0.001, float(now - int(start.get("msec", now))) / 1000.0)
	var result := {"seconds": snappedf(seconds, 0.1)}
	for key in RATE_KEYS:
		result[key + "_per_s"] = snappedf(float(int(totals[key]) - int(start.get(key, 0))) / seconds, 0.1)
	for key in ["dropped_out", "dropped_in", "send_errors", "relay_errors", "hitches"]:
		result[key] = int(totals[key]) - int(start.get(key, 0))
	return result


## One log line: rates (last second), round trip, buffers, hitches, errors.
func summary_line() -> String:
	return "%s room %s: out %d fr/%d pk/%d B/s, in %d fr/%d pk/%d B/s (peak out %d B/s %d fr/s, in %d B/s %d fr/s), rtt %d ms (avg %d, max %d), outbuf %d (max %d), inqueue max %d, hitch max %d ms (%d), dropped out %d in %d, send errors %d, relay errors %s, bundling %s" % [
		role, room_code, rate.frames_out, rate.packets_out, rate.bytes_out, rate.frames_in, rate.packets_in, rate.bytes_in,
		peak.bytes_out, peak.frames_out, peak.bytes_in, peak.frames_in, rtt_last, int(round(rtt_avg)), rtt_max,
		outbound_buffered, outbound_buffered_max, incoming_queue_max, longest_hitch_msec, totals.hitches,
		totals.dropped_out, totals.dropped_in, totals.send_errors, relay_errors, bundling]


# --- Static helpers (F9 report, lobby message) ---

## Compact snapshot for bug reports: the current connection (if any), the last disconnect and the
## frame rate. Safe to call at any time, also without any online session ({"online": false}).
static func snapshot() -> Dictionary:
	var result := {"online": false, "fps": Engine.get_frames_per_second()}
	var diagnostics := current()
	if diagnostics != null:
		result["online"] = true
		result["connection"] = diagnostics.to_dict()
	if not last_disconnect.is_empty():
		result["last_disconnect"] = last_disconnect.duplicate(true)
	var music_hitch := _music_hitch_ms()
	if music_hitch >= 0:
		# MusicPlayer measures main-thread stalls on its own (also offline, also in the browser,
		# where the main thread mixes the sound: a stall there is the "stuck record").
		result["music_hitch_ms"] = music_hitch
	return result


## Longest main-thread stall the music player saw (-1 without a music player).
static func _music_hitch_ms() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return -1
	var longest := -1
	for node in tree.root.find_children("*", "Node", true, false):
		if node.has_method(&"get_longest_hitch_ms"):
			longest = maxi(longest, int(node.call(&"get_longest_hitch_ms")))
	return longest


## One line for the player or the log: why the last session ended ("" if none ended yet).
## Example: "slow_consumer (close 4010 'slow consumer') 20:14:03, last data 0.2 s ago, rtt 85 ms,
## longest hitch 3400 ms".
static func describe_last_disconnect() -> String:
	if last_disconnect.is_empty():
		return ""
	var d := last_disconnect
	var text := "%s (close %d '%s') %s, last data %.1f s ago, rtt %d ms" % [d.end_reason, d.code, d.reason, str(d.at).get_slice("T", 1), d.silence_s, d.rtt_ms]
	if int(d.longest_hitch_ms) >= HITCH_MSEC:
		text += ", longest hitch %d ms" % d.longest_hitch_ms
	if not (d.relay_errors as Dictionary).is_empty():
		text += ", relay errors %s" % d.relay_errors
	return text


## Tests: forget the current connection and the last disconnect.
static func reset_static() -> void:
	_current = null
	last_disconnect = {}
