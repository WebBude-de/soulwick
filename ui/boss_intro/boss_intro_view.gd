class_name BossIntroView
extends CanvasLayer
## Presentation of the boss intro: darkened scene with a vignette in the boss colour, letterbox
## bars, a dialog in the lower third (portrait, name, trembling text typed letter by letter),
## babble sounds per syllable and the roar with a camera jolt at the end. Child of a BossIntro,
## reacts only to its signals; no game logic here. Measurements in mockup pixels (UiKit.px).
## The story intro (first encounter) also shows the line counter, how to page and skip, and a thin
## bar that fills while a skip key is held.

## Below DungeonUI (20): banners, hint cards and dialogs stay on top; above HUD (5) and vision (2).
const LAYER := 19
## TESTWERTE (look).
const DIM_ALPHA := 0.42
const VIGNETTE_ALPHA := 0.9
const BAR_HEIGHT := 18.0
const DIALOG_WIDTH := 292.0
const DIALOG_BOTTOM := 30.0
const PORTRAIT_SIZE := 48.0
const SPEECH_HEIGHT := 24.0
## Story lines are longer: room for two rows, so the dialog does not jump between lines.
const STORY_SPEECH_HEIGHT := 30.0
const HOLD_BAR_HEIGHT := 1.5
## Key hints (D-098 extension): tap pages, hold skips the whole story.
## Translation keys (D-111): the hint label gets the key, Godot translates it.
const SHORT_HINT: StringName = &"BOSS_INTRO_SKIP_HINT"
const STORY_HINT: StringName = &"BOSS_INTRO_STORY_HINT"
## The same hints with the gamepad's buttons while a gamepad is in use (D-192).
const SHORT_HINT_PAD: StringName = &"BOSS_INTRO_SKIP_HINT_PAD"
const STORY_HINT_PAD: StringName = &"BOSS_INTRO_STORY_HINT_PAD"
const KeyLine := preload("res://ui/widgets/key_line.gd")
const START_SHAKE := 3.0
const ROAR_SHAKE := 9.0
const PULSE_SCALE := 1.08
const BREATHE_SPEED := 2.6

var _intro: BossIntro = null
var _data: EnemyData = null
var _root: Control = null
var _dim: ColorRect = null
var _vignette: TextureRect = null
var _flash: ColorRect = null
var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null
var _dialog: Control = null
var _portrait: Control = null
var _speech: RichTextLabel = null
var _counter: Label = null
var _hold_bar: ProgressBar = null
var _time := 0.0


func _ready() -> void:
	layer = LAYER
	_intro = get_parent() as BossIntro
	if _intro == null or _intro.data == null:
		queue_free()
		return
	_data = _intro.data
	_build()
	_intro.line_started.connect(_on_line_started)
	_intro.characters_revealed.connect(_on_characters_revealed)
	_intro.syllable_spoken.connect(_on_syllable_spoken)
	_intro.hold_progress.connect(_on_hold_progress)
	_intro.ending.connect(_on_ending)
	_fade_in()


func _process(delta: float) -> void:
	_time += delta
	if _vignette != null:
		# Slow breathing of the darkness.
		_vignette.modulate.a = VIGNETTE_ALPHA * (0.85 + 0.15 * sin(_time * BREATHE_SPEED))


# --- Building ---

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.get_theme()
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(UiKit.COLOR_BG, DIM_ALPHA)
	_fill(_dim)

	_vignette = TextureRect.new()
	_vignette.texture = _vignette_texture(_data.intro_color)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_fill(_vignette)

	_flash = ColorRect.new()
	_flash.color = Color(_data.intro_color, 0.0)
	_fill(_flash)

	_top_bar = _bar(true)
	_bottom_bar = _bar(false)
	_dialog = _build_dialog()
	_root.add_child(_dialog)


func _fill(rect: Control) -> void:
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)


func _bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = UiKit.COLOR_BG
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0 if top else 1.0
	bar.anchor_bottom = bar.anchor_top
	var height := UiKit.px(BAR_HEIGHT)
	bar.offset_top = 0.0 if top else -height
	bar.offset_bottom = height if top else 0.0
	_root.add_child(bar)
	return bar


func _build_dialog() -> Control:
	var panel := UiKit.panel(&"dark")
	panel.name = "Dialog"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(UiKit.px(DIALOG_WIDTH), 0.0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -UiKit.px(DIALOG_WIDTH) * 0.5
	panel.offset_right = UiKit.px(DIALOG_WIDTH) * 0.5
	panel.offset_top = -UiKit.px(DIALOG_BOTTOM)
	panel.offset_bottom = -UiKit.px(DIALOG_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var row := UiKit.hbox(int(UiKit.px(8)))
	panel.add_child(row)
	_portrait = _build_portrait()
	row.add_child(_portrait)

	var column := UiKit.vbox(int(UiKit.px(1)))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var eyebrow := UiKit.eyebrow("Boss", _data.intro_color.lerp(UiKit.COLOR_MUTED, 0.45))
	column.add_child(eyebrow)
	var tier := _intro.boss.get_boss_tier() if _intro.boss != null and is_instance_valid(_intro.boss) else 0
	var title := UiKit.text_label(BossRules.boss_title(_data.display_name, tier), UiKit.SIZE_TITLE, _data.intro_color, true)
	column.add_child(title)
	_speech = _build_speech()
	column.add_child(_speech)
	column.add_child(_build_hint_row())
	if _intro.is_story:
		_hold_bar = _build_hold_bar()
		column.add_child(_hold_bar)
	return panel


## Short intro: one hint on the right. Story intro: "2/6" on the left, paging and skipping on the right.
func _build_hint_row() -> Control:
	var row := UiKit.hbox(int(UiKit.px(6)))
	row.name = "HintRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _intro.is_story:
		_counter = UiKit.text_label(counter_text(1, _intro.lines.size()), UiKit.SIZE_EYEBROW, _data.intro_color.lerp(UiKit.COLOR_DISABLED, 0.5))
		_counter.name = "Counter"
		row.add_child(_counter)
	# Keyboard text as the Label "Hint", the gamepad's buttons while a gamepad is in use (KeyLine);
	# touch keeps the keyboard text as before.
	var hint := KeyLine.new()
	hint.name = "HintLine"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.setup(UiKit.SIZE_EYEBROW, UiKit.COLOR_DISABLED, HORIZONTAL_ALIGNMENT_RIGHT)
	hint.label.name = "Hint"
	var text := STORY_HINT if _intro.is_story else SHORT_HINT
	hint.set_texts(text, STORY_HINT_PAD if _intro.is_story else SHORT_HINT_PAD)
	hint.set_touch_text(text)
	row.add_child(hint)
	return row


## Fills while a skip key is held (story intro); empty and invisible otherwise.
func _build_hold_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "HoldBar"
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(0.0, UiKit.px(HOLD_BAR_HEIGHT))
	var background := StyleBoxFlat.new()
	background.bg_color = Color(UiKit.COLOR_LINE, 0.6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _data.intro_color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.modulate.a = 0.0
	return bar


static func counter_text(line: int, total: int) -> String:
	return "%d/%d" % [line, total]


func _build_portrait() -> Control:
	var frame := UiKit.panel(&"normal")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var texture := EnemyArt.get_portrait(_data)
	var content: Control
	if texture != null:
		content = UiKit.pixel_icon(texture, PORTRAIT_SIZE)
	else:
		# No art yet: a tinted placeholder square (SPRITES naming convention fills it later).
		var square := ColorRect.new()
		square.color = _data.placeholder_color.darkened(0.25)
		square.custom_minimum_size = Vector2.ONE * UiKit.art_px(PORTRAIT_SIZE)
		square.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = square
	content.name = "Portrait"
	frame.add_child(content)
	return frame


func _build_speech() -> RichTextLabel:
	var speech := RichTextLabel.new()
	speech.name = "Speech"
	speech.bbcode_enabled = true
	speech.scroll_active = false
	speech.fit_content = false
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech.custom_minimum_size = Vector2(0.0, UiKit.px(STORY_SPEECH_HEIGHT if _intro.is_story else SPEECH_HEIGHT))
	speech.add_theme_font_override("normal_font", UiKit.get_font())
	speech.add_theme_font_size_override("normal_font_size", UiKit.font_px(UiKit.SIZE_VALUE))
	speech.add_theme_color_override("default_color", UiKit.COLOR_TEXT.lerp(_data.intro_color, 0.25))
	speech.add_theme_color_override("font_shadow_color", UiKit.COLOR_SHADOW)
	speech.add_theme_constant_override("shadow_offset_x", UiKit.SHADOW_OFFSET)
	speech.add_theme_constant_override("shadow_offset_y", UiKit.SHADOW_OFFSET)
	speech.visible_characters = 0
	return speech


## Radial darkness towards the edges, tinted a little with the boss colour.
static func _vignette_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	var edge := UiKit.COLOR_BG.lerp(color, 0.12)
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(edge, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(UiKit.COLOR_BG, 0.95))
	gradient.add_point(0.45, Color(edge, 0.0))
	gradient.add_point(0.8, Color(edge, 0.6))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 128
	texture.height = 72
	return texture


## Spoken line with the boss's trembling / wavering (BBCode effects of RichTextLabel).
static func speech_bbcode(data: EnemyData, line: String) -> String:
	var text := line.replace("[", "[lb]")
	if data.intro_wave > 0.0:
		text = "[wave amp=%.1f freq=4.0 connected=1]%s[/wave]" % [data.intro_wave, text]
	if data.intro_shake > 0.0:
		text = "[shake rate=18.0 level=%.1f connected=1]%s[/shake]" % [data.intro_shake, text]
	return text


# --- Reactions ---

func _fade_in() -> void:
	_root.modulate.a = 0.0
	var bar_height := UiKit.px(BAR_HEIGHT)
	_top_bar.position.y = -bar_height
	_bottom_bar.position.y = _root.get_viewport_rect().size.y
	var time := BossIntroRules.FADE_IN_TIME
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_root, "modulate:a", 1.0, time)
	tween.tween_property(_top_bar, "position:y", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bottom_bar, "position:y", _root.get_viewport_rect().size.y - bar_height, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _intro.boss != null and is_instance_valid(_intro.boss):
		CameraShake.shake(_intro.boss, START_SHAKE)


func _on_line_started(index: int, text: String) -> void:
	_speech.text = speech_bbcode(_data, text)
	_speech.visible_characters = 0
	if _counter != null:
		_counter.text = counter_text(index + 1, _intro.lines.size())


func _on_hold_progress(ratio: float) -> void:
	if _hold_bar == null:
		return
	_hold_bar.value = ratio
	_hold_bar.modulate.a = 1.0 if ratio > 0.0 else 0.0


func _on_characters_revealed(_index: int, count: int) -> void:
	_speech.visible_characters = count


func _on_syllable_spoken(_index: int, _char_index: int, variant: int) -> void:
	var sound := BossIntroRules.babble_sound(_data, variant)
	if sound != &"":
		Sfx.play_ui(self, sound, _data.intro_voice_db)
	_pulse_portrait()
	if _intro.boss != null and is_instance_valid(_intro.boss):
		_intro.boss.intro_speak_pulse()


func _pulse_portrait() -> void:
	if _portrait == null:
		return
	_portrait.pivot_offset = _portrait.size * 0.5
	var tween := _portrait.create_tween()
	tween.tween_property(_portrait, "scale", Vector2.ONE * PULSE_SCALE, 0.04)
	tween.tween_property(_portrait, "scale", Vector2.ONE, 0.09)


func _on_ending(_skipped: bool) -> void:
	Sfx.play_ui(self, &"boss_roar")
	if _intro.boss != null and is_instance_valid(_intro.boss):
		CameraShake.shake(_intro.boss, ROAR_SHAKE)
	var time := BossIntroRules.FADE_OUT_TIME
	_flash.color.a = 0.35 * GameOptions.get_flash_strength()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_flash, "color:a", 0.0, time)
	tween.tween_property(_root, "modulate:a", 0.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_top_bar, "position:y", -UiKit.px(BAR_HEIGHT), time)
	tween.tween_property(_bottom_bar, "position:y", _root.get_viewport_rect().size.y, time)
	tween.tween_property(_dialog, "position:y", _dialog.position.y + UiKit.px(12), time)
