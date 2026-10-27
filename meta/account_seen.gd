class_name AccountSeen
extends RefCounted
## Seen flags of one-time explanations per account, not per world (KE1, KONZEPT §7.2, §10): who
## starts a new world does not see the village tour, building intros or room explanations again.
## Stored in the account state of progress.cfg (AccountProgress.get_state/set_state, key "seen"):
## {"ids": [id, …], "all": bool, "imported": bool}. Merge rule: union (merge_states; the cloud sync
## of KF4 uses it).
## Old flags: on first use the [seen] of every world on this machine is taken over once (union,
## read only: SaveManager.has_slot/slot_path, the files read like ProgressSummary does, migrated in
## memory with SaveManager.migrate). A pre-D-087 world counts as "everything seen" (D-087) except
## the ids SaveManager.is_excluded_from_seen_all names (boss and room intros).
## has_seen also asks the loaded world (SaveManager.has_seen), so flags written by code that still
## marks per world count too until every caller uses this class (integrator).
## Pure static helpers, no autoload (D-044). Co-op: every client keeps its own flags (KONZEPT §7.2:
## the host only needs to know who has not seen a room type yet).

const STATE_KEY := "seen"


## True if this account (or the loaded world) has seen the explanation id.
static func has_seen(id: StringName) -> bool:
	if SaveManager.has_seen(id):
		return true
	return state_has(_state(), id)


## Marks id as seen for the account and writes progress.cfg at once. True if it was new.
static func mark_seen(id: StringName) -> bool:
	var progress := AccountProgress.current()
	var state := _state(progress)
	if state_has(state, id):
		return false
	var ids: Array = state["ids"]
	ids.append(String(id))
	progress.set_state(STATE_KEY, state)
	return true


## Every id seen by the account (without "everything seen" of old worlds).
static func get_ids() -> PackedStringArray:
	return PackedStringArray(_state()["ids"])


## True if an old world made the account count as "everything seen".
static func is_all_seen() -> bool:
	return _state()["all"]


## True if a state dictionary contains id (directly or through "everything seen").
static func state_has(state: Dictionary, id: StringName) -> bool:
	var ids: Variant = state.get("ids", [])
	if (ids is Array or ids is PackedStringArray) and Array(ids).has(String(id)):
		return true
	return _is_true(state.get("all", false)) and not SaveManager.is_excluded_from_seen_all(id)


## Union of two seen states (cloud merge, KONZEPT §10): every id of both, "all" if either has it.
static func merge_states(a: Dictionary, b: Dictionary) -> Dictionary:
	var merged := clean_state(a)
	for id: String in clean_state(b)["ids"]:
		if not (merged["ids"] as Array).has(id):
			(merged["ids"] as Array).append(id)
	merged["all"] = merged["all"] or _is_true(b.get("all", false))
	merged["imported"] = merged["imported"] or _is_true(b.get("imported", false))
	return merged


## A valid state from anything stored: ids as strings without doubles, all and imported as bools.
static func clean_state(raw: Dictionary) -> Dictionary:
	var ids: Array = []
	var stored: Variant = raw.get("ids", [])
	if stored is Array or stored is PackedStringArray:
		for item: Variant in stored:
			if (typeof(item) == TYPE_STRING or typeof(item) == TYPE_STRING_NAME) and not String(item).is_empty() \
					and not ids.has(String(item)):
				ids.append(String(item))
	return {"ids": ids, "all": _is_true(raw.get("all", false)), "imported": _is_true(raw.get("imported", false))}


static func _is_true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value


## Takes the seen flags of every world on this machine into the account once (union) and saves.
## Returns true if it ran now (false: done before). Called by the first has_seen/mark_seen.
static func import_worlds(progress: AccountProgress = null) -> bool:
	if progress == null:
		progress = AccountProgress.current()
	var state := clean_state(progress.get_state(STATE_KEY))
	if state["imported"]:
		return false
	for world in world_paths():
		state = merge_states(state, read_world(world))
	state["imported"] = true
	progress.set_state(STATE_KEY, state)
	return true


## Save files of this machine's worlds: every slot and the loaded save if it is no slot.
static func world_paths() -> Array[String]:
	var paths: Array[String] = []
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if SaveManager.has_slot(slot):
			paths.append(SaveManager.slot_path(slot))
	if not SaveManager.save_path.is_empty() and not paths.has(SaveManager.save_path) \
			and FileAccess.file_exists(SaveManager.save_path):
		paths.append(SaveManager.save_path)
	return paths


## The [seen] of one save file as a state ({} parts for a missing or unreadable file). Read only:
## the file is migrated in memory, never written.
static func read_world(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if SafeSave.load_config(config, path) != OK:
		return clean_state({})
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version < 1 or version > SaveManager.SAVE_VERSION:
		return clean_state({})
	SaveManager.migrate(config)
	return clean_state({
		"ids": config.get_value("seen", "ids", PackedStringArray()),
		"all": config.get_value("seen", "all", false),
	})


## The account's state, imported from the worlds on first use.
static func _state(progress: AccountProgress = null) -> Dictionary:
	if progress == null:
		progress = AccountProgress.current()
	import_worlds(progress)
	return clean_state(progress.get_state(STATE_KEY))
