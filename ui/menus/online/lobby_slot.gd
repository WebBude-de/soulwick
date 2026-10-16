class_name LobbySlot
extends PanelContainer
## One player place in the room dialog (D-152, OnlineMenu): frame, the player's figure standing idle
## in its look, name, host crown, status (ready / connecting / in the run) and ping bars; the own
## place has "Aussehen ändern", an empty one says "Wartet auf Spieler …" (the host's first empty
## place offers "Code teilen"). Frames: art/ui/lobby/slot_<kind>.png (9-slice, 6 px border,
## SPRITES_V10 §7) once they exist, else the panels of the theme (own = gold, empty = dark and
## faded). Crown and ping bars use art/ui/icon_host.png and icon_ping_*.png; the ready tick
## art/ui/lobby/ready.png, else a drawn one. Sizes in mockup pixels (UiKit.px).

enum Status { READY, CONNECTING, IN_RUN }

const ART_DIR := "res://art/ui/lobby/"
const HOST_ICON_PATH := "res://art/ui/icon_host.png"
const PING_ICON_PATHS := {
	&"good": "res://art/ui/icon_ping_good.png",
	&"mid": "res://art/ui/icon_ping_mid.png",
	&"bad": "res://art/ui/icon_ping_bad.png",
}
## TESTWERT: ping limits for the bars (ms): below GOOD three green bars, below MID two yellow.
const PING_GOOD_MS := 80
const PING_MID_MS := 160
const PREVIEW_SCALE := 2
## Mockup pixels: the place (fits the village dialog with code, hint and buttons) and its padding.
const HEIGHT := 64.0
const PADDING := 3.0
const STATUS_KEYS := {
	Status.READY: &"LOBBY_SLOT_READY",
	Status.CONNECTING: &"LOBBY_SLOT_CONNECTING",
	Status.IN_RUN: &"LOBBY_SLOT_IN_RUN",
}

var peer_id := 0
var is_own := false
var is_host := false
var is_empty := true
var _ping_icon: TextureRect = null
var _ping_label: Label = null

static var _ready_icon: Texture2D = null


## A taken place: index (P1..P4 colour), name, look ({} = unknown yet), host/own flags, status and
## ping (-1 = unknown). on_edit: "Aussehen ändern" of the own place (empty Callable = no button).
static func create_player(index: int, player_name: String, look: Dictionary, host: bool, own: bool,
		status: Status, ping_ms: int, width: float, on_edit: Callable = Callable()) -> LobbySlot:
	var slot := LobbySlot.new()
	slot.name = "Slot%d" % (index + 1)
	slot.is_empty = false
	slot.is_own = own
	slot.is_host = host
	slot._frame(&"own" if own else (&"host" if host else &"normal"), width)
	var box := slot._box()
	# P-tag top left, the figure in the middle, the host crown top right: one row.
	var top := UiKit.hbox(0)
	var tag := UiKit.text_label("P%d" % (index + 1), UiKit.SIZE_EYEBROW, NetPlayers.color_for(index), true)
	tag.name = "Tag"
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.custom_minimum_size.x = UiKit.px(9)
	top.add_child(tag)
	var preview := CharacterPreview.create(PREVIEW_SCALE, false)
	preview.name = "Preview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	top.add_child(preview)
	var crown_box := Control.new()
	crown_box.custom_minimum_size = UiKit.pxv(9, 7)
	crown_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	crown_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if host:
		var crown := UiKit.pixel_icon(load(HOST_ICON_PATH) as Texture2D, 9.0)
		crown.name = "HostCrown"
		crown.tooltip_text = tr_key(&"LOBBY_HOST")
		crown_box.add_child(crown)
	top.add_child(crown_box)
	box.add_child(top)
	if not look.is_empty():
		preview.set_look(look)
	else:
		preview.set_look(PlayerLook.default_look())
		preview.modulate = Color(UiKit.COLOR_SHADOW, 1.0)
	var name_label := UiKit.text_label(player_name if not player_name.is_empty() else "?", UiKit.SIZE_BODY, UiKit.COLOR_GOLD if own else UiKit.COLOR_TEXT, true)
	name_label.name = "PlayerName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)
	box.add_child(slot._status_row(status, ping_ms))
	if own and on_edit.is_valid():
		box.add_child(small_button("EditLook", &"LOBBY_EDIT_LOOK", on_edit, width))
	return slot


## A free place: "Wartet auf Spieler …"; on_share (host's first free place) copies the room code.
static func create_empty(index: int, width: float, on_share: Callable = Callable()) -> LobbySlot:
	var slot := LobbySlot.new()
	slot.name = "Slot%d" % (index + 1)
	slot._frame(&"empty", width)
	var box := slot._box()
	var tag := UiKit.text_label("P%d" % (index + 1), UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED, true)
	box.add_child(tag)
	var plus := UiKit.text_label("+", UiKit.SIZE_TITLE_LARGE, UiKit.COLOR_EMPTY_SLOT, true)
	plus.name = "Plus"
	plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.custom_minimum_size.y = UiKit.px(18)
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(plus)
	var waiting := UiKit.wrapped_text(tr_key(&"LOBBY_SLOT_WAITING"), width - PADDING * 2.0 - 2.0, UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	waiting.name = "Waiting"
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(waiting)
	if on_share.is_valid():
		box.add_child(small_button("ShareCode", &"LOBBY_SHARE_CODE", on_share, width))
	return slot


## A small framed button that never makes the place wider (text trimmed), focusable for keys and
## controller (gold frame), a tap target on touch.
static func small_button(node_name: String, key: StringName, on_pressed: Callable, width: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = key
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(UiKit.px(width - PADDING * 2.0 - 2.0), UiKit.px(11))
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
	button.add_theme_stylebox_override("normal", UiKit.padded_style(&"button", 1, 1))
	button.add_theme_stylebox_override("hover", UiKit.padded_style(&"button_hover", 1, 1))
	button.add_theme_stylebox_override("pressed", UiKit.padded_style(&"button_hover", 1, 1))
	button.pressed.connect(on_pressed)
	OnlineMenu._make_focusable(button)
	return button


## Updates the ping bars in place (once a second, no rebuild).
func set_ping(ping_ms: int) -> void:
	if _ping_icon == null:
		return
	_ping_icon.texture = load(PING_ICON_PATHS[ping_quality(ping_ms)]) as Texture2D
	_ping_icon.modulate.a = 1.0 if ping_ms >= 0 else 0.35
	_ping_label.text = str(ping_ms) if ping_ms >= 0 else "–"
	_ping_icon.tooltip_text = "%d ms" % ping_ms if ping_ms >= 0 else "– ms"


## &"good", &"mid" or &"bad" for a round trip (unknown counts as bad, shown faded).
static func ping_quality(ping_ms: int) -> StringName:
	if ping_ms < 0:
		return &"bad"
	if ping_ms < PING_GOOD_MS:
		return &"good"
	if ping_ms < PING_MID_MS:
		return &"mid"
	return &"bad"


static func tr_key(key: StringName) -> String:
	return TranslationServer.translate(key)


func _frame(kind: StringName, width: float) -> void:
	custom_minimum_size = UiKit.pxv(width, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	var art := ART_DIR + "slot_%s.png" % kind
	if ResourceLoader.exists(art):
		var style := StyleBoxTexture.new()
		style.texture = load(art) as Texture2D
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, 6)
			style.set_content_margin(side, UiKit.px(PADDING))
		add_theme_stylebox_override("panel", style)
	else:
		var panel_kind: StringName = {&"own": &"gold", &"empty": &"dark"}.get(kind, &"normal")
		add_theme_stylebox_override("panel", UiKit.padded_style(panel_kind, PADDING, PADDING))
	if kind == &"empty":
		self_modulate = Color(1, 1, 1, 0.7)


func _box() -> VBoxContainer:
	var box := UiKit.vbox(int(UiKit.px(1)))
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	return box


## "✓ Bereit" (or connecting / in the run) and the ping bars with the round trip, one line.
func _status_row(status: Status, ping_ms: int) -> Control:
	var row := UiKit.hbox(int(UiKit.px(1)))
	row.name = "Status"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if status == Status.READY:
		var tick := TextureRect.new()
		tick.name = "ReadyTick"
		tick.texture = ready_icon()
		tick.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tick.custom_minimum_size = UiKit.pxv(6, 6)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tick)
	var color := UiKit.COLOR_SUCCESS if status == Status.READY else UiKit.COLOR_MUTED
	var label := UiKit.text_label(STATUS_KEYS[status], UiKit.SIZE_EYEBROW, color)
	label.name = "StatusText"
	row.add_child(label)
	var gap := Control.new()
	gap.custom_minimum_size.x = UiKit.px(3)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_ping_icon = UiKit.pixel_icon(load(PING_ICON_PATHS[&"good"]) as Texture2D, 7.0)
	_ping_icon.name = "PingBars"
	_ping_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ping_icon)
	_ping_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED)
	_ping_label.name = "PingText"
	row.add_child(_ping_label)
	set_ping(ping_ms)
	return row


## The ready tick: art/ui/lobby/ready.png, else a drawn green tick (7×7).
static func ready_icon() -> Texture2D:
	if _ready_icon != null:
		return _ready_icon
	var path := ART_DIR + "ready.png"
	if ResourceLoader.exists(path):
		_ready_icon = load(path) as Texture2D
		return _ready_icon
	var image := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var tick := [Vector2i(0, 3), Vector2i(1, 4), Vector2i(2, 5), Vector2i(3, 4), Vector2i(4, 3), Vector2i(5, 2), Vector2i(6, 1)]
	for point: Vector2i in tick:
		image.set_pixelv(point, UiKit.COLOR_SUCCESS)
		if point.y + 1 < 7:
			image.set_pixelv(point + Vector2i(0, 1), UiKit.COLOR_SHADOW)
	_ready_icon = ImageTexture.create_from_image(image)
	return _ready_icon
