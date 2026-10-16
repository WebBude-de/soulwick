class_name EnemyHints
extends RefCounted
## First-encounter hints: the first time the player meets an enemy type, elite kind or a champion,
## DungeonUI shows a short card. "Seen" is persisted via SaveManager.unlock_content(&"hint_<id>").
## Pure: only builds the entries, DungeonUI decides when to show them.
## Texts are translation keys (D-111, localization/translations.csv); get_entries() and
## phase_two_entry() return them translated into the current language. EnemyData.display_name and
## EnemyData.hint hold keys too (ENEMY_<ID>_NAME, ENEMY_<ID>_HINT).

const PHASE_TWO_HINT_ID := &"hint_boss_phase"
## Keys of the phase-two card (Strings: DungeonUI puts them into a hint entry; prefer phase_two_entry()).
const PHASE_TWO_TITLE := "ENEMY_BOSS_PHASE_TWO_TITLE"
const PHASE_TWO_TEXT := "ENEMY_BOSS_PHASE_TWO_HINT"

## Card title of an elite hint ("Elite: %s" with the elite name, Enemy.ELITE_NAMES).
const ELITE_TITLE := &"ENEMY_ELITE_HINT_TITLE"
const ELITE_HINTS := {
	Enemy.Elite.SWIFT: &"ENEMY_ELITE_SWIFT_HINT",
	Enemy.Elite.ARMORED: &"ENEMY_ELITE_ARMORED_HINT",
	Enemy.Elite.VOLATILE: &"ENEMY_ELITE_VOLATILE_HINT",
}
const ELITE_IDS := {
	Enemy.Elite.SWIFT: &"swift",
	Enemy.Elite.ARMORED: &"armored",
	Enemy.Elite.VOLATILE: &"volatile",
}
const CHAMPION_TITLE := &"ENEMY_CHAMPION_TITLE"
const CHAMPION_TEXT := &"ENEMY_CHAMPION_HINT"


## Entries for one enemy, most specific last: [{id, title, text, badge}]. Bosses only get their
## type hint (their phase-two hint is shown when it happens).
static func get_entries(data: EnemyData, elite: int, is_champion: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if data == null:
		return entries
	if is_champion:
		entries.append(_entry(&"hint_champion", Loc.t(CHAMPION_TITLE), Loc.t(CHAMPION_TEXT), EnemyBadges.CHAMPION))
	if ELITE_HINTS.has(elite):
		var title := Loc.t(ELITE_TITLE, [Loc.t(Enemy.ELITE_NAMES[elite])])
		entries.append(_entry(StringName("hint_elite_%s" % ELITE_IDS[elite]), title, Loc.t(ELITE_HINTS[elite]), ELITE_IDS[elite]))
	if not data.hint.is_empty():
		var badges := EnemyBadges.badges_for(data, Enemy.Elite.NONE, false)
		var badge: StringName = badges[0] if not badges.is_empty() else &""
		var name := Loc.t(StringName(data.display_name))
		entries.append(_entry(get_type_hint_id(data), name, strip_name(Loc.t(StringName(data.hint)), name), badge))
	return entries


## The boss phase-two card (DungeonUI shows it once when a boss enrages), translated.
static func phase_two_entry() -> Dictionary:
	return _entry(PHASE_TWO_HINT_ID, Loc.t(PHASE_TWO_TITLE), Loc.t(PHASE_TWO_TEXT), &"")


static func get_type_hint_id(data: EnemyData) -> StringName:
	return StringName("hint_%s" % data.id)


## Hint texts start with the name ("Golem: Slow but tough ..."); the card shows the name as its
## title already.
static func strip_name(text: String, display_name: String) -> String:
	var prefix := display_name + ":"
	if text.begins_with(prefix):
		return text.substr(prefix.length()).strip_edges()
	return text.strip_edges()


static func _entry(id: StringName, title: String, text: String, badge: StringName) -> Dictionary:
	return {"id": id, "title": title, "text": text, "badge": badge}
