class_name SpellSlotsView
extends HBoxContainer
## Spell slots in the HUD's weapon block, right of the weapon slots (KE7, KONZEPT §6.2: "die
## Abklingzeit steht im HUD neben den Waffen"): one 20×20 slot per equipped spell with its symbol and
## the cooldown as a clock that runs out, then the key cap of the cast button. Hidden while the
## player has no spell. Reads the local player's PlayerSpells every frame (display only, it never
## decides anything); pictures from SpellArt (SPRITES_V13 §B5, drawn placeholders until delivered).

## Dimmed symbol while the spell recharges.
const COOLING_TINT := Color(0.55, 0.53, 0.62, 0.9)
const SHADE := Color(0.06, 0.05, 0.1, 0.62)
## A slot flashes this long when its spell is ready again.
const READY_FLASH_TIME := 0.25

var player: Player = null
var _icons: Array[SpellSlotIcon] = []
var _key: Control = null
var _shown_loadout: Array[StringName] = []
var _shown_key_action := false


func _init() -> void:
	name = "SpellSlots"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(UiKit.px(Hud.SLOT_GAP)))
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	visible = false


func bind_player(target: Player) -> void:
	player = target
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Rebuilds the slots when the loadout changed and moves the clocks.
func refresh() -> void:
	var spells := _spells()
	var loadout: Array[StringName] = []
	if spells != null:
		loadout = spells.get_loadout()
	var key_action := InputMap.has_action(PlayerSpells.ACTION)
	if loadout != _shown_loadout or key_action != _shown_key_action:
		_rebuild(loadout, key_action)
	visible = not loadout.is_empty()
	for slot in _icons.size():
		_icons[slot].set_share(spells.get_cooldown_share(slot) if spells != null else 0.0)


func get_slot_count() -> int:
	return _icons.size()


func get_icon(slot: int) -> SpellSlotIcon:
	return _icons[slot] if slot >= 0 and slot < _icons.size() else null


func _spells() -> PlayerSpells:
	if player == null or not is_instance_valid(player):
		return null
	return PlayerSpells.of(player)


func _rebuild(loadout: Array[StringName], key_action: bool) -> void:
	_shown_loadout = loadout.duplicate()
	_shown_key_action = key_action
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_icons.clear()
	_key = null
	for spell in loadout:
		var icon := SpellSlotIcon.new()
		icon.spell_id = spell
		add_child(icon)
		_icons.append(icon)
	# The cast button's key (keyboard or gamepad symbol) once the action exists (project.godot hook).
	if key_action and not loadout.is_empty():
		_key = KeyCap.for_action(PlayerSpells.ACTION, Hud.HUD_PIXEL)
		_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_key)


## One spell slot: frame, symbol and the cooldown clock (drawn at HUD_PIXEL per art pixel).
class SpellSlotIcon:
	extends Control

	var spell_id: StringName = &""
	## Share of the cooldown still to wait (1 = just cast, 0 = ready).
	var share := 0.0
	var _flash_left := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size = Vector2.ONE * float((SpellArt.ICON_SIZE + 4) * Hud.HUD_PIXEL)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_share(value: float) -> void:
		value = clampf(value, 0.0, 1.0)
		if share > 0.0 and value <= 0.0:
			_flash_left = READY_FLASH_TIME
		if not is_equal_approx(value, share):
			share = value
			queue_redraw()

	func is_ready() -> bool:
		return share <= 0.0

	func _process(delta: float) -> void:
		if _flash_left > 0.0:
			_flash_left = maxf(0.0, _flash_left - delta)
			queue_redraw()

	func _draw() -> void:
		var pixel := float(Hud.HUD_PIXEL)
		var full := Vector2.ONE * float(SpellArt.ICON_SIZE + 4) * pixel
		draw_texture_rect(SpellArt.slot_frame(), Rect2(Vector2.ZERO, full), false)
		var icon := SpellArt.icon(spell_id)
		if icon != null:
			var icon_rect := Rect2(Vector2.ONE * 2.0 * pixel, Vector2.ONE * float(SpellArt.ICON_SIZE) * pixel)
			draw_texture_rect(icon, icon_rect, false, COOLING_TINT if share > 0.0 else Color.WHITE)
		# A sliver of a fan does not triangulate: the last moment shows no clock.
		if share > 0.01:
			_draw_clock(full * 0.5, (float(SpellArt.ICON_SIZE) * 0.5) * pixel)
		if _flash_left > 0.0:
			draw_rect(Rect2(Vector2.ONE * pixel, full - Vector2.ONE * 2.0 * pixel), Color(1, 1, 1, 0.5 * _flash_left / READY_FLASH_TIME))

	## The part of the cooldown still to wait as a dark fan from twelve o'clock, clockwise, over the
	## square symbol area (half size half_size around center).
	func _draw_clock(center: Vector2, half_size: float) -> void:
		# Pixel fan (D-218): every HUD art pixel whose centre lies in the fan.
		PixelDraw.polygon(self, clock_polygon(center, half_size, share), SHADE, float(Hud.HUD_PIXEL))

	## Fan from twelve o'clock over share of a full turn, clockwise, cut to the square: the centre,
	## the square's edge at the start, every corner passed and the edge at the end.
	static func clock_polygon(center: Vector2, half_size: float, part: float) -> PackedVector2Array:
		var start := -PI * 0.5
		var end := start + TAU * clampf(part, 0.0, 1.0)
		var angles: Array[float] = [start]
		for corner in [-0.25, 0.25, 0.75, 1.25, 1.75]:
			var angle: float = corner * PI
			if angle > start and angle < end:
				angles.append(angle)
		angles.append(end)
		var points := PackedVector2Array([center])
		for angle in angles:
			var direction := Vector2(cos(angle), sin(angle))
			points.append(center + direction * half_size / maxf(absf(direction.x), absf(direction.y)))
		return points
