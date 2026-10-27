class_name RoomFlint
extends RefCounted
## Flint explains a room type the first time (WK11, KONZEPT §7.2, D-211: he replaces the explanation
## card of the intro pattern D-133; D-206: "Fang den Gekrönten"). The first time per account
## (AccountSeen, seen id "flint_room_<genre>") Flint flies the camera over the task - way, goal,
## danger - and says it in 2-4 short sentences (texts FLINT_ROOM_<GENRE>_<n>); a known room type
## gets the short intro without him.
##
## Who builds what:
## - RoomIntro (rooms with a goal: arena and the minigames) plays the tour between door and banner
##   and holds the countdown meanwhile (Phase.FLINT). The camera goals come from the mode
##   (get_flint_steps() on the mode node or on the goal, built with steps()), else the intro's focus.
## - Rooms without a RoomIntro (special rooms, trials, rest, elite nest, chasm ...): explain_room()
##   with goals from the room's content (room_points()); DungeonUI.show_genre asks it for every
##   local player.
##
## Co-op (D-085, D-088, D-123): nothing pauses. Every machine knows who knows which room type: the
## local account through AccountSeen, every player of a session through the lobby profile
## (NetPlayers, PROFILE_KEY -> player meta KNOWN_META), and after an intro all players count as
## knowing it. So every machine computes the same learners and the same extra countdown
## (estimated_duration, language independent). A learner sees the tour (protected by FlintGuide),
## the others the short sentence and the line "Flint erklärt Mia die Jagd …".
## Pure helpers (static), no state of their own; the knowledge lives at the player (meta).

const SEEN_PREFIX := "flint_room_"
## Id of the short version for players who know the room type (shown again every time asked).
const SHORT_SUFFIX := "_short"
## Player meta: PackedStringArray of the room types this player knows (co-op sessions only).
const KNOWN_META: StringName = &"flint_rooms_known"
## Key of the lobby profile (NetPlayers) with the room types the account knows.
const PROFILE_KEY := "flint_rooms"
## The tour's camera flies at most this far from the player (world px; the camera keeps to the
## room's limits anyway). TESTWERT
const MAX_PAN_DISTANCE := 560.0
## Co-op: extra seconds on top of Flint's estimated time before the banner comes. TESTWERT
const COOP_MARGIN := 0.5
## Single player: the intro waits for "Weiter" at most this long, then goes on without him. TESTWERT
const SOLO_MAX_WAIT := 120.0
## Tools and tests: scripts started with -s explain rooms only when this is set (or the environment
## variable ENV_SWITCH is "1", inherited by the client processes of net_run_smoke), like the
## practice run, so bots never wait for a "Weiter". Tools switched on through the environment play
## every tour on by itself (their bots never press "Weiter" either).
const ENV_SWITCH := "SOULWICK_FLINT_ROOMS"

## Sentences of a tour per genre: one mood per sentence (FLINT_ROOM_<GENRE>_1 ...). The mode gives
## the camera goal of each sentence (steps(), points by index). 2-4 sentences, at most two lines each.
const TOURS: Dictionary[StringName, Array] = {
	&"arena": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"escort": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"flame": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK],
	&"relic": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK],
	&"souls": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"rifts": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"hunt": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK],
	&"lightfire": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK],
	&"collapse": [FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED],
	&"elite_nest": [FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"catacomb": [FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"chasm": [FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"secret": [FlintGuideStep.Mood.HAPPY, FlintGuideStep.Mood.TALK],
	&"trial_gauntlet": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"trial_light_run": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"trial_crumble": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"pact_altar": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.WORRIED, FlintGuideStep.Mood.HAPPY],
	&"upgrade_altar": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.HAPPY],
	&"wager_altar": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"campfire": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK, FlintGuideStep.Mood.HAPPY],
	&"shop": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK],
	&"weapon": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.TALK],
	&"fountain": [FlintGuideStep.Mood.POINT, FlintGuideStep.Mood.HAPPY],
}
## Room types a RoomIntro introduces: they also have a short sentence (FLINT_ROOM_<GENRE>_SHORT) and
## a name for the co-op line (FLINT_ROOM_<GENRE>_NAME, with its article: "die Jagd").
const INTRO_GENRES: Array[StringName] = [&"arena", &"escort", &"flame", &"relic", &"souls", &"rifts", &"hunt", &"lightfire", &"collapse"]
## Campfire: the last sentence names the soul gate; dropped in a campfire without one.
const CAMPFIRE_PORTAL_STEP := 2

## Tests: explain rooms in a script run too.
static var explain_in_scripts := false


# --- Texts and tours ---

## True if Flint explains room types in this run (always in the game; scripts only when switched on).
static func is_enabled() -> bool:
	if explain_in_scripts or _switched_on_by_environment():
		return true
	return not PlayerProfile.is_script_run()


static func _switched_on_by_environment() -> bool:
	return OS.get_environment(ENV_SWITCH) == "1"


static func has_tour(genre: StringName) -> bool:
	return TOURS.has(genre)


static func seen_id(genre: StringName) -> StringName:
	return StringName(SEEN_PREFIX + String(genre))


static func sentence_count(genre: StringName) -> int:
	return (TOURS[genre] as Array).size() if has_tour(genre) else 0


## Key of the index-th sentence (0-based) of a genre's tour.
static func text_key(genre: StringName, index: int) -> StringName:
	return StringName("FLINT_ROOM_%s_%d" % [String(genre).to_upper(), index + 1])


static func short_key(genre: StringName) -> StringName:
	return StringName("FLINT_ROOM_%s_SHORT" % String(genre).to_upper())


static func name_key(genre: StringName) -> StringName:
	return StringName("FLINT_ROOM_%s_NAME" % String(genre).to_upper())


## The sentences of a genre's tour. points[i]: camera goal of sentence i (global; Vector2.INF or
## missing = Flint only talks, the camera comes home); args[i]: format arguments of sentence i.
static func steps(genre: StringName, points: Array = [], args: Dictionary = {}) -> Array[FlintGuideStep]:
	var result: Array[FlintGuideStep] = []
	if not has_tour(genre):
		return result
	var moods: Array = TOURS[genre]
	for i in moods.size():
		var step := FlintGuideStep.say(text_key(genre, i), moods[i], args.get(i, []))
		if i < points.size() and points[i] is Vector2 and (points[i] as Vector2).is_finite():
			step.at_point(points[i])
		result.append(step)
	return result


## The tour of a genre with these steps. coop: goes on by itself (the countdown waits a fixed
## time on every machine), single player waits for "Weiter" (not in a tool, ENV_SWITCH).
static func tour(genre: StringName, tour_steps: Array[FlintGuideStep], coop := false) -> FlintExplanation:
	var explanation := FlintExplanation.tour(seen_id(genre), tour_steps)
	explanation.auto_advance = coop or (_switched_on_by_environment() and PlayerProfile.is_script_run())
	explanation.max_pan_distance = MAX_PAN_DISTANCE
	return explanation


## The short version for players who know the room type while a mate learns it (co-op): one
## sentence in the corner, no camera, no lock, every time.
static func short_hint(genre: StringName) -> FlintExplanation:
	var hint := FlintExplanation.hint(StringName(String(seen_id(genre)) + SHORT_SUFFIX),
			[FlintGuideStep.say(short_key(genre), FlintGuideStep.Mood.TALK)] as Array[FlintGuideStep])
	hint.once = false
	return hint


## Seconds Flint needs for these steps without anybody pressing, plus COOP_MARGIN: the longest text
## of every language counts, so every machine of a session gets the same number.
static func estimated_duration(tour_steps: Array[FlintGuideStep]) -> float:
	var texts := PackedStringArray()
	for step in tour_steps:
		if step != null:
			texts.append(timing_text(step))
	return FlintGuideRules.estimated_duration(texts) + COOP_MARGIN


## The longest text of a step over the game's languages (formatted with its arguments).
static func timing_text(step: FlintGuideStep) -> String:
	var longest := step.get_text()
	for language in Loc.LANGUAGES:
		var translation := TranslationServer.get_translation_object(String(language))
		if translation == null:
			continue
		var text := String(translation.get_message(step.text_key))
		if text.is_empty() or text == String(step.text_key):
			continue
		if not step.text_args.is_empty() and text.contains("%"):
			text = text % step.text_args
		if text.length() > longest.length():
			longest = text
	return longest


# --- Who knows what ---

## True if player knows the room type: the session's state when there is one (lobby profile, the
## same on every machine), else the own account; a mate without a state (older build) counts as
## knowing, so nobody waits for an explanation he never gets.
static func knows(player: Node, genre: StringName) -> bool:
	if player == null or not is_instance_valid(player):
		return true
	if player.has_meta(KNOWN_META):
		return PackedStringArray(player.get_meta(KNOWN_META)).has(String(genre))
	if player.get(&"is_local") == true:
		return AccountSeen.has_seen(seen_id(genre))
	return true


## The players who do not know genre yet (only genres with a tour).
static func learners(players: Array[Player], genre: StringName) -> Array[Player]:
	var result: Array[Player] = []
	if not has_tour(genre):
		return result
	for player in players:
		if not knows(player, genre):
			result.append(player)
	return result


## Sets the room types a player knows (lobby profile; cleaned).
static func set_known(player: Node, genres: Variant) -> void:
	if player != null and is_instance_valid(player):
		player.set_meta(KNOWN_META, sanitize_known(genres))


## After an intro every player of the session knows its room type (players with a state only;
## the own account is marked by FlintGuide when the tour ends).
static func mark_known(players: Array[Player], genre: StringName) -> void:
	for player in players:
		if player == null or not is_instance_valid(player) or not player.has_meta(KNOWN_META):
			continue
		var known := PackedStringArray(player.get_meta(KNOWN_META))
		if not known.has(String(genre)):
			known.append(String(genre))
			player.set_meta(KNOWN_META, known)


## The room types this account knows (for the lobby profile).
static func account_known() -> PackedStringArray:
	var known := PackedStringArray()
	for genre: StringName in TOURS:
		if AccountSeen.has_seen(seen_id(genre)):
			known.append(String(genre))
	return known


## Only room types with a tour, each once (a profile from the network is checked here).
static func sanitize_known(raw: Variant) -> PackedStringArray:
	var clean := PackedStringArray()
	if not (raw is Array or raw is PackedStringArray):
		return clean
	for item: Variant in raw:
		if typeof(item) != TYPE_STRING and typeof(item) != TYPE_STRING_NAME:
			continue
		var genre := String(item)
		if TOURS.has(StringName(genre)) and not clean.has(genre):
			clean.append(genre)
	return clean


## "Mia", "Mia und Tom", "Mia, Tom und Ben" (name tags; "P2" without one).
static func names_text(players: Array[Player]) -> String:
	var names := PackedStringArray()
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		var tag := player.get_node_or_null(^"NameTag") as Label
		names.append(tag.text if tag != null and not tag.text.is_empty() else "P%d" % (player.player_id + 1))
	if names.size() <= 1:
		return "".join(names)
	var head := ", ".join(names.slice(0, names.size() - 1))
	return "%s %s %s" % [head, Loc.t(&"FLINT_ROOM_AND"), names[names.size() - 1]]


## "Flint erklärt Mia die Jagd …"
static func explaining_text(names: String, genre: StringName) -> String:
	return Loc.t(&"FLINT_ROOM_EXPLAINING", [names, Loc.t(name_key(genre))])


# --- Rooms without a RoomIntro ---

## Flint explains genre to player in room (special rooms, trials, rest, the elite nest ...): camera
## goals from the room's content. False when it will not show (seen, no tour, remote player, a
## RoomIntro of the room explains it itself).
static func explain_room(player: Player, genre: StringName, room: Node2D = null) -> bool:
	if not is_enabled() or not has_tour(genre) or player == null or not is_instance_valid(player) or not player.is_local:
		return false
	if knows(player, genre):
		return false
	if room != null and RoomIntro.get_intro(room) != null:
		return false
	var tour_steps := steps(genre, room_points(room, genre))
	if genre == &"campfire" and room != null and room.get(&"has_portal") == false:
		tour_steps.resize(CAMPFIRE_PORTAL_STEP)
	return FlintGuide.explain(player, tour(genre, tour_steps, GameMode.of(player).is_multiplayer()))


## Camera goals of a room without a mode, by sentence: the content (merchant, altar, fountain,
## weapons, campfire) or the trial's chest first; the rest Flint only says.
static func room_points(room: Node2D, genre: StringName) -> Array:
	if room == null or not is_instance_valid(room) or not room.is_inside_tree():
		return []
	for child in room.get_children():
		if child is TrialContent:
			var chest := (child as TrialContent).chest
			return [chest.global_position] if chest != null and is_instance_valid(chest) and chest.is_inside_tree() else []
	if genre == &"campfire" and room.has_method(&"get_campfire_content"):
		var fire := room.call(&"get_campfire_content") as Node2D
		return [fire.global_position] if fire != null and fire.is_inside_tree() else []
	for child in room.get_children():
		if child is SpecialContent:
			return [(child as Node2D).global_position]
	return []


## Global spot of the room's enemy source nearest to near (any source when near is INF), INF
## without sources: "from here they come".
static func source_point(room: Node, near := Vector2.INF) -> Vector2:
	var sources := SpawnSources.of(room) if room != null and is_instance_valid(room) else null
	if sources == null:
		return Vector2.INF
	var best := Vector2.INF
	var best_distance := INF
	for source in sources.get_sources():
		if not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var distance := source.global_position.distance_to(near) if near.is_finite() else 0.0
		if distance < best_distance:
			best_distance = distance
			best = source.global_position
	return best


## The room the local dungeon plays right now (the active slot), null outside a dungeon.
static func active_room_of(player: Node) -> Node2D:
	var world := player.get_parent() if player != null and is_instance_valid(player) else null
	if world == null or not world.has_method(&"get_active_slot") or not world.has_method(&"get_room_at_slot"):
		return null
	return world.call(&"get_room_at_slot", world.call(&"get_active_slot")) as Node2D


## The local players of a tree (co-op: this machine's own, D-088).
static func local_players(tree: SceneTree) -> Array[Player]:
	var result: Array[Player] = []
	if tree == null:
		return result
	for node in tree.get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local:
			result.append(player)
	return result


## True while Flint explains (or will explain) genre to one of these players.
static func is_explaining(players: Array[Player], genre: StringName) -> bool:
	for player in players:
		var guide := FlintGuide.of(player)
		if guide != null and guide.is_known(seen_id(genre)):
			return true
	return false
