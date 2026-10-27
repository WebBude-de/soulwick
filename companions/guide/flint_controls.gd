class_name FlintControls
extends Node
## The first-run key hints without cards (team member 22.10.2026: "Ganz durch Flint ersetzen"; replaces
## the controls card of UX1 and the overview tip in the first upgrade dialog): Flint says in his
## corner what is new, one short "first time" hint at a time (FlintExplanation.HINT: nothing stops,
## nothing locks, it closes by itself), the keys as the pictures of the device in use (GlyphText in
## the bubble, FlintGuideView). Each hint once per account (AccountSeen through FlintGuide).
## When the dungeon brings them (TESTWERTE below):
## - the run starts: walk and aim, attack and dash (BASICS)
## - room SPECIAL_ROOM begins: the special attack (SPECIAL)
## - a room from SPECIAL_ROOM on with two weapons in hand: switching weapons (SWITCH)
## - the first time the player can use something (his use prompt shows): the use key (INTERACT)
## - the first upgrade taken: the overview key (OVERVIEW)
## - the first soul crystal of a run: what crystals are for (FIRST_CRYSTAL, D-220)
## Hooks for other places (explain_first): small holes outside a chasm room (CHASM), the first side
## view segment (SIDE_VIEW), the first cracked wall struck (SECRET_WALL). All keys stay to look up in
## the pause menu (Optionen, Tasten).
## Worlds that saw the old card ("hint_controls", "hint_overview_key") skip the hints it covered.
## From room LAST_ROOM on the save's "hint_controls" is marked like the card did, so the HUD's key
## line shrinks (Hud). Lives under DungeonUI, pauses with the game; local players only, each machine
## for its own (D-088). Not while the touch controls are in use (like the card: they show their own
## buttons); then nothing is marked and the hints come on a later run.
## Shared run (feedback #2b1a5a87 23.10.2026: "Wenn dann sollen alle Spieler die Erklärung bekommen"):
## when a group router is in the tree (GROUP_ROUTER, NetGuide of the shared run), every hint goes to it
## instead of straight to Flint; the host then shows it to all players at once and holds them all
## until the learner is through (online/net_guide.gd).
## Queue (FS5): holes and the side view are URGENT, the use key and the cracked wall about the PLACE,
## the rest GENERAL (FlintExplanation.priority). A key hint that waits is dropped once the player
## did it himself (special used, weapon switched, something used with the use key); dropped, it is
## asked again from the next room on. The basics are marked seen when the practice run was completed
## (TutorialRun: everything there was shown already).

const NODE_NAME := &"FlintControls"
const BASICS: StringName = &"flint_controls_basics"
const SPECIAL: StringName = &"flint_controls_special"
const SWITCH: StringName = &"flint_controls_switch"
const INTERACT: StringName = &"flint_controls_interact"
const OVERVIEW: StringName = &"flint_controls_overview"
const CHASM: StringName = &"flint_chasm"
const SIDE_VIEW: StringName = &"flint_side_view"
const SECRET_WALL: StringName = &"flint_secret_wall"
const FIRST_CRYSTAL: StringName = &"flint_first_crystal"
## The hints this coach brings itself, in the order they usually come.
const RUN_HINTS: Array[StringName] = [BASICS, SPECIAL, SWITCH, INTERACT, OVERVIEW, FIRST_CRYSTAL]
## The hints the old controls card covered (worlds that saw it skip them).
const CARD_HINTS: Array[StringName] = [BASICS, SPECIAL, SWITCH, INTERACT]
## Key hints dropped while they wait once the player did the action himself (FS5).
const DONE_BY_ACTION: Array[StringName] = [SPECIAL, SWITCH, INTERACT]
## TESTWERTE: seconds after the run start before the basics; the room whose start brings the special
## (and the weapon switch with two weapons); the room from which the HUD's key line is short.
const START_DELAY := 1.5
const SPECIAL_ROOM := 2
const LAST_ROOM := 4
## The player's use prompt ("E Öffnen"), shown while something usable is near (Player).
const PROMPT_NODE := ^"PromptLabel"
## The player's area that finds usable things (Player; the use key is seen through their signal).
const INTERACTION_AREA_NODE := ^"InteractionArea"
## Group of the node that shares hints in a shared run (NetGuide): request_hint(player, id) -> bool,
## true when it took the hint over.
const GROUP_ROUTER: StringName = &"flint_group_hints"

## Seen lookup for the old card's flags (tests swap it).
var has_seen := func(id: StringName) -> bool: return AccountSeen.has_seen(id)
## Shows an explanation to a player (tests swap it): (player, explanation) -> bool.
var explain := func(player: Player, explanation: FlintExplanation) -> bool: return FlintGuide.explain(player, explanation)
## Marks the save's "hint_controls" (tests swap it).
var mark_card_seen := func() -> void: SaveManager.mark_seen(ControlsHint.SEEN_ID)
## The players this coach talks to (tests); empty: every local player in the tree.
var players_override: Array[Player] = []
## While false the coach waits (DungeonUI.show_controls_hint; the practice run holds it).
var enabled := true

var _time := 0.0
var _room := 0
var _upgrade_taken := false
var _card_marked := false
## "<player id>:<hint id>" -> true for every hint asked for already.
var _asked: Dictionary[String, bool] = {}
## Worlds that saw the old card (snapshot at the start: marking it for the HUD must not hide hints).
var _old_card_seen := false
var _old_overview_seen := false
## A soul crystal came in this run (RunManager.run_crystals_changed above 0).
var _crystal_found := false
## "<player id>:<hint id>" -> true: the player did the hint's action since it was asked (FS5).
var _done: Dictionary[String, bool] = {}
## "<player id>:<hint id>" -> room: a dropped hint is asked again only after this room.
var _retry_after: Dictionary[String, int] = {}
## Players whose weapon and guide signals this coach listens to (instance ids).
var _watched: Dictionary[int, bool] = {}
var _watched_guides: Dictionary[int, bool] = {}


## The explanation of a hint id (keys named with the current binding; GlyphText turns them into
## pictures of the device in use), or null for an unknown id.
static func explanation_for(id: StringName) -> FlintExplanation:
	var steps: Array[FlintGuideStep] = []
	var priority := FlintExplanation.Priority.GENERAL
	match id:
		BASICS:
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_MOVE", FlintGuideStep.Mood.TALK,
					[ControlsInfo.key_text(ControlsInfo.MOVE), ControlsInfo.key_text(ControlsInfo.AIM)]))
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_ATTACK", FlintGuideStep.Mood.POINT,
					[ControlsInfo.key_text(ControlsInfo.ATTACK), ControlsInfo.key_text(ControlsInfo.DASH)]))
		SPECIAL:
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_SPECIAL", FlintGuideStep.Mood.POINT,
					[ControlsInfo.key_text(ControlsInfo.SPECIAL)]))
		SWITCH:
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_SWITCH", FlintGuideStep.Mood.HAPPY,
					[ControlsInfo.key_text(ControlsInfo.SWITCH)]))
		INTERACT:
			priority = FlintExplanation.Priority.PLACE
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_INTERACT", FlintGuideStep.Mood.POINT,
					[ControlsInfo.key_text(ControlsInfo.INTERACT)]))
		OVERVIEW:
			steps.append(FlintGuideStep.say(&"FLINT_CONTROLS_OVERVIEW", FlintGuideStep.Mood.HAPPY,
					[ControlsInfo.key_text(ControlsInfo.OVERVIEW)]))
		CHASM:
			priority = FlintExplanation.Priority.URGENT
			steps.append(FlintGuideStep.say(&"FLINT_CHASM", FlintGuideStep.Mood.WORRIED,
					[ControlsInfo.key_text(ControlsInfo.DASH)]))
			steps.append(FlintGuideStep.say(&"FLINT_CHASM_2", FlintGuideStep.Mood.HAPPY))
		SIDE_VIEW:
			priority = FlintExplanation.Priority.URGENT
			PlayerSideMotion.ensure_actions()
			steps.append(FlintGuideStep.say(&"FLINT_SIDE_VIEW", FlintGuideStep.Mood.POINT,
					[_key_or(PlayerSideMotion.JUMP_ACTION, "Space")]))
		SECRET_WALL:
			priority = FlintExplanation.Priority.PLACE
			steps.append(FlintGuideStep.say(&"FLINT_SECRET_WALL", FlintGuideStep.Mood.WORRIED))
		FIRST_CRYSTAL:
			steps.append(FlintGuideStep.say(&"FLINT_FIRST_CRYSTAL", FlintGuideStep.Mood.HAPPY))
		_:
			return null
	var explanation := FlintExplanation.hint(id, steps)
	explanation.priority = priority
	return explanation


## Hook for single "first time" moments outside this coach (DungeonUI.show_flint_hint, the side view
## transit): Flint says the hint id to player once per account. False when he will not (seen, not a
## local player, unknown id).
static func explain_first(player: Player, id: StringName) -> bool:
	var explanation := explanation_for(id)
	if explanation == null:
		return false
	if route_to_group(player, id):
		return true
	return FlintGuide.explain(player, explanation)


## Shared run: hands the hint id of player to the group router (NetGuide). True if it took it over.
## still_due: () -> bool, false once the hint no longer fits this player (the router drops it).
static func route_to_group(player: Player, id: StringName, still_due := Callable()) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var router := player.get_tree().get_first_node_in_group(GROUP_ROUTER)
	if router == null or not router.has_method(&"request_hint"):
		return false
	if still_due.is_valid():
		return bool(router.call(&"request_hint", player, id, still_due))
	return bool(router.call(&"request_hint", player, id))


static func _key_or(action: StringName, fallback: String) -> String:
	var key := ControlsInfo.action_key(action)
	return key if not key.is_empty() else fallback


func _init() -> void:
	name = NODE_NAME
	# Pauses with the game: no hint runs out behind a dialog.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	_old_card_seen = bool(has_seen.call(ControlsHint.SEEN_ID)) and not bool(has_seen.call(BASICS))
	_old_overview_seen = bool(has_seen.call(ControlsHint.OVERVIEW_TIP_ID)) and not bool(has_seen.call(OVERVIEW))
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.upgrade_acquired.connect(_on_upgrade_acquired.unbind(2))
	RunManager.run_crystals_changed.connect(_on_run_crystals_changed)


func _process(delta: float) -> void:
	tick(delta)


## One step of the coach (every frame; tests call it directly).
func tick(delta: float) -> void:
	if not enabled or TouchState.shared().is_active():
		return
	_time += delta
	for player in _players():
		_watch(player)
		_check(player)
	if _room >= LAST_ROOM and not _card_marked:
		_card_marked = true
		mark_card_seen.call()


## True once the coach asked Flint for id with this player (whether he said it or knew it).
func was_asked(player: Player, id: StringName) -> bool:
	return _asked.has(_key(player, id))


func get_room() -> int:
	return _room


func _check(player: Player) -> void:
	if _time >= START_DELAY:
		_ask(player, BASICS)
	if _room >= SPECIAL_ROOM:
		_ask(player, SPECIAL)
		if _has_second_weapon(player):
			_ask(player, SWITCH)
	if _prompt_shown(player):
		_ask(player, INTERACT)
	if _upgrade_taken:
		_ask(player, OVERVIEW)
	if _crystal_found:
		_ask(player, FIRST_CRYSTAL)


func _ask(player: Player, id: StringName) -> void:
	var key := _key(player, id)
	if _asked.has(key) or _room <= int(_retry_after.get(key, -1)):
		return
	_asked[key] = true
	_done.erase(key)
	if _covered_by_old_card(id):
		return
	var still_due := Callable()
	if DONE_BY_ACTION.has(id):
		still_due = func() -> bool: return not _done.has(key)
	if route_to_group(player, id, still_due):
		return
	var explanation := explanation_for(id)
	explanation.still_due = still_due
	explain.call(player, explanation)


## True once player did the action of the hint id since it was asked (FS5: then it is dropped).
func did_action(player: Player, id: StringName) -> bool:
	return _done.has(_key(player, id))


## Notes that player did the action of the hint id (weapon signals, a thing used; tests call it).
func note_action(player: Player, id: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	var key := _key(player, id)
	if _asked.has(key):
		_done[key] = true


func _covered_by_old_card(id: StringName) -> bool:
	if id == OVERVIEW:
		return _old_overview_seen
	return _old_card_seen and CARD_HINTS.has(id)


## Listens once to what player does (special, weapon switch) and to his guide's drops; while the use
## hint is asked, to the things he can use right now.
func _watch(player: Player) -> void:
	var player_id := player.get_instance_id()
	if not _watched.has(player_id):
		_watched[player_id] = true
		var weapons := player.weapon_controller
		if weapons != null:
			weapons.special_performed.connect(func(_weapon: WeaponData) -> void: note_action(player, SPECIAL))
			weapons.active_slot_changed.connect(func(_slot: int) -> void: note_action(player, SWITCH))
	var guide := FlintGuide.of(player)
	if guide != null and not _watched_guides.has(guide.get_instance_id()):
		_watched_guides[guide.get_instance_id()] = true
		guide.dropped.connect(_on_dropped.bind(player))
	if _asked.has(_key(player, INTERACT)) and not _done.has(_key(player, INTERACT)):
		_watch_usables(player)


func _watch_usables(player: Player) -> void:
	var area := player.get_node_or_null(INTERACTION_AREA_NODE) as Area2D
	if area == null or not area.monitoring:
		return
	for found in area.get_overlapping_areas():
		var usable := found as Interactable
		if usable != null and not usable.interacted.is_connected(_on_used):
			usable.interacted.connect(_on_used)


func _on_used(by: Player) -> void:
	note_action(by, INTERACT)


## A hint of this coach was dropped unseen: asked again from the next room on (FS5).
func _on_dropped(explanation: FlintExplanation, player: Player) -> void:
	if explanation == null or not is_instance_valid(player) or not RUN_HINTS.has(explanation.id):
		return
	var key := _key(player, explanation.id)
	_asked.erase(key)
	_done.erase(key)
	_retry_after[key] = _room


func _players() -> Array[Player]:
	if not players_override.is_empty():
		return players_override
	var found: Array[Player] = []
	if not is_inside_tree():
		return found
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local and player.is_alive():
			found.append(player)
	return found


static func _key(player: Player, id: StringName) -> String:
	return "%d:%s" % [player.get_instance_id(), id]


static func _has_second_weapon(player: Player) -> bool:
	return player.weapon_controller != null and player.weapon_controller.get_weapon(1) != null


static func _prompt_shown(player: Player) -> bool:
	var prompt := player.get_node_or_null(PROMPT_NODE) as CanvasItem
	return prompt != null and prompt.visible


func _on_room_entered(room_index: int) -> void:
	_room = maxi(_room, room_index)


func _on_upgrade_acquired() -> void:
	_upgrade_taken = true


func _on_run_crystals_changed(run_crystals: int) -> void:
	if run_crystals > 0:
		_crystal_found = true
