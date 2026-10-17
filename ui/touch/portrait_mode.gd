extends Node
## Switches the portrait mode (PortraitLayout) on and off as the window turns: on a handheld (phone
## app, browser on a phone or tablet, forced for tests) a window taller than wide gets the game
## screen at the top and the controller field (PortraitPad) below; turning back restores the
## project's stretch settings exactly. Live, without a restart: the root's content scale changes,
## every layout follows its size_changed, the game state stays as it is.
## Lives under the root window (ensure()), across scene changes, also in the main menu.

const PortraitLayout := preload("res://ui/touch/portrait_layout.gd")
const PortraitPad := preload("res://ui/touch/portrait_pad.gd")
const MobileUi := preload("res://ui/menus/mobile_ui.gd")

## Web: the page's safe-area insets settle after loading; look again this often (frames).
const RECHECK_FRAMES := 30

static var _instance: Node = null

var pad: CanvasLayer
var _saved := false
var _saved_aspect := Window.CONTENT_SCALE_ASPECT_EXPAND
var _saved_size := Vector2i(1280, 720)
var _saved_transform := Transform2D.IDENTITY
var _applied_key := ""
var _busy := false
var _frames := 0


## Adds the switch under the root window once (deferred: may be called from physics frames).
static func ensure(tree: SceneTree) -> void:
	if tree == null or (is_instance_valid(_instance) and not _instance.is_queued_for_deletion()):
		return
	_instance = (load("res://ui/touch/portrait_mode.gd") as GDScript).new()
	_instance.name = "PortraitMode"
	tree.root.add_child.call_deferred(_instance)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = PortraitPad.new()
	pad.name = "PortraitPad"
	add_child(pad)


func _ready() -> void:
	get_tree().root.size_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	# Only the state: the root is left alone (the game is quitting, layouts are being freed).
	PortraitLayout.set_frame(null)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % RECHECK_FRAMES == 0:
		refresh()


## Portrait on or off for the current window (and again after the insets changed).
func refresh() -> void:
	if _busy or not is_inside_tree():
		return
	var root := get_tree().root
	var window := Vector2(root.size)
	if PortraitLayout.is_handheld() and PortraitLayout.is_upright(window):
		var insets := MobileUi.safe_insets()
		var key := "%s|%s" % [window, insets]
		if key != _applied_key or not PortraitLayout.is_active():
			_apply(root, PortraitLayout.compute(window, insets), key)
	elif PortraitLayout.is_active():
		_restore(root)


func _apply(root: Window, frame: PortraitLayout.Frame, key: String) -> void:
	_busy = true
	if not _saved:
		_saved = true
		_saved_aspect = root.content_scale_aspect
		_saved_size = root.content_scale_size
		_saved_transform = root.global_canvas_transform
	_applied_key = key
	# State first: layouts that follow size_changed read it right away.
	PortraitLayout.set_frame(frame)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = frame.screen_size
	root.global_canvas_transform = frame.global_transform()
	_busy = false


func _restore(root: Window) -> void:
	_busy = true
	_applied_key = ""
	PortraitLayout.set_frame(null)
	if _saved:
		root.global_canvas_transform = _saved_transform
		root.content_scale_size = _saved_size
		root.content_scale_aspect = _saved_aspect
	_busy = false
