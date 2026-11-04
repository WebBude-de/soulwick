class_name DecorCatalogDialog
extends RefCounted
## Catalog of the decorating mode (WK5, WK7): the Lager (what was bought and is not standing) and the
## shop by group, for the home with a style filter (Gemütlich, Rustikal, Seele) and the wallpaper and
## floor styles. A card shows the picture, the name and "Im Lager: 2", the price or the gold still
## missing; choosing a stored piece (or buying one) closes the dialog with its id, the editor then
## holds it. Wallpaper and floor are bought and put up right here. The head shows the gold and the
## collection ("Sammlung 12 / 150", the collecting incentive). Buttons work with mouse, touch and the
## gamepad focus of the Modal. Prices: DecorCatalog (TESTWERT).

const PAUSE_REASON: StringName = &"decor_catalog"
## Id of the Lager tab (no catalog group is called like it).
const STORAGE_TAB := "_lager"
const ALL_STYLES := ""
## Mockup px: dialog width, card size, columns, list height.
const WIDTH := 300.0
const COLUMNS := 5
const CARD_SIZE := Vector2(54, 58)
const PICTURE_SIZE := 30.0
const LIST_HEIGHT := 150.0
const TAB_COLUMNS := 7

var space: StringName = &""
var tab := STORAGE_TAB
var style_filter := ALL_STYLES
var modal: Modal = null
var _body: VBoxContainer = null


## Opens the catalog under parent; returns the id to hold ("" = closed without choosing).
static func open(parent: Node, catalog_space: StringName) -> String:
	var dialog := DecorCatalogDialog.new()
	dialog.space = catalog_space
	if DecorState.stored_ids(catalog_space).is_empty():
		var groups := DecorCatalog.groups_for(catalog_space)
		dialog.tab = groups[0] if not groups.is_empty() else STORAGE_TAB
	var result: Variant = await dialog.show(parent)
	return String(result) if typeof(result) == TYPE_STRING else ""


func show(parent: Node) -> Variant:
	modal = Modal.create(PAUSE_REASON)
	modal.name = "DecorCatalogModal"
	modal.set_width(WIDTH)
	_body = UiKit.vbox(int(UiKit.px(3)))
	_body.name = "Body"
	modal.content.add_child(_body)
	rebuild()
	return await modal.open(parent)


## Builds the content for the current tab and filter.
func rebuild() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_body.add_child(_head())
	_body.add_child(_tabs())
	if space == DecorCatalog.HOME and tab != STORAGE_TAB and tab != DecorCatalog.SURFACE_GROUP:
		_body.add_child(_style_row())
	var scroll := ScrollContainer.new()
	scroll.name = "ListScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, UiKit.px(LIST_HEIGHT))
	scroll.follow_focus = true
	_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Cards"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", int(UiKit.px(3)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(3)))
	scroll.add_child(grid)
	var items := shown_items()
	for item in items:
		grid.add_child(_card(item))
	if items.is_empty():
		var empty := UiKit.text_label(Loc.t(&"DECOR_STORAGE_EMPTY"), UiKit.SIZE_BODY, UiKit.COLOR_MUTED)
		empty.name = "EmptyLabel"
		grid.add_child(empty)
	var close := UiKit.dialog_button(Loc.t(&"MENU_CLOSE"), "", func() -> void: modal.finish(""))
	close.name = "CloseButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(close)


## Items of the current tab and style filter.
func shown_items() -> Array[DecorItem]:
	var list: Array[DecorItem] = []
	if tab == STORAGE_TAB:
		for id in DecorState.stored_ids(space):
			list.append(DecorCatalog.get_item(id))
		return list
	for item in DecorCatalog.items_for(space, tab):
		if style_filter == ALL_STYLES or item.style == style_filter or item.style.is_empty():
			list.append(item)
	return list


func _head() -> Control:
	var head := UiKit.hbox(int(UiKit.px(4)))
	head.name = "Head"
	var title := UiKit.title(Loc.t(&"DECOR_TITLE_VILLAGE" if space == DecorCatalog.VILLAGE else &"DECOR_TITLE_HOME"), UiKit.SIZE_HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var collection := DecorState.collection(space)
	var count := UiKit.text_label(Loc.t(&"DECOR_COLLECTION", [collection.x, collection.y]), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
	count.name = "Collection"
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if space == DecorCatalog.HOME:
		var tips := PackedStringArray()
		for style in DecorCatalog.STYLES:
			var owned := DecorState.style_collection(style)
			tips.append("%s %d / %d" % [DecorCatalog.style_name(style), owned.x, owned.y])
		count.tooltip_text = " · ".join(tips)
		count.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(count)
	var gold := UiKit.icon_value(UiKit.GOLD_ICON, str(SaveManager.get_permanent_gold()))
	gold.name = "Gold"
	head.add_child(gold)
	return head


func _tabs() -> Control:
	var tabs := GridContainer.new()
	tabs.name = "Tabs"
	tabs.columns = TAB_COLUMNS
	tabs.add_theme_constant_override("h_separation", int(UiKit.px(2)))
	tabs.add_theme_constant_override("v_separation", int(UiKit.px(2)))
	var ids: Array[String] = [STORAGE_TAB]
	ids.append_array(DecorCatalog.groups_for(space))
	for id in ids:
		var text := Loc.t(&"DECOR_STORAGE") if id == STORAGE_TAB else DecorCatalog.group_name(id)
		var button := _small_button(text, _set_tab.bind(id))
		button.name = "Tab_%s" % id
		button.disabled = id == tab
		tabs.add_child(button)
	return tabs


func _style_row() -> Control:
	var row := UiKit.hbox(int(UiKit.px(2)))
	row.name = "Styles"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var styles: Array[String] = [ALL_STYLES]
	styles.append_array(DecorCatalog.STYLES)
	for style in styles:
		var text := Loc.t(&"DECOR_STYLE_ALL") if style.is_empty() else DecorCatalog.style_name(style)
		var button := _small_button(text, _set_style.bind(style))
		button.name = "Style_%s" % (style if not style.is_empty() else "all")
		button.disabled = style == style_filter
		row.add_child(button)
	return row


func _small_button(text: String, on_pressed: Callable) -> Button:
	var button := UiKit.button(text, on_pressed)
	button.add_theme_font_size_override(&"font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
	button.add_theme_color_override(&"font_disabled_color", UiKit.COLOR_GOLD)
	Modal.compact_buttons(button)
	return button


func _set_tab(id: String) -> void:
	tab = id
	rebuild()


func _set_style(style: String) -> void:
	style_filter = style
	rebuild()


## One card: picture, name, Lager count / price / missing gold; pressed = choose.
func _card(item: DecorItem) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % item.id
	card.custom_minimum_size = UiKit.pxv(CARD_SIZE.x, CARD_SIZE.y)
	card.clip_text = true
	card.tooltip_text = DecorCatalog.display_name(item)
	card.add_theme_stylebox_override(&"normal", UiKit.padded_style(&"dark", 2, 2))
	card.add_theme_stylebox_override(&"hover", UiKit.padded_style(&"normal", 2, 2))
	card.add_theme_stylebox_override(&"pressed", UiKit.padded_style(&"normal", 2, 2))
	card.add_theme_stylebox_override(&"disabled", UiKit.padded_style(&"dark", 2, 2))
	var box := UiKit.vbox(0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = DecorCatalog.preview_texture(item)
	picture.custom_minimum_size = Vector2.ONE * UiKit.px(PICTURE_SIZE)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var name_label := UiKit.text_label(DecorCatalog.display_name(item).get_slice(" · ", 0), UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var line := UiKit.text_label(card_line(item), UiKit.SIZE_EYEBROW, _line_color(item))
	line.name = "Line"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	card.disabled = not can_choose(item)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(choose.bind(item.id))
	return card


## Line under the name: "Im Lager: 2", "Angebracht", "40 Gold" or "Noch 12 Gold".
static func card_line(item: DecorItem) -> String:
	if item.is_surface():
		if DecorState.owned_count(item.id) > 0:
			var active := DecorState.surface_style(DecorState.setting_of(item)) == item.style
			return Loc.t(&"DECOR_SURFACE_ACTIVE" if active else &"DECOR_SURFACE_OWNED")
	elif DecorState.stored_count(item.id) > 0:
		return Loc.t(&"DECOR_STATUS_STORED", [DecorState.stored_count(item.id)])
	var missing := DecorState.gold_missing(item.id)
	if missing > 0:
		return Loc.t(&"DECOR_MISSING_GOLD", [missing])
	return Loc.t(&"DECOR_PRICE", [item.price])


static func _line_color(item: DecorItem) -> Color:
	if DecorState.stored_count(item.id) > 0 or (item.is_surface() and DecorState.owned_count(item.id) > 0):
		return UiKit.COLOR_SUCCESS
	return UiKit.COLOR_DANGER_SOFT if DecorState.gold_missing(item.id) > 0 else UiKit.COLOR_GOLD


static func can_choose(item: DecorItem) -> bool:
	if item.is_surface():
		return DecorState.owned_count(item.id) > 0 or DecorState.can_buy(item.id)
	return DecorState.stored_count(item.id) > 0 or DecorState.can_buy(item.id)


## Takes a stored piece, buys one, or (wallpaper, floor) buys and puts up / takes down.
func choose(id: String) -> void:
	var item := DecorCatalog.get_item(id)
	if item == null:
		return
	if item.is_surface():
		var setting := DecorState.setting_of(item)
		if DecorState.owned_count(id) <= 0 and not DecorState.buy(id):
			return
		var active := DecorState.surface_style(setting) == item.style
		DecorState.set_surface_style(setting, "" if active else item.style)
		Sfx.play_ui(modal, &"coin")
		rebuild()
		return
	if DecorState.stored_count(id) <= 0:
		if not DecorState.buy(id):
			return
		Sfx.play_ui(modal, &"coin")
	modal.finish(id)
