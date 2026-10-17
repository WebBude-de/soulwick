class_name HostStall
extends RefCounted
## Is the host's game standing still? (Bug of 17.10.2026, D-183: the host's browser tab went into the
## background, its main loop stopped, and every client's own player was pulled back again and again.)
## Pure logic with hysteresis, fed by RelayPeer on a client once per poll with the host's silence:
## ms between this client's last poll and the last game frame of peer 1 (pongs of the relay do not
## count, a hang of this client does not count either, RelayPeer.get_host_silence_msec). A running
## host is never silent on purpose: it sends a beat to every room peer it sent nothing else to for
## BEAT_MSEC (also while that peer loads a world and gets no world data, RelayProtocol.BEAT_PAYLOAD),
## and before a world load of its own one with BEAT_LOADING, after which up to LOAD_GRACE_MSEC of
## silence do not count.
## - STALL_MSEC of silence: stalled. NetPlayerState stops the prediction (own player locked with
##   its own reason and held at the host's position, other players stand, input is sent once and
##   then only every second), NetDungeon keeps waiting as before.
## - NOTICE_MSEC: "Warte auf den Host …" (HostStallNotice); LEAVE_MSEC: the button "Raum verlassen".
## - The stall ends once host frames came with gaps below RESUME_GAP_MSEC for RESUME_MSEC (a host
##   that ticks once a second stays stalled instead of flickering).
## The host side: HOST_AWAY_NOTICE_MSEC is the own frame gap from which the host is told that its
## teammates waited (RelayPeer.host_hitched).

## TESTWERTE (ms): silence from which a client stops predicting (above a double TCP retransmit and a
## short WiFi gap, which stay invisible; below the 1 s history of NetPlayerState minus a round trip of
## up to ~250 ms (host tick included) - with a slower round trip a stalled host's position can pull the
## own player back for a moment before the lock; 500 until the follow-up of 17.10.2026); frames closer
## than RESUME_GAP_MSEC for RESUME_MSEC end the stall.
const STALL_MSEC := 750
const RESUME_GAP_MSEC := 150
const RESUME_MSEC := 300
## TESTWERTE (ms): the notice "Warte auf den Host …" from this long on, the leave button from this
## long on.
const NOTICE_MSEC := 1000
const LEAVE_MSEC := 15000
## TESTWERT (ms): a frame gap of the host itself from which it is told afterwards that the others waited.
const HOST_AWAY_NOTICE_MSEC := 2000
## TESTWERT (ms): the host's beat to a room peer it sent nothing else to for this long (beats go out
## at the host's polls, so at 30 fps 80-113 ms apart: below RESUME_GAP_MSEC, beats alone also end a
## stall; while world data flows, about 30 snapshots a second, no beat is needed; otherwise ~25 bytes
## about 12 times a second per peer).
const BEAT_MSEC := 80
## TESTWERT (ms): after the host announced a world load (beat with BEAT_LOADING) its silence does not
## count for this long (the dungeon start took up to ~2 s on a PC, longer in a browser); the next frame
## of the host ends the grace.
const LOAD_GRACE_MSEC := 8000

var stalled := false
## Local time (ms) of the host's last frame before the current stall (valid while stalled).
var since_msec := 0
## Stalls since the last reset and the longest one (ms, from the last frame before it until the
## frames came back), for NetDiagnostics, tools and tests.
var stall_count := 0
var longest_msec := 0
## While stalled: since when the host's frames come again (-1 = they do not).
var _flow_since := -1


func reset() -> void:
	stalled = false
	since_msec = 0
	_flow_since = -1


## silence_msec: the host's silence at this poll, now_msec: the time of this poll. Returns true when
## stalled changed.
func update(silence_msec: int, now_msec: int) -> bool:
	if not stalled:
		if silence_msec < STALL_MSEC:
			return false
		stalled = true
		since_msec = now_msec - silence_msec
		_flow_since = -1
		stall_count += 1
		return true
	if silence_msec >= RESUME_GAP_MSEC:
		_flow_since = -1
		return false
	if _flow_since < 0:
		_flow_since = now_msec
	if now_msec - _flow_since < RESUME_MSEC:
		return false
	stalled = false
	longest_msec = maxi(longest_msec, _flow_since - since_msec)
	_flow_since = -1
	return true


## How long the current stall lasts (0 when not stalled).
func stall_msec(now_msec: int) -> int:
	return maxi(0, now_msec - since_msec) if stalled else 0


## The notice "Warte auf den Host …" shows.
func shows_notice(now_msec: int) -> bool:
	return stall_msec(now_msec) >= NOTICE_MSEC


## The notice offers to leave the room.
func offers_leave(now_msec: int) -> bool:
	return stall_msec(now_msec) >= LEAVE_MSEC
