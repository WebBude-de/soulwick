class_name PlayerSpells
extends Node
## The spells of one player (KE7, KONZEPT §6.2; D-088: state per player, child "Spells" of the
## Player): which spells sit in the slots (from the talents, TalentEffects.stats_of), their
## cooldowns, and casting from the player's input object (MP1: PlayerInput, never Input).
## - Decision: where the game is decided (offline or on the host, is_authority()) a press of
##   ACTION casts the spell of slot 1 (ACTION_2 slot 2), if can_cast() and the spell is ready.
##   SpellEffects does the effect at the player; spell_cast carries the decision (the host sends it
##   to the clients, integrator hook in online/).
## - Clients never cast: their press travels as an input bit to the host's copy of the player; the
##   host's spell_cast comes back as an event and play_remote_cast() starts the cooldown and shows it.
## - Looks: spell_shown drives SpellLook on every machine (Flint flares, the effect leaves his flame).
## Usage: PlayerSpells.attach_to(player) once per spawned player (idempotent), PlayerSpells.of(node).

## A spell was cast here (authority only): id, slot (0-based), aim (normalised), cooldown in s.
signal spell_cast(spell_id: StringName, slot: int, aim: Vector2, cooldown: float)
## A cast is shown on this machine (own decision or the host's event): drives the looks.
signal spell_shown(spell_id: StringName, aim: Vector2, from_event: bool)

const NODE_NAME := &"Spells"
## Input actions (InputMap names, PlayerInput action ids): slot 1 and slot 2.
const ACTION: StringName = &"cast_spell"
const ACTION_2: StringName = &"cast_spell_2"
const SLOT_ACTIONS: Array[StringName] = [ACTION, ACTION_2]
## Slots at most (one, two with the soul capstone, KONZEPT §6.1).
const MAX_SLOTS := 2

var _player: Player = null
## Seconds left and the full cooldown per spell id (a spell moved to the other slot keeps its time).
var _cooldown_left: Dictionary[StringName, float] = {}
var _cooldown_total: Dictionary[StringName, float] = {}
## Loadout set from outside (client display from the own profile, tools, tests); null = talents.
var _loadout_override: Variant = null


## The spells of player, created on first use (idempotent). Call once per spawned player.
static func attach_to(target: Player) -> PlayerSpells:
	if target == null or not is_instance_valid(target):
		return null
	var existing := of(target)
	if existing != null:
		return existing
	var spells := PlayerSpells.new()
	spells.name = NODE_NAME
	target.add_child(spells)
	return spells


## The spells of a player (or of the player above node), null without.
static func of(node: Node) -> PlayerSpells:
	var player := _find_player(node)
	if player == null:
		return null
	var spells := player.get_node_or_null(NodePath(NODE_NAME)) as PlayerSpells
	if spells == null or spells.is_queued_for_deletion():
		return null
	return spells


static func _find_player(node: Node) -> Player:
	var current := node
	while current != null and is_instance_valid(current):
		if current is Player:
			return current as Player
		current = current.get_parent()
	return null


## Which slot a press of button (0 = ACTION, 1 = ACTION_2) casts. While the second button is not
## wired (ACTION_2 missing from PlayerInput.ACTIONS) the one button casts the first ready spell, so
## a second slot is never out of reach. -1 = nothing to cast.
static func slot_for_button(button: int, ready: Array[bool], second_button: bool) -> int:
	if button < 0 or button >= ready.size():
		return -1
	if button == 0 and not second_button:
		return ready.find(true)
	return button if ready[button] else -1


## The second cast button travels like every other action (bit in PlayerInput.ACTIONS).
static func has_second_button() -> bool:
	return PlayerInput.ACTIONS.has(ACTION_2)


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("PlayerSpells must be a child of a Player (PlayerSpells.attach_to).")
		return
	spell_shown.connect(_play_look)


func _physics_process(delta: float) -> void:
	tick(delta)
	if _player != null and is_authority():
		read_input(_player.input)


## Counts the cooldowns down.
func tick(delta: float) -> void:
	for id in _cooldown_left.keys():
		_cooldown_left[id] = maxf(0.0, _cooldown_left[id] - delta)


## Casts from this frame's presses of input (after the player polled it).
func read_input(input: PlayerInput) -> void:
	if input == null:
		return
	for button in SLOT_ACTIONS.size():
		if input.is_just_pressed(SLOT_ACTIONS[button]):
			press(button)


## A press of a cast button (0 or 1): casts the slot slot_for_button() picks. True if cast.
func press(button: int) -> bool:
	var slot := slot_for_button(button, get_ready_slots(), has_second_button())
	return slot >= 0 and try_cast_slot(slot)


## This machine decides the game: offline, single player, tests, or the host of a session.
func is_authority() -> bool:
	return not is_inside_tree() or multiplayer.is_server()


# --- Loadout ---

## Spells in the slots, slot by slot (empty without spell talents).
func get_loadout() -> Array[StringName]:
	if _loadout_override != null:
		return (_loadout_override as Array[StringName]).duplicate()
	return SpellEffects.loadout_of(TalentEffects.stats_of(_owner()))


## Puts spells into the slots instead of the talents' choice (unknown ids are dropped). Hook for a
## client: its own profile's spells for the HUD (the host runs the talents, the client does not);
## tools and tests use it to cast without a talent tree.
func set_loadout(spells: Array[StringName]) -> void:
	var loadout: Array[StringName] = []
	for spell in spells:
		if loadout.size() < MAX_SLOTS and SpellBook.has_spell(spell) and not loadout.has(spell):
			loadout.append(spell)
	_loadout_override = loadout


## Back to the talents' choice.
func clear_loadout() -> void:
	_loadout_override = null


func get_spell(slot: int) -> StringName:
	var loadout := get_loadout()
	return loadout[slot] if slot >= 0 and slot < loadout.size() else &""


func has_spells() -> bool:
	return not get_loadout().is_empty()


# --- Cooldowns ---

func get_cooldown_left(slot: int) -> float:
	return float(_cooldown_left.get(get_spell(slot), 0.0))


## Share of the slot's cooldown still to wait (1 = just cast, 0 = ready).
func get_cooldown_share(slot: int) -> float:
	var id := get_spell(slot)
	var total := float(_cooldown_total.get(id, 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(_cooldown_left.get(id, 0.0)) / total, 0.0, 1.0)


func is_ready(slot: int) -> bool:
	return get_spell(slot) != &"" and get_cooldown_left(slot) <= 0.0


## Ready flag per slot of the loadout.
func get_ready_slots() -> Array[bool]:
	var result: Array[bool] = []
	for slot in get_loadout().size():
		result.append(is_ready(slot))
	return result


func reset_cooldowns() -> void:
	_cooldown_left.clear()
	_cooldown_total.clear()


# --- Casting ---

## The player may cast now: alive, not stunned, not locked (intro, menu, falling), not carrying
## the lantern (no attacks then either).
func can_cast() -> bool:
	if _player == null or not is_instance_valid(_player) or not _player.is_node_ready():
		return false
	if not _player.is_alive() or _player.is_stunned() or _player.is_input_locked() or _player.is_falling():
		return false
	return LanternCarry.can_attack(_player)


## Casts the spell of slot if it is ready and the player can cast. True if cast.
func try_cast_slot(slot: int) -> bool:
	if not is_ready(slot) or not can_cast():
		return false
	cast(get_spell(slot), slot)
	return true


## The cast itself (no checks): cooldown, effect at the player, decision signal, looks.
func cast(spell_id: StringName, slot: int) -> void:
	var data := SpellBook.get_spell(spell_id)
	if data == null or _player == null:
		return
	var aim := _player.get_aim_direction()
	var cooldown := SpellEffects.cooldown(_player, data)
	_start_cooldown(spell_id, cooldown)
	SpellEffects.apply(_player, data, aim)
	spell_cast.emit(spell_id, slot, aim, cooldown)
	spell_shown.emit(spell_id, aim, false)


## Client: the host cast spell_id for this player (cast event, integrator hook in online/). Starts
## the cooldown the host computed and shows the cast; a spell the HUD does not know yet joins the
## shown loadout. Changes nothing in the game (the host's result comes with the vitals and enemy hits).
func play_remote_cast(spell_id: StringName, slot: int, aim: Vector2, cooldown: float) -> void:
	if not SpellBook.has_spell(spell_id):
		return
	var loadout := get_loadout()
	if not loadout.has(spell_id) and loadout.size() < MAX_SLOTS:
		if slot >= loadout.size():
			loadout.append(spell_id)
		else:
			loadout.insert(slot, spell_id)
		set_loadout(loadout)
	_start_cooldown(spell_id, cooldown)
	spell_shown.emit(spell_id, aim, true)


func _start_cooldown(spell_id: StringName, seconds: float) -> void:
	_cooldown_left[spell_id] = maxf(0.0, seconds)
	_cooldown_total[spell_id] = maxf(0.0, seconds)


func _play_look(spell_id: StringName, aim: Vector2, from_event: bool) -> void:
	SpellLook.play(_player, SpellBook.get_spell(spell_id), aim, from_event)


func _owner() -> Node:
	return _player if _player != null else get_parent()
