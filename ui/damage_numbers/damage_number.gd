class_name DamageNumber
extends Label
## Floating damage number. Shield and HP damage use different colours (PRD 4.7, ui_spec
## "damage_number" #f2cf4a / "shield_damage_number" #6cb2ec), Pixelify Sans with a 1 px shadow.
## Online test 16.10.2026 (numbers hid the enemies): numbers stay about half as long, are a little
## see-through, fade early and drift aside in turns (STAGGER), so quick hits do not pile up into one
## block over the enemy's silhouette. Status texts ("Betäubt!") keep the old time.

const HEALTH_COLOR := Color("#f2cf4a")
const SHIELD_COLOR := Color("#6cb2ec")
## Damage numbers (TESTWERTE): rise, whole time on screen and the share of it before the fade.
## Before: 26 px, 0.7 s rise plus a 0.7 s fade from 0.28 s (about 1.1 s on screen).
const RISE_DISTANCE := 20.0
const LIFETIME := 0.6
const FADE_FROM := 0.35
## Font size in mockup pixels (UiKit.font_px converts it). World space.
const FONT_SIZE := 6
## Status texts such as "Betäubt!" (unchanged: 0.7 s rise, fade over 0.7 s from 0.28 s).
const TEXT_RISE_DISTANCE := 26.0
const TEXT_LIFETIME := 0.7
const TEXT_FONT_SIZE := 6
## Sideways start offsets (world px) used in turn, and how far a number drifts further that way.
const STAGGER: Array[float] = [0.0, 9.0, -9.0, 16.0, -16.0]
const DRIFT := 0.5
## Numbers are a little see-through so the enemy under them stays visible.
const ALPHA := 0.9

## Status texts the callers still pass as German literals (player.gd, weapon_controller.gd) are
## found by their German translation and shown in the current language (bridge until the callers
## use spawn_status with the key; i18n round 3).
const STATUS_KEYS: Array[StringName] = [&"STATUS_STUNNED", &"STATUS_BLINDED", &"STATUS_AMBUSH"]

## Next STAGGER entry (look only, no RNG: the same hits always look the same).
static var _stagger_index := 0


static func spawn_for_result(parent: Node, global_pos: Vector2, result: DamageResult) -> void:
	if result.shield_damage > 0.0:
		_spawn(parent, global_pos + Vector2(-8.0, 0.0), result.shield_damage, SHIELD_COLOR)
	if result.health_damage > 0.0:
		_spawn(parent, global_pos + Vector2(8.0, 0.0), result.health_damage, HEALTH_COLOR)


## Numbers of a hit on an enemy (MP3, D-126): in a group game every player sees only the numbers
## of their own hits; single player shows all.
static func shows_hit_by(source: Node) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if not GameMode.of_tree(tree).is_multiplayer():
		return true
	var player := source as Player
	return player != null and is_instance_valid(player) and player.is_local


## Floating status text such as "Betäubt!" (German literals of STATUS_KEYS are translated).
static func spawn_text(parent: Node, global_pos: Vector2, text: String, color: Color) -> void:
	_spawn_label(parent, global_pos, status_text(text), color, true)


## Floating status text of a translation key (STATUS_STUNNED …).
static func spawn_status(parent: Node, global_pos: Vector2, key: StringName, color: Color) -> void:
	_spawn_label(parent, global_pos, Loc.t(key), color, true)


## The shown text of a status literal: the current language's text of the STATUS_KEYS entry whose
## German text it is, else the literal.
static func status_text(text: String) -> String:
	for key in STATUS_KEYS:
		if not Loc.has_key(key, &"de"):
			continue
		var german := TranslationServer.get_translation_object("de")
		if String(german.get_message(key)) == text:
			var translated := Loc.t(key)
			return translated if not translated.is_empty() and translated != String(key) else text
	return text


## Sideways offset of the next damage number (cycles through STAGGER).
static func next_stagger() -> float:
	var offset := STAGGER[_stagger_index % STAGGER.size()]
	_stagger_index = (_stagger_index + 1) % STAGGER.size()
	return offset


static func format_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(int(roundf(amount)))
	return "%.1f" % amount


static func _spawn(parent: Node, global_pos: Vector2, amount: float, font_color: Color) -> void:
	if not GameOptions.are_damage_numbers_enabled():
		return
	# No numbers on an enemy hidden in the dark (DarknessVisibility, optics only).
	if not DarknessVisibility.shows_number_at(global_pos):
		return
	_spawn_label(parent, global_pos, format_amount(amount), font_color, false)


static func _spawn_label(parent: Node, global_pos: Vector2, text: String, font_color: Color, status_text: bool) -> DamageNumber:
	if parent == null or not parent.is_inside_tree():
		return null
	var number := DamageNumber.new()
	number.text = text
	number.z_index = 100
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", UiKit.bold_font())
	number.add_theme_font_size_override("font_size", UiKit.font_px(TEXT_FONT_SIZE if status_text else FONT_SIZE))
	number.add_theme_color_override("font_color", font_color)
	number.add_theme_color_override("font_shadow_color", UiKit.COLOR_SHADOW)
	number.add_theme_constant_override("shadow_offset_x", UiKit.SHADOW_OFFSET)
	number.add_theme_constant_override("shadow_offset_y", UiKit.SHADOW_OFFSET)
	# Thin dark outline keeps numbers readable on bright effects (shadow alone vanishes there).
	number.add_theme_color_override("font_outline_color", UiKit.COLOR_SHADOW)
	number.add_theme_constant_override("outline_size", 2)
	parent.add_child(number)
	number.reset_size()
	var side := 0.0 if status_text else next_stagger()
	number.global_position = global_pos + Vector2(side, 0.0) - number.size * 0.5
	var lifetime := TEXT_LIFETIME if status_text else LIFETIME
	var rise := TEXT_RISE_DISTANCE if status_text else RISE_DISTANCE
	var fade_delay := lifetime * (0.4 if status_text else FADE_FROM)
	var fade_time := lifetime if status_text else lifetime - fade_delay
	if not status_text:
		number.modulate.a = ALPHA

	var tween := number.create_tween()
	tween.set_parallel(true)
	tween.tween_property(number, "position:y", number.position.y - rise, lifetime)
	if not is_zero_approx(side):
		tween.tween_property(number, "position:x", number.position.x + side * DRIFT, lifetime)
	tween.tween_property(number, "modulate:a", 0.0, fade_time).set_delay(fade_delay)
	tween.chain().tween_callback(number.queue_free)
	return number
