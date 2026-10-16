class_name NetInterpolator
extends RefCounted
## Snapshot interpolation for host-driven pictures on a client (online test 16.10.2026: enemies
## "jump" in the dungeon and much more in the side view). Instead of pulling a puppet towards the
## newest position (which steps 10-15 times a second and jumps whenever TCP delivers two snapshots
## at once), every position is stored with the host time it was taken at and the puppet is drawn
## DELAY_MSEC in the host's past, between the two samples around that moment. A late snapshot then
## changes nothing visible as long as it is less than the delay late.
## - Clock: the host sends its Time.get_ticks_msec() with every snapshot (begin_snapshot). The
##   offset host - local follows the fastest arrivals quickly and slower ones slowly, so the drawn
##   time runs evenly and the delay absorbs the jitter.
## - Delta snapshots (NetEnemies leaves out unchanged enemies): an entity missing from a snapshot
##   stood still; its last position is repeated at the previous snapshot's time before a new
##   sample, so it does not glide through the pause, and past its newest sample it is held, not
##   extrapolated. Only when the whole stream is late it is led by its velocity, at most
##   MAX_EXTRAPOLATE_MSEC.
## - Teleports: two samples further apart than teleport_distance are not blended (jump at the
##   newer sample's time).
## Used by NetEnemies (top-down puppets); NetSide's side-view enemies can use it the same way
## (hook in the report of 16.10.2026). Pure data: no node, no physics, testable with explicit times.

## TESTWERTE: render delay behind the host (ms; about 1.5 snapshot intervals at 15/s), the longest
## lead past the newest sample of a late stream, and how much history is kept.
const DELAY_MSEC := 100.0
const MAX_EXTRAPOLATE_MSEC := 100.0
const KEEP_MSEC := 1000.0
## TESTWERT: share of the gap closed per snapshot when packets arrive later than before (the
## offset jumps most of the way to an earlier arrival at once).
const OFFSET_SLOW := 0.02
const OFFSET_FAST := 0.5

var delay_msec := DELAY_MSEC
var teleport_distance := 120.0
## Samples per id: [[host_msec: float, position: Vector2], …], oldest first.
var _samples: Dictionary = {}
## Host time minus local time (ms), NAN until the first snapshot.
var _offset := NAN
## Host time of the newest and of the previous snapshot of the stream.
var _stream_latest := -INF
var _stream_previous := -INF


## A snapshot taken at host_msec arrived now (call before its push calls).
func begin_snapshot(host_msec: float, now_msec: float) -> void:
	var sample := host_msec - now_msec
	if is_nan(_offset):
		_offset = sample
	elif sample > _offset:
		_offset = lerpf(_offset, sample, OFFSET_FAST)
	else:
		_offset = lerpf(_offset, sample, OFFSET_SLOW)
	if host_msec > _stream_latest:
		_stream_previous = _stream_latest
		_stream_latest = host_msec


## Position of id at host_msec (from the snapshot begun last).
func push(id: int, host_msec: float, position: Vector2) -> void:
	var list: Array = _samples.get(id, [])
	if not list.is_empty():
		var last: Array = list.back()
		if host_msec <= float(last[0]):
			return
		# Left out of the snapshots in between: it stood until the previous one.
		if float(last[0]) < _stream_previous and _stream_previous < host_msec:
			list.append([_stream_previous, last[1]])
	list.append([host_msec, position])
	_samples[id] = list
	_prune(list)


func has(id: int) -> bool:
	return _samples.has(id)


func erase(id: int) -> void:
	_samples.erase(id)


func clear() -> void:
	_samples.clear()


## The host time that is drawn now (NAN before the first snapshot).
func render_time(now_msec: float) -> float:
	return now_msec + _offset - delay_msec


## Where id is drawn at local time now_msec (Vector2.INF if unknown).
func position_at(id: int, now_msec: float) -> Vector2:
	var list: Array = _samples.get(id, [])
	if list.is_empty():
		return Vector2.INF
	var newest: Array = list.back()
	if is_nan(_offset) or list.size() == 1:
		return newest[1]
	var t := render_time(now_msec)
	var oldest: Array = list[0]
	if t <= float(oldest[0]):
		return oldest[1]
	if t >= float(newest[0]):
		return _beyond(list, t)
	for i in range(list.size() - 1, 0, -1):
		var a: Array = list[i - 1]
		var b: Array = list[i]
		if t >= float(a[0]):
			var from: Vector2 = a[1]
			var to: Vector2 = b[1]
			if from.distance_to(to) > teleport_distance:
				return from
			var span := float(b[0]) - float(a[0])
			return to if span <= 0.0 else from.lerp(to, (t - float(a[0])) / span)
	return newest[1]


## Past the newest sample: held if the entity was left out of newer snapshots (it stands), led by
## its last velocity for a short time if the whole stream is late.
func _beyond(list: Array, t: float) -> Vector2:
	var newest: Array = list.back()
	var newest_time := float(newest[0])
	if newest_time < _stream_latest:
		return newest[1]
	var before: Array = list[list.size() - 2]
	var span := newest_time - float(before[0])
	var to: Vector2 = newest[1]
	var from: Vector2 = before[1]
	if span <= 0.0 or from.distance_to(to) > teleport_distance:
		return to
	var lead := minf(t - newest_time, MAX_EXTRAPOLATE_MSEC)
	return to + (to - from) * (lead / span)


func _prune(list: Array) -> void:
	if is_nan(_offset) or list.size() <= 2:
		return
	var limit := float(list.back()[0]) - KEEP_MSEC
	var drop := 0
	while drop < list.size() - 2 and float(list[drop + 1][0]) < limit:
		drop += 1
	if drop > 0:
		list.assign(list.slice(drop))
