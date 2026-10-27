class_name FlintExplanations
extends RefCounted
## The explanations that ship as data (companions/guide/explanations/<name>.tres) and the entry
## points the rest of the game calls (hooks for the integrator, KONZEPT §7.2):
## - entrance_danger(player): at the dungeon entrance (village_ui.show_entrance_info, KE1) Flint says
##   one sentence the first time (D-220: a newcomer does not understand "Gefahrenstufe 0 · Beute +0 %"
##   yet) and explains danger and rank once his danger level rose above 0 (entrance_danger_full).
## - the "first time" hints without camera: rank_up, talent_point, soul_gate, spell, and
##   on_village_arrival(player), which checks rank and free talent points itself.
## - the key hints of the first run (FlintControls; the controls card is gone) and their hooks for
##   single moments: chasm(player) for small holes, side_view(player) for the first side view
##   segment, secret_wall(player) for the first cracked wall struck.
## Every function returns whether Flint will say it (false: seen already, remote player, no player).
## New explanations: drop a .tres here (FlintExplanation with FlintGuideStep sub-resources, id
## "flint_<name>") and call explain(player, &"<name>"), or build one in code (FlintExplanation.tour).

const DIR := "res://companions/guide/explanations/"

const ENTRANCE_DANGER: StringName = &"entrance_danger"
const ENTRANCE_DANGER_FULL: StringName = &"entrance_danger_full"
const FIRST_RANK_UP: StringName = &"first_rank_up"
const FIRST_TALENT_POINT: StringName = &"first_talent_point"
const FIRST_SOUL_GATE: StringName = &"first_soul_gate"
const FIRST_SPELL: StringName = &"first_spell"
const FIRST_TIMES: Array[StringName] = [FIRST_RANK_UP, FIRST_TALENT_POINT, FIRST_SOUL_GATE, FIRST_SPELL]
## The entrance node the demo's camera shows (relative to the village, like VillageUI.ENTRANCE_NODE).
const ENTRANCE_NODE := ^"Buildings/DungeonEntrance"


## The explanation <name>.tres of DIR, or null (with a warning) when it is missing.
static func named(explanation_name: StringName) -> FlintExplanation:
	var path := DIR + String(explanation_name) + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("FlintExplanations: %s is missing; add it or check the name." % path)
		return null
	return load(path) as FlintExplanation


## Every explanation file of DIR (tests check them all).
static func all_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for file_name in ResourceLoader.list_directory(DIR):
		if file_name.get_extension() == "tres":
			names.append(StringName(file_name.get_basename()))
	names.sort()
	return names


## Flint explains the named explanation to player.
static func explain(player: Player, explanation_name: StringName, force := false) -> bool:
	return FlintGuide.explain(player, named(explanation_name), force)


## Demo (WK8, D-220): every time the rank card at the dungeon entrance shows. The first time Flint
## flies the camera to the entrance and says one sentence (the dark, his light); danger and rank he
## explains once they mean something: the first card with a danger level above 0 (the rank rose).
## entrance: the entrance node when the caller has it (else ENTRANCE_NODE under the player's world).
static func entrance_danger(player: Player, entrance: Node2D = null) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_local:
		return false
	var guide := FlintGuide.for_player(player)
	var intro_seen := guide != null and bool(guide.has_seen.call(StringName(FlintExplanation.ID_PREFIX + String(ENTRANCE_DANGER))))
	var which := entrance_choice(intro_seen, AccountProgress.current().get_danger_level())
	if which == &"":
		return false
	var explanation := named(which)
	if explanation == null:
		return false
	if entrance != null and explanation.steps[0].wants_camera():
		# A copy, so the shared resource never holds a node of one world.
		explanation = explanation.copy()
		explanation.steps[0].focus_node = entrance
	return FlintGuide.explain(player, explanation)


## Pure (D-220): which entrance explanation is due - the one-sentence intro first, the full one on
## danger and rank once the danger level rose above 0, else none (&"").
static func entrance_choice(intro_seen: bool, danger_level: int) -> StringName:
	if not intro_seen:
		return ENTRANCE_DANGER
	return ENTRANCE_DANGER_FULL if danger_level > 0 else &""


## The "first time" hints due when player arrives in the village: a rank above the start (danger
## level > 0, ranks can fall again, so "first" is the seen flag) and a free talent point. Returns
## how many were queued. Hook: the village calls it once its local player spawned.
static func on_village_arrival(player: Player) -> int:
	if player == null or not is_instance_valid(player) or not player.is_local:
		return 0
	var progress := AccountProgress.current()
	var queued := 0
	for first in village_firsts(progress.get_danger_level(), progress.get_free_points()):
		if explain(player, first):
			queued += 1
	return queued


## Pure: which village hints apply for this danger level and these free talent points.
static func village_firsts(danger_level: int, free_points: int) -> Array[StringName]:
	var due: Array[StringName] = []
	if danger_level > 0:
		due.append(FIRST_RANK_UP)
	if free_points > 0:
		due.append(FIRST_TALENT_POINT)
	return due


static func rank_up(player: Player) -> bool:
	return explain(player, FIRST_RANK_UP)


static func talent_point(player: Player) -> bool:
	return explain(player, FIRST_TALENT_POINT)


## The first soul gate (FS5): about the place, so before general hints; dropped unseen once the gate
## was used (its decision answered) before Flint got to it - then it comes at the next gate. gate: the
## soul gate (else the first one in the player's active room).
static func soul_gate(player: Player, gate: Node = null) -> bool:
	var explanation := named(FIRST_SOUL_GATE)
	if explanation == null:
		return false
	explanation = explanation.copy()
	explanation.priority = FlintExplanation.Priority.PLACE
	explanation.still_due = gate_still_unused(gate if gate != null else _soul_gate_near(player))
	return FlintGuide.explain(player, explanation)


## () -> bool: true until gate is used (E, its decision opened) or gone. Always true without a gate.
static func gate_still_unused(gate: Node) -> Callable:
	if gate == null or not is_instance_valid(gate):
		return Callable()
	var state := {"used": false}
	for child in gate.get_children():
		var usable := child as Interactable
		if usable != null:
			usable.interacted.connect(func(_by: Player) -> void: state["used"] = true, CONNECT_ONE_SHOT)
	return func() -> bool:
		if not is_instance_valid(gate) or bool(state["used"]):
			return false
		return not (gate.has_method(&"is_deciding") and bool(gate.call(&"is_deciding")))


static func _soul_gate_near(player: Player) -> Node:
	var room := RoomFlint.active_room_of(player)
	if room == null:
		return null
	for child in room.get_children():
		if child is SoulGate:
			return child
	return null


static func spell(player: Player) -> bool:
	return explain(player, FIRST_SPELL)


## Small holes outside a chasm room (replaces the card HINT_CHASM; hook in DungeonManager).
static func chasm(player: Player) -> bool:
	return FlintControls.explain_first(player, FlintControls.CHASM)


## The first side view segment: jump, double jump and dash (replaces the keys in the descent
## banner's subtitle, SideTransit.jump_hint_text; hook in SideTransit).
static func side_view(player: Player) -> bool:
	return FlintControls.explain_first(player, FlintControls.SIDE_VIEW)


## The first cracked wall struck without an explosion (replaces the card SECRET_HINT; hook in
## DungeonManager).
static func secret_wall(player: Player) -> bool:
	return FlintControls.explain_first(player, FlintControls.SECRET_WALL)
