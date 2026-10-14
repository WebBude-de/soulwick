class_name ArenaWaves
extends Node2D
## Openings of one arena room and the way enemies come through them (A5, KONZEPT_RAEUME 3.1).
## A plain arena shows a few fixed gates in its walls from the start; an ambush looks like an
## empty room and breaks new holes when its wave comes. Which gates a wave uses is decided here
## (WallGates, dungeon RNG, minimum distance to every player); the look lives in WallBreach.
## An enemy waits hidden, passive and invulnerable inside the wall (Enemy.begin_intro), then
## steps into the room and fights. Child of the RoomController at the room origin.

## Emitted when an enemy has stepped out of the wall and starts to fight.
signal enemy_emerged(enemy: Enemy)

## Fixed gates of a plain arena. TESTWERT
const GATE_COUNT := 5
## Seconds the wall cracks / the grate rattles before the first enemy comes. TESTWERT
const TELEGRAPH_TIME := 0.55
## Seconds to step from the wall onto the floor. TESTWERT
const EMERGE_TIME := 0.35
## Enemies sharing a gate come one after the other. TESTWERT
const SAME_GATE_DELAY := 0.4
## Ambush: the walls give way this long after the entrance door has closed. TESTWERT
const AMBUSH_DELAY := 0.3
## Extra hold time on top of the planned emergence, so a lost tween can never keep an enemy
## passive for long (Enemy.begin_intro ends by itself).
const HOLD_MARGIN := 0.3

var is_ambush := false

var _gates: Array[WallGates.Gate] = []
var _fixed: Array[WallGates.Gate] = []
var _views: Dictionary = {}
## Enemies still to come out per opening; a gate closes after the last one.
var _pending: Dictionary = {}
var _rng: RandomNumberGenerator = null
var _built := false
var _last_gates: Array[WallGates.Gate] = []


func _init() -> void:
	name = "ArenaWaves"
	y_sort_enabled = true


## gates: every possible opening of the room (WallGates.find_gates). A plain arena places its
## fixed gates right away (dungeon RNG, drawn while the room is prepared).
func setup(gates: Array[WallGates.Gate], ambush: bool, rng: RandomNumberGenerator) -> void:
	_gates = gates
	is_ambush = ambush
	_rng = rng
	_built = true
	if not is_ambush:
		_fixed = WallGates.place(gates, GATE_COUNT, WaveRules.MIN_SIDES, rng)
		for gate in _fixed:
			_view_for(gate)


## True once setup() has run (the room builds its gates one frame after it was prepared).
func is_built() -> bool:
	return _built


func get_gates() -> Array[WallGates.Gate]:
	return _gates


## Fixed gates of a plain arena (empty for an ambush).
func get_fixed_gates() -> Array[WallGates.Gate]:
	return _fixed


## Number of different openings: more enemies than that per wave become an extra wave (D-086).
func get_capacity() -> int:
	return _gates.size()


## Openings for count enemies of wave (1-based). The first ambush wave comes from (almost) every
## wall. A plain arena uses its fixed gates; when players stand so that fewer than MIN_SIDES of
## them keep the distance, new holes break open elsewhere.
func choose_gates(count: int, wave: int, player_positions: Array[Vector2]) -> Array[WallGates.Gate]:
	var min_sides := WaveRules.AMBUSH_MIN_SIDES if is_ambush and wave == 1 else WaveRules.MIN_SIDES
	var pool := _fixed
	if is_ambush or WallGates.count_sides(WallGates.filter_by_distance(_fixed, player_positions, WaveRules.MIN_PLAYER_DISTANCE)) < WaveRules.MIN_SIDES:
		pool = _gates
	_last_gates = WallGates.pick(pool, count, player_positions, WaveRules.MIN_PLAYER_DISTANCE, min_sides, _rng)
	return _last_gates


## Openings of the latest wave (tests, tools).
func get_last_gates() -> Array[WallGates.Gate]:
	return _last_gates


## Hides the freshly spawned enemies in the walls behind their gates and lets them come out one
## after another. enemies[i] uses gates[i % gates.size()]. start_delay: extra wait (ambush).
func release(enemies: Array[Enemy], gates: Array[WallGates.Gate], start_delay := 0.0) -> void:
	if gates.is_empty():
		return
	var queued := {}
	for i in enemies.size():
		var enemy := enemies[i]
		var gate := gates[i % gates.size()]
		var view := _view_for(gate)
		var place: int = queued.get(view, 0)
		queued[view] = place + 1
		if place == 0:
			_start_telegraph(view, start_delay)
		_pending[view] = int(_pending.get(view, 0)) + 1
		_hold(enemy, gate, view, start_delay + TELEGRAPH_TIME + place * SAME_GATE_DELAY, i == 0)


## Delay until the last of count enemies sharing one gate is out (tests, tools).
static func get_release_time(per_gate: int, start_delay := 0.0) -> float:
	return start_delay + TELEGRAPH_TIME + maxi(0, per_gate - 1) * SAME_GATE_DELAY + EMERGE_TIME


func get_view(gate: WallGates.Gate) -> WallBreach:
	return _views.get(gate.wall_tile)


func _view_for(gate: WallGates.Gate) -> WallBreach:
	var view: WallBreach = _views.get(gate.wall_tile)
	if view != null:
		return view
	view = WallBreach.new()
	view.name = "Breach_%d_%d" % [gate.wall_tile.x, gate.wall_tile.y]
	view.position = gate.get_edge_position()
	add_child(view)
	var mode := WallBreach.Mode.GATE if _fixed.has(gate) else WallBreach.Mode.BREACH
	view.setup(mode, gate.get_inward(), gate.wall_tile.x * 73 + gate.wall_tile.y * 31)
	_views[gate.wall_tile] = view
	return view


func _start_telegraph(view: WallBreach, delay: float) -> void:
	if delay <= 0.0:
		view.telegraph(TELEGRAPH_TIME)
		return
	var tween := view.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(view.telegraph.bind(TELEGRAPH_TIME))


func _hold(enemy: Enemy, gate: WallGates.Gate, view: WallBreach, delay: float, first: bool) -> void:
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	enemy.global_position = to_global(gate.get_wall_position())
	enemy.visible = false
	enemy.begin_intro(delay + EMERGE_TIME + HOLD_MARGIN)
	var tween := enemy.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_step_out.bind(enemy, view, first))
	tween.tween_property(enemy, "global_position", to_global(gate.get_floor_position()), EMERGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_emerged.bind(enemy, view))


func _step_out(enemy: Enemy, view: WallBreach, first: bool) -> void:
	if is_instance_valid(view):
		view.burst(first)
	if is_instance_valid(enemy) and not enemy.is_dead():
		enemy.visible = true


func _emerged(enemy: Enemy, view: WallBreach) -> void:
	if is_instance_valid(view):
		_pending[view] = int(_pending.get(view, 1)) - 1
		if _pending[view] <= 0:
			view.settle()
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	enemy.end_intro()
	enemy_emerged.emit(enemy)
