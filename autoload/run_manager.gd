extends Node
## Owns the current run: room number, run gold, run crystals, active one-run boosts and the
## run end (D-038, D-039, D-078). Run gold exists only here; other systems read it and spend via
## try_spend_run_gold(). The run end computes the payout ratio (the same for gold and crystals)
## and has SaveManager credit it exactly once.

signal run_gold_changed(run_gold: int)
signal run_crystals_changed(run_crystals: int)
signal room_changed(room_index: int)

enum EndReason { DEATH, ABORT, EXIT }

const EXIT_PAYOUT_RATIO := 1.0
const LOSS_PAYOUT_RATIO := 0.5

var _is_run_active := false
var _current_room := 0
var _run_gold := 0
## All run gold collected this run (before spending), for the statistics.
var _run_gold_earned := 0
var _run_crystals := 0
## Proviant boosts taken from SaveManager at run start; valid for this run only.
var _run_boosts: Array[StringName] = []
var _last_summary: Dictionary = {}


## Permanent gold (or crystals) credited for the remaining run amount (D-039).
## Odd amounts in the 50 % case are rounded up (D-062).
func calculate_payout(remaining_gold: int, reason: EndReason) -> int:
	if remaining_gold <= 0:
		return 0
	if reason == EndReason.EXIT:
		return remaining_gold
	return ceili(remaining_gold * LOSS_PAYOUT_RATIO)


func start_run() -> void:
	_is_run_active = true
	_current_room = 1
	_run_gold = 0
	_run_gold_earned = 0
	_run_crystals = 0
	# Pending boosts are consumed now and saved, so quitting mid-run cannot keep them. Group runs
	# without meta upgrades (quick game, D-081) neither use nor consume them: they wait for solo.
	if GameMode.of_tree(get_tree()).get_meta_source() == GameMode.MetaSource.LOCAL:
		_run_boosts = SaveManager.take_pending_boosts()
		if not _run_boosts.is_empty():
			SaveManager.save_game()
	else:
		_run_boosts.clear()
	run_gold_changed.emit(_run_gold)
	run_crystals_changed.emit(_run_crystals)
	room_changed.emit(_current_room)
	EventBus.run_started.emit()


func is_run_active() -> bool:
	return _is_run_active


func get_current_room() -> int:
	return _current_room


func advance_room() -> int:
	if not _is_run_active:
		push_error("RunManager.advance_room() called without an active run.")
		return _current_room
	_current_room += 1
	room_changed.emit(_current_room)
	return _current_room


func get_run_gold() -> int:
	return _run_gold


func add_run_gold(amount: int) -> void:
	if not _is_run_active or amount <= 0:
		return
	_run_gold += amount
	_run_gold_earned += amount
	run_gold_changed.emit(_run_gold)


func get_run_crystals() -> int:
	return _run_crystals


## Seelenkristalle collected this run (bosses, champions). Paid out like gold at the run end.
func add_run_crystals(amount: int) -> void:
	if not _is_run_active or amount <= 0:
		return
	_run_crystals += amount
	run_crystals_changed.emit(_run_crystals)


## Proviant boosts active in the current run (see MetaProgression.BOOSTS).
func get_run_boosts() -> Array[StringName]:
	return _run_boosts.duplicate()


func has_run_boost(id: StringName) -> bool:
	return _is_run_active and _run_boosts.has(id)


## MP3 (D-081): the host owns the shared run gold and crystals; a network client mirrors them.
func sync_from_host(gold: int, gold_earned: int, crystals: int) -> void:
	if not _is_run_active:
		return
	var gold_changed := gold != _run_gold
	var crystals_changed := crystals != _run_crystals
	_run_gold = maxi(0, gold)
	_run_gold_earned = maxi(0, gold_earned)
	_run_crystals = maxi(0, crystals)
	if gold_changed:
		run_gold_changed.emit(_run_gold)
	if crystals_changed:
		run_crystals_changed.emit(_run_crystals)


## MP3: the room number of a network client follows the host.
func sync_room(room_index: int) -> void:
	if _is_run_active and room_index > 0 and room_index != _current_room:
		_current_room = room_index
		room_changed.emit(_current_room)


func get_run_gold_earned() -> int:
	return _run_gold_earned


## Spends gold only if the full amount is available. Returns false without any change otherwise.
func try_spend_run_gold(amount: int) -> bool:
	if not _is_run_active or amount < 0 or amount > _run_gold:
		return false
	_run_gold -= amount
	run_gold_changed.emit(_run_gold)
	return true


## Ends the run exactly once and credits the payout. A second call returns false (no double payout).
func end_run(reason: EndReason) -> bool:
	if not _is_run_active:
		return false
	_is_run_active = false
	var remaining_gold := _run_gold
	var payout := calculate_payout(remaining_gold, reason)
	var remaining_crystals := _run_crystals
	var crystal_payout := calculate_payout(remaining_crystals, reason)
	SaveManager.add_permanent_gold(payout)
	SaveManager.add_permanent_crystals(crystal_payout)
	SaveManager.save_game()
	_last_summary = {
		"reason": reason,
		"room": _current_room,
		"remaining_gold": remaining_gold,
		"payout": payout,
		"gold_earned": _run_gold_earned,
		"remaining_crystals": remaining_crystals,
		"crystal_payout": crystal_payout,
	}
	_run_gold = 0
	_run_crystals = 0
	_run_boosts.clear()
	run_gold_changed.emit(_run_gold)
	run_crystals_changed.emit(_run_crystals)
	EventBus.run_ended.emit(reason, remaining_gold, payout)
	return true


## reason, room, remaining_gold, payout, gold_earned, remaining_crystals, crystal_payout
## of the last finished run.
func get_last_summary() -> Dictionary:
	return _last_summary
