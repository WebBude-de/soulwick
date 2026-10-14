class_name StatsTracker
extends Node
## Collects the chronicle statistics from global signals and stores them in SaveManager (D-078).
## Not an autoload: lives as a plain node in game.tscn. Play time counts while game.tscn is open
## (also in dialogs) and is flushed to the save on run start/end and when the node leaves the tree.
## Also records the village unlock events (MetaUnlocks, D-087): first finished run and first crystal
## at the run end, the first defeated boss right away (saved at once, it opens forge upgrades).

const RUNS: StringName = &"runs"
const DEATHS: StringName = &"deaths"
const EXITS: StringName = &"exits"
const DEEPEST_ROOM: StringName = &"deepest_room"
const ROOMS_CLEARED: StringName = &"rooms_cleared"
const KILLS: StringName = &"kills"
const BOSSES: StringName = &"bosses"
const CHAMPIONS: StringName = &"champions"
const GOLD_EARNED: StringName = &"gold_earned"
const GOLD_BANKED: StringName = &"gold_banked"
const BEST_RUN_GOLD: StringName = &"best_run_gold"
const CRYSTALS_EARNED: StringName = &"crystals_earned"
const PLAY_TIME: StringName = &"play_time"

## Unsaved play time is moved into SaveManager (memory only) at this interval.
const FLUSH_INTERVAL := 1.0

var _unflushed_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.room_completed.connect(_on_room_completed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func _process(delta: float) -> void:
	_unflushed_time += delta
	if _unflushed_time >= FLUSH_INTERVAL:
		_flush_time()


func _exit_tree() -> void:
	_flush_time()
	SaveManager.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_time()
		SaveManager.save_game()


## Human-readable play time, e.g. "3 h 07 min" or "12 min".
static func format_play_time(seconds: float) -> String:
	var minutes := floori(seconds / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	return "%d h %02d min" % [minutes / 60, minutes % 60]


func _flush_time() -> void:
	if _unflushed_time > 0.0:
		SaveManager.add_stat(PLAY_TIME, _unflushed_time)
		_unflushed_time = 0.0


func _on_run_started() -> void:
	SaveManager.add_stat(RUNS, 1)
	_flush_time()
	SaveManager.save_game()


func _on_run_ended(reason: int, _remaining: int, payout: int) -> void:
	var summary := RunManager.get_last_summary()
	if reason == RunManager.EndReason.DEATH:
		SaveManager.add_stat(DEATHS, 1)
	elif reason == RunManager.EndReason.EXIT:
		SaveManager.add_stat(EXITS, 1)
	var earned: int = summary.get("gold_earned", 0)
	SaveManager.add_stat(GOLD_EARNED, earned)
	SaveManager.record_stat_max(BEST_RUN_GOLD, earned)
	SaveManager.add_stat(GOLD_BANKED, payout)
	SaveManager.add_stat(CRYSTALS_EARNED, summary.get("crystal_payout", 0))
	SaveManager.record_stat_max(DEEPEST_ROOM, summary.get("room", 0))
	# Any finished run counts (also an abort); crystals and bosses follow from the statistics.
	MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_RUN)
	MetaUnlocks.sync_from_save()
	_flush_time()
	SaveManager.save_game()


func _on_room_entered(room_index: int) -> void:
	SaveManager.record_stat_max(DEEPEST_ROOM, room_index)


func _on_room_completed(_room_index: int) -> void:
	SaveManager.add_stat(ROOMS_CLEARED, 1)


func _on_enemy_damaged(enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
	if result == null or not result.killed:
		return
	SaveManager.add_stat(KILLS, 1)
	var foe := enemy as Enemy
	if foe == null or foe.data == null:
		return
	if foe.data.is_boss:
		SaveManager.add_stat(BOSSES, 1)
		if MetaUnlocks.record_event(MetaUnlocks.EVENT_FIRST_BOSS):
			SaveManager.save_game()
	elif foe.is_miniboss:
		SaveManager.add_stat(CHAMPIONS, 1)
