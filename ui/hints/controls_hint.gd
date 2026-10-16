class_name ControlsHint
extends PanelContainer
## First-run controls card (UX1): small panel on the left edge, never pausing the game. Two steps
## of four keys each (move, aim, attack, dash, then special, weapon, use, overview). A row turns
## green as soon as the player uses that key.
## Launch review P1-4 (16.10.2026: room 1 is cleared in ~15 s, the second step was never seen):
## step 1 moves on when its four keys were used, after STAGE_TIME seconds or when the player
## enters room 2. Step 2 has no timer: it stays through the next rooms until its four keys were
## used, at the latest until room LAST_ROOM begins. Its special row says "ready" while the special
## of the active weapon can be used, its overview row points at the first upgrade the player took.
## Shown once per save slot (SaveManager "hint_controls", marked when the card finishes).
## Reads input in _input without consuming it; while DungeonUI holds the card behind another
## teaching card (process mode disabled) a small tracker child still ticks the rows off. Key caps
## follow the device in use (keyboard and mouse or gamepad, InputDevice). While the card is open
## the HUD hides its key line (Hud polls GROUP), so room 1 no longer shows every key twice.
## The upgrade dialog names the overview key once per save (take_overview_key_hint, hook).

signal finished

## Device in use at this machine and the gamepad's aim actions (preloaded, so they resolve before
## the class list knows them).
const InputDeviceScript := preload("res://player/input/input_device.gd")
const GamepadInputScript := preload("res://player/input/gamepad_input.gd")
const SEEN_ID: StringName = &"hint_controls"
## Seen flag of the overview key in the first upgrade dialog (take_overview_key_hint).
const OVERVIEW_TIP_ID: StringName = &"hint_overview_key"
## The open card is in this group; the HUD hides its key line meanwhile.
const GROUP: StringName = &"controls_hint"
const STAGES: Array[Array] = [
	[ControlsInfo.MOVE, ControlsInfo.AIM, ControlsInfo.ATTACK, ControlsInfo.DASH],
	[ControlsInfo.SPECIAL, ControlsInfo.SWITCH, ControlsInfo.INTERACT, ControlsInfo.OVERVIEW],
]
## Short captions for the card as translation keys (the options page has the long ones; R8: no
## German literals any more).
const CAPTIONS := {
	ControlsInfo.MOVE: &"CONTROLS_MOVE",
	ControlsInfo.AIM: &"CONTROLS_AIM",
	ControlsInfo.ATTACK: &"CONTROLS_ATTACK",
	ControlsInfo.DASH: &"HINT_CONTROLS_DASH",
	ControlsInfo.SPECIAL: &"CONTROLS_SPECIAL",
	ControlsInfo.SWITCH: &"CONTROLS_SWITCH",
	ControlsInfo.INTERACT: &"CONTROLS_INTERACT",
	ControlsInfo.OVERVIEW: &"CONTROLS_OVERVIEW",
}
## Tags behind a row (translation keys): the special is ready, an upgrade was taken.
const TAG_READY: StringName = &"HINT_CONTROLS_READY"
const TAG_UPGRADE: StringName = &"HINT_CONTROLS_NEW_UPGRADE"
## Caption of the overview key in the first upgrade dialog.
const OVERVIEW_TIP_CAPTION: StringName = &"HINT_CONTROLS_OVERVIEW_ANYTIME"
## English and German texts of the new keys until localization has them (Hud.hud_text).
const FALLBACKS := {
	TAG_READY: ["ready", "bereit"],
	TAG_UPGRADE: ["new upgrade", "neues Upgrade"],
	OVERVIEW_TIP_CAPTION: ["view upgrades anytime", "Upgrades jederzeit ansehen"],
}
## TESTWERTE: longest time of step 1 (unpaused game seconds; step 2 has none), pause after the
## last key of a step, the room whose start ends the card at the latest.
const STAGE_TIME := 16.0
const DONE_LINGER := 0.9
const LAST_ROOM := 4
## Mouse travel (px) that counts as "aimed".
const AIM_DISTANCE := 60.0
## Layout in mockup pixels.
const WIDTH := 112.0
const KEY_WIDTH := 38.0
const EDGE_MARGIN := 8.0
## Tag pulse: alpha range and half period (s).
const TAG_PULSE_ALPHA := 0.45
const TAG_PULSE_TIME := 0.5

var _stage := -1
var _rows: Dictionary = {}
var _done: Dictionary = {}
## Row id -> tag translation key shown behind the caption.
var _tags: Dictionary = {}
var _time_left := 0.0
var _aim_travel := 0.0
var _finishing := false
## Special readiness last shown on the special row (-1 unknown, 0 not ready, 1 ready).
var _special_shown := -1
var _upgrade_seen := false
var _list: VBoxContainer = null
var _eyebrow: Label = null
var _footer: Control = null
var _box: VBoxContainer = null


## Ticks rows off while DungeonUI holds the card (process mode disabled behind another teaching
## card); pausable itself, so keys pressed in a pausing menu never count.
class HeldInputTracker extends Node:
	var card: ControlsHint = null

	func _input(event: InputEvent) -> void:
		if card != null and is_instance_valid(card) and not card.can_process():
			card.track_input(event)


## True while the save has not seen the card yet. The card teaches keyboard, mouse and gamepad:
## not while the touch controls are in use (G3); it stays unseen and comes on the next such run.
static func should_show() -> bool:
	return not SaveManager.has_seen(SEEN_ID) and not TouchState.shared().is_active()


## Hook for DungeonUI.choose_upgrade (P1-4): the first upgrade dialog of a save names the overview
## key once ("[Tab] Upgrades jederzeit ansehen"). Returns [key name, caption] for
## Modal.set_key_hints, or [] when this save saw it already or the touch controls are in use.
## Marks the save, so call it only when the dialog is really built.
static func take_overview_key_hint() -> Array:
	if SaveManager.has_seen(OVERVIEW_TIP_ID) or TouchState.shared().is_active():
		return []
	SaveManager.mark_seen(OVERVIEW_TIP_ID)
	return [ControlsInfo.key_text(ControlsInfo.OVERVIEW), text(OVERVIEW_TIP_CAPTION)]


## Text of one of the card's own keys in the current language (fallback until the CSV has it).
static func text(key: StringName) -> String:
	var fallback: Array = FALLBACKS.get(key, [String(key), String(key)])
	return Hud.hud_text(key, fallback[0], fallback[1])


func _ready() -> void:
	theme = UiKit.get_theme()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 5, 6))
	custom_minimum_size.x = UiKit.px(WIDTH)
	_box = UiKit.vbox(int(UiKit.px(3)))
	add_child(_box)
	_eyebrow = UiKit.eyebrow("", UiKit.COLOR_GOLD)
	_box.add_child(_eyebrow)
	_list = UiKit.vbox(int(UiKit.px(3)))
	_box.add_child(_list)
	_build_footer()
	var tracker := HeldInputTracker.new()
	tracker.name = "HeldInputTracker"
	tracker.card = self
	tracker.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(tracker)
	minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.upgrade_acquired.connect(_on_upgrade_acquired.unbind(2))
	InputDeviceScript.shared().changed.connect(_on_input_device_changed)
	_show_stage(0)
	_layout.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	if _finishing:
		return
	# The HUD's status frame may grow (second heart row, crystals): stay right below it.
	_layout()
	_update_special_tag()
	_time_left -= delta
	if _time_left <= 0.0:
		_next_stage()


func _input(event: InputEvent) -> void:
	track_input(event)


## Ticks off the rows of the current step that event uses (also called by the held tracker).
func track_input(event: InputEvent) -> void:
	if _finishing or _stage < 0:
		return
	for id: StringName in STAGES[_stage]:
		if not _done.has(id) and _matches(id, event):
			mark_done(id)


func get_stage() -> int:
	return _stage


func is_done(id: StringName) -> bool:
	return _done.has(id)


func is_finishing() -> bool:
	return _finishing


## Tag translation key behind row id (&"" = none).
func get_tag(id: StringName) -> StringName:
	return _tags.get(id, &"")


## Row id as used: green caption, dimmed key. The step ends shortly after its last key.
func mark_done(id: StringName) -> void:
	if _done.has(id) or not _rows.has(id):
		return
	_done[id] = true
	_tags.erase(id)
	var row := _rows[id] as Control
	_style_done(row)
	var tween := row.create_tween()
	tween.tween_property(row, "modulate", Color(1.4, 1.4, 1.4, 1.0), 0.08)
	tween.tween_property(row, "modulate", Color(1, 1, 1, 0.55), 0.3)
	if _is_stage_done():
		_time_left = minf(_time_left, DONE_LINGER)


## Fades out, marks the hint as seen for this save (unless mark is false) and frees itself.
func finish(mark := true) -> void:
	if _finishing:
		return
	_finishing = true
	# The HUD brings its key line back right away (short form once the save has seen the card).
	remove_from_group(GROUP)
	if mark:
		SaveManager.mark_seen(SEEN_ID)
	finished.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _is_stage_done() -> bool:
	for other: StringName in STAGES[_stage]:
		if not _done.has(other):
			return false
	return true


func _next_stage() -> void:
	if _stage + 1 < STAGES.size():
		_show_stage(_stage + 1)
	else:
		finish()


func _show_stage(stage: int) -> void:
	_stage = stage
	# Step 1 is timed; step 2 waits for its keys (or room LAST_ROOM).
	_time_left = STAGE_TIME if stage == 0 else INF
	_special_shown = -1
	_build_rows(true)
	if _is_stage_done():
		_time_left = minf(_time_left, DONE_LINGER)


## Rows of the current step: key caps of the device in use, caption, tag. Rows already used keep
## their done look (rebuilt when the device changes); fade_in staggers new rows in.
func _build_rows(fade_in: bool) -> void:
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_eyebrow.text = Loc.t(&"HINT_CONTROLS_STEP", [_stage + 1, STAGES.size()]).to_upper()
	for id: StringName in STAGES[_stage]:
		var row := UiKit.hbox(int(UiKit.px(5)))
		row.name = String(id).capitalize()
		row.add_child(_key_cell(id))
		var caption := UiKit.text_label(Loc.t(CAPTIONS[id]) if CAPTIONS.has(id) else ControlsInfo.caption(id), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(caption)
		row.set_meta(&"caption", caption)
		var tag := UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_GOLD, true)
		tag.name = "Tag"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.visible = false
		row.add_child(tag)
		row.set_meta(&"tag", tag)
		_list.add_child(row)
		_rows[id] = row
		if _done.has(id):
			_style_done(row)
			row.modulate = Color(1, 1, 1, 0.55)
		else:
			_apply_tag(id)
			if fade_in:
				row.modulate.a = 0.0
				row.create_tween().tween_property(row, "modulate:a", 1.0, 0.25).set_delay(0.06 * _rows.size())


func _style_done(row: Control) -> void:
	var caption := row.get_meta(&"caption") as Label
	caption.add_theme_color_override("font_color", UiKit.COLOR_SUCCESS)
	if row.has_meta(&"tag"):
		(row.get_meta(&"tag") as Label).visible = false


## Shows or hides the tag of row id (key &"" = none); a new tag flashes its row and pulses.
func _set_tag(id: StringName, key: StringName) -> void:
	if key == &"":
		_tags.erase(id)
	else:
		_tags[id] = key
	_apply_tag(id)
	if key != &"" and _rows.has(id):
		var row := _rows[id] as Control
		var flash := row.create_tween()
		flash.tween_property(row, "modulate", Color(1.5, 1.4, 1.0, 1.0), 0.12)
		flash.tween_property(row, "modulate", Color.WHITE, 0.35)


func _apply_tag(id: StringName) -> void:
	if not _rows.has(id):
		return
	var tag := (_rows[id] as Control).get_meta(&"tag") as Label
	var key: StringName = _tags.get(id, &"")
	if tag.has_meta(&"pulse"):
		var running := tag.get_meta(&"pulse") as Tween
		if running != null and running.is_valid():
			running.kill()
		tag.remove_meta(&"pulse")
	tag.visible = key != &"" and not _done.has(id)
	tag.modulate.a = 1.0
	if not tag.visible:
		return
	tag.text = text(key)
	var pulse := tag.create_tween().set_loops()
	pulse.tween_property(tag, "modulate:a", TAG_PULSE_ALPHA, TAG_PULSE_TIME)
	pulse.tween_property(tag, "modulate:a", 1.0, TAG_PULSE_TIME)
	tag.set_meta(&"pulse", pulse)


## Step 2: the special row says "ready" while the active weapon's special can be used (first time
## right when the step shows) and drops the tag while it recharges.
func _update_special_tag() -> void:
	if _stage != 1 or _done.has(ControlsInfo.SPECIAL):
		return
	var ready := _special_state()
	if ready < 0 or ready == _special_shown:
		return
	_special_shown = ready
	_set_tag(ControlsInfo.SPECIAL, TAG_READY if ready == 1 else &"")


## 1 = the local player's active weapon has a special that is ready, 0 = not (recharging or no
## special), -1 = no player known (tests, HUD without player).
func _special_state() -> int:
	var player := Hud.local_player(get_tree())
	if player == null:
		return -1
	var controller := player.weapon_controller
	var weapon := controller.get_active_weapon()
	if weapon == null or weapon.special_name.is_empty():
		return 0
	return 1 if controller.is_special_ready(controller.get_active_slot()) else 0


## Key caps of a control with input symbols (G3: mouse buttons, space … as pictures; gamepad
## buttons while the gamepad is in use), left in a cell of KEY_WIDTH so the captions line up.
func _key_cell(id: StringName) -> Control:
	var cell := HBoxContainer.new()
	cell.name = "Keys"
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.custom_minimum_size.x = UiKit.px(KEY_WIDTH)
	var caps := KeyCap.row_for_control(id, KeyCap.HUD_PIXEL)
	caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(caps)
	return cell


## "Alle Tasten: [Esc] → Optionen" with the Esc symbol (G3; gamepad: the pause button).
func _build_footer() -> void:
	if _footer != null:
		_box.remove_child(_footer)
		_footer.queue_free()
	_footer = GlyphText.line(Loc.t(&"HINT_CONTROLS_FOOTER"), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_footer.name = "Footer"
	_box.add_child(_footer)


func _matches(id: StringName, event: InputEvent) -> bool:
	if id == ControlsInfo.AIM:
		# Gamepad: the right stick (runtime aim actions, GamepadInput).
		for action in GamepadInputScript.AIM_ACTIONS:
			if InputMap.has_action(action) and event.is_action_pressed(action):
				return true
		var motion := event as InputEventMouseMotion
		if motion == null:
			return false
		_aim_travel += motion.relative.length()
		return _aim_travel >= AIM_DISTANCE
	for action in ControlsInfo.actions(id):
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


## Keyboard <-> gamepad: the caps show the other device's buttons. Touch controls: the card teaches
## keys, it steps aside without marking the save and comes on the next keyboard or gamepad run.
func _on_input_device_changed(kind: int) -> void:
	if _finishing or _stage < 0:
		return
	if kind == InputDeviceScript.Kind.TOUCH:
		finish(false)
		return
	_build_rows(false)
	_build_footer()


## Left edge in the upper left, below the banners' top band and the HUD's hearts (online test
## 16.10.2026: away from the player in the middle; it used to sit vertically centred).
func _layout() -> void:
	var own := get_combined_minimum_size()
	size = own
	position = Vector2(UiKit.px(EDGE_MARGIN), card_top(self, own.y))


## Top of a teaching card of height on the left edge: below the HUD's status frame, never lower
## than vertically centred.
static func card_top(card: Control, height: float) -> float:
	var view := card.get_viewport_rect().size
	var top := Hud.teaching_card_top(card.get_tree() if card.is_inside_tree() else null)
	return floorf(clampf(top, 0.0, maxf(0.0, (view.y - height) * 0.5)))


## Room 2 moves step 1 on to step 2; room LAST_ROOM ends the card (P1-4).
func _on_room_entered(room_index: int) -> void:
	if _finishing:
		return
	if room_index >= LAST_ROOM:
		finish()
	elif room_index >= 2 and _stage == 0:
		_show_stage(1)


## The first upgrade the player takes: step 2 shows (if it did not yet) and its overview row points
## at the new upgrade until the player opened the overview.
func _on_upgrade_acquired() -> void:
	if _finishing or _upgrade_seen or _stage < 0:
		return
	_upgrade_seen = true
	if _stage == 0:
		_show_stage(1)
	if not _done.has(ControlsInfo.OVERVIEW):
		_set_tag(ControlsInfo.OVERVIEW, TAG_UPGRADE)
