class_name TouchArt
extends RefCounted
## Sprites of the on-screen touch controls (briefing docs/design/sprites/delivered/SPRITES_V10.md §1):
## res://art/ui/touch/<name>.png replaces the drawn placeholder of the TouchOverlay as soon as the
## file exists (like EnemyArt/DoorArt); a missing file keeps the drawn pixel-art placeholder
## (TouchPixelArt, same names and sizes). Everything is pixel art drawn at whole screen pixels per
## art pixel with nearest filtering; the size option picks 2, 3 or 4 screen pixels per art pixel.
## texture()/frame()/icon()/attack_icon() return files only (null = missing); the *_sprite()
## functions add the placeholder and return what the overlay draws.
##
## Names: button frames touch_btn_large / touch_btn / touch_btn_small (+ _pressed, _disabled),
## stick touch_stick_base, touch_stick_knob (+ _pressed), touch_stick_arrows (optional), aim stick
## touch_stick_aim_base (optional, else touch_stick_base; the knob is shared),
## cooldown touch_cooldown_8f (8 frames, frame 1 = just used, frame 8 = almost ready),
## icons icon_<id> (ids below), weapon icons icon_attack_<weapon> (sword, bow, staff, dagger,
## hammer) with the HUD item icons art/ui/icon_<weapon>.png and icon_attack as fallbacks.

const DIR := "res://art/ui/touch/"
const PixelArt := preload("res://ui/touch/touch_pixel_art.gd")
## Screen pixels (1280×720 viewport) per art pixel of frames and the stick (= UiKit.ART_SCALE) at
## the medium size; the size option uses PIXEL - 1 .. PIXEL + 1.
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
## Tints of a delivered normal sprite while its pressed/disabled file is missing.
const TINT_PRESSED := Color(1.25, 1.1, 0.8)
const TINT_DISABLED := Color(0.55, 0.53, 0.62, 0.8)

const STICK_BASE := "touch_stick_base"
const STICK_KNOB := "touch_stick_knob"
const STICK_ARROWS := "touch_stick_arrows"
## Optional own base of the aim stick (right); without it the aim stick uses STICK_BASE.
const STICK_AIM_BASE := "touch_stick_aim_base"
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
## Cast button (KE7, SPRITES_V13 §B5 icon_spell); the landscape overlay draws the spell's own symbol.
const ICON_SPELL: StringName = &"spell"
const ICONS: Array[StringName] = [
	ICON_ATTACK, ICON_SPECIAL, ICON_DASH, ICON_JUMP, ICON_SIDE_DASH, ICON_INTERACT, ICON_SWITCH,
	ICON_PAUSE, ICON_MENU, ICON_SPELL,
]
## WeaponData.WeaponType -> weapon name in file names (icon_attack_<name>, art/ui/icon_<name>).
const WEAPON_NAMES := {
	WeaponData.WeaponType.SWORD: "sword", WeaponData.WeaponType.BOW: "bow",
	WeaponData.WeaponType.STAFF: "staff", WeaponData.WeaponType.DAGGER: "dagger",
	WeaponData.WeaponType.HAMMER: "hammer",
}
const ITEM_ICON_DIR := "res://art/ui/icon_"

static var _cache: Dictionary[String, Texture2D] = {}
static var _placeholders: Dictionary[String, Texture2D] = {}


## art/ui/touch/<name>.png, or null while it does not exist.
static func texture(art_name: String) -> Texture2D:
	return _load(DIR + art_name + ".png")


## Base of the aim stick: its own file if there is one, else the move stick's base; null = draw it.
static func aim_base() -> Texture2D:
	var own := texture(STICK_AIM_BASE)
	return own if own != null else texture(STICK_BASE)


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


## Screen size of a button frame at pixel screen pixels per art pixel.
static func frame_screen_size(size: Size, pixel := PIXEL) -> float:
	return float(FRAME_ART_SIZES[size] * pixel)


## Screen pixels per icon art pixel on a button of size when frames use pixel (large icons one
## step bigger, small ones one step smaller, never below 1).
static func icon_pixel(size: Size, pixel := PIXEL) -> int:
	return maxi(1, pixel + int(ICON_PIXELS[size]) - PIXEL)


# --- What the overlay draws: the file, else the drawn pixel-art placeholder ---

## The file of art_name, else its drawn placeholder (null only for unknown names).
static func sprite(art_name: String) -> Texture2D:
	var own := texture(art_name)
	return own if own != null else placeholder(art_name)


## Drawn pixel-art placeholder of art_name (TouchPixelArt), cached; null for unknown names.
static func placeholder(art_name: String) -> Texture2D:
	if _placeholders.has(art_name):
		return _placeholders[art_name]
	var image := PixelArt.image(art_name)
	var result: Texture2D = ImageTexture.create_from_image(image) if image != null else null
	_placeholders[art_name] = result
	return result


## Base of a stick: the aim stick's own file, the move stick's file, else the drawn base (each
## stick its own placeholder look: warm ring, ember ring with crosshair ticks).
static func stick_base_sprite(aim: bool) -> Texture2D:
	var own := aim_base() if aim else texture(STICK_BASE)
	if own != null:
		return own
	return placeholder(STICK_AIM_BASE if aim else STICK_BASE)


## Direction arrows on the move stick: the file; drawn ones only over the drawn base (a delivered
## base stands on its own).
static func arrows_sprite() -> Texture2D:
	var own := texture(STICK_ARROWS)
	if own != null or texture(STICK_BASE) != null:
		return own
	return placeholder(STICK_ARROWS)


## {texture, tint} of the knob: the pressed file, the normal file tinted, else the drawn knob.
static func knob_sprite(pressed: bool) -> Dictionary:
	return _stateful(STICK_KNOB, PRESSED if pressed else "")


## {texture, tint} of a button frame in a state ("", PRESSED, DISABLED): the file of that state,
## the normal file tinted, else the drawn frame of that state.
static func frame_sprite(size: Size, state := "") -> Dictionary:
	return _stateful(FRAME_NAMES[size], state)


## Icon of a button: the file, else the drawn icon.
static func icon_sprite(id: StringName) -> Texture2D:
	return sprite("icon_" + String(id))


## Attack icon of a weapon type: attack_icon(), else the drawn neutral attack icon.
static func attack_sprite(weapon_type: int) -> Texture2D:
	var own := attack_icon(weapon_type)
	return own if own != null else placeholder("icon_" + String(ICON_ATTACK))


## {texture, region} of the cooldown over a button of size: a frame of touch_cooldown_8f.png on
## normal buttons, else the drawn frame for that size (region = whole texture).
static func cooldown_sprite(size: Size, share_left: float) -> Dictionary:
	var frame_index := cooldown_frame(share_left)
	var strip := texture(COOLDOWN)
	if strip != null and size == Size.NORMAL:
		var frame_width := float(strip.get_width()) / COOLDOWN_FRAMES
		return {"texture": strip, "region": Rect2(frame_width * frame_index, 0.0, frame_width, strip.get_height())}
	var drawn := placeholder("touch_cooldown_%d_%d" % [FRAME_ART_SIZES[size], frame_index])
	return {"texture": drawn, "region": Rect2(Vector2.ZERO, drawn.get_size())}


## Art pixels the face (and its icon) sits off the frame centre: the drawn frames have a 2 px
## thickness below the face (pressed: the face sits on it). Delivered frames: centred.
static func face_offset(size: Size, pressed: bool) -> float:
	if texture(FRAME_NAMES[size]) != null:
		return 0.0
	return PixelArt.face_offset(pressed)


static func _stateful(base_name: String, state: String) -> Dictionary:
	var own := texture(base_name + state)
	if own != null:
		return {"texture": own, "tint": Color.WHITE}
	if not state.is_empty():
		var normal := texture(base_name)
		if normal != null:
			return {"texture": normal, "tint": TINT_PRESSED if state == PRESSED else TINT_DISABLED}
	return {"texture": placeholder(base_name + state), "tint": Color.WHITE}


## Cooldown frame (0-based) for the share of the cooldown that is left (1 = just used).
static func cooldown_frame(share_left: float) -> int:
	return clampi(int((1.0 - clampf(share_left, 0.0, 1.0)) * COOLDOWN_FRAMES), 0, COOLDOWN_FRAMES - 1)


## Forgets loaded textures (art dropped in while the game runs, tests).
static func clear_cache() -> void:
	_cache.clear()
	_placeholders.clear()


static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = null
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	_cache[path] = result
	return result
