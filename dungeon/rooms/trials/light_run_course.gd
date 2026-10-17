class_name LightRunCourse
extends TrialCourse
## Lichtlauf (D-112): free-standing torches along the parcours go out one after the
## other once a run starts; whoever is in the dark loses half a heart every 2 s (TrialRules). Reach
## the next torch before your own goes out. The room is dark (TrialContent sets the vision), the
## chest at the finish always glows. Spacing and the beat of the torches come from the dungeon RNG.
## The torch sequence is shared by all players (co-op: whoever starts first lights the fuse; open
## point for MP5), the darkness damage and "flawless" count per player.

## Torches (TESTWERTE): distance along the path, how long each one burns after the one before, the
## head start before the first one goes out, and the pause before all are lit again for a retry.
const SPACING_RANGE := Vector2(170.0, 220.0)
const OUT_INTERVAL_RANGE := Vector2(1.2, 1.7)
const START_GRACE := 1.6
const RELIGHT_DELAY := 2.5
## Light of a torch: the circle drawn into the darkness and the circle that counts as "in the light".
const LIGHT_RADIUS := 160.0
const LIT_RADIUS := 140.0
## Torches stand at the edge of the lane, not in the way.
const SIDE_OFFSET := 44.0
## Stop placing torches this close to the finish (the chest lights it).
const FINISH_CLEARANCE := 90.0

var torches: Array[TrialTorch] = []
## Seconds after the sequence start at which each torch goes out (cumulative).
var out_times: Array[float] = []

var _sequence_time := -1.0
var _dark_time: Dictionary[int, float] = {}


func build(rng: RandomNumberGenerator) -> void:
	var length := TrialLayout.get_path_length()
	var distance := 0.0
	var out_time := START_GRACE
	while distance <= length - FINISH_CLEARANCE:
		var torch := TrialTorch.new()
		torch.build(LIGHT_RADIUS)
		torch.base_position = _side_position(distance)
		torch.position = torch.base_position
		add_child(torch)
		SortLift.lift(torch)
		torches.append(torch)
		out_time += rng.randf_range(OUT_INTERVAL_RANGE.x, OUT_INTERVAL_RANGE.y)
		out_times.append(out_time)
		distance += rng.randf_range(SPACING_RANGE.x, SPACING_RANGE.y)


func is_sequence_running() -> bool:
	return _sequence_time >= 0.0


## Starts the torches' fuse (first run start; again only after all are lit again).
func on_run_started(player: Player) -> void:
	_dark_time[player.get_instance_id()] = 0.0
	if not is_sequence_running():
		_sequence_time = 0.0


func on_run_ended(player: Player) -> void:
	_dark_time.erase(player.get_instance_id())


func advance(delta: float) -> void:
	if not is_sequence_running():
		return
	_sequence_time += delta
	for i in torches.size():
		if torches[i].is_lit() and _sequence_time >= out_times[i]:
			torches[i].set_lit(false)
	var all_out := out_times.is_empty() or _sequence_time >= out_times[out_times.size() - 1] + RELIGHT_DELAY
	if all_out and not content.has_running_players():
		_sequence_time = -1.0
		for torch in torches:
			torch.set_lit(true)


## The light decision of this trial: inside the circle of a burning torch or a permanent light.
## Shared circle test (LightQuery, A9); the players' own circles do not count here on purpose.
func is_lit(point: Vector2) -> bool:
	return LightQuery.is_in_circles(point, LightQuery.circles_from_points(get_lit_points(), LIT_RADIUS))


func get_lit_points() -> PackedVector2Array:
	var points := content.get_permanent_lights() if content != null else PackedVector2Array()
	for torch in torches:
		if torch.is_lit():
			points.append(torch.base_position)
	return points


func get_damage(player: Player, feet: Vector2, delta: float) -> float:
	var id := player.get_instance_id()
	var result := TrialRules.tick_darkness(_dark_time.get(id, 0.0), delta, is_lit(feet))
	_dark_time[id] = result[0]
	return result[1]


func get_dark_time(player: Player) -> float:
	return _dark_time.get(player.get_instance_id(), 0.0)


## Torch spot at distance along the path, moved to the lane's north side (east side in the turn).
func _side_position(distance: float) -> Vector2:
	var here := TrialLayout.get_path_point(distance)
	var ahead := TrialLayout.get_path_point(distance + 4.0)
	var vertical := absf(ahead.x - here.x) < absf(ahead.y - here.y)
	return here + (Vector2(SIDE_OFFSET, 0.0) if vertical else Vector2(0.0, -SIDE_OFFSET))
