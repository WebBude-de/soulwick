class_name ArenaObjective
extends RoomObjective
## The arena as a room goal (KONZEPT_RAEUME_V2 §3.2, R3): "Überlebe N Wellen", task bar
## "Welle 1/N · x Gegner", between two waves "Welle 2/N kommt …" (wave_cleared: DungeonUI shows
## the wave banner and plays the gong). Reads the room only (get_wave_progress, get_wave_alive,
## get_alive_enemy_count, wave_started, completed); it never changes the fight.

## The running wave is down and another one follows (DungeonUI: banner "Welle 2/3" + gong).
signal wave_cleared(next_wave: int, total: int)

## Pause between two arena waves (07_ui.md: 2 s with "Welle 2/3" and a gong). Hook for
## RoomController.check_completion (see get_wave_pause). TESTWERT
const WAVE_PAUSE := 2.0

var _room: RoomController = null
var _between := false
var _cleared_wave := 0


## The arena goal of room (created and attached once; an existing one is returned).
static func attach_to(arena_room: RoomController) -> ArenaObjective:
	var existing := RoomObjective.of_room(arena_room) as ArenaObjective
	if existing != null:
		return existing
	var objective := ArenaObjective.new()
	objective.bind_room(arena_room)
	RoomObjective.attach(arena_room, objective)
	return objective


## Hook for RoomController.check_completion: seconds to wait before the next wave (0 = at once).
static func get_wave_pause(target_room: Node) -> float:
	return WAVE_PAUSE if RoomObjective.of_room(target_room) is ArenaObjective else 0.0


## Waves the arena will fight: the real plan once the fight runs, the rolled count before.
static func planned_waves(arena_room: RoomController) -> int:
	if arena_room.is_encounter_started():
		return maxi(1, arena_room.get_wave_progress().y)
	return maxi(1, WaveRules.get_wave_count(arena_room.room_index, true))


func bind_room(arena_room: RoomController) -> void:
	setup_mode(RoomObjective.ARENA)
	genre = RoomGenre.AMBUSH if arena_room.is_ambush_room() else RoomGenre.ARENA
	_room = arena_room
	room = arena_room
	goal_args = [planned_waves(arena_room)]
	arena_room.wave_started.connect(_on_wave_started)
	arena_room.completed.connect(_on_completed)
	_refresh()


func get_wave() -> int:
	return _room.get_wave_progress().x if _room != null and _room.is_encounter_started() else 0


func get_total_waves() -> int:
	return planned_waves(_room) if _room != null else 1


## true between two waves (the running one is down, the next one not out yet).
func is_between_waves() -> bool:
	return _between


func _process(delta: float) -> void:
	super(delta)
	if is_finished() or _room == null or not is_instance_valid(_room) or not _room.is_encounter_started():
		return
	var progress := _room.get_wave_progress()
	if not _between and progress.x < progress.y and _room.get_wave_alive(progress.x) <= 0 and _cleared_wave < progress.x:
		_between = true
		_cleared_wave = progress.x
		wave_cleared.emit(progress.x + 1, progress.y)
	_refresh()


func _refresh() -> void:
	if _room == null or not is_instance_valid(_room) or is_finished():
		return
	var total := get_total_waves()
	goal_args = [total]
	if not _room.is_encounter_started():
		set_label(DungeonTexts.t(&"OBJECTIVE_ARENA_READY", [total]))
		return
	var wave := get_wave()
	if _between:
		set_label(DungeonTexts.t(&"OBJECTIVE_ARENA_NEXT", [mini(wave + 1, total), total]))
		return
	set_label(DungeonTexts.t(&"OBJECTIVE_ARENA_WAVE", [wave, total, _room.get_alive_enemy_count()]))


func _on_wave_started(_r: RoomController, wave: int, total: int) -> void:
	_between = false
	if _cleared_wave < wave - 1:
		# The next wave came within the frame the last one fell (no pause in the room): the wave
		# change is still announced, now.
		_cleared_wave = wave - 1
		wave_cleared.emit(wave, total)
	_refresh()


func _on_completed(_r: RoomController) -> void:
	finish(true)
