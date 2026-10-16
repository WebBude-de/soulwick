class_name CreateSlotPanel
extends MenuPanel
## "Neue Welt" (D-152): a save slot is a world. Only its name is chosen here (empty = "Welt <n>");
## the figure is the player's profile and comes along into every world (shown small with a hint).
## Enter starts, Esc goes back. Typing ticks softly (UiSound). A new world has seen nothing, so the
## village explains itself (D-087). Texts are translation keys (D-111).

signal confirmed(slot: int, world_name: String)

## Sizes in mockup pixels.
const WIDTH := 236.0
const PREVIEW_SCALE := 3
const FOOTER: StringName = &"CREATE_FOOTER"

var slot := 1

var _name_edit: LineEdit = null
var _last_name_length := 0
var _start_button: Button = null
var _preview: CharacterPreview = null


static func create(target_slot: int) -> CreateSlotPanel:
	var panel := CreateSlotPanel.new()
	panel.slot = target_slot
	return panel


func _ready() -> void:
	set_width(WIDTH)
	add_header(tr(&"SLOTS_SLOT_NUMBER") % slot, &"CREATE_TITLE")

	var caption := UiKit.eyebrow(&"CREATE_NAME", UiKit.COLOR_GOLD)
	caption.uppercase = true
	content.add_child(caption)
	_name_edit = LineEdit.new()
	_name_edit.name = "WorldName"
	_name_edit.max_length = SaveSlots.NAME_MAX_LENGTH
	_name_edit.placeholder_text = SaveSlots.default_name(slot)
	_name_edit.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_CARD_NAME))
	_name_edit.add_theme_color_override("font_color", UiKit.COLOR_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", UiKit.COLOR_DISABLED)
	_name_edit.add_theme_color_override("caret_color", UiKit.COLOR_GOLD)
	_name_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_name_edit.add_theme_stylebox_override("normal", UiKit.padded_style(&"gold", 3, 5))
	_name_edit.text_submitted.connect(func(_text: String) -> void: confirm())
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_change_rejected.connect(func(_rejected: String) -> void: UiSound.error(self))
	content.add_child(_name_edit)

	# The player's figure comes along (D-152: one figure for every world).
	var who := UiKit.hbox(int(UiKit.px(6)))
	who.name = "Figure"
	_preview = CharacterPreview.create(PREVIEW_SCALE)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(_preview)
	_preview.set_look(PlayerProfile.current().look)
	var lines := UiKit.vbox(int(UiKit.px(1)))
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_child(UiKit.text_label(PlayerProfile.current().get_display_name(), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true))
	lines.add_child(UiKit.wrapped_text(tr(&"CREATE_FIGURE_HINT"), WIDTH - 60.0, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED))
	who.add_child(lines)
	content.add_child(who)

	var actions := UiKit.hbox(int(UiKit.px(6)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_start_button = MenuPanel.action_button(&"CREATE_START", "Enter", confirm, true)
	actions.add_child(_start_button)
	actions.add_child(MenuPanel.action_button(&"COMMON_BACK", "Esc", close))
	content.add_child(actions)
	set_footer(FOOTER)
	_name_edit.grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _start_button != null:
		set_header(tr(&"SLOTS_SLOT_NUMBER") % slot, tr(&"CREATE_TITLE"))


## World name as it will be saved (trimmed, "Welt <n>" when empty).
func get_world_name() -> String:
	return SaveSlots.sanitize_name(_name_edit.text, slot)


func set_world_name(text: String) -> void:
	_name_edit.text = text
	_last_name_length = text.length()


## Older tools (screenshots, scene gallery) still name the slot this way.
func set_profile_name(text: String) -> void:
	set_world_name(text)


func confirm() -> void:
	UiSound.play(self, UiSound.CONFIRM)
	confirmed.emit(slot, get_world_name())


## The name field gets keys before the menu: Enter and Esc are taken here so typing (also W/A/S/D
## and Space) stays in the field.
func _input(event: InputEvent) -> void:
	if _name_edit == null or not _name_edit.has_focus():
		return
	if MenuInput.is_enter(event):
		get_viewport().set_input_as_handled()
		confirm()
	elif MenuInput.is_back(event):
		get_viewport().set_input_as_handled()
		close()


func handle_input(event: InputEvent) -> bool:
	if MenuInput.is_back(event):
		close()
		return true
	if MenuInput.is_accept(event):
		confirm()
		return true
	if MenuInput.is_up(event) or MenuInput.is_down(event):
		_name_edit.grab_focus()
		return true
	return false


func _on_name_changed(text: String) -> void:
	var length := text.length()
	UiSound.type_key(self, length < _last_name_length)
	_last_name_length = length
