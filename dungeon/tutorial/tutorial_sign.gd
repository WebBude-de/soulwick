class_name TutorialSign
extends Node2D
## Station sign of the practice run (WK10): the delivered board on a post (station_sign.png) with the
## key symbol of the station on its board, for the device in use (TutorialKeys: mouse button, key,
## gamepad button or touch button), and the station's flag beside it (TutorialFlag). The symbol is
## rebuilt when the device changes. Optics only.

## Board of the sign in node space (world px; TutorialArt.SIGN_BOARD around the pivot).
const BOARD_CENTER := Vector2(0, -42)
## Key symbol size: world px per art pixel of the symbol.
const KEY_PIXEL := 2
## The flag stands this far east of the sign (px).
const FLAG_OFFSET := Vector2(36, 0)

var station: TutorialRules.Station = TutorialRules.Station.ATTACK
var flag: TutorialFlag = null

var _key_holder: Control = null


func _init(for_station: TutorialRules.Station = TutorialRules.Station.ATTACK) -> void:
	station = for_station
	name = "Sign%d" % TutorialRules.station_number(for_station)


func _ready() -> void:
	add_child(TutorialArt.sprite(&"sign"))
	_key_holder = Control.new()
	_key_holder.name = "Key"
	_key_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key_holder)
	_build_key()
	flag = TutorialFlag.new()
	flag.position = FLAG_OFFSET
	add_child(flag)
	var device := InputDevice.shared()
	if not device.changed.is_connected(_on_device_changed):
		device.changed.connect(_on_device_changed)


func _exit_tree() -> void:
	var device := InputDevice.shared()
	if device.changed.is_connected(_on_device_changed):
		device.changed.disconnect(_on_device_changed)


## The key cap on the board (tests).
func get_key() -> KeyCap:
	return _key_holder.get_child(0) as KeyCap if _key_holder != null and _key_holder.get_child_count() > 0 else null


func _build_key() -> void:
	for child in _key_holder.get_children():
		child.free()
	var action: StringName = TutorialRules.ACTIONS[station][0]
	var key := TutorialKeys.cap(action, TutorialRules.SIDE_VIEW_STATIONS.has(station), KEY_PIXEL)
	_key_holder.add_child(key)
	var size := key.get_combined_minimum_size()
	key.size = size
	key.position = BOARD_CENTER - size * 0.5


func _on_device_changed(_kind: int) -> void:
	if is_inside_tree():
		_build_key()
