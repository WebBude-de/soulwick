class_name GameOptions
extends RefCounted
## Player options that are not the Music/SFX volumes (UX1, UX3): language (D-111), master volume,
## window mode, VSync, brightness (R8, R6 hook), light effects (L1), screen shake, hit stop, damage numbers, reduced flashes,
## "Seitenwege auslassen" (M5, read by SideWays.is_skipped). Global like the
## volumes (settings.cfg [options] via SaveManager.get_option/set_option, not per save slot).
## Controls (P0-2): gamepad bindings and device watcher (apply_controls), gamepad aim assist.
## Touch controls (Projektmitglied 17.10.2026): swap sides, fixed or floating sticks, size,
## opacity, touch aim assist; the TouchOverlay reads them every frame, so a change shows at once.
## apply_all() runs at start (scenes/main.gd, scenes/world_controller.gd); the options view calls
## the setters, which store and apply at once. F11 toggles the window mode everywhere.
##
## Game-feel switches are read where the effect happens (one line each, see
## docs/SPRACHEN.md "Haken"): CameraShake (enabled is set here already,
## strength via get_screen_shake_strength()), HitStop.trigger (is_hit_stop_enabled()),
## DamageNumber (are_damage_numbers_enabled()), SpriteFx.flash / PostProcess.hit_pulse
## (get_flash_strength()).

const LANGUAGE: StringName = &"language"
## Bus "Master" as an option: SaveManager's volumes only know the Music and SFX buses (their
## defaults decide what is read back from settings.cfg), so Master would not survive a restart there.
const MASTER_VOLUME: StringName = &"master_volume"
const WINDOW_MODE: StringName = &"window_mode"
## UX1 stored a bool here; it is read once to migrate to WINDOW_MODE.
const FULLSCREEN: StringName = &"fullscreen"
const VSYNC: StringName = &"vsync"
## Strength 0 / 0.5 / 1 (UX1 stored a bool, read as 0 or 1).
const SCREEN_SHAKE: StringName = &"screen_shake"
const HIT_STOP: StringName = &"hit_stop"
const DAMAGE_NUMBERS: StringName = &"damage_numbers"
const REDUCE_FLASHES: StringName = &"reduce_flashes"
## Brightness of the dungeon darkness, -1 (darker) .. +1 (brighter), 0 = as designed (R6/R8). Only
## the drawn ambient moves (LightingProfile.set_brightness); what enemies and the player see in game
## logic (LightQuery) stays the same.
const BRIGHTNESS: StringName = &"brightness"
const BRIGHTNESS_MIN := -1.0
const BRIGHTNESS_MAX := 1.0
## Light effects (L1): "high" draws glow halos, biome grading, mist and ambient particles, "low"
## switches them off for weak computers (LightingQuality). Gameplay light stays the same.
const LIGHT_EFFECTS: StringName = &"light_effects"
const LIGHT_LOW: StringName = &"low"
const LIGHT_HIGH: StringName = &"high"
const LIGHT_LEVELS: Array[StringName] = [LIGHT_LOW, LIGHT_HIGH]
## Light aim assist on the gamepad's right stick, ranged weapons only (P0-2, same rule as touch,
## D-155; TouchAimAssist). Read by GamepadInput every frame.
const GAMEPAD_AIM_ASSIST: StringName = &"gamepad_aim_assist"
## Side segments between rooms off (M5, D-144 "abschaltbar"): the key SideWays reads
## (SideRules.OPTION_SKIP; written out, so this script loads nothing of the dungeon).
const SKIP_SIDE_PATHS: StringName = &"skip_side_paths"
## Touch controls (TouchOverlay, TouchInput). Swap sides: move stick right, aim stick left.
const TOUCH_SWAP_SIDES: StringName = &"touch_swap_sides"
## "fixed": the sticks stay at their place (default); "floating": they start under the thumb and
## follow it (the behaviour before 17.10.2026).
const TOUCH_STICKS: StringName = &"touch_sticks"
const TOUCH_FIXED: StringName = &"fixed"
const TOUCH_FLOATING: StringName = &"floating"
const TOUCH_STICK_MODES: Array[StringName] = [TOUCH_FIXED, TOUCH_FLOATING]
## Size step 0 (small), 1 (medium), 2 (large, default since D-219): the TouchOverlay turns it into
## millimetres on the real screen (TouchMetrics), the PortraitPad likewise.
const TOUCH_SIZE: StringName = &"touch_size"
const TOUCH_SIZE_STEPS := 3
const TOUCH_SIZE_DEFAULT := 2
## Opacity of the whole overlay (TESTWERT steps).
const TOUCH_OPACITY: StringName = &"touch_opacity"
const TOUCH_OPACITIES: Array[float] = [0.5, 0.75, 1.0]
## Touch aim assist (D-155, ranged weapons only; TouchAimAssist). Read by TouchInput every frame.
const TOUCH_AIM_ASSIST: StringName = &"touch_aim_assist"

const LANGUAGE_AUTO: StringName = &"auto"
const LANGUAGES: Array[StringName] = [LANGUAGE_AUTO, &"en", &"de"]
const WINDOWED: StringName = &"windowed"
const FULLSCREEN_MODE: StringName = &"fullscreen"
const BORDERLESS: StringName = &"borderless"
const WINDOW_MODES: Array[StringName] = [WINDOWED, FULLSCREEN_MODE, BORDERLESS]
const SHAKE_OFF := 0.0
const SHAKE_LIGHT := 0.5
const SHAKE_NORMAL := 1.0
const SHAKE_STRENGTHS: Array[float] = [SHAKE_OFF, SHAKE_LIGHT, SHAKE_NORMAL]
## Flash peak with "Blitze reduzieren" (TESTWERT): hit flashes and the chromatic pulse scaled down.
const REDUCED_FLASH_STRENGTH := 0.35
const MASTER_BUS: StringName = &"Master"

const DEFAULTS := {
	LANGUAGE: "auto",
	MASTER_VOLUME: 1.0,
	WINDOW_MODE: "windowed",
	VSYNC: true,
	SCREEN_SHAKE: SHAKE_NORMAL,
	HIT_STOP: true,
	DAMAGE_NUMBERS: true,
	REDUCE_FLASHES: false,
	BRIGHTNESS: 0.0,
	LIGHT_EFFECTS: "high",
	GAMEPAD_AIM_ASSIST: true,
	TOUCH_SWAP_SIDES: false,
	TOUCH_STICKS: "fixed",
	TOUCH_SIZE: TOUCH_SIZE_DEFAULT,
	TOUCH_OPACITY: 1.0,
	TOUCH_AIM_ASSIST: true,
	SKIP_SIDE_PATHS: false,
}


static func apply_all() -> void:
	apply_language()
	apply_window_mode()
	apply_vsync()
	apply_master_volume()
	apply_brightness()
	apply_light_effects()
	apply_controls()
	CameraShake.enabled = is_screen_shake_enabled()


## Everything back to the defaults: options and the Music/SFX volumes, never save slots.
static func reset_to_defaults() -> void:
	for key in DEFAULTS:
		SaveManager.set_option(key, DEFAULTS[key])
	for bus in SaveManager.DEFAULT_VOLUMES:
		SaveManager.set_volume(bus, SaveManager.DEFAULT_VOLUMES[bus])
	SaveManager.save_settings()
	apply_all()


# --- Language (D-111) ---

## "auto", "en" or "de".
static func get_language() -> StringName:
	var value := StringName(SaveManager.get_option(LANGUAGE, "auto"))
	return value if LANGUAGES.has(value) else LANGUAGE_AUTO


static func set_language(language: StringName) -> void:
	if not LANGUAGES.has(language):
		language = LANGUAGE_AUTO
	SaveManager.set_option(LANGUAGE, String(language))
	apply_language()


static func apply_language() -> void:
	Loc.apply(get_language())


# --- Audio ---

## Linear 0..1 of the Master bus.
static func get_master_volume() -> float:
	return clampf(SaveManager.get_option(MASTER_VOLUME, 1.0), 0.0, 1.0)


static func set_master_volume(linear: float) -> void:
	SaveManager.set_option(MASTER_VOLUME, clampf(linear, 0.0, 1.0))
	apply_master_volume()


static func apply_master_volume() -> void:
	var index := AudioServer.get_bus_index(MASTER_BUS)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, get_master_volume())))


# --- Window ---

## "windowed", "fullscreen" or "borderless". A UX1 file with fullscreen=true reads as "fullscreen".
static func get_window_mode() -> StringName:
	var value := StringName(SaveManager.get_option(WINDOW_MODE, ""))
	if WINDOW_MODES.has(value):
		return value
	return FULLSCREEN_MODE if SaveManager.get_option(FULLSCREEN, false) else WINDOWED


static func set_window_mode(mode: StringName) -> void:
	if not WINDOW_MODES.has(mode):
		mode = WINDOWED
	SaveManager.set_option(WINDOW_MODE, String(mode))
	apply_window_mode()


## Fullscreen or borderless: the window covers the screen.
static func is_fullscreen() -> bool:
	return get_window_mode() != WINDOWED


static func set_fullscreen(on: bool) -> void:
	set_window_mode(FULLSCREEN_MODE if on else WINDOWED)


static func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


## Puts the window into the stored mode. Leaves a maximised window alone when "Fenster" is chosen,
## and does nothing without a real window (headless tests and tools).
static func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var current := DisplayServer.window_get_mode()
	var is_full := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var is_borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	var screen := DisplayServer.window_get_current_screen()
	match get_window_mode():
		FULLSCREEN_MODE:
			if is_borderless:
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if not is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		BORDERLESS:
			# A frameless window the size of the screen (no mode switch, alt-tab stays quick).
			if is_full or current == DisplayServer.WINDOW_MODE_MAXIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
		_:
			if is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if is_borderless:
				# Back from borderless: the project's window size, centred on the same screen.
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				var size := Vector2i(
					int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
					int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
				DisplayServer.window_set_size(size)
				var offset := Vector2i(Vector2(DisplayServer.screen_get_size(screen) - size) * 0.5)
				DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + offset)


static func is_vsync_enabled() -> bool:
	return SaveManager.get_option(VSYNC, true)


static func set_vsync(on: bool) -> void:
	SaveManager.set_option(VSYNC, on)
	apply_vsync()


## Frame cap without vsync. Godot frees replaced audio bus data two frames later while its mixer
## thread may still read it (crash in AudioServer::_mix_step); uncapped frame rates make two frames
## shorter than a mixing step (D-134). TESTWERT
const MAX_FPS_WITHOUT_VSYNC := 240


static func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var on := is_vsync_enabled()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0 if on else MAX_FPS_WITHOUT_VSYNC


# --- Brightness (R8, hook of R6) ---

## -1 .. +1, 0 = as designed.
static func get_brightness() -> float:
	var value: Variant = SaveManager.get_option(BRIGHTNESS, 0.0)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 0.0
	return clampf(float(value), BRIGHTNESS_MIN, BRIGHTNESS_MAX)


static func set_brightness(value: float) -> void:
	SaveManager.set_option(BRIGHTNESS, snappedf(clampf(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX), 0.05))
	apply_brightness()


static func apply_brightness() -> void:
	LightingProfile.set_brightness(get_brightness())


# --- Light effects (L1) ---

## "high" (default) or "low".
static func get_light_effects() -> StringName:
	var value := StringName(str(SaveManager.get_option(LIGHT_EFFECTS, "high")))
	return value if LIGHT_LEVELS.has(value) else LIGHT_HIGH


static func set_light_effects(level: StringName) -> void:
	if not LIGHT_LEVELS.has(level):
		level = LIGHT_HIGH
	SaveManager.set_option(LIGHT_EFFECTS, String(level))
	apply_light_effects()


static func apply_light_effects() -> void:
	LightingQuality.set_high(get_light_effects() == LIGHT_HIGH)


# --- Controls (P0-2) ---

## Gamepad bindings into the InputMap and the watcher that switches key symbols and the mouse
## cursor with the device in use (GamepadInput, InputDeviceWatcher). Runs with apply_all at start.
## Loaded at call time, not referenced by class: GamepadInput reaches Enemy (aim assist), Enemy
## preloads gold_pickup.tscn, and that scene's LightSource reads GameOptions - a load cycle at start.
static func apply_controls() -> void:
	load("res://player/input/gamepad_input.gd").ensure_actions()
	load("res://player/input/input_device_watcher.gd").ensure(Engine.get_main_loop() as SceneTree)


static func is_gamepad_aim_assist_enabled() -> bool:
	return SaveManager.get_option(GAMEPAD_AIM_ASSIST, true)


static func set_gamepad_aim_assist(on: bool) -> void:
	SaveManager.set_option(GAMEPAD_AIM_ASSIST, on)


# --- Touch controls (17.10.2026) ---

static func is_touch_swap_sides() -> bool:
	return SaveManager.get_option(TOUCH_SWAP_SIDES, false)


static func set_touch_swap_sides(on: bool) -> void:
	SaveManager.set_option(TOUCH_SWAP_SIDES, on)


## "fixed" (default) or "floating".
static func get_touch_stick_mode() -> StringName:
	var value := StringName(str(SaveManager.get_option(TOUCH_STICKS, "fixed")))
	return value if TOUCH_STICK_MODES.has(value) else TOUCH_FIXED


static func set_touch_stick_mode(mode: StringName) -> void:
	if not TOUCH_STICK_MODES.has(mode):
		mode = TOUCH_FIXED
	SaveManager.set_option(TOUCH_STICKS, String(mode))


static func are_touch_sticks_floating() -> bool:
	return get_touch_stick_mode() == TOUCH_FLOATING


## 0 (small), 1 (medium), 2 (large, default; D-219).
static func get_touch_size() -> int:
	var value: Variant = SaveManager.get_option(TOUCH_SIZE, TOUCH_SIZE_DEFAULT)
	return clampi(int(value), 0, TOUCH_SIZE_STEPS - 1)


static func set_touch_size(step: int) -> void:
	SaveManager.set_option(TOUCH_SIZE, clampi(step, 0, TOUCH_SIZE_STEPS - 1))


## 0.5 .. 1.0 (default 1.0, the designed look).
static func get_touch_opacity() -> float:
	var value: Variant = SaveManager.get_option(TOUCH_OPACITY, 1.0)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 1.0
	return clampf(float(value), TOUCH_OPACITIES[0], 1.0)


static func set_touch_opacity(opacity: float) -> void:
	SaveManager.set_option(TOUCH_OPACITY, clampf(opacity, TOUCH_OPACITIES[0], 1.0))


static func is_touch_aim_assist_enabled() -> bool:
	return SaveManager.get_option(TOUCH_AIM_ASSIST, true)


static func set_touch_aim_assist(on: bool) -> void:
	SaveManager.set_option(TOUCH_AIM_ASSIST, on)


# --- Game feel ---

## 0 (off), 0.5 (light) or 1 (normal). Hook for CameraShake.shake: multiply the trauma with it.
static func get_screen_shake_strength() -> float:
	var value: Variant = SaveManager.get_option(SCREEN_SHAKE, -1.0)
	if typeof(value) == TYPE_FLOAT and value >= 0.0:
		return clampf(value, 0.0, 1.0)
	# UX1 stored a bool (false = off); an int from a hand-edited file counts as a strength too.
	var legacy: Variant = SaveManager.get_option(SCREEN_SHAKE, true)
	if typeof(legacy) == TYPE_BOOL:
		return SHAKE_NORMAL if legacy else SHAKE_OFF
	var number: Variant = SaveManager.get_option(SCREEN_SHAKE, 1)
	return clampf(float(number), 0.0, 1.0)


static func set_screen_shake_strength(strength: float) -> void:
	SaveManager.set_option(SCREEN_SHAKE, clampf(strength, 0.0, 1.0))
	CameraShake.enabled = strength > 0.0


static func is_screen_shake_enabled() -> bool:
	return get_screen_shake_strength() > 0.0


## Kept for callers of UX1: on = normal strength, off = none.
static func set_screen_shake(on: bool) -> void:
	set_screen_shake_strength(SHAKE_NORMAL if on else SHAKE_OFF)


## Hook for HitStop.trigger: return early when false.
static func is_hit_stop_enabled() -> bool:
	return SaveManager.get_option(HIT_STOP, true)


static func set_hit_stop(on: bool) -> void:
	SaveManager.set_option(HIT_STOP, on)


## Hook for DamageNumber._spawn: no floating numbers when false (status texts stay).
static func are_damage_numbers_enabled() -> bool:
	return SaveManager.get_option(DAMAGE_NUMBERS, true)


static func set_damage_numbers(on: bool) -> void:
	SaveManager.set_option(DAMAGE_NUMBERS, on)


static func is_reduce_flashes_enabled() -> bool:
	return SaveManager.get_option(REDUCE_FLASHES, false)


static func set_reduce_flashes(on: bool) -> void:
	SaveManager.set_option(REDUCE_FLASHES, on)


## 1.0 normally, REDUCED_FLASH_STRENGTH with "Blitze reduzieren". Hook for SpriteFx.flash (peak of
## the flash parameter), PostProcess.hit_pulse (strength) and LightSource.flash (intensity).
static func get_flash_strength() -> float:
	return REDUCED_FLASH_STRENGTH if is_reduce_flashes_enabled() else 1.0


# --- Side segments (M5) ---

## true: every way between two rooms is a plain corridor (no side segment, no ladder door). In a
## group game the host's option decides.
static func is_skip_side_paths_enabled() -> bool:
	return bool(SaveManager.get_option(SKIP_SIDE_PATHS, false))


static func set_skip_side_paths(on: bool) -> void:
	SaveManager.set_option(SKIP_SIDE_PATHS, on)


# --- Shortcuts ---

## F11 toggles fullscreen. Returns true if the event was used.
static func handle_shortcut(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode == KEY_F11:
		toggle_fullscreen()
		return true
	return false
