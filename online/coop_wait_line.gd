class_name CoopWaitLine
extends CanvasLayer
## The co-op wait display (online test 16.10.2026), child of NetDungeon on every machine, at the top
## centre of the screen: the group countdown (CoopWaitBanner, like the truck of R.E.P.O.: a big
## number over "Beeil dich!" for a straggler, a smaller one over "Warte auf <Name> …" for the ones
## waiting), a small line for plain status texts ("Warte auf die Wahl der anderen …") and the arrow
## from the local player towards where the others wait. It replaces the old label in the playfield:
## that one sat half outside the left screen edge (its x was set as if relative to the centre
## anchor) and shared one text between four owners. Everything sits below the task bar or the boss
## bar when one is up (Hud.TOP_CENTER_GROUP; the HUD's room line dodges it in turn), never over the
## middle of the playfield, and above DungeonUI's banners (LAYER). Several owners write at once (side
## way, room change, upgrade round, waiting for clients): one channel each, the first non-empty one
## in CHANNELS shows - as the countdown when its channel has one (set_countdown), else as the line.

const NODE_NAME := &"CoopWaitLine"
## The countdown (online/coop_wait_banner.gd, class CoopWaitBanner; preloaded, so it also resolves
## before the editor's class list knows it).
const WaitBanner := preload("res://online/coop_wait_banner.gd")
const OverlayDodge := preload("res://ui/hints/overlay_dodge.gd")
## Above DungeonUI (20: banners, task bar), below the pause menu and the side transit's fade.
const LAYER := 21
const CHANNEL_SIDE := &"side"
const CHANNEL_ROOM := &"room"
const CHANNEL_UPGRADES := &"upgrades"
const CHANNEL_PLAYERS := &"players"
## Priority: the first channel with a text shows (and the first with an arrow points).
const CHANNELS: Array[StringName] = [CHANNEL_SIDE, CHANNEL_ROOM, CHANNEL_UPGRADES, CHANNEL_PLAYERS]
## Mockup px (UiKit.px): top of the line (like DungeonUI.TOP_BAR_Y), gap below a top bar.
const TOP := 4.0
const GAP := 3.0
const COLOR := Color(1.0, 0.85, 0.4)
## TESTWERTE: the arrow sits this far (mockup px) from the local player and hides within this
## distance (world px) of its target.
const ARROW_DISTANCE := 46.0
const ARROW_HIDE_DISTANCE := 40.0
const ARROW_SIZE := 11.0
## The countdown stays above this share of the screen height (never over the middle of the field).
const SCREEN_TOP_SHARE := 0.4
## Translation key and English fallback of the straggler's line under the big number.
const HURRY_KEY := &"NET_HURRY"
const HURRY_FALLBACK := "Hurry up!"

## Tests and tools: how often a text or a countdown appeared (nothing -> something), frames the
## arrow was shown.
var shown_count := 0
var arrow_frames := 0
## Tests and tools: frames the straggler's big countdown ("Beeil dich!") was on screen, and of those
## the frames it lay wholly inside the screen above SCREEN_TOP_SHARE of its height.
var hurry_frames := 0
var hurry_frames_on_screen := 0

var _texts: Dictionary[StringName, String] = {}
## channel -> [time_left: float, hurry: bool]
var _countdowns: Dictionary[StringName, Array] = {}
## channel -> [player: Node2D, target: Vector2 (global)]
var _arrows: Dictionary[StringName, Array] = {}
var _shown := ""
var _shown_channel: StringName = &""
var _arrow_channel: StringName = &""
var _panel: PanelContainer = null
var _label: Label = null
var _banner: WaitBanner = null
var _arrow: Polygon2D = null


## Translated text of key with args; fallback (English) while the key has no translation yet, so a
## missing entry never shows the bare key or breaks the formatting.
static func format(key: StringName, args: Array, fallback: String) -> String:
	var text := Loc.t(key)
	if text.is_empty() or text == String(key):
		text = fallback
	if args.is_empty() or not text.contains("%"):
		return text
	return text % args


## The straggler's line under the big number: "Beeil dich!".
static func hurry_text() -> String:
	return format(HURRY_KEY, [], HURRY_FALLBACK)


func _init() -> void:
	name = NODE_NAME
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.get_theme()
	add_child(root)
	_panel = UiKit.panel(&"dark")
	_panel.name = "Line"
	_panel.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 5))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.add_to_group(Hud.TOP_CENTER_GROUP)
	root.add_child(_panel)
	_label = UiKit.text_label("", UiKit.SIZE_BODY, COLOR, true)
	_label.name = "Text"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_banner = WaitBanner.new()
	_banner.add_to_group(Hud.TOP_CENTER_GROUP)
	root.add_child(_banner)
	# Points along +x, turned towards the target.
	_arrow = Polygon2D.new()
	_arrow.name = "Arrow"
	var size := UiKit.px(ARROW_SIZE)
	_arrow.polygon = PackedVector2Array([Vector2(size, 0.0), Vector2(-size * 0.7, -size * 0.75),
			Vector2(-size * 0.3, 0.0), Vector2(-size * 0.7, size * 0.75)])
	_arrow.color = COLOR
	_arrow.visible = false
	add_child(_arrow)


func _process(delta: float) -> void:
	if _panel.visible:
		_place(_panel)
		_panel.modulate.a = OverlayDodge.step(_panel.modulate.a, OverlayDodge.is_covering(get_line_rect(), OverlayDodge.body_rects(get_tree())), delta)
	if _banner.visible:
		_place(_banner)
		if _banner.is_hurry():
			hurry_frames += 1
			if is_on_screen_top():
				hurry_frames_on_screen += 1
	_update_arrow()


## The line or countdown lies wholly inside the screen, above SCREEN_TOP_SHARE of its height.
func is_on_screen_top() -> bool:
	var rect := get_line_rect()
	if not rect.has_area() or not is_inside_tree():
		return false
	var view := get_viewport().get_visible_rect().size
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= view.x and rect.end.y <= view.y * SCREEN_TOP_SHARE


# --- Text and countdown ---

func set_text(channel: StringName, text: String) -> void:
	if _texts.get(channel, "") == text:
		return
	_texts[channel] = text
	_refresh()


## The countdown of channel: time_left seconds, hurry = big for a straggler. Shown with the
## channel's text under the number while that channel is the one on screen.
func set_countdown(channel: StringName, time_left: float, hurry: bool) -> void:
	_countdowns[channel] = [time_left, hurry]
	if channel == _shown_channel:
		_refresh()


func clear_countdown(channel: StringName) -> void:
	if not _countdowns.has(channel):
		return
	_countdowns.erase(channel)
	_refresh()


func get_channel_text(channel: StringName) -> String:
	return _texts.get(channel, "")


## The text on screen ("" = none; with a countdown the line under the number) and its channel.
func get_text() -> String:
	return _shown


func get_shown_channel() -> StringName:
	return _shown_channel


## Something is on screen (the line or the countdown).
func is_line_visible() -> bool:
	return _panel.visible or _banner.visible


func is_countdown_visible() -> bool:
	return _banner.visible


func get_banner() -> WaitBanner:
	return _banner


## Where the line or the countdown is on screen (canvas px of this layer, no transform: viewport
## coordinates; empty when nothing shows).
func get_line_rect() -> Rect2:
	if _banner.visible:
		return Rect2(_banner.position, _banner.size)
	if _panel.visible:
		return Rect2(_panel.position, _panel.size)
	return Rect2()


## Everything off (session lost, run over).
func clear_all() -> void:
	_texts.clear()
	_countdowns.clear()
	_arrows.clear()
	_refresh()
	_arrow.visible = false
	_arrow_channel = &""


func _refresh() -> void:
	var text := ""
	var channel: StringName = &""
	for key in CHANNELS:
		var candidate: String = _texts.get(key, "")
		if not candidate.is_empty():
			text = candidate
			channel = key
			break
	var was_showing := is_line_visible()
	_shown_channel = channel
	_shown = text
	var countdown: Array = _countdowns.get(channel, [])
	if not text.is_empty() and not countdown.is_empty():
		_panel.visible = false
		_banner.show_countdown(float(countdown[0]), text, bool(countdown[1]))
	else:
		_banner.hide_countdown()
		if _label.text != text:
			_label.text = text
		_panel.visible = not text.is_empty()
	if not was_showing and is_line_visible():
		shown_count += 1
	if is_inside_tree():
		if _panel.visible:
			_place(_panel)
		if _banner.visible:
			_place(_banner)


## Top centre of the screen, below every visible bar of the top centre that it would touch.
func _place(control: Control) -> void:
	control.reset_size()
	var size := control.get_combined_minimum_size()
	var view := control.get_parent_area_size()
	var rect := Rect2(Vector2(roundf((view.x - size.x) * 0.5), UiKit.px(TOP)), size)
	for node in get_tree().get_nodes_in_group(Hud.TOP_CENTER_GROUP):
		var bar := node as Control
		if bar == null or bar == _panel or bar == _banner or not bar.is_visible_in_tree():
			continue
		var bar_rect := bar.get_global_rect()
		if bar_rect.position.x < rect.end.x and bar_rect.end.x > rect.position.x and bar_rect.position.y < rect.end.y + UiKit.px(GAP):
			rect.position.y = maxf(rect.position.y, bar_rect.end.y + UiKit.px(GAP))
	control.position = rect.position
	control.size = size


# --- Arrow ---

## The arrow of channel points from player (on screen) towards target (global world position).
func set_arrow(channel: StringName, player: Node2D, target: Vector2) -> void:
	_arrows[channel] = [player, target]


func clear_arrow(channel: StringName) -> void:
	_arrows.erase(channel)


## The channel whose arrow is on screen (&"" = none).
func get_arrow_channel() -> StringName:
	return _arrow_channel if _arrow.visible else &""


func is_arrow_visible() -> bool:
	return _arrow.visible


func _update_arrow() -> void:
	var show := false
	_arrow_channel = &""
	for channel in CHANNELS:
		if not _arrows.has(channel):
			continue
		var entry: Array = _arrows[channel]
		var player := entry[0] as Node2D if is_instance_valid(entry[0]) else null
		if player == null or not player.is_inside_tree():
			continue
		var offset: Vector2 = (entry[1] as Vector2) - player.global_position
		_arrow_channel = channel
		if offset.length() > ARROW_HIDE_DISTANCE:
			var direction := offset.normalized()
			_arrow.position = player.get_global_transform_with_canvas().origin + direction * UiKit.px(ARROW_DISTANCE)
			_arrow.rotation = direction.angle()
			_arrow.color = WaitBanner.URGENT_COLOR if _banner.is_urgent() else COLOR
			show = true
		break
	_arrow.visible = show
	if show:
		arrow_frames += 1
