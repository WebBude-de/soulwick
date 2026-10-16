class_name SaveSlots
extends RefCounted
## Read-only helpers for save slots (MM1): summaries for the slot list without loading a slot,
## name rules and German formatting. State changes (create, load, delete) live in SaveManager.
## D-152: a slot is a world ("Welt 1", own name possible); the player's name and figure are the
## account profile (PlayerProfile). read_legacy_profile() reads what MM1 slots stored about the player.

## Number of local save slots (TESTWERT).
const SLOT_COUNT := 3
## Longest world name in characters (TESTWERT).
const NAME_MAX_LENGTH := 16


## Slot file name inside SaveManager.saves_dir.
static func file_name(slot: int) -> String:
	return "slot_%d.cfg" % slot


## Name shown for a world without a name of its own, in the current language ("Welt 2" / "World 2",
## D-111, D-152).
static func default_name(slot: int) -> String:
	return Loc.t(&"WORLD_DEFAULT_NAME", [slot])


## Trims, drops control characters and cuts to NAME_MAX_LENGTH; empty -> default_name(slot).
static func sanitize_name(text: String, slot: int) -> String:
	var cleaned := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 32 and code != 127:
			cleaned += text[i]
	cleaned = cleaned.strip_edges()
	if cleaned.length() > NAME_MAX_LENGTH:
		cleaned = cleaned.substr(0, NAME_MAX_LENGTH).strip_edges()
	return cleaned if not cleaned.is_empty() else default_name(slot)


## What the slot list shows. Never changes the file. Keys: exists, broken, name (the world's name or
## "Welt <n>"), world_name (stored name, "" = default), version, gold, crystals, deepest_room,
## play_time (s), last_played (unix s, 0 = unknown), all_seen.
static func read_summary(path: String, slot: int) -> Dictionary:
	var summary := {
		"exists": false, "broken": false, "name": default_name(slot), "world_name": "", "version": 0,
		"gold": 0, "crystals": 0, "deepest_room": 0, "play_time": 0.0, "last_played": 0, "all_seen": false,
	}
	if not FileAccess.file_exists(path):
		return summary
	summary["exists"] = true
	var config := ConfigFile.new()
	if config.load(path) != OK:
		summary["broken"] = true
		return summary
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version < 1:
		summary["broken"] = true
	else:
		summary["version"] = version
	# Before D-152 (v4) [profile] name was the player's name, not the world's: such a world has none.
	var stored_name: Variant = config.get_value("world", "name", "")
	if typeof(stored_name) == TYPE_STRING and not String(stored_name).strip_edges().is_empty():
		summary["name"] = String(stored_name)
		summary["world_name"] = String(stored_name)
	summary["gold"] = _non_negative_int(config.get_value("progress", "permanent_gold", 0))
	summary["crystals"] = _non_negative_int(config.get_value("progress", "permanent_crystals", 0))
	summary["deepest_room"] = _non_negative_int(config.get_value("stats", "deepest_room", 0))
	var play_time: Variant = config.get_value("stats", "play_time", 0.0)
	if typeof(play_time) == TYPE_FLOAT or typeof(play_time) == TYPE_INT:
		summary["play_time"] = maxf(0.0, float(play_time))
	var last_played := _non_negative_int(config.get_value("profile", "last_played", 0))
	if last_played == 0:
		# Old saves have no timestamp: the file time is the best guess.
		last_played = FileAccess.get_modified_time(path)
	summary["last_played"] = last_played
	summary["all_seen"] = not config.has_section("seen") or config.get_value("seen", "all", false) == true
	return summary


## What an MM1 slot stored about the player: {name, character (StringName), color (alpha 0 = the
## figure's default)}; files of v1..v3 have it in [profile], migrated v4 files in [legacy_profile].
## {} for new worlds, missing or unreadable files. Never changes the file.
static func read_legacy_profile(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return {}
	var version: Variant = config.get_value("meta", "version", -1)
	var section := "legacy_profile" if typeof(version) == TYPE_INT and version >= 4 else "profile"
	if not config.has_section_key(section, "name") and not config.has_section_key(section, "character"):
		return {}
	var stored_name: Variant = config.get_value(section, "name", "")
	var character: Variant = config.get_value(section, "character", "")
	return {
		"name": String(stored_name) if typeof(stored_name) == TYPE_STRING else "",
		"character": StringName(character) if typeof(character) == TYPE_STRING or typeof(character) == TYPE_STRING_NAME else &"",
		"color": parse_color(config.get_value(section, "color", "")),
	}


## "#rrggbb" -> Color; anything else -> transparent (= use the character's default colour).
static func parse_color(value: Variant) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
		return Color(0, 0, 0, 0)
	return Color.html(value)


## "45 min", "1:08 h", "12:30 h"; under a minute "< 1 min".
static func format_play_time(seconds: float) -> String:
	var minutes := floori(maxf(0.0, seconds) / 60.0)
	if minutes < 1:
		return "< 1 min"
	if minutes < 60:
		return "%d min" % minutes
	return "%d:%02d h" % [floori(minutes / 60.0), minutes % 60]


## Local date "14.10.2026 · 03:03" (English "2026-10-14 · 03:03"); "heute · 03:03" / "gestern · 03:03"
## ("today" / "yesterday") when close; 0 -> "–".
static func format_last_played(unix_time: int, now := -1) -> String:
	if unix_time <= 0:
		return "–"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := Time.get_datetime_dict_from_unix_time(unix_time + bias)
	var clock := "%02d:%02d" % [local["hour"], local["minute"]]
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var day := floori(float(unix_time + bias) / 86400.0)
	var today := floori(float(now + bias) / 86400.0)
	if day == today:
		return Loc.t(&"SAVE_TODAY", [clock])
	if day == today - 1:
		return Loc.t(&"SAVE_YESTERDAY", [clock])
	if Loc.current_language() == &"de":
		return "%02d.%02d.%d · %s" % [local["day"], local["month"], local["year"], clock]
	return "%d-%02d-%02d · %s" % [local["year"], local["month"], local["day"], clock]


static func _non_negative_int(value: Variant) -> int:
	return maxi(0, int(value)) if typeof(value) == TYPE_INT else 0
