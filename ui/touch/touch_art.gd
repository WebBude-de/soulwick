class_name TouchArt
extends RefCounted
## Sprites of the on-screen touch controls (briefing docs/design/sprites/SPRITES_V10.md §1):
## res://art/ui/touch/<name>.png replaces the drawn placeholder of the TouchOverlay as soon as the
## file exists (like EnemyArt/DoorArt); a missing file keeps the drawing. Everything is pixel art
## drawn at whole screen pixels per art pixel with nearest filtering.
##
## Names: button frames touch_btn_large / touch_btn / touch_btn_small (+ _pressed, _disabled),
## stick touch_stick_base, touch_stick_knob (+ _pressed), touch_stick_arrows (optional),
## cooldown touch_cooldown_8f (8 frames, frame 1 = just used, frame 8 = almost ready),
## icons icon_<id> (ids below), weapon icons icon_attack_<weapon> (sword, bow, staff, dagger,
## hammer) with the HUD item icons art/ui/icon_<weapon>.png and icon_attack as fallbacks.

const DIR := "res://art/ui/touch/"
## Screen pixels (1280×720 viewport) per art pixel of frames and the stick (= UiKit.ART_SCALE).
const PIXEL: int = UiKit.ART_SCALE

## Button sizes: frame name, frame size in art pixels, screen pixels per icon art pixel.
enum Size { LARGE, NORMAL, SMALL }
const FRAME_NAMES := {Size.LARGE: "touch_btn_large", Size.NORMAL: "touch_btn", Size.SMALL: "touch_btn_small"}
const FRAME_ART_SIZES := {Size.LARGE: 48, Size.NORMAL: 32, Size.SMALL: 24}
const ICON_PIXELS := {Size.LARGE: PIXEL + 1, Size.NORMAL: PIXEL, Size.SMALL: PIXEL - 1}
## Icons are ICON_ART_SIZE × ICON_ART_SIZE art pixels.
const ICON_ART_SIZE := 16

## Button states (file suffixes).
const PRESSED := "_pressed"
const DISABLED := "_disabled"

const STICK_BASE := "touch_stick_base"
const STICK_KNOB := "touch_stick_knob"
const STICK_ARROWS := "touch_stick_arrows"
const STICK_BASE_ART_SIZE := 60
const STICK_KNOB_ART_SIZE := 24
const COOLDOWN := "touch_cooldown_8f"
const COOLDOWN_FRAMES := 8

## Icon ids (file icon_<id>.png).
const ICON_ATTACK: StringName = &"attack"
const ICON_SPECIAL: StringName = &"special"
const ICON_DASH: StringName = &"dash"
const ICON_JUMP: StringName = &"jump"
const ICON_SIDE_DASH: StringName = &"side_dash"
const ICON_INTERACT: StringName = &"interact"
const ICON_SWITCH: StringName = &"switch"
const ICON_PAUSE: StringName = &"pause"
const ICON_MENU: StringName = &"menu"
const ICONS: Array[StringName] = [
	ICON_ATTACK, ICON_SPECIAL, ICON_DASH, ICON_JUMP, ICON_SIDE_DASH, ICON_INTERACT, ICON_SWITCH,
	ICON_PAUSE, ICON_MENU,
]
## WeaponData.WeaponType -> weapon name in file names (icon_attack_<name>, art/ui/icon_<name>).
const WEAPON_NAMES := {
	WeaponData.WeaponType.SWORD: "sword", WeaponData.WeaponType.BOW: "bow",
	WeaponData.WeaponType.STAFF: "staff", WeaponData.WeaponType.DAGGER: "dagger",
	WeaponData.WeaponType.HAMMER: "hammer",
}
const ITEM_ICON_DIR := "res://art/ui/icon_"

static var _cache: Dictionary[String, Texture2D] = {}


## art/ui/touch/<name>.png, or null while it does not exist.
static func texture(art_name: String) -> Texture2D:
	return _load(DIR + art_name + ".png")


## Button frame of a size in a state ("", PRESSED, DISABLED); null = draw it.
static func frame(size: Size, state := "") -> Texture2D:
	return texture(FRAME_NAMES[size] + state)


## Icon of a button; null = draw it.
static func icon(id: StringName) -> Texture2D:
	return texture("icon_" + String(id))


## Attack icon of a weapon type (-1 = unknown): icon_attack_<weapon>, the HUD item icon of the
## weapon, icon_attack; null = draw the sword.
static func attack_icon(weapon_type: int) -> Texture2D:
	var weapon_name: String = WEAPON_NAMES.get(weapon_type, "")
	if not weapon_name.is_empty():
		var own := texture("icon_attack_" + weapon_name)
		if own != null:
			return own
		var item := _load(ITEM_ICON_DIR + weapon_name + ".png")
		if item != null:
			return item
	return icon(ICON_ATTACK)


## Screen size of a button frame.
static func frame_screen_size(size: Size) -> float:
	return float(FRAME_ART_SIZES[size] * PIXEL)


## Cooldown frame (0-based) for the share of the cooldown that is left (1 = just used).
static func cooldown_frame(share_left: float) -> int:
	return clampi(int((1.0 - clampf(share_left, 0.0, 1.0)) * COOLDOWN_FRAMES), 0, COOLDOWN_FRAMES - 1)


## Forgets loaded textures (art dropped in while the game runs, tests).
static func clear_cache() -> void:
	_cache.clear()


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = null
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	_cache[path] = result
	return result
