class_name TalentTreeDialog
extends VBoxContainer
## The talent tree at the candle altar (KE8, KONZEPT §6.1/§6.2, Mockup 14): a large dialog with the
## three paths Wind, Glut and Seele as candle branches, four Ebenen each, the nodes aus / verfügbar /
## gesetzt / Schlussstein, "Talentpunkte: n" at the top, the chosen talent on the right with
## "+ Punkt setzen" / "− Zurücknehmen", the spell slots with the unlocked spells, and at the bottom
## what the respec costs before anything is paid (D-196: 10 % of the points taken back in
## Seelenkristalle of the world being played, at least 1). Rules live in TalentTreeEdit.
## Input: mouse and touch click the nodes (first click chooses, a click on the chosen node sets a
## point); keyboard and gamepad move the Modal focus over the nodes (the focused node is the chosen
## one), Enter/A sets a point, Entf/Backspace/− or Y takes one back, +/X sets one, Esc/B closes.
## Closing with free changes stores them; with a fee it asks first (pay, discard, back).
## Read-only (co-op guests): the same view without any button that changes something.

signal closed(applied: bool)

const PAUSE_REASON: StringName = &"talent_tree"
const CONFIRM_PAUSE_REASON: StringName = &"talent_tree_confirm"
## Layout in mockup px (480×270): detail column, tier column, gaps.
const DETAIL_WIDTH := 104.0
const TIER_WIDTH := 30.0
const COLUMN_GAP := 6.0
const PATH_ICON := 18.0
const SPELL_ICON := 12.0
## Choices of the confirm dialog.
const CHOICE_PAY: StringName = &"pay"
const CHOICE_DISCARD: StringName = &"discard"
const CHOICE_BACK: StringName = &"back"

var edit: TalentTreeEdit = null
var modal: Modal = null
## Talent id that is chosen (detail panel, +/−).
var selected_id: StringName = &""
## Spell slot a picked spell goes to.
var selected_slot := 0
var applied := false

var _columns: Dictionary[StringName, TalentPathColumn] = {}
var _points_label: Label = null
var _crystals_label: Label = null
var _detail_name: Label = null
var _detail_path: Label = null
var _detail_level: Label = null
var _detail_desc: Label = null
var _detail_reason: Label = null
var _raise_button: Button = null
var _lower_button: Button = null
var _slots_row: HBoxContainer = null
var _spells_box: VBoxContainer = null
var _cost_label: Label = null
var _apply_button: Button = null
var _discard_button: Button = null
var _close_button: Button = null
var _confirm: Modal = null
var _layer: CanvasLayer = null


## Builds the dialog for a visit (not shown yet: show_on / open).
static func create(visit: TalentTreeEdit) -> TalentTreeDialog:
	var dialog := TalentTreeDialog.new()
	dialog.name = "TalentTree"
	dialog.edit = visit
	dialog.modal = Modal.create(PAUSE_REASON)
	dialog.modal.name = "TalentTreeModal"
	dialog.modal.content.add_child(dialog)
	dialog._build()
	return dialog


## Opens the tree for this machine's account on parent and waits until it is closed.
static func open_for_account(parent: Node, can_edit := true) -> bool:
	var dialog := create(TalentTreeEdit.for_account(can_edit))
	dialog.show_on(parent)
	return await dialog.closed


## Shows the dialog under parent (a CanvasLayer, else an own layer on top of the game).
func show_on(parent: Node) -> void:
	var host := parent
	if not (parent is CanvasLayer):
		_layer = CanvasLayer.new()
		_layer.name = "TalentTreeLayer"
		_layer.layer = 20
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		parent.add_child(_layer)
		host = _layer
	modal.show_on(host)
	if InputGlyphs.is_gamepad():
		_focus_selected.call_deferred()


func open(parent: Node) -> bool:
	show_on(parent)
	return await closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	edit.changed.connect(refresh)
	SaveManager.permanent_crystals_changed.connect(_on_crystals_changed)


func _exit_tree() -> void:
	if SaveManager.permanent_crystals_changed.is_connected(_on_crystals_changed):
		SaveManager.permanent_crystals_changed.disconnect(_on_crystals_changed)


# --- Building ---

func _build() -> void:
	add_theme_constant_override("separation", int(UiKit.px(4)))
	modal.cancel_allowed = false
	modal.input_handler = handle_input
	modal.close_action = request_close
	add_child(_header())
	if not edit.editable:
		var note := UiKit.text_label(Loc.t(&"TALENT_TREE_VIEW_ONLY"), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		note.name = "ViewOnlyNote"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(note)
	var body := UiKit.hbox(int(UiKit.px(COLUMN_GAP)))
	body.name = "Body"
	add_child(body)
	body.add_child(_tier_column())
	for talent_path in TalentDef.PATHS:
		body.add_child(_path_column(talent_path))
	var line := ColorRect.new()
	line.color = UiKit.COLOR_LINE
	line.custom_minimum_size = Vector2(UiKit.px(1), 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(line)
	body.add_child(_detail_column())
	add_child(UiKit.separator())
	add_child(_footer())
	selected_id = _first_choice()
	modal.set_key_hints(_key_entries(), true)
	refresh()


func _header() -> Control:
	var row := UiKit.hbox(int(UiKit.px(8)))
	row.name = "Header"
	var title := UiKit.title(Loc.t(&"TALENT_TREE_TITLE").to_upper(), UiKit.SIZE_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(title)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(filler)
	_points_label = UiKit.text_label("", UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
	_points_label.name = "PointsLabel"
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_points_label)
	var crystals := UiKit.icon_value(UiKit.CRYSTAL_ICON, "0", UiKit.COLOR_CRYSTAL, UiKit.SIZE_KEY_HINT, 10.0)
	crystals.name = "Crystals"
	for child in crystals.get_children():
		if child is Label:
			_crystals_label = child as Label
	row.add_child(crystals)
	return row


## "Ebene 1 … 4" with the points that open it, on the height of the node rows.
func _tier_column() -> Control:
	var column := UiKit.vbox(0)
	column.name = "Tiers"
	column.custom_minimum_size.x = UiKit.px(TIER_WIDTH)
	column.add_child(_path_header_spacer())
	for rank in range(TalentDef.MIN_RANK, TalentDef.MAX_RANK + 1):
		var cell := UiKit.vbox(0)
		cell.name = "Tier%d" % rank
		cell.custom_minimum_size.y = TalentPathColumn.row_height()
		cell.alignment = BoxContainer.ALIGNMENT_BEGIN
		var tier := UiKit.text_label(Loc.t(&"TALENT_TREE_TIER", [rank]), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT, true)
		tier.name = "TierLabel"
		cell.add_child(tier)
		var threshold := edit.get_rank_threshold(rank)
		var caption := Loc.t(&"TALENT_CAPSTONE") if rank == TalentDef.MAX_RANK else ""
		if threshold > 0:
			caption = Loc.t(&"TALENT_TREE_TIER_OPENS", [threshold]) + ("\n" + caption if not caption.is_empty() else "")
		var opens := UiKit.text_label(caption, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
		opens.name = "TierOpens"
		cell.add_child(opens)
		column.add_child(cell)
	return column


func _path_header_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.y = _path_header_height()
	return spacer


func _path_header_height() -> float:
	return UiKit.art_px(PATH_ICON, TalentTreeArt.PATH_ICON_SIZE) + UiKit.px(4)


func _path_column(talent_path: StringName) -> Control:
	var box := UiKit.vbox(0)
	box.name = "Column_%s" % talent_path
	var head := UiKit.hbox(int(UiKit.px(2)))
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.custom_minimum_size.y = _path_header_height()
	head.add_child(UiKit.pixel_icon(TalentTreeArt.path_icon(talent_path), PATH_ICON))
	var name_label := UiKit.text_label(Loc.t(TalentDef.path_name_key(talent_path)), UiKit.SIZE_KEY_HINT,
		TalentTreeArt.path_color(talent_path), true)
	name_label.name = "PathName"
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(name_label)
	box.add_child(head)
	var column := TalentPathColumn.create(talent_path, edit.tree)
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for node in column.get_nodes():
		node.pressed.connect(_on_node_pressed.bind(node.talent.id))
	_columns[talent_path] = column
	box.add_child(column)
	return box


func _detail_column() -> Control:
	var box := UiKit.vbox(int(UiKit.px(3)))
	box.name = "Detail"
	box.custom_minimum_size.x = UiKit.px(DETAIL_WIDTH)
	_detail_path = UiKit.eyebrow("")
	_detail_path.name = "DetailPath"
	box.add_child(_detail_path)
	_detail_name = UiKit.text_label("", UiKit.SIZE_HEADING, UiKit.COLOR_TEXT, true)
	_detail_name.name = "DetailName"
	box.add_child(_detail_name)
	_detail_level = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	_detail_level.name = "DetailLevel"
	box.add_child(_detail_level)
	_detail_desc = UiKit.wrapped_text("", DETAIL_WIDTH)
	_detail_desc.name = "DetailDesc"
	box.add_child(_detail_desc)
	_detail_reason = UiKit.wrapped_text("", DETAIL_WIDTH, UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_MUTED)
	_detail_reason.name = "DetailReason"
	box.add_child(_detail_reason)
	var buttons := UiKit.hbox(int(UiKit.px(3)))
	buttons.name = "PointButtons"
	_lower_button = _small_button(Loc.t(&"TALENT_TREE_LOWER"), lower_selected)
	_lower_button.name = "LowerButton"
	buttons.add_child(_lower_button)
	_raise_button = _small_button(Loc.t(&"TALENT_TREE_RAISE"), raise_selected)
	_raise_button.name = "RaiseButton"
	buttons.add_child(_raise_button)
	buttons.visible = edit.editable
	box.add_child(buttons)
	box.add_child(UiKit.separator())
	var spells_title := UiKit.eyebrow(Loc.t(&"TALENT_TREE_SPELL_SLOTS"))
	spells_title.name = "SpellsTitle"
	box.add_child(spells_title)
	_slots_row = UiKit.hbox(int(UiKit.px(3)))
	_slots_row.name = "Slots"
	box.add_child(_slots_row)
	_spells_box = UiKit.vbox(int(UiKit.px(2)))
	_spells_box.name = "Spells"
	box.add_child(_spells_box)
	return box


func _footer() -> Control:
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.name = "Footer"
	_cost_label = UiKit.text_label("", UiKit.SIZE_BODY, UiKit.COLOR_MUTED, true)
	_cost_label.name = "CostLabel"
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_cost_label)
	_discard_button = UiKit.dialog_button(Loc.t(&"TALENT_TREE_DISCARD"), "", discard)
	_discard_button.name = "DiscardButton"
	_discard_button.visible = edit.editable
	row.add_child(_discard_button)
	_apply_button = UiKit.dialog_button(Loc.t(&"TALENT_TREE_APPLY"), "", request_apply, true)
	_apply_button.name = "ApplyButton"
	_apply_button.visible = edit.editable
	row.add_child(_apply_button)
	_close_button = UiKit.dialog_button(Loc.t(&"MENU_CLOSE"), "", request_close)
	_close_button.name = "CloseButton"
	row.add_child(_close_button)
	return row


func _small_button(text: String, on_pressed: Callable) -> Button:
	var button := UiKit.button(text, on_pressed)
	button.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_BODY))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = maxf(UiKit.px(14), UiKit.touch_button_height())
	return button


func _key_entries() -> Array:
	var entries: Array = [[Loc.t(&"MENU_KEY_ENTER"), Loc.t(&"TALENT_TREE_KEY_RAISE")]]
	if edit.editable:
		entries.append([Loc.t(&"TALENT_TREE_KEY_LOWER_CAP"), Loc.t(&"TALENT_TREE_KEY_LOWER")])
	else:
		entries = [[Loc.t(&"MENU_KEY_ARROWS"), Loc.t(&"MENU_HINT_MOVE")]]
	entries.append([Loc.t(&"MENU_KEY_ESC"), Loc.t(&"MENU_HINT_CLOSE")])
	return entries


## The first node that takes a point now, else the first node of the tree.
func _first_choice() -> StringName:
	for talent in edit.tree.talents:
		if talent != null and edit.can_raise(talent.id):
			return talent.id
	return edit.tree.talents[0].id if not edit.tree.talents.is_empty() else &""


# --- State to view ---

## Redraws everything from the visit (after every change).
func refresh() -> void:
	if _points_label == null:
		return
	_points_label.text = Loc.t(&"TALENT_TREE_POINTS", [edit.get_free_points()])
	if _crystals_label != null:
		_crystals_label.text = str(edit.get_crystals())
	for talent_path in _columns:
		var column := _columns[talent_path]
		var open_rank := 0
		for rank in range(TalentDef.MIN_RANK, TalentDef.MAX_RANK + 1):
			if edit.is_rank_open(talent_path, rank):
				open_rank = rank
		column.open_rank = open_rank
		column.queue_redraw()
		for node in column.get_nodes():
			node.set_view(edit.get_node_state(node.talent.id), edit.get_level(node.talent.id), node.talent.id == selected_id)
	_refresh_detail()
	_refresh_spells()
	_refresh_footer()


func _refresh_detail() -> void:
	var talent := edit.tree.get_talent(selected_id)
	if talent == null:
		return
	var tier := Loc.t(&"TALENT_TREE_TIER", [talent.rank])
	if talent.is_capstone():
		tier = Loc.t(&"TALENT_CAPSTONE")
	_detail_path.text = ("%s · %s" % [Loc.t(TalentDef.path_name_key(talent.path)), tier]).to_upper()
	_detail_path.add_theme_color_override("font_color", TalentTreeArt.path_color(talent.path))
	_detail_name.text = talent.get_display_name()
	_detail_level.text = Loc.t(&"TALENT_TREE_LEVEL", [edit.get_level(talent.id), talent.max_level])
	var description := talent.get_description()
	if talent.unlocks_spell():
		description += "\n" + SpellBook.description(talent.spell)
	_detail_desc.text = description
	_detail_reason.text = reason_text(edit.raise_reason(talent.id), talent)
	_raise_button.disabled = not edit.can_raise(talent.id)
	_lower_button.disabled = not edit.can_lower(talent.id)


## Why the chosen talent takes no point right now (empty when it does).
func reason_text(reason: TalentTreeEdit.Reason, talent: TalentDef) -> String:
	match reason:
		TalentTreeEdit.Reason.LOCKED:
			return Loc.t(&"TALENT_TREE_LOCKED", [edit.get_rank_threshold(talent.rank)])
		TalentTreeEdit.Reason.NO_POINTS:
			return Loc.t(&"TALENT_TREE_NO_POINTS")
		TalentTreeEdit.Reason.FULL:
			return Loc.t(&"TALENT_TREE_FULL")
	return ""


func _refresh_spells() -> void:
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	for child in _spells_box.get_children():
		_spells_box.remove_child(child)
		child.queue_free()
	var slots := edit.get_spell_slots()
	selected_slot = clampi(selected_slot, 0, maxi(0, slots - 1))
	if slots == 0:
		var hint := UiKit.wrapped_text(Loc.t(&"TALENT_TREE_NO_SPELL"), DETAIL_WIDTH, UiKit.SIZE_EYEBROW + 1, UiKit.COLOR_MUTED)
		hint.name = "NoSpellHint"
		_spells_box.add_child(hint)
		return
	for slot in slots:
		_slots_row.add_child(_slot_button(slot))
	for spell in edit.get_unlocked_spells():
		_spells_box.add_child(_spell_button(spell))


func _slot_button(slot: int) -> Button:
	var spell := edit.get_equipped_spell(slot)
	var caption := Loc.t(&"TALENT_TREE_SLOT", [slot + 1])
	var button := _small_button(caption, _on_slot_pressed.bind(slot))
	button.name = "Slot%d" % (slot + 1)
	button.icon = UiKit.upscale(SpellArt.icon(spell) if spell != &"" else SpellArt.slot_frame(), UiKit.ART_SCALE)
	button.expand_icon = false
	button.tooltip_text = SpellBook.display_name(spell) if spell != &"" else Loc.t(&"TALENT_TREE_SLOT_EMPTY")
	if slot == selected_slot and edit.get_spell_slots() > 1:
		button.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	button.disabled = not edit.editable and spell == &""
	return button


func _spell_button(spell: StringName) -> Button:
	var button := _small_button(SpellBook.display_name(spell), _on_spell_pressed.bind(spell))
	button.name = "Spell_%s" % spell
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = UiKit.upscale(SpellArt.icon(spell), 2)
	button.tooltip_text = SpellBook.description(spell)
	var slot := -1
	for index in edit.get_spell_slots():
		if edit.get_equipped_spell(index) == spell:
			slot = index
	if slot >= 0:
		button.text += "  · " + Loc.t(&"TALENT_TREE_SLOT", [slot + 1])
		button.add_theme_color_override("font_color", UiKit.COLOR_GOLD)
	button.disabled = not edit.editable
	return button


func _refresh_footer() -> void:
	var cost := edit.get_cost()
	if not edit.editable:
		_cost_label.text = ""
	elif cost > 0:
		var key := &"TALENT_TREE_COST_ONE" if cost == 1 else &"TALENT_TREE_COST"
		_cost_label.text = Loc.t(key, [cost])
		if not edit.can_afford():
			_cost_label.text += " · " + Loc.t(&"TALENT_TREE_COST_MISSING", [edit.get_crystals()])
		_cost_label.add_theme_color_override("font_color", UiKit.COLOR_CRYSTAL if edit.can_afford() else UiKit.COLOR_DANGER_SOFT)
	else:
		_cost_label.text = Loc.t(&"TALENT_TREE_COST_FREE")
		_cost_label.add_theme_color_override("font_color", UiKit.COLOR_MUTED)
	_apply_button.disabled = not edit.can_apply()
	_discard_button.disabled = not edit.is_dirty()


# --- Actions ---

## Chooses a node; choosing the chosen one again sets a point (mouse and touch: two taps).
func choose(id: StringName) -> void:
	if id == selected_id:
		raise_selected()
		return
	selected_id = id
	refresh()


func raise_selected() -> bool:
	if not edit.raise(selected_id):
		if edit.editable:
			UiSound.error(self)
		return false
	Sfx.play_ui(self, &"upgrade")
	_bump_selected()
	return true


func lower_selected() -> bool:
	if not edit.lower(selected_id):
		if edit.editable:
			UiSound.error(self)
		return false
	Sfx.play_ui(self, &"ui_back")
	return true


func discard() -> void:
	edit.discard()


## Stores the changes; with a fee it shows the cost first and asks.
func request_apply() -> void:
	if not edit.can_apply():
		UiSound.error(self)
		return
	if edit.get_cost() > 0:
		var choice: StringName = await _ask_respec(false)
		if choice != CHOICE_PAY:
			return
	_apply()


## Esc, B, "Schließen" and the X: free changes are stored, a fee asks first.
func request_close() -> void:
	if _confirm != null:
		return
	if edit.editable and edit.is_dirty():
		if edit.get_cost() > 0:
			var choice: StringName = await _ask_respec(true)
			if choice == CHOICE_BACK:
				return
			if choice == CHOICE_PAY and not _apply():
				return
			if choice == CHOICE_DISCARD:
				edit.discard()
		elif not _apply():
			return
	close()


func close() -> void:
	if modal != null and is_instance_valid(modal):
		modal.finish(applied)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	closed.emit(applied)


func _apply() -> bool:
	if not edit.apply():
		UiSound.error(self)
		return false
	applied = true
	Sfx.play_ui(self, &"ui_confirm")
	return true


func _on_node_pressed(id: StringName) -> void:
	choose(id)


func _on_slot_pressed(slot: int) -> void:
	if not edit.editable:
		return
	if slot == selected_slot:
		edit.unequip_spell(slot)
	else:
		selected_slot = slot
		refresh()


func _on_spell_pressed(spell: StringName) -> void:
	if edit.equip_spell(spell, selected_slot):
		Sfx.play_ui(self, &"ui_toggle")


func _on_crystals_changed(_amount: int) -> void:
	refresh()


func _bump_selected() -> void:
	var node := get_node_button(selected_id)
	if node != null:
		UiKit.bump(node, 1.15, 0.15)


# --- Input ---

## Keys and gamepad buttons the Modal does not know (called first by Modal._unhandled_input).
func handle_input(event: InputEvent) -> bool:
	if _confirm != null:
		# The question on top answers; nothing below changes meanwhile.
		return true
	if event.is_action_pressed(&"ui_cancel"):
		request_close()
		return true
	if MenuInput.is_pad_button(event, JOY_BUTTON_Y) or _is_key(event, [KEY_DELETE, KEY_BACKSPACE, KEY_MINUS, KEY_KP_SUBTRACT]):
		lower_selected()
		return true
	if MenuInput.is_pad_button(event, JOY_BUTTON_X) or _is_key(event, [KEY_PLUS, KEY_KP_ADD, KEY_EQUAL]):
		raise_selected()
		return true
	return false


static func _is_key(event: InputEvent, keys: Array) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and keys.has(key.keycode)


## The gamepad/keyboard focus chooses the node it is on (A then sets a point right away).
func _process(_delta: float) -> void:
	if modal == null or not is_instance_valid(modal):
		return
	var focused := modal.get_focused_button() as TalentNodeButton
	if focused != null and focused.talent.id != selected_id:
		selected_id = focused.talent.id
		refresh()


func _focus_selected() -> void:
	var node := get_node_button(selected_id)
	if node != null and modal != null and is_instance_valid(modal):
		modal.focus_button(node)


# --- Confirm ---

## "Umskillen?": what is taken back, what it costs and what the player has. on_close adds
## "Verwerfen" (close without the changes). Returns CHOICE_PAY, CHOICE_DISCARD or CHOICE_BACK.
func _ask_respec(on_close: bool) -> StringName:
	_confirm = Modal.create(CONFIRM_PAUSE_REASON)
	_confirm.name = "RespecConfirm"
	_confirm.cancel_result = CHOICE_BACK
	_confirm.content.add_child(UiKit.title(Loc.t(&"TALENT_TREE_CONFIRM_TITLE")))
	var text := UiKit.wrapped_text(Loc.t(&"TALENT_TREE_CONFIRM_TEXT",
		[edit.get_refunded_points(), edit.get_cost(), edit.get_crystals()]), 200.0, UiKit.SIZE_BODY)
	text.name = "ConfirmText"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.content.add_child(text)
	var row := UiKit.hbox(int(UiKit.px(4)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var confirm := _confirm
	var pay := UiKit.dialog_button(Loc.t(&"TALENT_TREE_PAY_CLOSE" if on_close else &"TALENT_TREE_PAY"),
		Loc.t(&"TALENT_TREE_COST_ONE" if edit.get_cost() == 1 else &"TALENT_TREE_COST", [edit.get_cost()]),
		func() -> void: confirm.finish(CHOICE_PAY), true)
	pay.name = "PayButton"
	pay.set_meta(Modal.META_PAD_OPTION, true)
	pay.set_meta(Modal.META_PAD_DEFAULT, true)
	row.add_child(pay)
	if on_close:
		var drop := UiKit.dialog_button(Loc.t(&"TALENT_TREE_DISCARD"), "", func() -> void: confirm.finish(CHOICE_DISCARD))
		drop.name = "DiscardButton"
		drop.set_meta(Modal.META_PAD_OPTION, true)
		row.add_child(drop)
	var back := UiKit.dialog_button(Loc.t(&"COMMON_BACK"), "", func() -> void: confirm.finish(CHOICE_BACK))
	back.name = "BackButton"
	back.set_meta(Modal.META_PAD_OPTION, true)
	row.add_child(back)
	_confirm.content.add_child(row)
	var parent := modal.get_parent() if modal.get_parent() != null else self
	var result: Variant = await _confirm.open(parent)
	_confirm = null
	return result if result is StringName else CHOICE_BACK


## The open "Umskillen?" question (null if none), for tests and tools.
func get_confirm() -> Modal:
	return _confirm


# --- Lookups for tests and tools ---

func get_node_button(id: StringName) -> TalentNodeButton:
	for column in _columns.values():
		for node in (column as TalentPathColumn).get_nodes():
			if node.talent.id == id:
				return node
	return null


func get_column(talent_path: StringName) -> TalentPathColumn:
	return _columns.get(talent_path)


func get_points_text() -> String:
	return _points_label.text if _points_label != null else ""


func get_cost_text() -> String:
	return _cost_label.text if _cost_label != null else ""


func get_apply_button() -> Button:
	return _apply_button


func get_raise_button() -> Button:
	return _raise_button


func get_lower_button() -> Button:
	return _lower_button
