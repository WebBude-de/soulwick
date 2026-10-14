class_name EnemyHints
extends RefCounted
## First-encounter hints: the first time the player meets an enemy type, elite kind or a champion,
## DungeonUI shows a short card. "Seen" is persisted via SaveManager.unlock_content(&"hint_<id>").
## Pure: only builds the entries, DungeonUI decides when to show them.

const PHASE_TWO_HINT_ID := &"hint_boss_phase"
const PHASE_TWO_TITLE := "Zweite Phase"
const PHASE_TWO_TEXT := "Unter halber Lebensenergie brüllt jeder Boss kurz auf (unverwundbar) und greift danach schneller und mit neuen Mustern an."

const ELITE_HINTS := {
	Enemy.Elite.SWIFT: ["Elite: Flink", "Läuft und schlägt deutlich schneller zu. Erkennbar am cyanfarbenen Umriss und Blitz-Symbol."],
	Enemy.Elite.ARMORED: ["Elite: Gepanzert", "Fast doppelt so viel Leben (blauer Balken) und kaum Rückstoß. Nimm dir Zeit."],
	Enemy.Elite.VOLATILE: ["Elite: Explosiv", "Explodiert beim Tod! Erledige ihn auf Abstand oder springe danach sofort weg."],
}
const ELITE_IDS := {
	Enemy.Elite.SWIFT: &"swift",
	Enemy.Elite.ARMORED: &"armored",
	Enemy.Elite.VOLATILE: &"volatile",
}
const CHAMPION_TITLE := "Champion"
const CHAMPION_TEXT := "Ein Miniboss mit Elite-Eigenschaft, eigenem Spezialangriff und Gefolge. Unter halber Lebensenergie wird er wütend."


## Entries for one enemy, most specific last: [{id, title, text, badge}]. Bosses only get their
## type hint (their phase-two hint is shown when it happens).
static func get_entries(data: EnemyData, elite: int, is_champion: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if data == null:
		return entries
	if is_champion:
		entries.append(_entry(&"hint_champion", CHAMPION_TITLE, CHAMPION_TEXT, EnemyBadges.CHAMPION))
	if ELITE_HINTS.has(elite):
		var elite_hint: Array = ELITE_HINTS[elite]
		entries.append(_entry(StringName("hint_elite_%s" % ELITE_IDS[elite]), elite_hint[0], elite_hint[1], ELITE_IDS[elite]))
	if not data.hint.is_empty():
		var badges := EnemyBadges.badges_for(data, Enemy.Elite.NONE, false)
		var badge: StringName = badges[0] if not badges.is_empty() else &""
		entries.append(_entry(get_type_hint_id(data), data.display_name, strip_name(data.hint, data.display_name), badge))
	return entries


static func get_type_hint_id(data: EnemyData) -> StringName:
	return StringName("hint_%s" % data.id)


## Hints are written as "Golem: Langsam ..."; the card shows the name as its title already.
static func strip_name(text: String, display_name: String) -> String:
	var prefix := display_name + ":"
	if text.begins_with(prefix):
		return text.substr(prefix.length()).strip_edges()
	return text.strip_edges()


static func _entry(id: StringName, title: String, text: String, badge: StringName) -> Dictionary:
	return {"id": id, "title": title, "text": text, "badge": badge}
