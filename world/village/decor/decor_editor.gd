class_name DecorEditor
extends Node2D
## The decorating mode (WK5 "Dorf schmücken", WK7 "Zuhause einrichten"): a cursor on the grid of
## the space, the held piece as a see-through ghost (green: fits, red: the reason in the bar), and a
## bar with the actions. Setzen/Aufnehmen picks up a placed piece or puts the held one down; on an
## empty cell it opens the catalog (DecorCatalogDialog: Lager and shop). Drehen turns (the _side
## view, the opposite side mirrored), Wegräumen puts the piece back into the Lager, Fertig ends.
## Rules of the grid: DecorGrid; the save: DecorState (every change is saved at once).
## Controls: keyboard and mouse (WASD/arrows or the mouse move the cursor, E/Enter/left click set,
## Q/R/right click turn, F/Entf wegräumen, Tab catalog, Esc done; the view scrolls at the screen
## edge), gamepad (stick or D-pad, A/X set, Y turn, RB wegräumen, Back catalog, B/Start done) and
## touch (tap a cell, tap it again to set, drag to scroll, the bar's buttons).
## The player who opened it stands still (Player.set_input_locked) and only his own camera moves;
## nothing pauses (D-085). Only alone (solo session): in a group the host's village is view only
## (VillageDecorStation).

signal closed

const LOCK_REASON: StringName = &"decor_editor"
const UI_LAYER := 21
## TESTWERT: cursor repeat while a direction is held (s): first step at once, then after the delay.
const REPEAT_DELAY := 0.28
const REPEAT_STEP := 0.09
## TESTWERT: the cursor stays this far inside the visible rectangle (share of the half size).
const FOLLOW_INNER := 0.6
## TESTWERT: camera smoothing (1/s) and edge scrolling of the mouse (share of the screen, world px/s).
const CAMERA_SPEED := 10.0
const EDGE_SHARE := 0.03
const EDGE_SPEED := 700.0
## TESTWERT: a touch that moves less than this (screen px) is a tap.
const TAP_SLOP := 14.0
const GOOD_COLOR := Color(0.45, 1.0, 0.55, 0.32)
const BAD_COLOR := Color(1.0, 0.35, 0.3, 0.36)
const GRID_COLOR := Color(1.0, 0.95, 0.8, 0.16)
const CURSOR_COLOR := Color("#f2cf4a")
const GHOST_ALPHA := 0.72
## TESTWERT: cells around the cursor that show the grid.
const GRID_RADIUS := 5
const ICON_SIZE := 18.0
## Mockup px: room for name and status, distance of the bar to the screen edge.
const TEXT_WIDTH := 120.0
const BAR_MARGIN := 4.0
## The bar goes to the top while the cursor is below this share of the screen height, and back
## below BAR_FLIP_ABOVE (no flicker in between).
const BAR_FLIP_BELOW := 0.62
const BAR_FLIP_ABOVE := 0.45
const PadNav := preload("res://ui/widgets/pad_nav.gd")
## Bar buttons: id, input action whose key is shown, text key (the first one changes, _primary_key).
const ACTIONS := [
	[&"primary", &"interact", &"DECOR_ACTION_SET"],
	[&"rotate", &"switch_weapon", &"DECOR_ACTION_ROTATE"],
	[&"store", &"cast_spell", &"DECOR_ACTION_STORE"],
	[&"catalog", &"upgrade_overview", &"DECOR_ACTION_CATALOG"],
	[&"done", &"ui_cancel", &"DECOR_ACTION_DONE"],
]

var space: StringName = &""
var grid: DecorGrid = null
var layer: DecorLayer = null
var player: Player = null
var cursor := Vector2i.ZERO
## The held piece: {id, rot, from (placement index, -1 = from the Lager)}; {} = nothing held.
var held: Dictionary = {}
## Reason key of the last refused action or the ghost's place (&"" = fits).
var reason: StringName = &""
var ui: CanvasLayer = null
var catalog_open := false
var _ghost: DecorPiece = null
var _view := Vector2.ZERO
var _repeat_left := 0.0
var _last_dir := Vector2i.ZERO
var _touch_start := Vector2.ZERO
var _touch_dragged := false
var _name_label: Label = null
var _status_label: Label = null
var _icon: TextureRect = null
var _buttons: Dictionary[StringName, Button] = {}
var _bar: PanelContainer = null
var _bar_on_top := false
var _closing := false
var _mouse_moved := false
## Text of the first button: Setzen (held), Aufnehmen (on a piece) or Katalog (empty cell).
var _primary_key: StringName = &"DECOR_ACTION_CATALOG"


## Opens the editor for player over layer (the space's placed pieces); null if it may not open.
static func open_for(world: Node2D, decor_layer: DecorLayer, by: Player) -> DecorEditor:
	if world == null or decor_layer == null or decor_layer.grid == null or by == null:
		return null
	var editor := DecorEditor.new()
	editor.name = "DecorEditor"
	editor.layer = decor_layer
	editor.grid = decor_layer.grid
	editor.space = decor_layer.space
	editor.player = by
	world.add_child(editor)
	return editor


func _ready() -> void:
	z_index = 40
	if player != null and is_instance_valid(player):
		player.set_input_locked(LOCK_REASON, true)
		cursor = grid.clamp_cell(grid.cell_at(player.global_position))
		_view = player.global_position
	_build_ui()
	_refresh()
	var device := InputDevice.shared()
	if not device.changed.is_connected(_on_device_changed):
		device.changed.connect(_on_device_changed)


func _exit_tree() -> void:
	var device := InputDevice.shared()
	if device.changed.is_connected(_on_device_changed):
		device.changed.disconnect(_on_device_changed)


## Ends the mode: the held piece goes back (a picked-up one to its place), the camera home.
func close() -> void:
	if _closing:
		return
	_closing = true
	_drop_held()
	if player != null and is_instance_valid(player):
		player.set_input_locked(LOCK_REASON, false)
		var camera := _camera()
		if camera != null:
			var tween := camera.create_tween()
			tween.tween_property(camera, "position", Vector2.ZERO, 0.25)
	Sfx.play_ui(self, &"ui_close")
	closed.emit()
	queue_free()


func is_closing() -> bool:
	return _closing


# --- Actions (also for tests and tools) ---

## Setzen/Aufnehmen at the cursor.
func primary() -> void:
	if not held.is_empty():
		place_held()
		return
	var index := grid.placement_at(layer.placements(), cursor)
	if index >= 0:
		pick_up(index)
	else:
		open_catalog()


## Puts the held piece at the cursor if it fits (reason says why not).
func place_held() -> bool:
	if held.is_empty():
		return false
	var item := DecorCatalog.get_item(String(held["id"]))
	var from := int(held["from"])
	reason = grid.check(item, cursor, int(held["rot"]), layer.placements(), from, _player_feet())
	if reason != DecorGrid.OK:
		Sfx.play_ui(self, &"ui_error")
		_refresh()
		return false
	var done := DecorState.move(space, from, cursor, int(held["rot"])) if from >= 0 \
		else DecorState.place(space, String(held["id"]), cursor, int(held["rot"]))
	if not done:
		return false
	Sfx.play_ui(self, &"ui_confirm")
	# From the Lager: keep the next one in the hand (fences, paving in a row).
	if from < 0 and DecorState.stored_count(String(held["id"])) > 0:
		held = {"id": held["id"], "rot": held["rot"], "from": -1}
	else:
		held = {}
	_refresh()
	return true


## Picks up the placement at index (it stays saved until it is set or put away).
func pick_up(index: int) -> void:
	for entry in layer.placements():
		if int(entry["index"]) == index:
			held = {"id": entry["id"], "rot": entry["rot"], "from": index}
			cursor = entry["cell"]
			Sfx.play_ui(self, &"ui_click")
			_refresh()
			return


## Takes a piece of id from the Lager into the hand.
func hold_from_storage(id: String) -> bool:
	if DecorState.stored_count(id) <= 0:
		return false
	_drop_held()
	held = {"id": id, "rot": 0, "from": -1}
	_refresh()
	return true


## Turns the held piece, or the placed one at the cursor (if it still fits turned).
func turn() -> void:
	if not held.is_empty():
		var item := DecorCatalog.get_item(String(held["id"]))
		held["rot"] = item.next_rotation(int(held["rot"]))
		Sfx.play_ui(self, &"ui_click")
		_refresh()
		return
	var placements := layer.placements()
	var index := grid.placement_at(placements, cursor)
	if index < 0:
		return
	for entry in placements:
		if int(entry["index"]) != index:
			continue
		var item := DecorCatalog.get_item(String(entry["id"]))
		var turned := item.next_rotation(int(entry["rot"]))
		reason = grid.check(item, entry["cell"], turned, placements, index, _player_feet())
		if reason == DecorGrid.OK and DecorState.move(space, index, entry["cell"], turned):
			Sfx.play_ui(self, &"ui_click")
		else:
			Sfx.play_ui(self, &"ui_error")
		_refresh()
		return


## Puts the held piece (or the placed one at the cursor) back into the Lager.
func store() -> void:
	if not held.is_empty():
		var from := int(held["from"])
		held = {}
		if from >= 0:
			DecorState.remove(space, from)
		Sfx.play_ui(self, &"ui_click")
		_refresh()
		return
	var index := grid.placement_at(layer.placements(), cursor)
	if index >= 0 and DecorState.remove(space, index):
		Sfx.play_ui(self, &"ui_click")
		_refresh()


## The held piece goes back: a picked-up one stays where it was, one from the Lager stays there.
func cancel_held() -> void:
	_drop_held()
	_refresh()


func open_catalog() -> void:
	if catalog_open or _closing:
		return
	catalog_open = true
	var picked: String = await DecorCatalogDialog.open(ui, space)
	catalog_open = false
	if not is_inside_tree() or _closing:
		return
	if not picked.is_empty():
		hold_from_storage(picked)
	_refresh()


func move_cursor(step: Vector2i) -> void:
	cursor = grid.clamp_cell(cursor + step)
	reason = &""
	_refresh()


func set_cursor(cell: Vector2i) -> void:
	cursor = grid.clamp_cell(cell)
	reason = &""
	_refresh()


func _drop_held() -> void:
	held = {}
	reason = &""


# --- Input ---

func _input(event: InputEvent) -> void:
	if _closing or catalog_open:
		return
	var action := _action_of(event)
	if action == &"":
		return
	get_viewport().set_input_as_handled()
	match action:
		&"primary":
			primary()
		&"rotate":
			turn()
		&"store":
			store()
		&"catalog":
			open_catalog()
		&"done":
			if held.is_empty():
				close()
			else:
				cancel_held()


func _action_of(event: InputEvent) -> StringName:
	if event.is_echo():
		return &""
	var key := event as InputEventKey
	if key != null and key.pressed:
		match key.keycode:
			KEY_R:
				return &"rotate"
			KEY_DELETE, KEY_BACKSPACE:
				return &"store"
			KEY_ENTER, KEY_KP_ENTER:
				return &"primary"
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		return &"primary"
	if event.is_action_pressed(&"switch_weapon"):
		return &"rotate"
	if event.is_action_pressed(&"cast_spell"):
		return &"store"
	if event.is_action_pressed(&"upgrade_overview"):
		return &"catalog"
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_menu"):
		return &"done"
	return &""


## Mouse and touch on the world (the bar's buttons take theirs first).
func _unhandled_input(event: InputEvent) -> void:
	if _closing or catalog_open:
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.device != InputEvent.DEVICE_ID_EMULATION and mouse.pressed:
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			set_cursor(grid.cell_at(get_global_mouse_position()))
			primary()
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			set_cursor(grid.cell_at(get_global_mouse_position()))
			turn()
			get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and motion.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_moved = true
		var cell := grid.clamp_cell(grid.cell_at(get_global_mouse_position()))
		if cell != cursor:
			cursor = cell
			reason = &""
			_refresh()
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touch_start = touch.position
			_touch_dragged = false
		elif not _touch_dragged:
			_mouse_moved = false
			var cell := grid.clamp_cell(grid.cell_at(_screen_to_world(touch.position)))
			if cell == cursor:
				primary()
			else:
				set_cursor(cell)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.position.distance_to(_touch_start) > TAP_SLOP:
			_touch_dragged = true
		var camera := _camera()
		var zoom := camera.zoom.x if camera != null else 1.0
		_view -= drag.relative / zoom
		get_viewport().set_input_as_handled()


func _screen_to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _process(delta: float) -> void:
	if _closing:
		return
	if not catalog_open:
		_step_cursor(delta)
		_edge_scroll(delta)
	_follow_cursor()
	_move_camera(delta)
	_update_bar_side()
	queue_redraw()


func _step_cursor(delta: float) -> void:
	var vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", 0.5)
	vector += Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down", 0.5)
	var dir := Vector2i(signi(roundi(vector.x)), signi(roundi(vector.y)))
	if dir == Vector2i.ZERO:
		_last_dir = Vector2i.ZERO
		return
	if dir != _last_dir:
		_last_dir = dir
		_repeat_left = REPEAT_DELAY
		_mouse_moved = false
		move_cursor(dir)
		return
	_repeat_left -= delta
	if _repeat_left <= 0.0:
		_repeat_left = REPEAT_STEP
		move_cursor(dir)


func _edge_scroll(delta: float) -> void:
	if not _mouse_moved or InputDevice.is_gamepad() or DisplayServer.is_touchscreen_available():
		return
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var mouse := viewport.get_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(mouse):
		return
	var margin := size * EDGE_SHARE
	var push := Vector2.ZERO
	push.x = -1.0 if mouse.x < margin.x else (1.0 if mouse.x > size.x - margin.x else 0.0)
	push.y = -1.0 if mouse.y < margin.y else (1.0 if mouse.y > size.y - margin.y else 0.0)
	_view += push * EDGE_SPEED * delta


## Keeps the cursor inside the inner part of the view (keys, gamepad, a tap).
func _follow_cursor() -> void:
	var camera := _camera()
	if camera == null:
		return
	var bounds := Rect2(Vector2.ZERO, Vector2(grid.size) * grid.tile)
	if _mouse_moved:
		_view = _view.clamp(bounds.position, bounds.end)
		return
	var half := get_viewport().get_visible_rect().size / camera.zoom * 0.5 * FOLLOW_INNER
	var centre := grid.rect_of(_held_item_or_null(), cursor, _held_rot()).get_center() if not held.is_empty() \
		else (Vector2(cursor) + Vector2(0.5, 0.5)) * grid.tile
	_view.x = clampf(_view.x, centre.x - half.x, centre.x + half.x)
	_view.y = clampf(_view.y, centre.y - half.y, centre.y + half.y)
	_view = _view.clamp(bounds.position, bounds.end)


func _move_camera(delta: float) -> void:
	var camera := _camera()
	if camera == null or player == null or not is_instance_valid(player):
		return
	var target := _view - player.global_position
	camera.position = camera.position.lerp(target, 1.0 - exp(-CAMERA_SPEED * delta))


func _camera() -> Camera2D:
	if player == null or not is_instance_valid(player):
		return null
	var camera := player.get_node_or_null(^"Camera2D") as Camera2D
	return camera if camera != null and camera.enabled else null


## Feet of every player of this world (no blocking piece on top of anyone).
func _player_feet() -> Array[Vector2]:
	var feet: Array[Vector2] = []
	if not is_inside_tree():
		return feet
	var controller := HomeTravel.find_controller(self)
	var players: Array[Player] = []
	if controller != null:
		players = controller.get_players()
	if players.is_empty() and player != null and is_instance_valid(player):
		players.append(player)
	for each in players:
		if each != null and is_instance_valid(each):
			feet.append(each.global_position + Player.FEET_OFFSET)
	return feet


# --- Drawing: grid, cursor, ghost ---

func _held_item_or_null() -> DecorItem:
	return DecorCatalog.get_item(String(held.get("id", ""))) if not held.is_empty() else null


func _held_rot() -> int:
	return int(held.get("rot", 0))


func _draw() -> void:
	for y in range(cursor.y - GRID_RADIUS, cursor.y + GRID_RADIUS + 1):
		for x in range(cursor.x - GRID_RADIUS, cursor.x + GRID_RADIUS + 1):
			var cell := Vector2i(x, y)
			if grid.floor_cells.has(cell) or grid.wall_cells.has(cell):
				draw_rect(Rect2(Vector2(cell) * grid.tile, Vector2.ONE * grid.tile).grow(-1.0), GRID_COLOR, false, 1.0)
	var item := _held_item_or_null()
	if item != null:
		var fits := grid.check(item, cursor, _held_rot(), layer.placements(), int(held["from"]), _player_feet()) == DecorGrid.OK
		draw_rect(grid.rect_of(item, cursor, _held_rot()), GOOD_COLOR if fits else BAD_COLOR)
	var frame := Rect2(Vector2(cursor) * grid.tile, Vector2.ONE * grid.tile)
	if item != null:
		frame = grid.rect_of(item, cursor, _held_rot())
	draw_rect(frame, CURSOR_COLOR, false, 2.0)


func _update_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	for piece in layer.get_pieces():
		piece.visible = held.is_empty() or piece.index != int(held["from"])
	var item := _held_item_or_null()
	if item == null:
		return
	_ghost = DecorPiece.create(item, cursor, _held_rot(), grid, true)
	_ghost.name = "Ghost"
	_ghost.position -= global_position
	_ghost.modulate = Color(1, 1, 1, GHOST_ALPHA)
	add_child(_ghost)


# --- The bar ---

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "DecorUI"
	ui.layer = UI_LAYER
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.get_theme()
	ui.add_child(root)
	_bar = UiKit.panel(&"dark")
	_bar.name = "Bar"
	_bar.add_theme_stylebox_override(&"panel", UiKit.padded_style(&"dark", 3, 5))
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_bar)
	var row := UiKit.hbox(int(UiKit.px(4)))
	_bar.add_child(row)
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.custom_minimum_size = Vector2.ONE * UiKit.px(ICON_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_icon)
	var texts := UiKit.vbox(0)
	texts.custom_minimum_size.x = UiKit.px(TEXT_WIDTH)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	_name_label = UiKit.text_label("", UiKit.SIZE_KEY_HINT, UiKit.COLOR_GOLD, true)
	_name_label.name = "NameLabel"
	_name_label.clip_text = true
	texts.add_child(_name_label)
	_status_label = UiKit.text_label("", UiKit.SIZE_EYEBROW, UiKit.COLOR_TEXT_SOFT)
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.x = UiKit.px(TEXT_WIDTH)
	texts.add_child(_status_label)
	for entry: Array in ACTIONS:
		var id: StringName = entry[0]
		var button := UiKit.button("", _on_bar_button.bind(id))
		button.name = "Button_%s" % id
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", UiKit.font_px(UiKit.SIZE_EYEBROW))
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_buttons[id] = button
		row.add_child(button)
	var gold := UiKit.icon_value(UiKit.GOLD_ICON, str(SaveManager.get_permanent_gold()), UiKit.COLOR_GOLD, UiKit.SIZE_KEY_HINT, 10.0)
	gold.name = "Gold"
	row.add_child(gold)
	_update_button_texts()
	_place_bar(false)


## The bar sits at the bottom, or at the top while the cursor is in the lower part of the screen
## (it never covers the piece being set).
func _place_bar(top: bool) -> void:
	_bar_on_top = top
	var margin := UiKit.px(BAR_MARGIN)
	if top:
		_bar.anchor_top = 0.0
		_bar.anchor_bottom = 0.0
		_bar.grow_vertical = Control.GROW_DIRECTION_END
		_bar.offset_top = margin
		_bar.offset_bottom = margin
	else:
		_bar.anchor_top = 1.0
		_bar.anchor_bottom = 1.0
		_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_bar.offset_top = -margin
		_bar.offset_bottom = -margin


func _update_bar_side() -> void:
	if _bar == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var cursor_y := (get_canvas_transform() * ((Vector2(cursor) + Vector2(0.5, 1.0)) * grid.tile)).y / maxf(1.0, screen.y)
	if not _bar_on_top and cursor_y > BAR_FLIP_BELOW:
		_place_bar(true)
	elif _bar_on_top and cursor_y < BAR_FLIP_ABOVE:
		_place_bar(false)


## True while the bar is at the top of the screen (tests).
func is_bar_on_top() -> bool:
	return _bar_on_top


func _on_bar_button(id: StringName) -> void:
	match id:
		&"primary":
			primary()
		&"rotate":
			turn()
		&"store":
			store()
		&"catalog":
			open_catalog()
		&"done":
			close()


func _update_button_texts() -> void:
	for entry: Array in ACTIONS:
		var button: Button = _buttons.get(entry[0], null)
		if button == null:
			continue
		var key := PadNav.key_name(entry[1])
		var text := Loc.t(_primary_key if entry[0] == &"primary" else entry[2])
		button.text = "%s %s" % [key, text] if not key.is_empty() and not DisplayServer.is_touchscreen_available() else text


func _on_device_changed(_kind: int) -> void:
	_update_button_texts()



## Bar and ghost from the state (held piece, cursor, reason).
func _refresh() -> void:
	if ui == null:
		return
	_update_ghost()
	var item := _held_item_or_null()
	var under := -1
	if item == null:
		under = grid.placement_at(layer.placements(), cursor)
		if under >= 0:
			for entry in layer.placements():
				if int(entry["index"]) == under:
					item = DecorCatalog.get_item(String(entry["id"]))
	_icon.texture = DecorCatalog.preview_texture(item) if item != null else null
	if item != null:
		_name_label.text = DecorCatalog.display_name(item)
	else:
		_name_label.text = Loc.t(&"DECOR_TITLE_VILLAGE" if space == DecorCatalog.VILLAGE else &"DECOR_TITLE_HOME")
	var status := ""
	if not held.is_empty():
		var fit := grid.check(item, cursor, _held_rot(), layer.placements(), int(held["from"]), _player_feet())
		status = Loc.t(fit) if fit != DecorGrid.OK else Loc.t(&"DECOR_STATUS_FITS")
		if int(held["from"]) < 0:
			status += " · " + Loc.t(&"DECOR_STATUS_STORED", [DecorState.stored_count(String(held["id"]))])
	elif reason != DecorGrid.OK:
		status = Loc.t(reason)
	elif under >= 0:
		status = Loc.t(&"DECOR_STATUS_PLACED")
	else:
		status = Loc.t(&"DECOR_STATUS_EMPTY")
	_status_label.text = status
	_status_label.add_theme_color_override(&"font_color", UiKit.COLOR_DANGER_SOFT if status_is_bad() else UiKit.COLOR_TEXT_SOFT)
	var primary_key: StringName = &"DECOR_ACTION_SET" if not held.is_empty() else (&"DECOR_ACTION_PICK" if under >= 0 else &"DECOR_ACTION_CATALOG")
	_primary_key = primary_key
	_update_button_texts()
	_buttons[&"rotate"].disabled = held.is_empty() and under < 0
	_buttons[&"store"].disabled = held.is_empty() and under < 0
	var gold := ui.find_child("Gold", true, false)
	if gold != null:
		for child in gold.get_children():
			if child is Label:
				(child as Label).text = str(SaveManager.get_permanent_gold())


## True when the bar shows a reason why the held piece does not fit.
func status_is_bad() -> bool:
	if held.is_empty():
		return reason != DecorGrid.OK
	var item := _held_item_or_null()
	return grid.check(item, cursor, _held_rot(), layer.placements(), int(held["from"]), _player_feet()) != DecorGrid.OK
