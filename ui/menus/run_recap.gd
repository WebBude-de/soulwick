class_name RunRecap
extends Node
## Collects the numbers of the current run for the run end screen (UX1): kills, cleared rooms,
## upgrades taken, play time and what hit the player last (cause of death). Only listens to global
## signals and the local player's hurtbox; decides nothing. Lives under GameUI (game.tscn).
## RunManager.get_last_summary() keeps room, gold and crystals; get_stats() adds the rest.
##
## Account level (D-188, KF2): at the run end the run is counted once for the account
## (AccountProgress.record_run with this run's id, rooms, champions, bosses, record, portal, daily
## bonus, +20 % with 2–4 players); create_xp_view() builds the "+XP" block of the run end dialog
## (XpGainView). Each client counts only its own player, the host never counts for others.
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
## Bosses and champions (minibosses) defeated this run (account XP, KF2).
var bosses := 0
var champions := 0
## Id of this run for the account XP (once per run and player), "" before the first run.
var run_id := ""
## Account record (deepest room over all worlds) before this run.
var account_record_before := 0
var _xp_result: Dictionary = {}

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
	bosses = 0
	champions = 0
	run_id = AccountProgress.new_run_id()
	_xp_result = {}
	# Loaded now, before the run changes any world: a first file takes the worlds' record.
	account_record_before = AccountProgress.current().best_room
	_running = true


func is_running() -> bool:
	return _running


## kills, rooms_cleared, upgrades, play_time (s), cause ("" = unknown), record_before, bosses,
## champions.
func get_stats() -> Dictionary:
	return {
		"bosses": bosses,
		"champions": champions,
		"kills": kills,
		"rooms_cleared": rooms_cleared,
		"upgrades": upgrades,
		"play_time": play_time,
		"cause": last_hit_by,
		"record_before": record_before,
	}


## Counts this run for the account level once (AccountProgress.record_run, D-188 KF2) and returns
## the result {"added", "xp", "parts", "xp_before", "xp_after", "level_before", "level_after"}, also on
## later calls. {} while the run is still on or without a run (a run end shown by a test).
func award_xp() -> Dictionary:
	if not _xp_result.is_empty() or run_id.is_empty() or RunManager.is_run_active():
		return _xp_result
	var summary := RunManager.get_last_summary()
	var run := {
		"rooms_cleared": rooms_cleared,
		"champions": champions,
		"bosses": bosses,
		"room": int(summary.get("room", 0)),
		"record_before": account_record_before,
		"exit": int(summary.get("reason", -1)) == RunManager.EndReason.EXIT,
		"end_reason": xp_end_reason(int(summary.get("reason", -1))),
		"players": GameMode.of(self).get_player_count(),
		"duration": roundi(play_time),
	}
	_xp_result = AccountProgress.current().record_run(run_id, run)
	return _xp_result


## RunManager.EndReason -> the contract's end reason of an XP entry (portal, wiped, abandoned).
static func xp_end_reason(reason: int) -> String:
	match reason:
		RunManager.EndReason.EXIT:
			return AccountProgress.END_PORTAL
		RunManager.EndReason.DEATH:
			return AccountProgress.END_WIPED
	return AccountProgress.END_ABANDONED


func get_xp_result() -> Dictionary:
	return _xp_result


## The "+XP" block for the run end dialog (hook for GameUI.show_run_end): XpGainView of this run's
## account XP, null when there is none (no run).
func create_xp_view() -> XpGainView:
	var result := award_xp()
	if result.is_empty():
		return null
	return XpGainView.create(result)


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


## "Neuer Rekord!": deeper than the record before; the first run (no record yet) always is one (P1-3).
static func is_new_record(room: int, record_before: int) -> bool:
	if record_before <= 0:
		return room >= 1
	return room > record_before


## The cheapest forge step for the run end (P1-3, rules of MetaProgression and MetaUnlocks, read
## only): {"id", "level" (the level it would buy), "cost", "missing" (gold still missing, 0 =
## affordable now)}; ties keep the forge order. {} when every open upgrade is at its limit.
## gold: village gold to compare with (-1 = the save's permanent gold). Same rule as the village's
## "!" over the forge (world/village/village_affordable.gd): open forge, open upgrade, next cost.
static func next_forge_step(gold := -1) -> Dictionary:
	if gold < 0:
		gold = SaveManager.get_permanent_gold()
	var best: Dictionary = {}
	if not MetaUnlocks.is_building_open(VillageBuildings.FORGE):
		return best
	for id in MetaUnlocks.get_open_upgrades():
		var cost := MetaProgression.get_next_cost(id)
		if cost < 0:
			continue
		if best.is_empty() or cost < int(best["cost"]):
			best = {"id": id, "level": MetaProgression.get_level(id) + 1, "cost": cost, "missing": maxi(0, cost - gold)}
	return best


## Level as a Roman numeral ("I" … "X"); larger numbers stay digits.
static func roman(level: int) -> String:
	const NUMERALS: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return NUMERALS[level - 1] if level >= 1 and level <= NUMERALS.size() else str(level)


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
	award_xp()


func _on_room_completed(_room_index: int) -> void:
	if _running:
		rooms_cleared += 1


func _on_enemy_damaged(enemy: Node2D, result: DamageResult, _damage: DamageData) -> void:
	if not _running or result == null or not result.killed:
		return
	kills += 1
	var foe := enemy as Enemy
	if foe == null or foe.data == null:
		return
	if foe.data.is_boss:
		bosses += 1
	elif foe.is_miniboss:
		champions += 1


func _on_upgrade_acquired(_upgrade_id: StringName, _stacks: int) -> void:
	if _running:
		upgrades += 1


func _on_player_hit(result: DamageResult, damage: DamageData) -> void:
	if not _running or result == null or result.health_damage <= 0.0:
		return
	last_hit_by = describe_hit(damage)
