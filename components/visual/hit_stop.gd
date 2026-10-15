class_name HitStop
extends RefCounted
## Brief freeze/slow-motion for impact (kills, player hits, death) via Engine.time_scale.
## Every trigger gets a token; only the newest trigger's timer restores normal speed, so overlapping
## triggers never leave the game slowed down. The timer ignores time scale and pause.
## Single player only (D-085, D-123): in a group game the shared time never changes, so the
## GameMode of the context decides whether a trigger does anything.

const FREEZE_SCALE := 0.05

static var _token := 0


static func trigger(context: Node, duration: float, time_scale := FREEZE_SCALE) -> void:
	if context == null or not context.is_inside_tree():
		return
	if not GameOptions.is_hit_stop_enabled():
		return
	if not GameMode.of(context).allows_hit_stop():
		return
	_token += 1
	Engine.time_scale = minf(Engine.time_scale, time_scale)
	var timer := context.get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(_release.bind(_token))


static func reset() -> void:
	_token += 1
	Engine.time_scale = 1.0


static func _release(token: int) -> void:
	if token == _token:
		Engine.time_scale = 1.0
