class_name DamageNumber
extends Label
## Floating damage number. Shield and HP damage use different colours (PRD 4.7, ui_spec
## "damage_number" #f2cf4a / "shield_damage_number" #6cb2ec), Pixelify Sans with a 1 px shadow.

const HEALTH_COLOR := Color("#f2cf4a")
const SHIELD_COLOR := Color("#6cb2ec")
const RISE_DISTANCE := 26.0
const LIFETIME := 0.7
## Font size in mockup pixels (UiKit.font_px converts it). World space: kept at the old 16 px on screen.
const FONT_SIZE := 6


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


## Floating status text such as "Betäubt!".
static func spawn_text(parent: Node, global_pos: Vector2, text: String, color: Color) -> void:
	_spawn_label(parent, global_pos, text, color)


static func format_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(int(roundf(amount)))
	return "%.1f" % amount


static func _spawn(parent: Node, global_pos: Vector2, amount: float, font_color: Color) -> void:
	if not GameOptions.are_damage_numbers_enabled():
		return
	_spawn_label(parent, global_pos, format_amount(amount), font_color)


static func _spawn_label(parent: Node, global_pos: Vector2, text: String, font_color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var number := DamageNumber.new()
	number.text = text
	number.z_index = 100
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", UiKit.bold_font())
	number.add_theme_font_size_override("font_size", UiKit.font_px(FONT_SIZE))
	number.add_theme_color_override("font_color", font_color)
	number.add_theme_color_override("font_shadow_color", UiKit.COLOR_SHADOW)
	number.add_theme_constant_override("shadow_offset_x", UiKit.SHADOW_OFFSET)
	number.add_theme_constant_override("shadow_offset_y", UiKit.SHADOW_OFFSET)
	# Thin dark outline keeps numbers readable on bright effects (shadow alone vanishes there).
	number.add_theme_color_override("font_outline_color", UiKit.COLOR_SHADOW)
	number.add_theme_constant_override("outline_size", 2)
	parent.add_child(number)
	number.reset_size()
	number.global_position = global_pos - number.size * 0.5

	var tween := number.create_tween()
	tween.set_parallel(true)
	tween.tween_property(number, "position:y", number.position.y - RISE_DISTANCE, LIFETIME)
	tween.tween_property(number, "modulate:a", 0.0, LIFETIME).set_delay(LIFETIME * 0.4)
	tween.chain().tween_callback(number.queue_free)
