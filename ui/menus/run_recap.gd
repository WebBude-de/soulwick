class_name RunRecap
extends Node
## Collects the numbers of the current run for the run end screen (UX1): kills, cleared rooms,
## upgrades taken, play time and what hit the player last (cause of death). Only listens to global
## signals and the local player's hurtbox; decides nothing. Lives under GameUI (game.tscn).
## RunManager.get_last_summary() keeps room, gold and crystals; get_stats() adds the rest.
##
## Multiplayer later: one recap per local view; kills are counted for the whole group today.

const UNKNOWN_CAUSE := ""
## Damage tags of traps without a source node -> translation key of their name (D-111;
## dungeon/environment/traps).
const TRAP_CAUSES: Array[Array] = [
	[&"fire", &"RECAP_CAUSE_FIRE"],
	[&"poison", &"RECAP_CAUSE_POISON"],
	[&"trap", &"RECAP_CAUSE_TRAP"],
	[&"pit", &"RECAP_CAUSE_PIT"],
]

var kills := 0
var rooms_cleared := 0
var upgrades := 0
## Unpaused run time in seconds (dialogs and the pause menu do not count).
var play_time := 0.0
## Name of what dealt the last health damage ("" = unknown), in the language of that moment.
var last_hit_by := UNKNOWN_CAUSE
## Deepest room of the save before this run (for "Neuer Rekord!").
var record_before := 0

var _running := false
var _player: Player = null


func _ready() -> void:
	# Counts game time only: stops with the tree pause like the world.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.room_completed.connect(_on_room_completed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.upgrade_acquired.connect(_on_upgrade_acquired)


func _process(delta: float) -> void:
	if _running:
		# Engine.time_scale (HitStop) slows delta down; real seconds are what the player feels.
		play_time += delta / maxf(Engine.time_scale, 0.01)


## The local player whose hits are watched (WorldController calls this for every new player).
func bind_player(player: Player) -> void:
	if _player != null and is_instance_valid(_player) and _player.hurtbox.hit_received.is_connected(_on_player_hit):
		_player.hurtbox.hit_received.disconnect(_on_player_hit)
	_player = player
	if player != null:
		player.hurtbox.hit_received.connect(_on_player_hit)


func reset() -> void:
	kills = 0
	rooms_cleared = 0
	upgrades = 0
	play_time = 0.0
	last_hit_by = UNKNOWN_CAUSE
	record_before = int(SaveManager.get_stat(StatsTracker.DEEPEST_ROOM))
	_running = true


func is_running() -> bool:
	return _running


## kills, rooms_cleared, upgrades, play_time (s), cause ("" = unknown), record_before.
func get_stats() -> Dictionary:
	return {
		"kills": kills,
		"rooms_cleared": rooms_cleared,
		"upgrades": upgrades,
		"play_time": play_time,
		"cause": last_hit_by,
		"record_before": record_before,
	}


## Name of what dealt damage: the enemy (with elite prefix) or the trap kind (current language).
static func describe_hit(damage: DamageData) -> String:
	if damage == null:
		return UNKNOWN_CAUSE
	var source: Node = damage.source if is_instance_valid(damage.source) else null
	var enemy := source as Enemy
	if enemy != null and enemy.data != null:
		return enemy.get_display_name()
	for entry in TRAP_CAUSES:
		if damage.tags.has(entry[0]):
			return Loc.t(entry[1])
	return UNKNOWN_CAUSE


## "4:07" or "1:02:09".
static func format_duration(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	var hours := floori(total / 3600.0)
	var minutes := floori(total / 60.0) % 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%d:%02d" % [minutes, secs]


func _on_run_started() -> void:
	reset()


func _on_run_ended(_reason: int, _remaining: int, _payout: int) -> void:
	_running = false


func _on_room_completed(_room_index: int) -> void:
	if _running:
		rooms_cleared += 1


func _on_enemy_damaged(_enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
	if _running and result != null and result.killed:
		kills += 1


func _on_upgrade_acquired(_upgrade_id: StringName, _stacks: int) -> void:
	if _running:
		upgrades += 1


func _on_player_hit(result: DamageResult, damage: DamageData) -> void:
	if not _running or result == null or result.health_damage <= 0.0:
		return
	last_hit_by = describe_hit(damage)
