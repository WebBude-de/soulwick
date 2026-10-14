class_name RoomIntroCard
extends PanelContainer
## First-time explanation of a room genre (D-110, UX2): small dark card on the left edge, in the
## look and place of the first-run controls card (ControlsHint). Eyebrow "NEU: ARENA" with the
## genre symbol, one or two sentences, a thin bar that runs down while it stays. Never pauses the
## game; it pauses with it (PROCESS_MODE_PAUSABLE), so a dialog never eats it. DungeonUI decides
## when it appears (one teaching card at a time) and marks the genre as seen.

signal finished

## Width and margins in mockup pixels (ControlsHint: 124 wide; explanations need a bit more room).
const WIDTH := 150.0
const EDGE_MARGIN := 8.0
const ICON_SIZE := 12.0
const BAR_HEIGHT := 1.0
## Time on screen: base plus reading time per character, clamped (TESTWERTE).
const BASE_TIME := 4.0
const TIME_PER_CHAR := 0.045
const MIN_TIME := 6.0
const MAX_TIME := 13.0

var genre: StringName = RoomGenre.NONE
var _duration := MIN_TIME
var _left := MIN_TIME
var _bar: ProgressBar = null
var _finishing := false


## Card for a genre (texts and symbol from RoomGenre).
static func create(for_genre: StringName) -> RoomIntroCard:
	var card := RoomIntroCard.new()
	card.genre = for_genre
	card.name = "RoomIntro_%s" % for_genre
	return card


## Seconds a text of this length stays on screen.
static func duration_for(text: String) -> float:
	return clampf(BASE_TIME + text.length() * TIME_PER_CHAR, MIN_TIME, MAX_TIME)


func _ready() -> void:
	theme = UiKit.get_theme()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 5, 6))
	custom_minimum_size.x = UiKit.px(WIDTH)
	var color := RoomGenre.get_color(genre)
	var box := UiKit.vbox(int(UiKit.px(3)))
	add_child(box)
	var head := UiKit.hbox(int(UiKit.px(3)))
	box.add_child(head)
	var icon_texture := RoomGenre.get_icon(genre)
	if icon_texture != null:
		var icon := UiKit.pixel_icon(icon_texture, ICON_SIZE)
		if RoomGenre.is_icon_tinted(genre):
			icon.modulate = color
		head.add_child(icon)
	var eyebrow := UiKit.eyebrow(DungeonTexts.t(&"ROOM_INTRO_EYEBROW", [RoomGenre.get_title(genre)]), color)
	eyebrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(eyebrow)
	var text := RoomGenre.get_intro(genre)
	box.add_child(UiKit.wrapped_text(text, WIDTH - 12.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT))
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size.y = maxf(1.0, UiKit.px(BAR_HEIGHT))
	_bar.add_theme_stylebox_override("fill", UiKit.bar_style(Color(color, 0.8)))
	_bar.add_theme_stylebox_override("background", UiKit.bar_style(UiKit.COLOR_SHADOW))
	box.add_child(_bar)
	_duration = duration_for(text)
	_left = _duration
	minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _process(delta: float) -> void:
	if _finishing:
		return
	_left -= delta
	_bar.value = clampf(_left / _duration, 0.0, 1.0)
	if _left <= 0.0:
		finish()


func get_duration() -> float:
	return _duration


## Fades out and frees itself.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	finished.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


## Left edge, vertically centred, like the controls card.
func _layout() -> void:
	var own := get_combined_minimum_size()
	size = own
	position = Vector2(UiKit.px(EDGE_MARGIN), floorf((get_viewport_rect().size.y - own.y) * 0.5))
