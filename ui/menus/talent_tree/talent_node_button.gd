class_name TalentNodeButton
extends Button
## One node of the talent tree view (KE8, Mockup 14): the frame of its state (aus, verfügbar,
## gesetzt, Schlussstein, TalentTreeArt), the talent icon on it and "2/3" below. A plain Button, so
## mouse, touch and the dialog's gamepad/keyboard focus (Modal) reach it; it is never disabled (a
## locked node can still be chosen to read what opens it). Drawing only: the dialog decides.

## Node size in art px (frame 22×22, icon 16×16) and the line below for the level (mockup px).
const FRAME_ART := 22
const ICON_ART := 16
const LEVEL_LINE := 8.0
const SELECTED_COLOR := UiKit.COLOR_GOLD
const LEVEL_COLOR := UiKit.COLOR_TEXT_SOFT
const LOCKED_ICON_ALPHA := 0.35

var talent: TalentDef = null
var state := TalentTreeEdit.NodeState.LOCKED
var level := 0
var selected := false
## Seconds for the glow of a full node.
var _time := 0.0


static func create(def: TalentDef) -> TalentNodeButton:
	var node := TalentNodeButton.new()
	node.talent = def
	node.name = "Node_%s" % def.id
	return node


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	for style in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	custom_minimum_size = min_size()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	tooltip_text = talent.get_display_name() if talent != null else ""


## Size of a node button: the frame with a little air and the level line below.
static func min_size() -> Vector2:
	return Vector2(frame_px() + UiKit.px(2), frame_px() + UiKit.px(LEVEL_LINE))


## Frame size on screen (whole multiples of the art).
static func frame_px() -> float:
	return UiKit.art_px(FRAME_ART, FRAME_ART)


func set_view(node_state: TalentTreeEdit.NodeState, node_level: int, is_selected: bool) -> void:
	state = node_state
	level = node_level
	selected = is_selected
	queue_redraw()


func _process(delta: float) -> void:
	if state == TalentTreeEdit.NodeState.FULL and TalentTreeArt.glow_strip() != null:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if talent == null:
		return
	var frame_size := frame_px()
	var frame_rect := Rect2(Vector2((size.x - frame_size) * 0.5, 0.0), Vector2(frame_size, frame_size))
	var glow := TalentTreeArt.glow_strip() if state == TalentTreeEdit.NodeState.FULL and not talent.is_capstone() else null
	if glow != null:
		var frame := TalentTreeArt.glow_frame(_time)
		draw_texture_rect_region(glow, frame_rect, Rect2(frame * FRAME_ART, 0, FRAME_ART, FRAME_ART))
	else:
		draw_texture_rect(TalentTreeArt.node_frame(state, talent.is_capstone()), frame_rect, false)
	var icon := TalentTreeArt.talent_icon(talent)
	var icon_size := frame_size * float(ICON_ART) / float(FRAME_ART)
	var icon_rect := Rect2(frame_rect.get_center() - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size))
	var tint := Color(1, 1, 1, LOCKED_ICON_ALPHA) if state == TalentTreeEdit.NodeState.LOCKED else Color.WHITE
	draw_texture_rect(icon, icon_rect, false, tint)
	if selected:
		_draw_corners(frame_rect.grow(UiKit.px(1)))
	var font := UiKit.bold_font()
	var font_size := UiKit.font_px(UiKit.SIZE_EYEBROW)
	var caption := "%d/%d" % [level, talent.max_level]
	var color := LEVEL_COLOR if state != TalentTreeEdit.NodeState.LOCKED else UiKit.COLOR_DISABLED
	if state == TalentTreeEdit.NodeState.FULL:
		color = UiKit.COLOR_GOLD
	var baseline := frame_rect.end.y + font_size
	draw_string(font, Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


## Gold corner marks around the chosen node (the gamepad frame of Modal comes on top).
func _draw_corners(rect: Rect2) -> void:
	var arm := UiKit.px(4)
	var width := float(UiKit.ART_SCALE)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if corner.x <= rect.get_center().x else -1.0
		var sy := 1.0 if corner.y <= rect.get_center().y else -1.0
		# Arms as rects on the UI art-pixel grid (D-218).
		var across := Vector2(arm * sx, width)
		var down := Vector2(width, arm * sy)
		PixelDraw.rect(self, _abs_rect(corner - Vector2(0, width * 0.5), across), SELECTED_COLOR, width)
		PixelDraw.rect(self, _abs_rect(corner - Vector2(width * 0.5, 0), down), SELECTED_COLOR, width)


static func _abs_rect(origin: Vector2, extent: Vector2) -> Rect2:
	return Rect2(origin, extent).abs()
