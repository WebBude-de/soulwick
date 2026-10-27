class_name FlintGuideView
extends CanvasLayer
## The explanation corner of "Flint erklärt" (KONZEPT §7.2, mockup SPRITES_V13 §A2): at the bottom
## right Flint big in his round frame (FlintPortrait), left of him his speech bubble with at most two
## lines and "Weiter ▸", above it a quiet "Überspringen". In portrait on a phone the corner sits at
## the bottom right of the game screen, i.e. right above the controller (MobileUi zoom and safe area).
## Only the local player's machine shows it (FlintGuide creates it); it follows the guide's signals
## and calls press()/skip() for clicks and taps on its buttons or the bubble. Babble per syllable
## (FlintBabble), the portrait bounces with it. Nothing here decides anything.
## Key names in a sentence ("Mit Leertaste weichst du aus", FlintControls) show as the pictures of the
## device in use (GlyphText): the bubble then types into a RichTextLabel instead of the plain label,
## a picture appearing with the first letter of the key name it stands for.
## The delivered bubble is light parchment (#e9e4d2, the colour of the UI text): on it the sentence is
## dark ink without the shadow and "Weiter" dark wood (feedback #8e2a665c "Man kann den Text kaum
## lesen": the light text vanished, only its shadow showed); the placeholder panel keeps light text.

## Above the village and dungeon UI (20), under the touch controls (25) and the pause menu (30).
const LAYER := 21
## Mockup pixels (480x270 layout, UiKit.px).
const MARGIN := 6.0
const BUBBLE_WIDTH := 200.0
const GAP := 3.0
const TEXT_SIZE := UiKit.SIZE_KEY_HINT
const HOLD_BAR_WIDTH := 28.0
const HOLD_BAR_HEIGHT := 2.0
## Pop of the corner when Flint arrives and leaves (s, TESTWERT).
const POP_TIME := 0.18
const POP_FROM := 0.4
## The "Weiter" arrow pulses (placeholder without guide_next art).
const ARROW_PULSE_SPEED := 4.0
## The bubble's tail (speech_bubble_tail.png, 8x8): mirrored so it points down right to Flint, its right
## edge this many art pixels inside the bubble's right edge, its top row over the bubble's bottom border.
const TAIL_SIZE := 8.0
const TAIL_INSET := 3.0
const TAIL_OVERLAP := 2.0
## Text on the light bubble art (HANDOUT palette): panel colour as ink, "Weiter" in dark wood.
const INK_ON_PAPER := Color("#2a2638")
const NEXT_ON_PAPER := Color("#5c3a24")

var guide: FlintGuide = null

var _root: Control = null
var _corner: HBoxContainer = null
var _bubble_frame: BubbleFrame = null
var _bubble: PanelContainer = null
var _tail: TextureRect = null
var _speech: Label = null
## The sentence with key pictures (only while it names keys; _speech is hidden then).
var _speech_glyphs: RichTextLabel = null
## Per character of _speech_glyphs (a picture counts as one): the index in the sentence where it
## starts, so the typing of the sentence maps onto it.
var _glyph_starts := PackedInt32Array()
var _next: Button = null
var _skip: Button = null
var _hold_bar: ProgressBar = null
var _portrait_slot: Control = null
var _portrait: FlintPortrait = null
var _arrow_frames: Array[Texture2D] = []
var _arrow_time := 0.0
var _shown := false


func _init(owner_guide: FlintGuide = null) -> void:
	guide = owner_guide
	layer = LAYER
	name = "FlintGuideView"
	_build()


func _ready() -> void:
	UiKit.MobileUi.fit_to_safe_area(_root, true)
	if guide == null:
		guide = get_parent() as FlintGuide
	if guide == null:
		return
	guide.phase_changed.connect(_on_phase_changed)
	guide.step_started.connect(_on_step_started)
	guide.characters_revealed.connect(_on_characters_revealed)
	guide.syllable_spoken.connect(_on_syllable_spoken)
	guide.hold_progress.connect(_on_hold_progress)
	_apply_style()
	if guide.phase == FlintGuide.Phase.TALK:
		_appear()


## Global world point of the portrait's middle: where Flint flies to (FlintExcursion).
func get_corner_world_point() -> Vector2:
	var point := get_corner_screen_point()
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.INF
	return viewport.get_canvas_transform().affine_inverse() * point


## The portrait's middle in screen (canvas layer) coordinates.
func get_corner_screen_point() -> Vector2:
	if _portrait_slot == null or not _portrait_slot.is_inside_tree():
		return Vector2.INF
	return _portrait_slot.get_global_rect().get_center()


func get_speech() -> Label:
	return _speech


## The bubble's sentence with key pictures, or null while the sentence names no key.
func get_speech_glyphs() -> RichTextLabel:
	return _speech_glyphs if _speech_glyphs != null and _speech_glyphs.visible else null


func get_next_button() -> Button:
	return _next


func get_skip_button() -> Button:
	return _skip


func get_bubble() -> PanelContainer:
	return _bubble


## The delivered tail under the bubble or null (placeholder bubble without tail).
func get_bubble_tail() -> TextureRect:
	return _tail


func get_portrait() -> FlintPortrait:
	return _portrait


func is_shown() -> bool:
	return _shown


## A click or tap on the bubble goes on like "Weiter". True if it was such a press.
func handle_bubble_input(event: InputEvent) -> bool:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed and guide != null:
		guide.press()
	return pressed


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiKit.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_corner = UiKit.hbox(int(UiKit.px(GAP)))
	_corner.name = "Corner"
	_corner.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_corner)
	_corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner.offset_right = -UiKit.px(MARGIN)
	_corner.offset_bottom = -UiKit.px(MARGIN)
	_corner.modulate.a = 0.0
	_corner.add_child(_build_column())
	_portrait_slot = Control.new()
	_portrait_slot.name = "PortraitSlot"
	_portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait = FlintPortrait.new()
	_portrait.name = "Portrait"
	_portrait_slot.custom_minimum_size = _portrait.custom_minimum_size
	_portrait_slot.size_flags_vertical = Control.SIZE_SHRINK_END
	_portrait_slot.add_child(_portrait)
	_corner.add_child(_portrait_slot)


func _build_column() -> VBoxContainer:
	var column := UiKit.vbox(int(UiKit.px(GAP)))
	column.name = "Column"
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	_skip = UiKit.button(Loc.t(&"FLINT_GUIDE_SKIP"), _on_skip_pressed)
	_skip.name = "Skip"
	_skip.flat = true
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_skip.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
	_skip.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
	column.add_child(_skip)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.gui_input.connect(func(event: InputEvent) -> void:
		if handle_bubble_input(event):
			_bubble.accept_event())
	_bubble_frame = BubbleFrame.new()
	_bubble_frame.name = "BubbleFrame"
	_bubble_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_frame.bubble = _bubble
	_bubble_frame.add_child(_bubble)
	column.add_child(_bubble_frame)
	var box := UiKit.vbox(0)
	_bubble.add_child(box)
	_speech = UiKit.wrapped_text("", BUBBLE_WIDTH, TEXT_SIZE, UiKit.COLOR_TEXT)
	_speech.name = "Speech"
	_speech.max_lines_visible = FlintGuideRules.MAX_LINES
	_speech.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	box.add_child(_speech)
	_speech_glyphs = GlyphText.rich_label(TEXT_SIZE, UiKit.COLOR_TEXT)
	_speech_glyphs.name = "SpeechGlyphs"
	_speech_glyphs.custom_minimum_size = Vector2(UiKit.px(BUBBLE_WIDTH), 0)
	_speech_glyphs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_glyphs.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_speech_glyphs.visible = false
	box.add_child(_speech_glyphs)
	var row := UiKit.hbox(int(UiKit.px(GAP)))
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	_hold_bar = ProgressBar.new()
	_hold_bar.name = "HoldBar"
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.custom_minimum_size = UiKit.pxv(HOLD_BAR_WIDTH, HOLD_BAR_HEIGHT)
	_hold_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_bar.modulate.a = 0.0
	row.add_child(_hold_bar)
	_next = UiKit.button(Loc.t(&"FLINT_GUIDE_NEXT"), _on_next_pressed)
	_next.name = "Next"
	_next.flat = true
	_next.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
	_next.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	row.add_child(_next)
	return column


## Delivered bubble and arrow art, else the warm menu panel and a pulsing text arrow.
func _apply_style() -> void:
	var bubble_texture := FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_FILE)
	if bubble_texture != null:
		var style := StyleBoxTexture.new()
		style.texture = UiKit.upscale(bubble_texture)
		style.set_texture_margin_all(FlintPortraitArt.BUBBLE_MARGIN * UiKit.ART_SCALE)
		style.set_content_margin_all(UiKit.px(FlintPortraitArt.BUBBLE_MARGIN))
		_bubble.add_theme_stylebox_override("panel", style)
		_use_ink()
	else:
		_bubble.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", 5, 7))
	_arrow_frames = FlintPortraitArt.next_arrow_frames()
	if not _arrow_frames.is_empty():
		_next.icon = UiKit.upscale(_arrow_frames[0])
		_next.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tail_texture := FlintPortraitArt.texture(FlintPortraitArt.BUBBLE_TAIL_FILE)
	if tail_texture != null and bubble_texture != null:
		_tail = UiKit.icon(UiKit.upscale(tail_texture), UiKit.art_px(TAIL_SIZE, float(tail_texture.get_width())))
		_tail.name = "Tail"
		# Delivered pointing down left; Flint sits to the right.
		_tail.flip_h = true
		_bubble_frame.add_child(_tail)
		_bubble_frame.tail = _tail
		var art_pixel := _tail.custom_minimum_size.x / float(tail_texture.get_width())
		_bubble_frame.tail_inset = TAIL_INSET * art_pixel
		_bubble_frame.tail_overlap = TAIL_OVERLAP * art_pixel
		_bubble_frame.update_minimum_size()
		_bubble_frame.queue_sort()


## Dark text without shadow for the light bubble art.
func _use_ink() -> void:
	_speech.add_theme_color_override("font_color", INK_ON_PAPER)
	_speech.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_speech.add_theme_constant_override("shadow_offset_x", 0)
	_speech.add_theme_constant_override("shadow_offset_y", 0)
	_speech_glyphs.add_theme_color_override("default_color", INK_ON_PAPER)
	_speech_glyphs.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_speech_glyphs.add_theme_constant_override("shadow_offset_x", 0)
	_speech_glyphs.add_theme_constant_override("shadow_offset_y", 0)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		_next.add_theme_color_override(state, NEXT_ON_PAPER)
	_next.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))


func _process(delta: float) -> void:
	if not _shown or _next == null:
		return
	_arrow_time += delta
	if _arrow_frames.size() > 1:
		var index := int(_arrow_time * 6.0) % _arrow_frames.size()
		_next.icon = UiKit.upscale(_arrow_frames[index])
	var complete := guide != null and guide.get_revealed() >= guide.get_text().length()
	_next.modulate.a = (0.75 + 0.25 * sin(_arrow_time * ARROW_PULSE_SPEED)) if complete else 0.45


# --- Reactions ---

func _on_phase_changed(phase: FlintGuide.Phase) -> void:
	match phase:
		FlintGuide.Phase.TALK:
			_appear()
		FlintGuide.Phase.FLY_BACK, FlintGuide.Phase.IDLE:
			_disappear()


func _appear() -> void:
	if _shown:
		return
	_shown = true
	var current := guide.current if guide != null else null
	# A one-sentence hint needs no "Überspringen": "Weiter" closes it.
	_skip.visible = current != null and (current.locks_player() or current.steps.size() > 1)
	_corner.pivot_offset = _corner.size
	_corner.scale = Vector2.ONE * POP_FROM
	_portrait.pivot_offset = _portrait.size * 0.5
	var tween := _corner.create_tween().set_parallel(true)
	tween.tween_property(_corner, "modulate:a", 1.0, POP_TIME)
	tween.tween_property(_corner, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _disappear() -> void:
	if not _shown:
		return
	_shown = false
	_corner.pivot_offset = _corner.size
	var tween := _corner.create_tween().set_parallel(true)
	tween.tween_property(_corner, "modulate:a", 0.0, POP_TIME)
	tween.tween_property(_corner, "scale", Vector2.ONE * POP_FROM, POP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_step_started(_index: int, text: String, mood: FlintGuideStep.Mood) -> void:
	_speech.text = text
	_speech.visible_characters = 0
	var parts := GlyphText.split(text)
	var glyphs := GlyphText.has_glyphs(parts)
	_glyph_starts = glyph_starts(text, parts) if glyphs else PackedInt32Array()
	if glyphs:
		GlyphText.fill(_speech_glyphs, parts, KeyCap.HUD_PIXEL)
		_speech_glyphs.visible_characters = 0
	_speech_glyphs.visible = glyphs
	_speech.visible = not glyphs
	_portrait.set_mood(mood)


func _on_characters_revealed(count: int) -> void:
	_speech.visible_characters = count
	if _speech_glyphs.visible:
		var shown := 0
		while shown < _glyph_starts.size() and _glyph_starts[shown] < count:
			shown += 1
		_speech_glyphs.visible_characters = shown if shown < _glyph_starts.size() else -1


## For the parts of GlyphText.split(text): per shown character (a picture is one) the index in text
## where it starts. A picture stands for the key name between the strings around it.
static func glyph_starts(text: String, parts: Array) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var at := 0
	var i := 0
	while i < parts.size():
		var part: Variant = parts[i]
		if part is String:
			var found := text.find(part, at)
			at = found if found >= 0 else at
			for j in (part as String).length():
				starts.append(at + j)
			at += (part as String).length()
			i += 1
			continue
		# A run of pictures up to the next string (or the end) shares the key names in between.
		var run := 0
		while i + run < parts.size() and not parts[i + run] is String:
			run += 1
		var end := text.length()
		if i + run < parts.size():
			var next := text.find(parts[i + run] as String, at)
			end = next if next >= 0 else end
		var each := maxi(1, (end - at) / run)
		for k in run:
			starts.append(mini(at + k * each, maxi(at, end - 1)))
		at = end
		i += run
	return starts


func _on_syllable_spoken(_char_index: int, syllable: String) -> void:
	FlintBabble.play(self, syllable)
	_portrait.pulse()


func _on_hold_progress(ratio: float) -> void:
	_hold_bar.value = ratio
	_hold_bar.modulate.a = 1.0 if ratio > 0.0 else 0.0


func _on_next_pressed() -> void:
	if guide != null:
		guide.press()


func _on_skip_pressed() -> void:
	if guide != null:
		guide.skip()


## The bubble with its tail hanging out at the bottom right: the bubble fills the frame except the
## strip under it where the tail sits, so the tail is never stretched over the text by the panel.
class BubbleFrame extends Container:
	var bubble: Control = null
	var tail: Control = null
	var tail_inset := 0.0
	var tail_overlap := 0.0

	func _get_minimum_size() -> Vector2:
		var result := bubble.get_combined_minimum_size() if bubble != null else Vector2.ZERO
		result.y += _tail_below()
		return result

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN or bubble == null:
			return
		var bubble_size := Vector2(size.x, size.y - _tail_below())
		fit_child_in_rect(bubble, Rect2(Vector2.ZERO, bubble_size))
		if tail != null:
			tail.size = tail.custom_minimum_size
			tail.position = Vector2(bubble_size.x - tail_inset - tail.size.x, bubble_size.y - tail_overlap)

	## Height the tail adds below the bubble.
	func _tail_below() -> float:
		if tail == null or not tail.visible:
			return 0.0
		return maxf(0.0, tail.custom_minimum_size.y - tail_overlap)
