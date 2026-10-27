class_name RoomObjective
extends Node
## Goal of a room with gameplay of its own (RAEUME §1.3/§1.4, R3): one sentence, one
## symbol, one colour and the progress the task bar at the top centre shows ("Welle 1/3 · 6 Gegner",
## "Flamme 70 %" + 0:27). Data only: a mode (the arena now, the minigames of R4) creates one, adds it
## under its room (attach) and keeps it up to date; DungeonUI finds it (node_added) and binds the
## task bar (ObjectiveBar). It lives and dies with its room and never touches nodes of others.
##
## Texts are DungeonTexts keys (D-111), resolved when shown, so a language change follows:
## <prefix>_TITLE ("Arena"), <prefix>_GOAL (big banner sentence, may take goal_args) and
## <prefix>_RULE (small rule line). The prefix comes from MODES.

## Something the bar shows changed (progress, time, danger, label, status).
signal changed
## The goal ended: success = done, otherwise failed (the run goes on, only the bonus is lost).
signal finished(success: bool)
## A running countdown (count_down = true) reached zero; the mode decides what that means.
signal time_up

enum Progress { NONE, COUNT, RATIO }

const GROUP: StringName = &"room_objective"
const META_KEY: StringName = &"room_objective"

# --- Mode ids (RAEUME §2) ---
const ARENA: StringName = &"arena"
const ESCORT: StringName = &"escort"
const FLAME: StringName = &"flame"
const RELIC: StringName = &"relic"
const SOULS: StringName = &"souls"
const RIFTS: StringName = &"rifts"
const HUNT: StringName = &"hunt"
const LIGHTFIRE: StringName = &"lightfire"
const COLLAPSE: StringName = &"collapse"
const ELITE_NEST: StringName = &"elite_nest"

## 16×16 symbols in one row (door_modes.json), grey art tinted with the mode colour; V9 sheet with
## the ladder as the eleventh column (the first ten are the same as door_mode_symbols.png).
const MODE_SYMBOLS_PATH := "res://art/environment/doors/door_mode_symbols_11.png"
const SYMBOL_SIZE := 16
## symbol: frame in MODE_SYMBOLS_PATH; color: mode colour (07_ui.md, door_modes.json); key: text
## prefix in DungeonTexts; calm: intro tone intro_banner_calm instead of intro_banner_combat.
const MODES: Dictionary[StringName, Dictionary] = {
	ARENA: {"symbol": 0, "color": Color("#e0463a"), "key": "ROOM_ARENA", "calm": false},
	ESCORT: {"symbol": 1, "color": Color("#ffd166"), "key": "MODE_ESCORT", "calm": true},
	FLAME: {"symbol": 2, "color": Color("#6a4fc4"), "key": "MODE_FLAME", "calm": false},
	RELIC: {"symbol": 3, "color": Color("#f2cf4a"), "key": "MODE_RELIC", "calm": true},
	SOULS: {"symbol": 4, "color": Color("#2fb391"), "key": "MODE_SOULS", "calm": true},
	RIFTS: {"symbol": 5, "color": Color("#5fcd62"), "key": "MODE_RIFTS", "calm": false},
	HUNT: {"symbol": 6, "color": Color("#ff8a3c"), "key": "MODE_HUNT", "calm": false},
	LIGHTFIRE: {"symbol": 7, "color": Color("#5a2a22"), "key": "MODE_LIGHTFIRE", "calm": true},
	COLLAPSE: {"symbol": 8, "color": Color("#8c8f9a"), "key": "MODE_COLLAPSE", "calm": false},
	ELITE_NEST: {"symbol": 9, "color": Color("#a66ef0"), "key": "ROOM_ELITE_NEST", "calm": false},
}
## Dark mode colours (Lichtfeuer #5a2a22) are lifted this much for text and symbols on panel_dark.
const MIN_UI_LUMINANCE := 0.35
## Danger follows the ratio below this share when auto_danger is on (flame < 30 %, 07_ui.md). TESTWERT
const DANGER_RATIO := 0.3

static var _symbol_cache: Dictionary[StringName, Texture2D] = {}

var mode_id: StringName = ARENA
## RoomGenre of the first-time explanation card (defaults to the mode id).
var genre: StringName = ARENA
## The room this goal belongs to (set by attach).
var room: Node2D = null
var title_key: StringName = &""
var goal_key: StringName = &""
var goal_args: Array = []
var rule_key: StringName = &""
var rule_args: Array = []
## Short progress text of the bar, already translated by the mode ("Welle 1/3 · 6 Gegner").
var label_text := ""
## Optional line under the bar ("Der Dorfbewohner bleibt stehen – Gegner in der Nähe").
var status_text := ""
var progress_kind: Progress = Progress.NONE
var value := 0.0
var max_value := 1.0
## Seconds left; negative = no time shown.
var time_left := -1.0
## true: time_left runs down by itself (pauses with the game) and time_up fires once at zero.
var count_down := false
var danger := false
## true: danger follows get_ratio() < DANGER_RATIO whenever the progress changes.
var auto_danger := false
var success := false

var _finished := false
var _time_up_sent := false


func _init() -> void:
	name = "Objective"
	add_to_group(GROUP)


## A fresh goal of a mode with its keys and colour from MODES.
static func create(mode: StringName) -> RoomObjective:
	var objective := RoomObjective.new()
	objective.setup_mode(mode)
	return objective


## Adds objective under room (one per room; an older one is replaced) and returns it.
static func attach(target_room: Node2D, objective: RoomObjective) -> RoomObjective:
	var old := of_room(target_room)
	if old != null and old != objective:
		target_room.remove_meta(META_KEY)
		old.queue_free()
	objective.room = target_room
	target_room.set_meta(META_KEY, objective)
	if objective.get_parent() == null:
		target_room.add_child(objective)
	return objective


## The goal of a room (null if it has none).
static func of_room(target_room: Node) -> RoomObjective:
	if target_room == null or not is_instance_valid(target_room) or not target_room.has_meta(META_KEY):
		return null
	var objective := target_room.get_meta(META_KEY) as RoomObjective
	return objective if is_instance_valid(objective) and not objective.is_queued_for_deletion() else null


# --- Mode table ---

static func has_mode(mode: StringName) -> bool:
	return MODES.has(mode)


static func get_mode_color(mode: StringName) -> Color:
	return (MODES[mode] as Dictionary).get("color", Color.WHITE) if has_mode(mode) else Color.WHITE


## Mode colour readable on the dark panels (very dark colours are lifted).
static func get_mode_ui_color(mode: StringName) -> Color:
	var color := get_mode_color(mode)
	if color.get_luminance() < MIN_UI_LUMINANCE:
		color = color.lightened(0.45)
	return color


## Grey 16×16 symbol of a mode (tint it with get_mode_ui_color); null if the art is missing.
static func get_mode_icon(mode: StringName) -> Texture2D:
	if not has_mode(mode):
		return null
	if _symbol_cache.has(mode):
		return _symbol_cache[mode]
	var icon: Texture2D = null
	if ResourceLoader.exists(MODE_SYMBOLS_PATH):
		var sheet := load(MODE_SYMBOLS_PATH) as Texture2D
		var frame: int = (MODES[mode] as Dictionary).get("symbol", 0)
		if sheet != null and (frame + 1) * SYMBOL_SIZE <= sheet.get_width():
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(frame * SYMBOL_SIZE, 0, SYMBOL_SIZE, SYMBOL_SIZE)
			icon = atlas
	_symbol_cache[mode] = icon
	return icon


## true: the intro plays the calm banner tone (escort, souls …), false: the combat tone.
static func is_calm_mode(mode: StringName) -> bool:
	return has_mode(mode) and (MODES[mode] as Dictionary).get("calm", false)


static func get_text_prefix(mode: StringName) -> String:
	return String((MODES[mode] as Dictionary).get("key", "")) if has_mode(mode) else ""


## Fills mode, genre and the text keys from MODES.
func setup_mode(mode: StringName) -> void:
	mode_id = mode
	genre = mode
	var prefix := get_text_prefix(mode)
	if prefix.is_empty():
		return
	title_key = StringName(prefix + "_TITLE")
	goal_key = StringName(prefix + "_GOAL")
	rule_key = StringName(prefix + "_RULE")


# --- Texts and look ---

func get_title() -> String:
	return DungeonTexts.t(title_key) if title_key != &"" else ""


## The big sentence of the intro banner ("Überlebe 3 Wellen").
func get_goal() -> String:
	return DungeonTexts.t(goal_key, goal_args) if goal_key != &"" else ""


## The small rule line under it.
func get_rule() -> String:
	return DungeonTexts.t(rule_key, rule_args) if rule_key != &"" else ""


func get_color() -> Color:
	return get_mode_color(mode_id)


func get_ui_color() -> Color:
	return get_mode_ui_color(mode_id)


func get_icon() -> Texture2D:
	return get_mode_icon(mode_id)


# --- Progress, time, danger ---

## Progress as a count ("2/3", "Seelen 4/12").
func set_count(current: int, maximum: int) -> void:
	_set_progress(Progress.COUNT, float(current), float(maxi(1, maximum)))


## Progress as a share 0..1 (flame HP, escort path).
func set_ratio(ratio: float) -> void:
	_set_progress(Progress.RATIO, clampf(ratio, 0.0, 1.0), 1.0)


func clear_progress() -> void:
	_set_progress(Progress.NONE, 0.0, 1.0)


func has_progress() -> bool:
	return progress_kind != Progress.NONE


## Progress as a share 0..1 (0 without progress).
func get_ratio() -> float:
	if progress_kind == Progress.NONE:
		return 0.0
	return clampf(value / maxf(0.0001, max_value), 0.0, 1.0)


## "2/3" for a count, "62 %" for a share, "" without progress.
func get_progress_text() -> String:
	match progress_kind:
		Progress.COUNT:
			return "%d/%d" % [int(value), int(max_value)]
		Progress.RATIO:
			return "%d %%" % roundi(get_ratio() * 100.0)
	return ""


## Shows seconds left; running = true counts down by itself (time_up at zero).
func set_time(seconds: float, running := false) -> void:
	var changed_text := format_time(seconds) != format_time(time_left) or not has_time()
	time_left = maxf(0.0, seconds)
	count_down = running
	_time_up_sent = false
	if changed_text:
		changed.emit()


func clear_time() -> void:
	if not has_time():
		return
	time_left = -1.0
	count_down = false
	changed.emit()


func has_time() -> bool:
	return time_left >= 0.0


## "0:27"; "" for no time.
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return ""
	var whole := ceili(seconds)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


func set_danger(on: bool) -> void:
	if danger == on:
		return
	danger = on
	changed.emit()


func set_label(text: String) -> void:
	if label_text == text:
		return
	label_text = text
	changed.emit()


func set_status(text: String) -> void:
	if status_text == text:
		return
	status_text = text
	changed.emit()


# --- End ---

## Ends the goal once (success or not) and tells the bar.
func finish(was_success: bool) -> void:
	if _finished:
		return
	_finished = true
	success = was_success
	count_down = false
	danger = false
	changed.emit()
	finished.emit(was_success)


func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	if not count_down or _finished or time_left <= 0.0:
		return
	var before := format_time(time_left)
	time_left = maxf(0.0, time_left - delta)
	if format_time(time_left) != before:
		changed.emit()
	if time_left <= 0.0 and not _time_up_sent:
		_time_up_sent = true
		count_down = false
		time_up.emit()


func _exit_tree() -> void:
	if room != null and is_instance_valid(room) and room.has_meta(META_KEY) and room.get_meta(META_KEY) == self:
		room.remove_meta(META_KEY)


func _set_progress(kind: Progress, new_value: float, new_max: float) -> void:
	if progress_kind == kind and is_equal_approx(value, new_value) and is_equal_approx(max_value, new_max):
		return
	progress_kind = kind
	value = new_value
	max_value = new_max
	if auto_danger and not _finished:
		danger = kind != Progress.NONE and get_ratio() < DANGER_RATIO
	changed.emit()
