extends GutTest
## Spells on screen (KE7): placeholder pictures in the briefing's sizes (SPRITES_V13 §B5), the
## spell slots with their cooldown clock next to the weapons in the HUD, and the cast buttons of
## the touch controls (landscape overlay and portrait pad), shown only while a spell is equipped.
## Never touches a save.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const PortraitPadScript := preload("res://ui/touch/portrait_pad.gd")
const SCREEN := Rect2(0, 0, 1280, 720)

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_spells_ui_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path
	_free_effects()


func after_each() -> void:
	_free_effects()


## Effects of casts (sparks, flashes, rings, wisps, damage numbers) land next to the player, i.e.
## under this test.
func _free_effects() -> void:
	for child in get_children():
		if child is WillOWisp or child is SpellRing or child is SpellSpark or child is CPUParticles2D \
				or child is LightSource or child is AnimatedSprite2D or child is Label:
			child.free()


func _player_with(loadout: Array[StringName]) -> Player:
	var player := add_child_autofree(PLAYER_SCENE.instantiate()) as Player
	player.set_physics_process(false)
	var spells := PlayerSpells.attach_to(player)
	spells.set_physics_process(false)
	spells.set_loadout(loadout)
	return player


# --- Pictures ---

func test_placeholder_pictures_have_the_briefing_sizes() -> void:
	for id in SpellBook.IDS:
		var rows: Array = SpellArt.ICON_GRIDS[id]
		assert_eq(rows.size(), SpellArt.ICON_SIZE, "%s grid height" % id)
		for row: String in rows:
			assert_eq(row.length(), SpellArt.ICON_SIZE, "%s grid width" % id)
		var icon := SpellArt.icon(id)
		assert_not_null(icon, "%s has a symbol" % id)
		assert_eq(Vector2i(icon.get_size()), Vector2i(16, 16))
	assert_eq(Vector2i(SpellArt.slot_frame().get_size()), Vector2i(20, 20))
	assert_eq(SpellArt.effect(&"nonsense"), {})
	assert_true(TouchArt.ICONS.has(TouchArt.ICON_SPELL))
	assert_eq(Vector2i(TouchArt.icon_sprite(TouchArt.ICON_SPELL).get_size()), Vector2i(16, 16), "touch fallback icon")


func test_effect_values_come_from_the_json_with_defaults_for_gaps() -> void:
	var defaults: Dictionary = SpellArt.EFFECTS[&"heal_spark"]
	var bare := SpellArt.apply_spec(defaults, {})
	assert_eq(bare["fps"], defaults["fps"], "no JSON value: the old fps")
	assert_eq(bare["pivot"], Vector2(defaults["frame"]) * 0.5, "no JSON value: the middle of the frame")
	var partial := SpellArt.apply_spec(defaults, {"pivot": [32, 56], "fps": 0})
	assert_eq(partial["pivot"], Vector2(32, 56))
	assert_eq(partial["fps"], defaults["fps"], "fps 0 is no value")
	assert_eq(SpellArt.apply_spec(defaults, {"frame_size": [32, 20]})["pivot"], Vector2(16, 10), "middle of the new frame")
	if SpellArt.effect(&"heal_spark").is_empty():
		pass_test("effect strips not delivered")
		return
	var heal := SpellArt.effect(&"heal_spark")
	assert_eq(heal["fps"], 12.0, "heal_spark 12 fps (spell_fx.json)")
	assert_eq(heal["pivot"], Vector2(32, 56))
	assert_eq(SpellArt.effect(&"flame_ring")["pivot"], Vector2(48, 52))
	assert_eq(SpellArt.effect(&"light_flash")["pivot"], Vector2(48, 48))
	assert_eq(SpellArt.effect(&"wisp")["fps"], 8.0, "wisp 8 fps")
	assert_true(SpellArt.effect(&"soul_shield_loop")["loop"], "the shield loop loops")
	assert_false(SpellArt.effect(&"wisp_trail").is_empty(), "the wisp trail is delivered")


func test_the_shield_bubble_glows_on_in_its_loop() -> void:
	if SpellArt.effect(&"soul_shield").is_empty() or SpellArt.effect(&"soul_shield_loop").is_empty():
		pass_test("shield strips not delivered")
		return
	var player := _player_with([&"soul_shield"] as Array[StringName])
	assert_true(PlayerSpells.of(player).try_cast_slot(0))
	assert_null(player.find_child("SpellGlow", false, false), "the bubble forms first")
	var intro: Dictionary = SpellArt.effect(&"soul_shield")
	await wait_seconds(6.0 / float(intro["fps"]) + 0.15)
	var glow := player.find_child("SpellGlow", false, false) as AnimatedSprite2D
	assert_not_null(glow, "then it glows on in soul_shield_loop")
	if glow != null:
		assert_true(glow.sprite_frames.get_animation_loop(&"default"))
		assert_eq(glow.sprite_frames.get_frame_count(&"default"), 4)


func test_wisps_use_their_strip_and_leave_a_trail() -> void:
	if SpellArt.effect(&"wisp").is_empty() or SpellArt.effect(&"wisp_trail").is_empty():
		pass_test("wisp strips not delivered")
		return
	var caster := _player_with([] as Array[StringName])
	var wisps := WillOWisp.launch_all(caster, SpellBook.get_spell(SpellBook.WILL_O_WISP), caster.global_position, Vector2.RIGHT, 1.0, false)
	var wisp: WillOWisp = wisps[0]
	var sprite := wisp.get_node("Sprite") as AnimatedSprite2D
	assert_eq(sprite.sprite_frames.get_animation_speed(&"default"), 8.0, "fps from spell_fx.json")
	for i in 30:
		for each: WillOWisp in wisps:
			each.set_physics_process(false)
			each.step(1.0 / 60.0)
	var puffs := 0
	for child in get_children():
		if String(child.name).contains("WispTrail"):
			puffs += 1
	assert_gt(puffs, 3, "puffs of wisp_trail behind the wisps")


# --- HUD ---

func test_hud_shows_spell_slots_next_to_the_weapons() -> void:
	var hud: Hud = add_child_autofree(preload("res://ui/hud/hud.tscn").instantiate())
	var player := _player_with([&"flame_ring", &"heal_spark"] as Array[StringName])
	hud.bind_player(player)
	hud.set_dungeon_mode(true)
	var view := hud.find_child("SpellSlots", true, false) as SpellSlotsView
	assert_not_null(view, "spell slots in the HUD")
	assert_eq(view.get_parent(), hud.find_child("Slot1", true, false).get_parent(), "in the row of the weapon slots")
	view.refresh()
	assert_true(view.visible)
	assert_eq(view.get_slot_count(), 2)
	assert_true(view.get_icon(0).is_ready())
	var spells := PlayerSpells.of(player)
	assert_true(spells.try_cast_slot(0))
	view.refresh()
	assert_almost_eq(view.get_icon(0).share, 1.0, 0.001, "the clock is full right after the cast")
	spells.tick(5.0)
	view.refresh()
	assert_almost_eq(view.get_icon(0).share, 0.5, 0.001, "half of 10 s")
	assert_true(view.get_icon(1).is_ready(), "the other slot is ready")
	spells.set_loadout([] as Array[StringName])
	view.refresh()
	assert_false(view.visible, "hidden without spells")


func test_clock_polygon_follows_the_share() -> void:
	var quarter := SpellSlotsView.SpellSlotIcon.clock_polygon(Vector2.ZERO, 10.0, 0.25)
	assert_eq(quarter[0], Vector2.ZERO, "starts at the centre")
	assert_almost_eq(quarter[1].x, 0.0, 0.001)
	assert_almost_eq(quarter[1].y, -10.0, 0.001, "twelve o'clock")
	assert_true(quarter.has(Vector2(10, -10)), "passes the top right corner")
	assert_almost_eq(quarter[quarter.size() - 1].x, 10.0, 0.001)
	assert_almost_eq(quarter[quarter.size() - 1].y, 0.0, 0.001, "ends at three o'clock")
	var full := SpellSlotsView.SpellSlotIcon.clock_polygon(Vector2.ZERO, 10.0, 1.0)
	assert_eq(full.size(), 7, "centre, start, four corners, end")


# --- Touch ---

func _overlay(state: TouchState) -> TouchOverlay:
	var overlay := TouchOverlay.new(state)
	overlay.follow_options = false
	overlay.set_options(false, false, 1, 1.0)
	add_child_autofree(overlay)
	overlay.layout(SCREEN)
	overlay.set_shown(true)
	return overlay


func _button(overlay: TouchOverlay, action: StringName) -> Dictionary:
	for button in overlay.buttons:
		if button.action == action:
			return button
	return {}


func test_touch_cast_button_only_with_a_spell() -> void:
	var state := TouchState.new()
	state.forced = true
	state.mark_polled(false, true)
	var overlay := _overlay(state)
	var cast := _button(overlay, PlayerSpells.ACTION)
	assert_false(cast.is_empty(), "the cast button has its place")
	overlay.set_spells(null)
	assert_false(overlay.is_button_active(cast), "hidden without spells")
	assert_eq(overlay.button_at(cast.center), {}, "a hidden button takes no finger")
	var player := _player_with([&"will_o_wisp", &"soul_shield"] as Array[StringName])
	var spells := PlayerSpells.of(player)
	overlay.set_spells(spells)
	assert_eq(overlay.get_spell_on_button(0), SpellBook.WILL_O_WISP, "shows the spell it casts")
	assert_eq(overlay.get_spell_on_button(1) != &"", PlayerSpells.has_second_button(), "second button only with its own action")
	assert_true(overlay.handle_touch(0, cast.center, true))
	assert_true(state.went_down(PlayerSpells.ACTION), "the press goes into the touch state like every button")
	overlay.handle_touch(0, cast.center, false)
	spells.try_cast_slot(0)
	spells.try_cast_slot(1)
	overlay.set_spells(spells)
	assert_gt(state.cooldown_share(PlayerSpells.ACTION), 0.0, "the button shows the cooldown")
	overlay._view.queue_redraw()
	await wait_process_frames(2)


func test_portrait_pad_cast_button() -> void:
	assert_eq(PortraitPadScript.action_of(PortraitPadScript.SPELL, false), PlayerSpells.ACTION)
	assert_eq(PortraitPadScript.action_of(PortraitPadScript.SPELL, true), PlayerSpells.ACTION)
	assert_eq(PortraitPadScript.icon_of(PlayerSpells.ACTION, false), TouchArt.ICON_SPELL)
	var pad = autofree(PortraitPadScript.new(TouchState.new()))
	var button := {"id": PortraitPadScript.SPELL}
	pad.set_spell(null)
	assert_false(pad.is_button_active(button), "hidden without a spell")
	pad.set_spell(PlayerSpells.of(_player_with([&"light_flash"] as Array[StringName])))
	assert_true(pad.is_button_active(button))
	assert_eq(pad.spell_shown, SpellBook.LIGHT_FLASH)
	assert_true(pad.is_button_active({"id": PortraitPadScript.A}), "other buttons stay")
