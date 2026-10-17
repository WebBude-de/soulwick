class_name GauntletCourse
extends TrialCourse
## Spießrutenlauf (D-112): both lanes of the parcours hold spikes, flame jets and
## pendulum blades with their own beats. Every kind appears at least once; order, columns, gaps
## and timing are rolled with the dungeon RNG, so no two rooms play the same.

enum Kind { SPIKES, FLAMES, PENDULUM }

## Free columns between two hazards (TESTWERTE): room to wait for the next gap.
const GAP_RANGE := Vector2i(1, 2)
## Hazards beyond the first three (one of each kind) are drawn at random.
const EXTRA_HAZARDS := 4

var hazards: Array[TrialHazard] = []
## Kind per placed hazard column, in placement order (tests).
var placed_kinds: Array[Kind] = []


func build(rng: RandomNumberGenerator) -> void:
	var queue: Array[Kind] = [Kind.SPIKES, Kind.FLAMES, Kind.PENDULUM]
	_shuffle(queue, rng)
	for i in EXTRA_HAZARDS:
		queue.append(rng.randi_range(0, Kind.size() - 1) as Kind)
	# Lane A runs east from the start, lane B west to the finish.
	var columns_a := _pick_columns(TrialLayout.LANE_A_HAZARD_COLUMNS, rng)
	var columns_b := _pick_columns(TrialLayout.LANE_B_HAZARD_COLUMNS, rng)
	columns_b.reverse()
	for column in columns_a:
		if queue.is_empty():
			break
		_place(queue.pop_front(), TrialLayout.LANE_A, column, rng)
	for column in columns_b:
		if queue.is_empty():
			break
		_place(queue.pop_front(), TrialLayout.LANE_B, column, rng)


func advance(delta: float) -> void:
	for hazard in hazards:
		hazard.advance(delta)


func get_damage(_player: Player, feet: Vector2, _delta: float) -> float:
	for hazard in hazards:
		if hazard.hits(feet, FEET_MARGIN):
			return TrialRules.MISTAKE_DAMAGE
	return 0.0


## Hazard columns of one lane (inclusive range), with GAP_RANGE free columns in between.
func _pick_columns(range_columns: Vector2i, rng: RandomNumberGenerator) -> Array[int]:
	var columns: Array[int] = []
	var x := range_columns.x + rng.randi_range(0, 1)
	while x <= range_columns.y:
		columns.append(x)
		x += 1 + rng.randi_range(GAP_RANGE.x, GAP_RANGE.y)
	return columns


func _place(kind: Kind, lane: Rect2i, column: int, rng: RandomNumberGenerator) -> void:
	var rect := TrialLayout.column_rect(lane, column)
	placed_kinds.append(kind)
	match kind:
		Kind.SPIKES:
			var spikes := TrialSpikes.new()
			spikes.build(rect)
			add_child(spikes)
			spikes.configure(rng, TrialSpikes.IDLE_RANGE, TrialSpikes.WARN_TIME, TrialSpikes.ACTIVE_TIME)
			hazards.append(spikes)
		Kind.FLAMES:
			# One nozzle per lane row. Every second row copies the beat of the first one, shifted by
			# a whole burst: it fires while the other row rests, so one row is always quiet.
			var first: TrialFlameJet = null
			for row in lane.size.y:
				var tile_rect := Rect2(Vector2(column, lane.position.y + row) * RoomTiles.TILE_WORLD, Vector2.ONE * RoomTiles.TILE_WORLD)
				var jet := TrialFlameJet.new()
				jet.build(tile_rect)
				add_child(jet)
				SortLift.lift(jet)
				if row % 2 == 0:
					jet.configure(rng, TrialFlameJet.IDLE_RANGE, TrialFlameJet.WARN_TIME, TrialFlameJet.ACTIVE_TIME)
					first = jet
				else:
					jet.copy_timing(first)
					jet.advance(TrialFlameJet.WARN_TIME + TrialFlameJet.ACTIVE_TIME)
				hazards.append(jet)
		Kind.PENDULUM:
			var pendulum := TrialPendulum.new()
			pendulum.build(rect)
			add_child(pendulum)
			SortLift.lift(pendulum)
			pendulum.configure_swing(rng)
			hazards.append(pendulum)


## Fisher-Yates with the dungeon RNG (Array.shuffle would use the global one).
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
