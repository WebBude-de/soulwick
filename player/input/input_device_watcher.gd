class_name InputDeviceWatcher
extends Node
## Feeds every input event of this machine to InputDevice (P0-2), so key symbols and the mouse
## cursor follow the device in use. One node under the tree root, added on demand by ensure():
## at start (GameOptions.apply_controls) and by the first polled local player. Reads in _input,
## before menus and the game, and never consumes an event. Runs while the game is paused (menus).

const NODE_NAME := "InputDeviceWatcher"

static var _instance: InputDeviceWatcher = null


## Adds the watcher under the root of tree once (deferred: callers may be inside _ready).
static func ensure(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return
	_instance = InputDeviceWatcher.new()
	_instance.name = NODE_NAME
	_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_instance)


## The watcher node (null before ensure()).
static func get_instance() -> InputDeviceWatcher:
	return _instance if is_instance_valid(_instance) else null


func _input(event: InputEvent) -> void:
	InputDevice.shared().note(event)


func _exit_tree() -> void:
	# Never leave the player without a cursor (the watcher goes when the game quits).
	InputDevice.apply_cursor(InputDevice.Kind.KEYBOARD_MOUSE)
