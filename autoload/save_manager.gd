extends Node
## Owns permanent progress only (permanent gold and crystals, unlocks, village upgrade levels,
## pending one-run boosts, statistics, the world's name) plus the global settings. Never stores run
## state (D-040).
## Save format (D-059, extended by D-078, D-087, MM1, D-152 and KE4): ConfigFile with [meta] version and
## sections [progress] (also start_weapon/second_weapon), [meta_upgrades] (forge levels, KONZEPT §5.1),
## [trade_levels] (trading post levels, KE5), [boosts], [stats], [seen], [world] (id, name), [profile]
## (created, last_played), [migration] (what v5 did, once per world) and, in migrated files only,
## [legacy_profile]. Older versions are migrated
## on load (the untouched file is kept once as *.v<old>.bak before); missing files start fresh, a
## broken file (unreadable, newer or invalid) is kept as *.bak and its last good copy is loaded (P1-8,
## see below), only without one the game starts fresh.
## P1-8: every file written here (slots, the pre-slot save, settings.cfg) goes through SafeSave: written
## to <file>.tmp, read back, then renamed into place; the file it replaces is kept as <file>.prev.bak
## (the last good copy). A crash while saving leaves either the old or the new file, never half of one.
## D-152: a slot is a world ("Welt 1"), the player's name and look live in the account profile
## (PlayerProfile, profile.cfg), not in the slot. The old per-slot name, character and colour stay
## in [legacy_profile] for the one-time suggestion of the first start (PlayerProfile.legacy_suggestion).
##
## Save slots (MM1): every slot is one such file, saves_dir/slot_<n>.cfg. save_path always points at
## the loaded file, so load_game()/save_game() and all getters work as before (tests and tools only
## redirect save_path). The single save of older builds (user://savegame.cfg) is copied unchanged
## into the first free slot once (import_legacy_save_into_slot), when the main menu opens; it is
## never changed or deleted. Global settings (volume, last slot) live in settings_path; their first
## values come from the old save's [settings] section.

signal permanent_gold_changed(permanent_gold: int)
signal permanent_crystals_changed(permanent_crystals: int)
## Upgrade levels, pending boosts or the start weapon choice changed.
signal meta_changed
## A one-time explanation (e.g. a village building intro, D-087) was marked as seen.
signal seen_changed(id: StringName)
## Another slot was loaded, created or the loaded slot was deleted.
signal slot_changed(slot: int)
## The player's profile (PlayerProfile: name, figure, colours) changed, or another profile was loaded.
## Hook for the player sprite: re-apply CharacterCatalog.apply_active(sprite).
signal profile_changed
## An unlock id was stored for the first time (enemy hints, village events of MetaUnlocks, …).
signal content_unlocked(id: StringName)
## P1-8: the loaded save file was broken and its last good copy (*.prev.bak) was loaded instead.
## Hook for a notice in the menu ("Spielstand aus der Sicherung geladen").
signal save_restored(path: String)

const SAVE_VERSION := 5
const SETTINGS_VERSION := 1
## The save file of builds before slots (MM1); imported into a slot, kept as it is.
const DEFAULT_SAVE_PATH := "user://savegame.cfg"
const DEFAULT_SAVES_DIR := "user://saves"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
## A deleted slot is renamed to this suffix (one undo by hand, overwritten by the next delete).
const DELETED_SUFFIX := ".deleted"
## The project was called "Dungeon Roguelite" before D-094; Godot derives the user:// folder from the
## project name, so an old save is copied over once.
const LEGACY_USER_DIR_NAME := "Dungeon Roguelite"
const DEFAULT_VOLUMES: Dictionary[StringName, float] = {&"Music": 0.8, &"SFX": 1.0}
## Seen ids that "everything seen" of old saves does not cover: the boss story (BI2,
## boss_intro_<boss>) is new and should be shown once also in migrated saves; so are Flint's
## explanations (flint_*, WK8/WK9).
const SEEN_ALL_EXCLUDED_PREFIXES: Array[String] = ["boss_intro_", "room_intro_", "flint_"]
## Suffix of the copy kept before a migration: slot_1.cfg -> slot_1.cfg.v2.bak (written once).
const MIGRATION_BACKUP_SUFFIX := ".v%d.bak"
## Crash-safe writing (P1-8). Preloaded instead of the global class name, so the autoload also
## compiles before the editor registered the new class.
const _SafeSave := preload("res://meta/safe_save.gd")

# --- Migration v2 -> v3 (B2, D-087). Frozen: later changes need their own migration step. ---
## Forge level rule per upgrade: [numerator, denominator, new maximum]. New level = old effect
## rounded up to the new step (ceil(old * numerator / denominator)), at most the new maximum.
## No gold is refunded. Schärfe 5 % -> 10 %, Startschild 2 -> 3, Goldgier 10 % -> 15 %.
const V3_LEVEL_RULES := {
	"vitality": [1, 1, 5],
	"start_shield": [2, 3, 3],
	"sharpness": [1, 2, 4],
	"gold_greed": [2, 3, 3],
	"dash_training": [1, 1, 3],
	"arsenal": [1, 1, 2],
}
## Old saves count as "everything unlocked" (D-087): the village events of MetaUnlocks.EVENTS and
## their announcements ("Neu freigeschaltet" is not shown for them).
const V3_UNLOCKED_EVENTS: Array[String] = ["event_first_run", "event_first_crystal", "event_first_boss"]
const V3_ANNOUNCED_IDS: Array[String] = ["unlock_first_run", "unlock_first_crystal", "unlock_first_boss"]
# --- Migration v3 -> v4 (D-152). Frozen. ---
## [profile] keys that named the player in MM1 saves; v4 keeps them in [legacy_profile].
const V4_LEGACY_PROFILE_KEYS: Array[String] = ["name", "character", "color"]
# --- Migration v4 -> v5 (KE4, KONZEPT §5.1). Frozen. ---
## Forge upgrades that left the forge (Vitalität and Dash-Training went to the talent tree, Goldgier
## becomes Proviant, Schärfe is gone): the gold paid for every level is refunded in full. Costs of
## the v3/v4 builds per level (D-087 with D-167: Vitalität I and Startschild I cheaper).
const V5_REFUND_COSTS := {
	"vitality": [20, 80, 140, 220, 320],
	"sharpness": [70, 150, 260, 400],
	"gold_greed": [60, 140, 250],
	"dash_training": [60, 140, 260],
}
## Startschild becomes Schildplatte with the same level (at most 3).
const V5_SHIELD_KEY := "start_shield"
const V5_SHIELD_PLATE_KEY := "shield_plate"
const V5_SHIELD_PLATE_MAX := 3
## Arsenal level -> start weapons it unlocks (arsenal_<weapon> = 1). Old Arsenal gave a second start
## weapon, so any level also keeps the second start slot (second_slot = 1, nothing is lost).
const V5_ARSENAL_KEY := "arsenal"
const V5_ARSENAL_WEAPONS: Array = [[], ["bow"], ["bow", "staff"]]
const V5_ARSENAL_PREFIX := "arsenal_"
const V5_SECOND_SLOT_KEY := "second_slot"
## Trading post levels (KE5 builds them; v5 only stores them): id -> default level.
const TRADE_LEVEL_DEFAULTS := {"provision_slot": 0, "luck": 0, "merchant_friend": 0}
## Start weapon of every world that never picked one (the sword is always unlocked).
const DEFAULT_START_WEAPON := "sword"
# --- Proviant ids before KE5 (KONZEPT §5.2). Frozen. ---
## Packed Proviant of older builds -> the Proviant that replaced it (same or better effect, so nothing
## is lost): Heiltrank stays, the random upgrade becomes the Glücksamulett (rare upgrade), the
## Goldbeutel (+25 %) becomes Goldregen (double gold). Mapped on every load (migrate), no version step.
const LEGACY_BOOST_IDS := {"potion": "healing_potion", "upgrade": "lucky_amulet", "gold": "gold_rain"}

## The loaded save file. Overridable for tests and tools (they never touch the real save).
var save_path := DEFAULT_SAVE_PATH
## Slot folder, global settings file and the pre-slot save. Redirect all of them with
## set_storage_root() in tests and tools that use slots or settings.
var saves_dir := DEFAULT_SAVES_DIR
var settings_path := DEFAULT_SETTINGS_PATH
var legacy_save_path := DEFAULT_SAVE_PATH

var _permanent_gold := 0
var _permanent_crystals := 0
var _unlocked_content: Dictionary[StringName, bool] = {}
var _meta_levels: Dictionary[StringName, int] = {}
var _pending_boosts: Array[StringName] = []
## Start weapons picked in the forge (Arsenal, KE4): the first slot (default the sword) and the
## second one (needs the second start slot), empty = none.
var _start_weapon: StringName = &""
var _second_weapon: StringName = &""
## Trading post levels ([trade_levels], KE5): id -> level, missing = TRADE_LEVEL_DEFAULTS.
var _trade_levels: Dictionary[StringName, int] = {}
## The world's id ([world] id, v5): a UUID v4 given once, the same on every device (cloud worlds,
## D-188). "" until the first save of a fresh world.
var _world_id := ""
## [migration]: what the v4 -> v5 migration did (refunded gold, old levels, new unlocks) and whether
## the village still has to say so. Kept for good (the refund happens once per world).
var _migration: Dictionary = {}
## Statistics for the chronicle: ints, play_time is a float in seconds.
var _stats: Dictionary[StringName, Variant] = {}
## One-time explanations the player has already seen (D-087), e.g. &"intro_forge".
var _seen: Dictionary[StringName, bool] = {}
## True for saves written before the [seen] section existed: they count as "everything seen" (D-087).
var _seen_all := false
## The world's own name ([world] name, D-152), "" = "Welt <n>".
var _world_name := ""
## [legacy_profile] of a migrated MM1 slot: name, character, color as stored (kept on save).
var _legacy_profile: Dictionary = {}
## Creation and last save time ([profile], unix seconds, 0 = unknown).
var _created_at := 0
var _last_played := 0
## P1-8: the last load_game() used the last good copy; why the last file was rejected.
var _restored_from_backup := false
var _load_failure := ""
## The loaded file was rejected: the next save must not copy it over the last good copy.
var _skip_backup_once := false

# --- Global settings (settings_path) ---
## Linear 0..1 volume per audio bus.
var _volumes: Dictionary[StringName, float] = DEFAULT_VOLUMES.duplicate()
## Slot "Weiterspielen" continues (0 = none yet).
var _last_slot := 0
## True once the pre-slot save was copied into a slot.
var _legacy_imported := false
## Global player options (UX1: fullscreen, screen shake, …), section [options] of settings.cfg.
var _options: Dictionary = {}


func _ready() -> void:
	_import_pre_rename_save()
	recover_storage()
	load_settings()
	save_path = _startup_save_path()
	load_game()
	_apply_volumes()


## Copies the save from the pre-rename user folder if the current one has none (never deletes it).
func _import_pre_rename_save() -> void:
	if legacy_save_path != DEFAULT_SAVE_PATH or FileAccess.file_exists(legacy_save_path):
		return
	var legacy := OS.get_user_data_dir().get_base_dir().path_join(LEGACY_USER_DIR_NAME).path_join("savegame.cfg")
	if FileAccess.file_exists(legacy):
		DirAccess.copy_absolute(legacy, ProjectSettings.globalize_path(legacy_save_path))


## Which file the game uses before the menu picked a slot (e.g. game.tscn started directly).
## Read-only: the pre-slot save stays in use until the main menu imported it.
func _startup_save_path() -> String:
	if needs_legacy_import():
		return legacy_save_path
	var slot := get_continue_slot()
	return slot_path(slot if slot > 0 else 1)


## Loads save_path. P1-8: a file broken by a crash or a full disk (unreadable, invalid values) is
## kept as *.bak (D-059) and the last good copy (*.prev.bak, SafeSave) is loaded instead, with a
## warning; only without a usable copy the game starts fresh. The rejected file is never copied over
## the good copy (the next save skips that once). A file of a newer version falls back the same way
## (an older copy beats a fresh start; the newer file stays as *.bak).
func load_game() -> Error:
	_reset()
	_restored_from_backup = false
	_skip_backup_once = false
	_SafeSave.recover(save_path)
	if not FileAccess.file_exists(save_path):
		return ERR_FILE_NOT_FOUND
	var err := _load_file(save_path)
	if err == OK:
		return OK
	var reason := _load_failure
	push_warning("SaveManager: save file %s rejected (%s)." % [save_path, reason])
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak"))
	_skip_backup_once = true
	var backup := _SafeSave.backup_path(save_path)
	if FileAccess.file_exists(backup):
		_reset()
		if _load_file(backup) == OK:
			push_warning("SaveManager: loaded the last good copy %s instead." % backup)
			_restored_from_backup = true
			save_restored.emit(save_path)
			return OK
		push_warning("SaveManager: the last good copy %s is not usable either (%s)." % [backup, _load_failure])
	push_warning("SaveManager: starting fresh.")
	_reset()
	return err


## True when the last load_game() had to use the last good copy (*.prev.bak) of a broken file.
func was_restored_from_backup() -> bool:
	return _restored_from_backup


## Reads, migrates, checks and applies one save file (save_path or its copy). Nothing is changed in
## memory when the file is rejected; _load_failure says why.
func _load_file(path: String) -> Error:
	_load_failure = ""
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return _fail("unreadable", ERR_FILE_CORRUPT)
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version < 1 or version > SAVE_VERSION:
		return _fail("unsupported version %s" % str(version), ERR_FILE_UNRECOGNIZED)
	if version < SAVE_VERSION:
		_backup_before_migration(version, path)
	migrate(config)

	var gold: Variant = config.get_value("progress", "permanent_gold", 0)
	if typeof(gold) != TYPE_INT or gold < 0:
		return _fail("invalid permanent_gold", ERR_INVALID_DATA)
	var crystals: Variant = config.get_value("progress", "permanent_crystals", 0)
	if typeof(crystals) != TYPE_INT or crystals < 0:
		return _fail("invalid permanent_crystals", ERR_INVALID_DATA)
	var unlocked: Variant = config.get_value("progress", "unlocked", PackedStringArray())
	if typeof(unlocked) != TYPE_PACKED_STRING_ARRAY:
		return _fail("invalid unlocked list", ERR_INVALID_DATA)
	var levels: Dictionary[StringName, int] = {}
	if config.has_section("meta_upgrades"):
		for key in config.get_section_keys("meta_upgrades"):
			var level: Variant = config.get_value("meta_upgrades", key)
			if typeof(level) != TYPE_INT or level < 0:
				return _fail("invalid meta upgrade level %s" % key, ERR_INVALID_DATA)
			levels[StringName(key)] = level

	_permanent_gold = gold
	_permanent_crystals = crystals
	for id in unlocked:
		_unlocked_content[StringName(id)] = true
	_meta_levels = levels
	_start_weapon = StringName(str(config.get_value("progress", "start_weapon", DEFAULT_START_WEAPON)))
	_second_weapon = StringName(str(config.get_value("progress", "second_weapon", "")))
	# Trading post levels and the migration notes are not worth a full reset: invalid entries are dropped.
	if config.has_section("trade_levels"):
		for key in config.get_section_keys("trade_levels"):
			var trade_level: Variant = config.get_value("trade_levels", key)
			if typeof(trade_level) == TYPE_INT and trade_level >= 0:
				_trade_levels[StringName(key)] = trade_level
	if config.has_section("migration"):
		for key in config.get_section_keys("migration"):
			_migration[key] = config.get_value("migration", key)
	var world_id: Variant = config.get_value("world", "id", "")
	_world_id = String(world_id) if is_valid_world_id(world_id) else new_world_id()
	# Boosts and statistics are not worth a full reset: invalid entries are dropped.
	var boosts: Variant = config.get_value("boosts", "pending", PackedStringArray())
	if typeof(boosts) == TYPE_PACKED_STRING_ARRAY:
		for id in boosts:
			if not _pending_boosts.has(StringName(id)):
				_pending_boosts.append(StringName(id))
	if config.has_section("stats"):
		for key in config.get_section_keys("stats"):
			var value: Variant = config.get_value("stats", key)
			if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value >= 0:
				_stats[StringName(key)] = value
	# Seen flags only decide whether an explanation is shown again: invalid entries are dropped.
	var seen_all: Variant = config.get_value("seen", "all", false)
	_seen_all = typeof(seen_all) == TYPE_BOOL and seen_all
	var seen: Variant = config.get_value("seen", "ids", PackedStringArray())
	if typeof(seen) == TYPE_PACKED_STRING_ARRAY:
		for id in seen:
			_seen[StringName(id)] = true
	# Name and times only label the world: invalid entries fall back to defaults. Volumes in an old
	# [settings] section are ignored here; they are global now (load_settings migrates them once).
	var world_name: Variant = config.get_value("world", "name", "")
	if typeof(world_name) == TYPE_STRING:
		_world_name = String(world_name)
	if config.has_section("legacy_profile"):
		for key in config.get_section_keys("legacy_profile"):
			_legacy_profile[key] = config.get_value("legacy_profile", key)
	var created: Variant = config.get_value("profile", "created", 0)
	_created_at = maxi(0, created) if typeof(created) == TYPE_INT else 0
	var last_played: Variant = config.get_value("profile", "last_played", 0)
	_last_played = maxi(0, last_played) if typeof(last_played) == TYPE_INT else 0
	permanent_gold_changed.emit(_permanent_gold)
	permanent_crystals_changed.emit(_permanent_crystals)
	meta_changed.emit()
	profile_changed.emit()
	return OK


## Upgrades an older config in place to SAVE_VERSION. Returns the version it started from.
## v1 -> v2: adds crystals, village upgrade levels, boosts and statistics with empty defaults.
## Any version without a [seen] section (written before D-087 explanations existed) is marked
## "everything seen" (D-087). This is additive: save_game() always writes [seen], so the section is
## missing only in older files and the version number did not have to change.
## [profile] (MM1) is additive too: a missing section means default name, character and colour, so
## it needs no migration step. [seen] is never removed by a migration.
## v2 -> v3 (B2, D-087): forge levels are converted to the shorter table (V3_LEVEL_RULES), and the
## save counts as "everything unlocked": all village events (V3_UNLOCKED_EVENTS) are added and their
## announcements marked as shown. Invalid values are left alone (load_game() rejects them).
## v3 -> v4 (D-152): the slot is a world. Name, character and colour of [profile] move to
## [legacy_profile] (the player's profile takes them once, PlayerProfile.legacy_suggestion); the world
## has no name of its own yet ("Welt <n>"). created/last_played stay in [profile].
## v4 -> v5 (KE4, KONZEPT §5.1): the new forge. Vitalität, Schärfe, Goldgier and Dash-Training are
## removed and their gold refunded in full (once per world: [migration] v5_refund_gold is the marker),
## Startschild becomes Schildplatte with the same level, Arsenal 1 unlocks the bow and Arsenal 2 bow
## and staff (both keep the second start slot); the world gets its id ([world] id) and the trading
## post levels ([trade_levels]) with their defaults. [migration] keeps what happened for the village
## notice (v5_notice_pending). Invalid values are left alone (load_game() rejects them).
## Every version (KE5): packed Proviant of older builds gets its new id (_map_legacy_boosts).
static func migrate(config: ConfigFile) -> int:
	var from_version: int = config.get_value("meta", "version", SAVE_VERSION)
	if from_version < 2:
		if not config.has_section_key("progress", "permanent_crystals"):
			config.set_value("progress", "permanent_crystals", 0)
		if not config.has_section_key("boosts", "pending"):
			config.set_value("boosts", "pending", PackedStringArray())
	if not config.has_section("seen"):
		config.set_value("seen", "all", true)
		config.set_value("seen", "ids", PackedStringArray())
	if from_version < 3:
		_migrate_to_v3(config)
	if from_version < 4:
		_migrate_to_v4(config)
	if from_version < 5:
		_migrate_to_v5(config)
	_map_legacy_boosts(config)
	config.set_value("meta", "version", SAVE_VERSION)
	return from_version


## Packed Proviant with an id of older builds (LEGACY_BOOST_IDS) gets the new id, each id once
## (KE5). Additive like [seen]: it applies to every version, so the save version stays.
static func _map_legacy_boosts(config: ConfigFile) -> void:
	var pending: Variant = config.get_value("boosts", "pending", PackedStringArray())
	if typeof(pending) != TYPE_PACKED_STRING_ARRAY:
		return
	var mapped := PackedStringArray()
	for id in pending:
		var new_id := String(LEGACY_BOOST_IDS.get(id, id))
		if not mapped.has(new_id):
			mapped.append(new_id)
	if mapped != pending:
		config.set_value("boosts", "pending", mapped)


static func _migrate_to_v3(config: ConfigFile) -> void:
	if config.has_section("meta_upgrades"):
		for key in config.get_section_keys("meta_upgrades"):
			var level: Variant = config.get_value("meta_upgrades", key)
			if typeof(level) == TYPE_INT and level >= 0:
				config.set_value("meta_upgrades", key, migrate_level_to_v3(key, level))
	var unlocked: Variant = config.get_value("progress", "unlocked", PackedStringArray())
	if typeof(unlocked) == TYPE_PACKED_STRING_ARRAY:
		config.set_value("progress", "unlocked", _with_ids(unlocked, V3_UNLOCKED_EVENTS))
	var seen: Variant = config.get_value("seen", "ids", PackedStringArray())
	if typeof(seen) != TYPE_PACKED_STRING_ARRAY:
		seen = PackedStringArray()
	config.set_value("seen", "ids", _with_ids(seen, V3_ANNOUNCED_IDS))


static func _migrate_to_v4(config: ConfigFile) -> void:
	for key in V4_LEGACY_PROFILE_KEYS:
		if config.has_section_key("profile", key):
			if not config.has_section_key("legacy_profile", key):
				config.set_value("legacy_profile", key, config.get_value("profile", key))
			config.erase_section_key("profile", key)


static func _migrate_to_v5(config: ConfigFile) -> void:
	var refund := 0
	var refunded := PackedStringArray()
	for key: String in V5_REFUND_COSTS:
		var level: Variant = config.get_value("meta_upgrades", key, 0)
		if typeof(level) != TYPE_INT or level < 0:
			continue
		var paid := refund_for_level(key, level)
		if paid > 0:
			refund += paid
			refunded.append("%s:%d" % [key, mini(level, (V5_REFUND_COSTS[key] as Array).size())])
		if config.has_section_key("meta_upgrades", key):
			config.erase_section_key("meta_upgrades", key)
	var shield_plate := 0
	var shield: Variant = config.get_value("meta_upgrades", V5_SHIELD_KEY, 0)
	if typeof(shield) == TYPE_INT and shield >= 0:
		shield_plate = mini(shield, V5_SHIELD_PLATE_MAX)
		if config.has_section_key("meta_upgrades", V5_SHIELD_KEY):
			config.erase_section_key("meta_upgrades", V5_SHIELD_KEY)
		if shield_plate > 0:
			config.set_value("meta_upgrades", V5_SHIELD_PLATE_KEY, shield_plate)
	var weapons := PackedStringArray()
	var arsenal: Variant = config.get_value("meta_upgrades", V5_ARSENAL_KEY, 0)
	if typeof(arsenal) == TYPE_INT and arsenal >= 0:
		weapons.append_array(arsenal_weapons_for_level(arsenal))
		if config.has_section_key("meta_upgrades", V5_ARSENAL_KEY):
			config.erase_section_key("meta_upgrades", V5_ARSENAL_KEY)
		for weapon in weapons:
			config.set_value("meta_upgrades", V5_ARSENAL_PREFIX + weapon, 1)
		if not weapons.is_empty():
			config.set_value("meta_upgrades", V5_SECOND_SLOT_KEY, 1)
			# v4 started with the first Arsenal weapon when none was picked: keep that.
			var second: Variant = config.get_value("progress", "second_weapon", "")
			if typeof(second) != TYPE_STRING or not weapons.has(String(second)):
				config.set_value("progress", "second_weapon", weapons[0])
	# The old second weapon stays the second one; the first slot keeps the sword.
	if not config.has_section_key("progress", "start_weapon"):
		config.set_value("progress", "start_weapon", DEFAULT_START_WEAPON)
	if not is_valid_world_id(config.get_value("world", "id", "")):
		config.set_value("world", "id", new_world_id())
	for key: String in TRADE_LEVEL_DEFAULTS:
		if not config.has_section_key("trade_levels", key):
			config.set_value("trade_levels", key, TRADE_LEVEL_DEFAULTS[key])
	# Once per world: a marker from an earlier run of this migration (or a merged cloud state) wins.
	if config.has_section_key("migration", "v5_refund_gold"):
		return
	var gold: Variant = config.get_value("progress", "permanent_gold", 0)
	if refund > 0 and typeof(gold) == TYPE_INT and gold >= 0:
		config.set_value("progress", "permanent_gold", gold + refund)
	config.set_value("migration", "v5_refund_gold", refund)
	config.set_value("migration", "v5_refunded", refunded)
	config.set_value("migration", "v5_shield_plate", shield_plate)
	config.set_value("migration", "v5_weapons", weapons)
	config.set_value("migration", "v5_notice_pending", refund > 0 or shield_plate > 0 or not weapons.is_empty())


## Gold paid for the first level levels of an upgrade the v5 forge removed (V5_REFUND_COSTS); 0 for
## other ids. Levels above the old maximum count as the maximum.
static func refund_for_level(id: String, level: int) -> int:
	if level <= 0 or not V5_REFUND_COSTS.has(id):
		return 0
	var costs: Array = V5_REFUND_COSTS[id]
	var total := 0
	for i in mini(level, costs.size()):
		total += int(costs[i])
	return total


## Start weapons an old Arsenal level unlocks in v5: 1 = bow, 2 (or more) = bow and staff.
static func arsenal_weapons_for_level(level: int) -> PackedStringArray:
	var index := clampi(level, 0, V5_ARSENAL_WEAPONS.size() - 1)
	return PackedStringArray(V5_ARSENAL_WEAPONS[index])


## A UUID v4 for a new world id ([world] id, D-188).
static func new_world_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## True for a UUID in the form the platform expects (8-4-4-4-12 hex digits).
static func is_valid_world_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return regex.search(String(value)) != null


## Forge level of a v2 save converted to v3 (D-087): ceil(old effect / new step), at most the new
## maximum. Unknown upgrades keep their level; negative levels stay (they are rejected on load).
static func migrate_level_to_v3(id: String, level: int) -> int:
	if level <= 0 or not V3_LEVEL_RULES.has(id):
		return level
	var rule: Array = V3_LEVEL_RULES[id]
	var numerator: int = rule[0]
	var denominator: int = rule[1]
	@warning_ignore("integer_division")
	return mini(int(rule[2]), (level * numerator + denominator - 1) / denominator)


static func _with_ids(ids: PackedStringArray, extra: Array[String]) -> PackedStringArray:
	var result := ids.duplicate()
	for id in extra:
		if not result.has(id):
			result.append(id)
	return result


## Keeps the untouched older file once before it is migrated (save_path + ".v2.bak"); an existing
## backup is never overwritten, so it always holds the first file of that version. source is the
## file being loaded (save_path, or its last good copy after a broken file).
func _backup_before_migration(from_version: int, source: String) -> void:
	var backup := save_path + MIGRATION_BACKUP_SUFFIX % from_version
	if FileAccess.file_exists(backup):
		return
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(backup))
	if err != OK:
		push_warning("SaveManager: could not back up %s before migrating (%s)." % [source, error_string(err)])


func save_game() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("progress", "permanent_gold", _permanent_gold)
	config.set_value("progress", "permanent_crystals", _permanent_crystals)
	var unlocked := PackedStringArray()
	for id in _unlocked_content:
		unlocked.append(String(id))
	config.set_value("progress", "unlocked", unlocked)
	config.set_value("progress", "start_weapon", String(_start_weapon) if _start_weapon != &"" else DEFAULT_START_WEAPON)
	config.set_value("progress", "second_weapon", String(_second_weapon))
	for id in _meta_levels:
		config.set_value("meta_upgrades", String(id), _meta_levels[id])
	for key: String in TRADE_LEVEL_DEFAULTS:
		config.set_value("trade_levels", key, get_trade_level(StringName(key)))
	for id in _trade_levels:
		config.set_value("trade_levels", String(id), _trade_levels[id])
	for key: String in _migration:
		config.set_value("migration", key, _migration[key])
	var boosts := PackedStringArray()
	for id in _pending_boosts:
		boosts.append(String(id))
	config.set_value("boosts", "pending", boosts)
	for id in _stats:
		config.set_value("stats", String(id), _stats[id])
	# Always written (also when empty): a missing [seen] section marks a pre-D-087 save.
	config.set_value("seen", "all", _seen_all)
	var seen := PackedStringArray()
	for id in _seen:
		seen.append(String(id))
	config.set_value("seen", "ids", seen)
	_last_played = int(Time.get_unix_time_from_system())
	if _created_at <= 0:
		_created_at = _last_played
	if _world_id.is_empty():
		_world_id = new_world_id()
	config.set_value("world", "id", _world_id)
	config.set_value("world", "name", _world_name)
	config.set_value("profile", "created", _created_at)
	config.set_value("profile", "last_played", _last_played)
	for key: String in _legacy_profile:
		config.set_value("legacy_profile", key, _legacy_profile[key])
	# P1-8: .tmp, read back, rename; a rejected file is not kept as the last good copy.
	var err := _SafeSave.write_config(config, save_path, not _skip_backup_once)
	if err != OK:
		push_error("SaveManager: could not write %s (%s)." % [save_path, error_string(err)])
	else:
		_skip_backup_once = false
	return err


# --- Currencies ---

func get_permanent_gold() -> int:
	return _permanent_gold


func add_permanent_gold(amount: int) -> void:
	if amount <= 0:
		return
	_permanent_gold += amount
	permanent_gold_changed.emit(_permanent_gold)


## Spends only if the full amount is available; otherwise nothing changes.
func try_spend_permanent_gold(amount: int) -> bool:
	if amount < 0 or amount > _permanent_gold:
		return false
	_permanent_gold -= amount
	permanent_gold_changed.emit(_permanent_gold)
	return true


func get_permanent_crystals() -> int:
	return _permanent_crystals


func add_permanent_crystals(amount: int) -> void:
	if amount <= 0:
		return
	_permanent_crystals += amount
	permanent_crystals_changed.emit(_permanent_crystals)


func try_spend_permanent_crystals(amount: int) -> bool:
	if amount < 0 or amount > _permanent_crystals:
		return false
	_permanent_crystals -= amount
	permanent_crystals_changed.emit(_permanent_crystals)
	return true


# --- Unlocks and village upgrades ---

## Stores an unlock id (memory only; the caller saves). Emits content_unlocked the first time.
func unlock_content(id: StringName) -> void:
	if _unlocked_content.has(id):
		return
	_unlocked_content[id] = true
	content_unlocked.emit(id)


func is_unlocked(id: StringName) -> bool:
	return _unlocked_content.has(id)


func get_meta_level(id: StringName) -> int:
	return _meta_levels.get(id, 0)


func set_meta_level(id: StringName, level: int) -> void:
	_meta_levels[id] = maxi(0, level)
	meta_changed.emit()


func get_second_weapon() -> StringName:
	return _second_weapon


func set_second_weapon(id: StringName) -> void:
	_second_weapon = id
	meta_changed.emit()


## First start weapon as stored (MetaProgression checks it against the unlocks); the sword by default.
func get_start_weapon() -> StringName:
	return _start_weapon if _start_weapon != &"" else StringName(DEFAULT_START_WEAPON)


func set_start_weapon(id: StringName) -> void:
	_start_weapon = id
	meta_changed.emit()


# --- Trading post levels (KE5; stored since v5) ---

func get_trade_level(id: StringName) -> int:
	return _trade_levels.get(id, int(TRADE_LEVEL_DEFAULTS.get(String(id), 0)))


func set_trade_level(id: StringName, level: int) -> void:
	_trade_levels[id] = maxi(0, level)
	meta_changed.emit()


# --- World id and the v5 migration notes ---

## The world's id ([world] id, UUID v4, D-188); given with the first save of a fresh world.
func get_world_id() -> String:
	if _world_id.is_empty():
		_world_id = new_world_id()
	return _world_id


## What the v4 -> v5 migration did in this world: {refund_gold (int), refunded (["vitality:2", …]),
## shield_plate (int), weapons (["bow", …]), notice_pending (bool)}; {} for worlds started in v5.
func get_v5_report() -> Dictionary:
	if not _migration.has("v5_refund_gold"):
		return {}
	return {
		"refund_gold": maxi(0, int(_migration.get("v5_refund_gold", 0))),
		"refunded": _string_list(_migration.get("v5_refunded", PackedStringArray())),
		"shield_plate": maxi(0, int(_migration.get("v5_shield_plate", 0))),
		"weapons": _string_list(_migration.get("v5_weapons", PackedStringArray())),
		"notice_pending": _migration.get("v5_notice_pending", false) == true,
	}


## True while the village has not told the player what the v5 migration did.
func is_v5_notice_pending() -> bool:
	return _migration.get("v5_notice_pending", false) == true


## The notice was shown (memory only; the caller saves). The report itself stays.
func clear_v5_notice() -> void:
	if _migration.has("v5_notice_pending"):
		_migration["v5_notice_pending"] = false


static func _string_list(value: Variant) -> PackedStringArray:
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		return value
	var result := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value:
			result.append(str(item))
	return result


# --- One-run boosts (Proviant) ---

func get_pending_boosts() -> Array[StringName]:
	return _pending_boosts.duplicate()


func has_pending_boost(id: StringName) -> bool:
	return _pending_boosts.has(id)


func add_pending_boost(id: StringName) -> bool:
	if _pending_boosts.has(id):
		return false
	_pending_boosts.append(id)
	meta_changed.emit()
	return true


## Returns and clears all pending boosts (they apply to exactly one run).
func take_pending_boosts() -> Array[StringName]:
	var taken := _pending_boosts.duplicate()
	_pending_boosts.clear()
	if not taken.is_empty():
		meta_changed.emit()
	return taken


# --- Statistics ---

func get_stat(id: StringName) -> Variant:
	return _stats.get(id, 0)


func add_stat(id: StringName, amount: Variant) -> void:
	if amount <= 0:
		return
	_stats[id] = _stats.get(id, 0) + amount


## Keeps the larger value (records such as the deepest room).
func record_stat_max(id: StringName, value: Variant) -> void:
	if value > _stats.get(id, 0):
		_stats[id] = value


# --- Seen flags (one-time explanations, D-087) ---

## Old saves without [seen] count as "everything seen" (D-087), except for ids starting with one of
## SEEN_ALL_EXCLUDED_PREFIXES (content that did not exist back then, e.g. the boss story BI2).
func has_seen(id: StringName) -> bool:
	return _seen.has(id) or (_seen_all and not is_excluded_from_seen_all(id))


static func is_excluded_from_seen_all(id: StringName) -> bool:
	for prefix in SEEN_ALL_EXCLUDED_PREFIXES:
		if String(id).begins_with(prefix):
			return true
	return false


## Marks an explanation as seen. Returns true if it was new. The caller decides when to save.
func mark_seen(id: StringName) -> bool:
	if has_seen(id):
		return false
	_seen[id] = true
	seen_changed.emit(id)
	return true


# --- World name (D-152) and the player's profile ---

## The world's own name; "" while it has none (see get_world_display_name()).
func get_world_name() -> String:
	return _world_name


## Name for menus: the world's name or "Welt <n>".
func get_world_display_name() -> String:
	if not _world_name.strip_edges().is_empty():
		return _world_name
	return SaveSlots.default_name(maxi(1, get_active_slot()))


## Renames the loaded world (memory only; the caller saves). Empty = back to "Welt <n>".
func set_world_name(text: String) -> void:
	var slot := maxi(1, get_active_slot())
	var cleaned := SaveSlots.sanitize_name(text, slot)
	_world_name = "" if cleaned == SaveSlots.default_name(slot) else cleaned


## Renames a world (slot list). The loaded world is renamed in memory and saved, another one only in
## its file ([world] name; a file of an older version gets it on its next migration). Empty = back
## to "Welt <n>". Returns the write result.
func rename_slot(slot: int, text: String) -> Error:
	if not has_slot(slot):
		return ERR_FILE_NOT_FOUND
	var cleaned := SaveSlots.sanitize_name(text, slot)
	var stored := "" if cleaned == SaveSlots.default_name(slot) else cleaned
	if save_path == slot_path(slot):
		_world_name = stored
		return save_game()
	var config := ConfigFile.new()
	if _SafeSave.load_config(config, slot_path(slot)) != OK:
		return ERR_FILE_CORRUPT
	config.set_value("world", "name", stored)
	return _SafeSave.write_config(config, slot_path(slot))


## [legacy_profile] of the loaded world ({} for new worlds), see PlayerProfile.legacy_suggestion().
func get_legacy_profile() -> Dictionary:
	return _legacy_profile.duplicate()


## The player's name (PlayerProfile, D-152); before D-152 this was the slot's name.
func get_display_name() -> String:
	return PlayerProfile.current().get_display_name()


## The player's chosen name ("" before the first start), PlayerProfile.
func get_profile_name() -> String:
	return PlayerProfile.current().player_name


## Figure of the player's profile (older one-figure code: online profile, menus).
func get_character_id() -> StringName:
	return PlayerLook.get_character(PlayerProfile.current().look)


## Outfit colour of the player's profile (older one-colour code).
func get_character_color() -> Color:
	return PlayerLook.outfit_color(PlayerProfile.current().look)


## Puts on the nearest outfit colour of the palette (older wardrobe API, memory only).
func set_character_color(color: Color) -> void:
	PlayerProfile.current().set_color(PlayerLook.OUTFIT, PlayerLook.nearest_index(PlayerLook.OUTFIT, color))


## True once an outfit colour other than the figure's start colour is worn.
func has_character_color() -> bool:
	var look := PlayerProfile.current().look
	return PlayerLook.get_index(look, PlayerLook.OUTFIT) != int(PlayerLook.default_colors(PlayerLook.get_character(look))["outfit"])


func get_last_played() -> int:
	return _last_played


# --- Save slots (MM1) ---

func slot_path(slot: int) -> String:
	return saves_dir.path_join(SaveSlots.file_name(slot))


## Slot number of the loaded file, 0 if save_path is not a slot (old save, test file).
func get_active_slot() -> int:
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if save_path == slot_path(slot):
			return slot
	return 0


func has_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SaveSlots.SLOT_COUNT and FileAccess.file_exists(slot_path(slot))


func get_slot_summary(slot: int) -> Dictionary:
	return SaveSlots.read_summary(slot_path(slot), slot)


## First slot without a file, 0 if all are used.
func get_free_slot() -> int:
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if not has_slot(slot):
			return slot
	return 0


## The slot "Weiterspielen" loads: the last used one, else the most recently played, else 0.
func get_continue_slot() -> int:
	if has_slot(_last_slot):
		return _last_slot
	var best := 0
	var best_time := -1
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if has_slot(slot):
			var played: int = get_slot_summary(slot).get("last_played", 0)
			if played > best_time:
				best_time = played
				best = slot
	return best


## Makes slot the loaded save. Returns the load_game() result (a broken file starts fresh, *.bak).
func load_slot(slot: int) -> Error:
	if not has_slot(slot):
		return ERR_FILE_NOT_FOUND
	save_path = slot_path(slot)
	var err := load_game()
	_remember_slot(slot)
	slot_changed.emit(slot)
	return err


## Starts a fresh world in an empty slot (no explanations seen, D-087) and writes it. world_name ""
## = "Welt <n>". The figure is the player's profile (D-152); the last two parameters are ignored
## (kept for older tools).
func create_slot(slot: int, world_name := "", _character_id: StringName = &"", _color := Color(0, 0, 0, 0)) -> Error:
	if slot < 1 or slot > SaveSlots.SLOT_COUNT:
		return ERR_PARAMETER_RANGE_ERROR
	if has_slot(slot):
		return ERR_ALREADY_EXISTS
	save_path = slot_path(slot)
	_reset()
	_created_at = int(Time.get_unix_time_from_system())
	var cleaned := SaveSlots.sanitize_name(world_name, slot)
	_world_name = "" if cleaned == SaveSlots.default_name(slot) else cleaned
	var err := save_game()
	_remember_slot(slot)
	slot_changed.emit(slot)
	return err


## Removes a slot. The file is kept once as slot_<n>.cfg.deleted (never shown in the game).
## Deleting the loaded slot leaves an empty in-memory state that is not saved anywhere by itself.
func delete_slot(slot: int) -> Error:
	if not has_slot(slot):
		return ERR_FILE_NOT_FOUND
	var path := ProjectSettings.globalize_path(slot_path(slot))
	if FileAccess.file_exists(path + DELETED_SUFFIX):
		DirAccess.remove_absolute(path + DELETED_SUFFIX)
	var err := DirAccess.rename_absolute(path, path + DELETED_SUFFIX)
	if err != OK:
		return err
	# Its last good copy must not bring the world back (SafeSave.recover, load_game).
	_SafeSave.remove_companions(slot_path(slot))
	if _last_slot == slot:
		_last_slot = 0
		save_settings()
	if save_path == slot_path(slot):
		_reset()
		slot_changed.emit(0)
	return OK


## True while the pre-slot save exists and was not copied into a slot yet.
func needs_legacy_import() -> bool:
	return not _legacy_imported and FileAccess.file_exists(legacy_save_path)


## Copies the pre-slot save byte for byte into the first free slot (slot 1 on a first start) and
## makes it the loaded save. The old file stays untouched. Returns the slot, 0 if nothing was done
## (nothing to import, or all slots used: then it is tried again next time).
func import_legacy_save_into_slot() -> int:
	if not needs_legacy_import():
		return 0
	var slot := get_free_slot()
	if slot == 0:
		return 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves_dir))
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(legacy_save_path), ProjectSettings.globalize_path(slot_path(slot)))
	if err != OK:
		push_warning("SaveManager: could not import %s (%s)." % [legacy_save_path, error_string(err)])
		return 0
	_legacy_imported = true
	if not FileAccess.file_exists(settings_path):
		# First settings file: take the volumes of the old save (they were per save before MM1).
		var legacy := ConfigFile.new()
		if legacy.load(legacy_save_path) == OK:
			_read_volumes(legacy, "settings")
			_apply_volumes()
	var loaded_legacy := save_path == legacy_save_path
	if _last_slot == 0 or loaded_legacy:
		_last_slot = slot
	save_settings()
	if loaded_legacy:
		save_path = slot_path(slot)
		load_game()
		slot_changed.emit(slot)
	return slot


func _remember_slot(slot: int) -> void:
	if _last_slot != slot:
		_last_slot = slot
		save_settings()


## Points slots, settings and the pre-slot save at root (tests/tools: a test folder; "user://" =
## the real defaults) and loads that folder's settings. save_path is set to root/savegame.cfg.
func set_storage_root(root: String) -> void:
	saves_dir = root.path_join("saves")
	settings_path = root.path_join("settings.cfg")
	legacy_save_path = root.path_join("savegame.cfg")
	save_path = legacy_save_path
	recover_storage()
	load_settings()
	# The player's profile lives next to the settings (PlayerProfile.default_path).
	PlayerProfile.reset()


## P1-8: finishes saves a crash interrupted (SafeSave.recover) for the settings, the pre-slot save and
## every slot, so a world whose file was being replaced is not shown as empty. Startup and
## set_storage_root(); load_game() and load_settings() do it for their own file anyway.
func recover_storage() -> void:
	_SafeSave.recover(settings_path)
	_SafeSave.recover(legacy_save_path)
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		_SafeSave.recover(slot_path(slot))


# --- Global settings (MM1: user://settings.cfg, not per slot) ---

## Reads volume and last slot. Without a settings file the volumes of the pre-slot save are used
## (migration of the old [settings] section), else the defaults.
func load_settings() -> Error:
	_volumes = DEFAULT_VOLUMES.duplicate()
	_last_slot = 0
	_legacy_imported = false
	_options = {}
	var config := ConfigFile.new()
	var err := ERR_FILE_NOT_FOUND
	_SafeSave.recover(settings_path)
	if FileAccess.file_exists(settings_path):
		# P1-8: an unreadable file falls back to its last good copy (SafeSave warns).
		err = _SafeSave.load_config(config, settings_path)
		if err != OK:
			push_warning("SaveManager: settings %s unreadable (%s); using defaults." % [settings_path, error_string(err)])
	if err == OK:
		_read_volumes(config, "audio")
		var last: Variant = config.get_value("slots", "last", 0)
		if typeof(last) == TYPE_INT and last >= 0 and last <= SaveSlots.SLOT_COUNT:
			_last_slot = last
		_legacy_imported = config.get_value("slots", "legacy_imported", false) == true
		if config.has_section("options"):
			for key in config.get_section_keys("options"):
				_options[StringName(key)] = config.get_value("options", key)
	elif FileAccess.file_exists(legacy_save_path):
		var legacy := ConfigFile.new()
		if legacy.load(legacy_save_path) == OK:
			_read_volumes(legacy, "settings")
	_apply_volumes()
	return err


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SETTINGS_VERSION)
	for bus in _volumes:
		config.set_value("audio", "volume_" + String(bus).to_lower(), _volumes[bus])
	config.set_value("slots", "last", _last_slot)
	config.set_value("slots", "legacy_imported", _legacy_imported)
	for key in _options:
		config.set_value("options", String(key), _options[key])
	var err := _SafeSave.write_config(config, settings_path)
	if err != OK:
		push_error("SaveManager: could not write %s (%s)." % [settings_path, error_string(err)])
	return err


## A global option (not per slot); default when it was never set or has another type.
func get_option(key: StringName, default: Variant) -> Variant:
	var value: Variant = _options.get(key, default)
	return value if typeof(value) == typeof(default) else default


## Stores a global option and writes settings.cfg at once.
func set_option(key: StringName, value: Variant) -> void:
	_options[key] = value
	save_settings()


func _read_volumes(config: ConfigFile, section: String) -> void:
	for bus in _volumes.keys():
		var volume: Variant = config.get_value(section, "volume_" + String(bus).to_lower(), _volumes[bus])
		if typeof(volume) == TYPE_FLOAT or typeof(volume) == TYPE_INT:
			_volumes[bus] = clampf(float(volume), 0.0, 1.0)


func get_volume(bus: StringName) -> float:
	return _volumes.get(bus, 1.0)


func get_bus_volume_db(bus: StringName) -> float:
	return linear_to_db(maxf(0.0001, get_volume(bus)))


## Changes the volume immediately; save_settings() persists it (the sliders call it on release).
func set_volume(bus: StringName, linear: float) -> void:
	_volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volumes()


func _apply_volumes() -> void:
	for bus in _volumes:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, get_bus_volume_db(bus))


func _reset() -> void:
	_permanent_gold = 0
	_permanent_crystals = 0
	_unlocked_content.clear()
	_meta_levels.clear()
	_pending_boosts.clear()
	_start_weapon = &""
	_second_weapon = &""
	_trade_levels.clear()
	_world_id = ""
	_migration = {}
	_stats.clear()
	_seen.clear()
	_seen_all = false
	_world_name = ""
	_legacy_profile = {}
	_created_at = 0
	_last_played = 0
	permanent_gold_changed.emit(_permanent_gold)
	permanent_crystals_changed.emit(_permanent_crystals)
	meta_changed.emit()
	profile_changed.emit()


## Why _load_file() rejected a file (load_game() logs it and keeps the file as *.bak, D-059).
func _fail(reason: String, err: Error) -> Error:
	_load_failure = reason
	return err
