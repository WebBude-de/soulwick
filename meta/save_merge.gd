class_name SaveMerge
extends RefCounted
## Cloud merge of one world (KF9, D-188 rule 7, KONZEPT §10 and the field table of the account
## concept §4.3): two states of the same world (this device and the server) become one without a
## dialog. Monotone progress is merged per field (maximum, minimum or union), everything else comes
## from the state played last (larger [profile] last_played; a tie keeps this device's state). The
## rules live in FIELD_RULES, one entry per field; a new save field gets its rule here in the package
## that introduces it (ROADMAP rule 4; without one it counts as "last played").
## Also converts a save (ConfigFile) to the cloud blob of the contract (WorldData in
## soulwick-platform packages/contracts/src/world.ts: {"<section>": {"<key>": json}}) and back, and
## hashes its content (what CloudSave compares to decide whether a world changed).
## Only static functions (D-044): no state, no file access.

## How a field is merged.
enum Rule {
	## The larger number (levels, records, counters).
	MAX,
	## The smaller number above 0 (0 = unknown, e.g. the creation time).
	MIN,
	## Both lists, each entry once (unlocks, seen ids).
	UNION,
	## true if one side is true (seen "all").
	ANY,
	## true only if both sides are true (a notice still pending; shown once is enough).
	ALL,
	## From the state played last.
	LATEST,
	## Must be equal on both sides (the world id), otherwise these are two worlds.
	SAME,
	## Local sync data ([cloud]): never uploaded, the result keeps this device's values.
	LOCAL,
}

## Rule per field ("section/key"); "section/*" is the rule of every other key of that section.
## Fields and sections not listed here come from the state played last (Rule.LATEST), like the
## concept's default for new fields.
const FIELD_RULES := {
	"meta/version": Rule.MAX,
	# Currencies and choices: the state played last (concept §4.3).
	"progress/permanent_gold": Rule.LATEST,
	"progress/permanent_crystals": Rule.LATEST,
	"progress/start_weapon": Rule.LATEST,
	"progress/second_weapon": Rule.LATEST,
	"progress/unlocked": Rule.UNION,
	# Forge (KE4): weapon levels, Arsenal unlocks (0/1), second slot, Schildplatte, Laterne.
	"meta_upgrades/*": Rule.MAX,
	# Trading post levels (KE5): Proviant slots, luck, merchant friend.
	"trade_levels/*": Rule.MAX,
	# Packed Proviant (KONZEPT §10).
	"boosts/pending": Rule.LATEST,
	# Records and chronicle counters, rescued villagers and chickens: all monotone.
	"stats/*": Rule.MAX,
	"seen/ids": Rule.UNION,
	"seen/all": Rule.ANY,
	"world/id": Rule.SAME,
	"world/name": Rule.LATEST,
	"profile/created": Rule.MIN,
	"profile/last_played": Rule.MAX,
	# The v5 refund happens once per world (marker v5_refund_gold, KONZEPT §10: maximum).
	"migration/v5_refund_gold": Rule.MAX,
	"migration/v5_shield_plate": Rule.MAX,
	"migration/v5_refunded": Rule.UNION,
	"migration/v5_weapons": Rule.UNION,
	"migration/v5_notice_pending": Rule.ALL,
	"legacy_profile/*": Rule.LATEST,
	"cloud/*": Rule.LOCAL,
}
## Sections that never leave the device (contract: the server drops `cloud` anyway).
const LOCAL_SECTIONS: Array[String] = ["cloud"]
## Fields left out of content_hash(): saving alone changes them, the world's content does not.
const HASH_IGNORED_FIELDS: Array[String] = ["profile/last_played"]
## Section and key names the contract accepts (CONFIG_NAME in world.ts).
const NAME_PATTERN := "^[A-Za-z0-9_.:/-]{1,128}$"
## Floats are rounded to this step in the blob (play time), so a value survives JSON both ways.
const FLOAT_STEP := 0.001
## Largest integer a JSON number carries exactly (2^53).
const MAX_EXACT_INT := 9007199254740992.0

const LOCAL := "local"
const SERVER := "server"


## The rule of one field.
static func rule_for(section: String, key: String) -> Rule:
	var exact := "%s/%s" % [section, key]
	if FIELD_RULES.has(exact):
		return FIELD_RULES[exact]
	return FIELD_RULES.get("%s/*" % section, Rule.LATEST)


## Merges two states of the same world. Both are migrated copies first (the configs themselves stay
## untouched). Returns {ok, error ("" | "world_id_mismatch" | "newer_version"), config (the merged
## state, [cloud] of local), winner (LOCAL or SERVER: whose "last played" fields were taken),
## loser_lost (true if a "last played" field of the other side differs from the result, i.e. its
## state is worth a backup on the server)}.
static func merge(local: ConfigFile, server: ConfigFile) -> Dictionary:
	var result := {"ok": false, "error": "", "config": null, "winner": LOCAL, "loser_lost": false}
	if _version(local) > SaveManager.SAVE_VERSION or _version(server) > SaveManager.SAVE_VERSION:
		result["error"] = "newer_version"
		return result
	var a := _migrated(local)
	var b := _migrated(server)
	if String(a.get_value("world", "id", "")).to_lower() != String(b.get_value("world", "id", "")).to_lower():
		result["error"] = "world_id_mismatch"
		return result
	var local_wins := _last_played(a) >= _last_played(b)
	var winner := a if local_wins else b
	var loser := b if local_wins else a
	var merged := ConfigFile.new()
	var lost := false
	for section in _sections(winner, loser):
		for key in _keys(section, winner, loser):
			var rule := rule_for(section, key)
			var has_w := winner.has_section_key(section, key)
			var has_l := loser.has_section_key(section, key)
			var value: Variant = null
			if rule == Rule.LOCAL:
				if a.has_section_key(section, key):
					merged.set_value(section, key, a.get_value(section, key))
				continue
			if rule == Rule.LATEST or rule == Rule.SAME:
				if has_l and (not has_w or not _same(winner.get_value(section, key), loser.get_value(section, key))):
					lost = true
				if not has_w:
					continue
				value = winner.get_value(section, key)
			elif not has_l:
				value = winner.get_value(section, key)
			elif not has_w:
				value = loser.get_value(section, key)
			else:
				value = merge_value(rule, winner.get_value(section, key), loser.get_value(section, key))
			merged.set_value(section, key, value)
	result["ok"] = true
	result["config"] = merged
	result["winner"] = LOCAL if local_wins else SERVER
	result["loser_lost"] = lost
	return result


## One field with both values present: winner is the state played last. Values of the wrong type for
## the rule keep the winner's value.
static func merge_value(rule: Rule, winner: Variant, loser: Variant) -> Variant:
	match rule:
		Rule.MAX:
			if _is_number(winner) and _is_number(loser):
				return loser if loser > winner else winner
		Rule.MIN:
			if _is_number(winner) and _is_number(loser):
				if winner <= 0:
					return loser
				if loser <= 0:
					return winner
				return loser if loser < winner else winner
		Rule.UNION:
			if _is_list(winner) and _is_list(loser):
				return _union(winner, loser)
		Rule.ANY:
			if typeof(winner) == TYPE_BOOL and typeof(loser) == TYPE_BOOL:
				return winner or loser
		Rule.ALL:
			if typeof(winner) == TYPE_BOOL and typeof(loser) == TYPE_BOOL:
				return winner and loser
	return winner


# --- The cloud blob (WorldData) ---

## The save as WorldData: one dictionary per section, values JSON-safe (PackedStringArray -> array,
## whole floats -> int, other floats rounded to FLOAT_STEP). [cloud] and names the contract would
## reject are left out (the latter with a warning).
static func to_world_data(config: ConfigFile) -> Dictionary:
	var data := {}
	if config == null:
		return data
	var regex := RegEx.create_from_string(NAME_PATTERN)
	for section in config.get_sections():
		if LOCAL_SECTIONS.has(section):
			continue
		if regex.search(section) == null:
			push_warning("SaveMerge: section [%s] cannot go to the cloud (name), left out." % section)
			continue
		var values := {}
		for key in config.get_section_keys(section):
			if regex.search(key) == null:
				push_warning("SaveMerge: [%s] %s cannot go to the cloud (name), left out." % [section, key])
				continue
			values[key] = to_json_value(config.get_value(section, key))
		data[section] = values
	return data


## WorldData (e.g. parsed from the API) as a save: whole numbers become int, string lists
## PackedStringArray, nulls are left out. Never fails; check the result like a loaded file.
static func from_world_data(data: Dictionary) -> ConfigFile:
	var config := ConfigFile.new()
	for section: Variant in data:
		var values: Variant = data[section]
		if typeof(section) != TYPE_STRING or typeof(values) != TYPE_DICTIONARY:
			continue
		for key: Variant in values:
			var value: Variant = from_json_value(values[key])
			if typeof(key) == TYPE_STRING and value != null:
				config.set_value(section, key, value)
	return config


static func to_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return _json_number(value)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_COLOR:
			return "#" + (value as Color).to_html(false)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var list := []
			for item: Variant in value:
				list.append(to_json_value(item))
			return list
		TYPE_DICTIONARY:
			var dict := {}
			for key: Variant in value:
				dict[str(key)] = to_json_value(value[key])
			return dict
		TYPE_NIL:
			return null
	return var_to_str(value)


static func from_json_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return _json_number(value)
		TYPE_ARRAY:
			var strings := PackedStringArray()
			var all_strings := true
			for item: Variant in value:
				if typeof(item) != TYPE_STRING:
					all_strings = false
					break
				strings.append(item)
			if all_strings:
				return strings
			var list := []
			for item: Variant in value:
				list.append(from_json_value(item))
			return list
		TYPE_DICTIONARY:
			var dict := {}
			for key: Variant in value:
				dict[str(key)] = from_json_value(value[key])
			return dict
	return value


## Hash of a world's content (WorldData): equal content gives the same hash, whatever the order of
## sections, keys and list entries. HASH_IGNORED_FIELDS and [cloud] do not count.
static func content_hash(data: Dictionary) -> String:
	var copy := {}
	for section: Variant in data:
		if LOCAL_SECTIONS.has(str(section)) or typeof(data[section]) != TYPE_DICTIONARY:
			continue
		var values := {}
		for key: Variant in data[section]:
			if HASH_IGNORED_FIELDS.has("%s/%s" % [section, key]):
				continue
			values[str(key)] = _hash_value(to_json_value(data[section][key]))
		copy[str(section)] = values
	return JSON.stringify(copy, "", true, true).sha256_text()


## Size of the blob in bytes as the server counts it (UTF-8 of its JSON).
static func data_size(data: Dictionary) -> int:
	return JSON.stringify(data).to_utf8_buffer().size()


# --- Helpers ---

static func _json_number(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	var number := float(value)
	if is_finite(number) and absf(number) < MAX_EXACT_INT and number == floorf(number):
		return int(number)
	return snappedf(number, FLOAT_STEP)


## Lists are compared as sets (sorted), so the order of unlocks does not make a world "changed".
static func _hash_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var all_strings := true
		for item: Variant in value:
			if typeof(item) != TYPE_STRING:
				all_strings = false
		if all_strings:
			var sorted: Array = (value as Array).duplicate()
			sorted.sort()
			return sorted
	return value


static func _migrated(config: ConfigFile) -> ConfigFile:
	var copy := ConfigFile.new()
	copy.parse(config.encode_to_text())
	if typeof(copy.get_value("meta", "version", "")) != TYPE_INT:
		copy.set_value("meta", "version", SaveManager.SAVE_VERSION)
	SaveManager.migrate(copy)
	return copy


static func _version(config: ConfigFile) -> int:
	var version: Variant = config.get_value("meta", "version", 0)
	return int(version) if typeof(version) == TYPE_INT else 0


static func _last_played(config: ConfigFile) -> int:
	var value: Variant = config.get_value("profile", "last_played", 0)
	return int(value) if typeof(value) == TYPE_INT else 0


## Sections of both states, the winner's order first.
static func _sections(winner: ConfigFile, loser: ConfigFile) -> PackedStringArray:
	var sections := winner.get_sections()
	for section in loser.get_sections():
		if not sections.has(section):
			sections.append(section)
	return sections


static func _keys(section: String, winner: ConfigFile, loser: ConfigFile) -> PackedStringArray:
	var keys := winner.get_section_keys(section) if winner.has_section(section) else PackedStringArray()
	if loser.has_section(section):
		for key in loser.get_section_keys(section):
			if not keys.has(key):
				keys.append(key)
	return keys


static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b or JSON.stringify(to_json_value(a)) == JSON.stringify(to_json_value(b))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_list(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_STRING_ARRAY or typeof(value) == TYPE_ARRAY


static func _union(winner: Variant, loser: Variant) -> Variant:
	var result: Variant = winner.duplicate()
	var strings := typeof(result) == TYPE_PACKED_STRING_ARRAY
	for item: Variant in loser:
		var entry: Variant = str(item) if strings else item
		if not result.has(entry):
			result.append(entry)
	return result
