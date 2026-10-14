extends Node
## Owns permanent progress only (permanent gold and crystals, unlocks, village upgrade levels,
## pending one-run boosts, statistics, the slot profile) plus the global settings. Never stores run
## state (D-040).
## Save format (D-059, extended by D-078, D-087 and MM1): ConfigFile with [meta] version and sections
## [progress], [meta_upgrades], [boosts], [stats], [seen], [profile]. Older versions are migrated on
## load (the untouched file is kept once as *.v<old>.bak before); missing, unreadable, newer or invalid
## files fall back to a fresh state and a broken file is kept as *.bak.
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
## Name, character or clothing colour of the loaded save changed (e.g. at home in the village).
## Hook for the player sprite: re-apply CharacterCatalog.apply_active(sprite).
signal profile_changed
## An unlock id was stored for the first time (enemy hints, village events of MetaUnlocks, …).
signal content_unlocked(id: StringName)

const SAVE_VERSION := 3
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
## boss_intro_<boss>) is new and should be shown once also in migrated saves.
const SEEN_ALL_EXCLUDED_PREFIXES: Array[String] = ["boss_intro_"]
## Suffix of the copy kept before a migration: slot_1.cfg -> slot_1.cfg.v2.bak (written once).
const MIGRATION_BACKUP_SUFFIX := ".v%d.bak"

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
## Second start weapon picked in the forge (Arsenal), empty = default.
var _second_weapon: StringName = &""
## Statistics for the chronicle: ints, play_time is a float in seconds.
var _stats: Dictionary[StringName, Variant] = {}
## One-time explanations the player has already seen (D-087), e.g. &"intro_forge".
var _seen: Dictionary[StringName, bool] = {}
## True for saves written before the [seen] section existed: they count as "everything seen" (D-087).
var _seen_all := false
## Slot profile (MM1, [profile]): name, character, clothing colour (alpha 0 = character default),
## creation and last save time (unix seconds, 0 = unknown).
var _profile_name := ""
var _character_id: StringName = &""
var _character_color := Color(0, 0, 0, 0)
var _created_at := 0
var _last_played := 0

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


func load_game() -> Error:
	_reset()
	if not FileAccess.file_exists(save_path):
		return ERR_FILE_NOT_FOUND
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return _reject("unreadable", ERR_FILE_CORRUPT)
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version < 1 or version > SAVE_VERSION:
		return _reject("unsupported version %s" % str(version), ERR_FILE_UNRECOGNIZED)
	if version < SAVE_VERSION:
		_backup_before_migration(version)
	migrate(config)

	var gold: Variant = config.get_value("progress", "permanent_gold", 0)
	if typeof(gold) != TYPE_INT or gold < 0:
		return _reject("invalid permanent_gold", ERR_INVALID_DATA)
	var crystals: Variant = config.get_value("progress", "permanent_crystals", 0)
	if typeof(crystals) != TYPE_INT or crystals < 0:
		return _reject("invalid permanent_crystals", ERR_INVALID_DATA)
	var unlocked: Variant = config.get_value("progress", "unlocked", PackedStringArray())
	if typeof(unlocked) != TYPE_PACKED_STRING_ARRAY:
		return _reject("invalid unlocked list", ERR_INVALID_DATA)
	var levels: Dictionary[StringName, int] = {}
	if config.has_section("meta_upgrades"):
		for key in config.get_section_keys("meta_upgrades"):
			var level: Variant = config.get_value("meta_upgrades", key)
			if typeof(level) != TYPE_INT or level < 0:
				return _reject("invalid meta upgrade level %s" % key, ERR_INVALID_DATA)
			levels[StringName(key)] = level

	_permanent_gold = gold
	_permanent_crystals = crystals
	for id in unlocked:
		_unlocked_content[StringName(id)] = true
	_meta_levels = levels
	_second_weapon = StringName(str(config.get_value("progress", "second_weapon", "")))
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
	# The profile only labels the slot: invalid entries fall back to defaults. Volumes in an old
	# [settings] section are ignored here; they are global now (load_settings migrates them once).
	var profile_name: Variant = config.get_value("profile", "name", "")
	if typeof(profile_name) == TYPE_STRING:
		_profile_name = String(profile_name)
	var character: Variant = config.get_value("profile", "character", "")
	if typeof(character) == TYPE_STRING or typeof(character) == TYPE_STRING_NAME:
		_character_id = StringName(character)
	_character_color = SaveSlots.parse_color(config.get_value("profile", "color", ""))
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
## it needs no migration step. [profile] and [seen] are never removed by a migration.
## v2 -> v3 (B2, D-087): forge levels are converted to the shorter table (V3_LEVEL_RULES), and the
## save counts as "everything unlocked": all village events (V3_UNLOCKED_EVENTS) are added and their
## announcements marked as shown. Invalid values are left alone (load_game() rejects them).
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
	config.set_value("meta", "version", SAVE_VERSION)
	return from_version


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
## backup is never overwritten, so it always holds the first file of that version.
func _backup_before_migration(from_version: int) -> void:
	var backup := save_path + MIGRATION_BACKUP_SUFFIX % from_version
	if FileAccess.file_exists(backup):
		return
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup))
	if err != OK:
		push_warning("SaveManager: could not back up %s before migrating (%s)." % [save_path, error_string(err)])


func save_game() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("progress", "permanent_gold", _permanent_gold)
	config.set_value("progress", "permanent_crystals", _permanent_crystals)
	var unlocked := PackedStringArray()
	for id in _unlocked_content:
		unlocked.append(String(id))
	config.set_value("progress", "unlocked", unlocked)
	config.set_value("progress", "second_weapon", String(_second_weapon))
	for id in _meta_levels:
		config.set_value("meta_upgrades", String(id), _meta_levels[id])
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
	config.set_value("profile", "name", _profile_name)
	config.set_value("profile", "character", String(_character_id))
	config.set_value("profile", "color", _character_color.to_html(false) if _character_color.a > 0.0 else "")
	config.set_value("profile", "created", _created_at)
	config.set_value("profile", "last_played", _last_played)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	var err := config.save(save_path)
	if err != OK:
		push_error("SaveManager: could not write %s (%s)." % [save_path, error_string(err)])
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


# --- Slot profile (MM1) ---

## Stored profile name; empty for saves without one (see get_display_name()).
func get_profile_name() -> String:
	return _profile_name


## Name for menus: the profile name or "Spielstand <n>".
func get_display_name() -> String:
	if not _profile_name.strip_edges().is_empty():
		return _profile_name
	return SaveSlots.default_name(maxi(1, get_active_slot()))


func get_character_id() -> StringName:
	return _character_id if _character_id != &"" else CharacterCatalog.DEFAULT_ID


## Clothing colour of the loaded save; the character's default when none was picked.
func get_character_color() -> Color:
	if _character_color.a > 0.0:
		return _character_color
	var data := CharacterCatalog.get_character(get_character_id())
	return data.default_color if data != null else Color.WHITE


## Sets the profile of the loaded save (memory only; the caller decides when to save).
## A colour with alpha 0 means "the character's default colour".
func set_profile(profile_name: String, character_id: StringName, color := Color(0, 0, 0, 0)) -> void:
	_profile_name = profile_name
	_character_id = character_id
	_character_color = Color(color, 1.0) if color.a > 0.0 else Color(0, 0, 0, 0)
	profile_changed.emit()


## Changes only the clothing colour (wardrobe at home, memory only; the caller saves).
func set_character_color(color: Color) -> void:
	set_profile(_profile_name, _character_id, color)


## True once a clothing colour was picked (else the character's default is used).
func has_character_color() -> bool:
	return _character_color.a > 0.0


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


## Starts a fresh save in an empty slot (no explanations seen, D-087) and writes it.
func create_slot(slot: int, profile_name: String, character_id: StringName, color := Color(0, 0, 0, 0)) -> Error:
	if slot < 1 or slot > SaveSlots.SLOT_COUNT:
		return ERR_PARAMETER_RANGE_ERROR
	if has_slot(slot):
		return ERR_ALREADY_EXISTS
	save_path = slot_path(slot)
	_reset()
	_created_at = int(Time.get_unix_time_from_system())
	set_profile(SaveSlots.sanitize_name(profile_name, slot), character_id, color)
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
	load_settings()


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
	if FileAccess.file_exists(settings_path):
		err = config.load(settings_path)
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(settings_path.get_base_dir()))
	var err := config.save(settings_path)
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
	_second_weapon = &""
	_stats.clear()
	_seen.clear()
	_seen_all = false
	_profile_name = ""
	_character_id = &""
	_character_color = Color(0, 0, 0, 0)
	_created_at = 0
	_last_played = 0
	permanent_gold_changed.emit(_permanent_gold)
	permanent_crystals_changed.emit(_permanent_crystals)
	meta_changed.emit()
	profile_changed.emit()


func _reject(reason: String, err: Error) -> Error:
	push_warning("SaveManager: save file %s rejected (%s); starting fresh." % [save_path, reason])
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak"))
	_reset()
	return err
