class_name DoorView
extends Node2D
## Everything you see and hear of a Door (ROADMAP_AUSBAU D1): leaf animation, frame, torches,
## light, glow, symbol, particles, light flash and sound. Follows Door.state_changed and never
## changes the door's state itself (logic and effects separated, D-088).
## The way behind an exit door (R5, 05_tueren.md): the mode symbol over the arch (or over the corridor
## of a side door) and a light cone in the mode colour on the floor in front of the door, pointing
## into the room, with a soft light of the same colour (DoorStyle.mode / way_color).
## One gate per transition (M2): a north exit shows its gate (DoorStyle.gate, 32x48, standing on the
## floor line of the front tile and reaching half a tile into the crown) in the biome's tint, framed by
## the cave mouth or the arch, two pebbles and a tuft at its foot. The light cone shines at
## CONE_CLOSED_SHARE while the gate is shut and at full strength once it is open. An entrance draws
## nothing but a little rubble while it is blocked (nothing behind it).
## Positions are world px relative to the door's tile origin (top-left of the door tile).

## Glow strengths (alpha of the additive overlay). Kept low for long sessions. TESTWERTE.
const GLOW_PULSE_BASE := 0.35
const GLOW_PULSE_AMPLITUDE := 0.25
const GLOW_PULSE_SPEED := 1.6
const GLOW_FLICKER_BASE := 0.45
const GLOW_FLICKER_AMPLITUDE := 0.3
const GLOW_THREAT_BASE := 0.4
const GLOW_THREAT_AMPLITUDE := 0.45
const GLOW_THREAT_SPEED := 3.2
const GLOW_FADE_SPEED := 2.5
## Pulsing light of a closed boss gate (radius px, intensity range).
const THREAT_LIGHT_RADIUS := 110.0
const THREAT_LIGHT_MIN := 0.15
const THREAT_LIGHT_MAX := 0.5
## Torch light of the door (one light for both torches, keeps the VisionOverlay light count low).
const TORCH_LIGHT_RADIUS := 170.0
const TORCH_LIGHT_RADIUS_BOSS := 220.0
const TORCH_LIGHT_INTENSITY := 0.85
const TORCH_LIGHT_FLICKER := 0.07
## How far below the door tile the torch light sits (world px). TESTWERT
const TORCH_LIGHT_DROP := 40.0
const FLASH_DURATION := 0.45
## Sign colour for delivered (white/grey) symbol art.
const SYMBOL_TINT := Color("f2cf4a")
## Light cone of the way (art/environment/doors/door_glow.png, 48x32, pivot top centre): size on top
## of the pixel scale, strength (alpha of the additive sprite), slow breathing, the soft light it
## throws. TESTWERTE
const CONE_PATH := "res://art/environment/doors/door_glow.png"
const CONE_SCALE := 1.5
const CONE_ALPHA := 0.8
const CONE_PULSE := 0.12
const CONE_PULSE_SPEED := 1.3
const CONE_FADE_TIME := 0.6
## Above the floor tiles (z -10) and the floor decals, below the characters.
const CONE_Z := -7
const WAY_LIGHT_RADIUS := 150.0
const WAY_LIGHT_INTENSITY := 0.8
## Cone and way light of a shut gate: a hint of the way (M2, 11_makeover3_komplett.md §11). TESTWERT
const CONE_CLOSED_SHARE := 0.3
## The cone follows the gate within its opening time (0.4 s).
const CONE_SHARE_TIME := 0.4
## Pebbles and a tuft at the foot of a mouth (M2 §2.2/§12): place (world px from the door tile
## origin) and scale; floor decals over the floor tiles, under the cone.
const MOUTH_DECO := [
	{"cell": &"pebbles", "pos": Vector2(-26, 70), "scale": 1.2, "flip": false},
	{"cell": &"pebbles", "pos": Vector2(84, 74), "scale": 1.0, "flip": true},
	{"cell": &"tuft", "pos": Vector2(-34, 50), "scale": 1.4, "flip": false},
]
const MOUTH_DECO_Z := -9
## Rubble in an entrance that leads nowhere any more (DecoProp items).
const BLOCKED_RUBBLE := [
	{"item": &"rubble_2", "pos": Vector2(30, 40)},
	{"item": &"rubble_1", "pos": Vector2(18, 54)},
]
## The mode symbol hangs this far above the arch (world px) and a little lighter than the mode
## colour, so dark modes (Lichtfeuer, Flamme) read on the rock.
const MODE_SYMBOL_GAP := 2.0
const MODE_SYMBOL_LIGHTEN := 0.25
const PIXEL_SCALE := 2.0
const TILE := 64.0
## Side doors: the torch on the front above the corridor reaches up to y -72 (pivot (16, 18) at
## -TILE + 28, scale 2); the sign's centre sits above it with a gap (16 px art = 32 px tall).
const SIDE_TORCH_Y := -TILE + 28.0
const SIDE_SYMBOL_Y := SIDE_TORCH_Y - 18.0 * PIXEL_SCALE - 12.0 - 16.0

var style: DoorStyle = null
var is_entrance := false
## Wall of the door (RoomTiles.DoorSide); set by Door before apply_style.
var side: int = 0
## Sounds are played only when true (Door.configure was called), see Door.is_configured.
var sounds_enabled := false

var _leaf: AnimatedSprite2D = null
var _frame: Sprite2D = null
var _glow: Sprite2D = null
var _symbol: Sprite2D = null
var _torches: Array[AnimatedProp] = []
var _torch_light: LightSource = null
var _threat_light: LightSource = null
var _cone: Sprite2D = null
var _way_light: LightSource = null
var _sealed := false
var _door_open := false
## Share of the cone and way light shown (CONE_CLOSED_SHARE .. 1).
var _cone_share := CONE_CLOSED_SHARE
var _mouth_deco: Array[Sprite2D] = []
var _rubble: Array[Node2D] = []
var _glow_strength := 0.0
var _time := randf() * 10.0


func _init() -> void:
	# Frame, glow and sign sort with the player by the frame's floor line (see _make_sprite).
	y_sort_enabled = true


func setup(leaf: AnimatedSprite2D) -> void:
	_leaf = leaf
	if not _leaf.animation_finished.is_connected(_on_leaf_finished):
		_leaf.animation_finished.connect(_on_leaf_finished)


## Builds all visuals for a style. Entrances (M2) get no leaf and no frame: an open gap in the wall.
func apply_style(new_style: DoorStyle, entrance: bool) -> void:
	style = new_style
	is_entrance = entrance
	_clear()
	if is_entrance:
		if _leaf != null:
			_leaf.sprite_frames = null
			_leaf.visible = false
		_build_rubble()
		return
	if _leaf != null:
		_leaf.visible = true
		var strip := DoorArt.get_leaf_strip(style)
		var frames := SpriteStrip.make_frames(strip, style.leaf_size, 1.0, false, &"closed")
		# "closed" = first frame of the strip only.
		while frames.get_frame_count(&"closed") > 1:
			frames.remove_frame(&"closed", frames.get_frame_count(&"closed") - 1)
		SpriteStrip.add_strip(frames, &"open", strip, style.leaf_size, style.leaf_fps, false)
		_leaf.sprite_frames = frames
		# A gate stands on the floor line of its tile and reaches up into the crown (gates.json).
		_leaf.position = Vector2(0.0, float(32 - style.leaf_size.y) * PIXEL_SCALE)
		_leaf.modulate = style.tint if style.is_gate() else Color.WHITE
	if _is_side():
		_apply_side_style()
		return
	var frame_pos := -Vector2(style.leaf_offset) * PIXEL_SCALE
	# The passage of the frame is transparent (DoorArt.open_passage); the gate sits in it, and a
	# player walking through is drawn behind the arch or the mouth.
	_frame = _make_sprite("Frame", DoorArt.get_frame(style), frame_pos, 0)
	if not style.is_boss():
		_build_mouth_deco()
	if style.is_boss():
		# The boss gate is biome-neutral and tinted per biome (SPRITES_V4 §4), placeholder too.
		_frame.modulate = style.tint
	var glow_texture := DoorArt.get_glow(style)
	if glow_texture != null:
		_glow = _make_sprite("Glow", glow_texture, frame_pos, 0)
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = additive
		_glow.modulate = Color(1, 1, 1, 0)
	if not is_entrance:
		_build_torches()
		set_symbol(style.symbol)
		_build_way_light()
	if style.glow_mode == DoorStyle.GLOW_THREAT:
		_threat_light = LightSource.new()
		_threat_light.name = "ThreatLight"
		_threat_light.radius = THREAT_LIGHT_RADIUS
		_threat_light.position = Vector2(TILE * 0.5, TILE * 0.5)
		add_child(_threat_light)


## Sign over the door; &"" removes it. Entrance doors never show one.
func set_symbol(symbol_id: StringName) -> void:
	if _symbol != null:
		remove_child(_symbol)
		_symbol.free()
		_symbol = null
	if style == null or is_entrance or style.is_boss():
		return
	# R5: the mode of the next room wins over a special or branch sign (grey art, mode colour).
	var mode_icon: Texture2D = RoomObjective.get_mode_icon(style.mode) if style.mode != &"" else null
	var texture: Texture2D = mode_icon if mode_icon != null else DoorArt.get_symbol(symbol_id)
	if texture == null:
		return
	_symbol = Sprite2D.new()
	_symbol.name = "Symbol"
	_symbol.texture = texture
	_symbol.scale = Vector2.ONE * PIXEL_SCALE
	if mode_icon != null:
		_symbol.modulate = RoomObjective.get_mode_ui_color(style.mode).lightened(MODE_SYMBOL_LIGHTEN)
	# Delivered special signs are grey and tinted; the branch signs come in their own colours.
	elif DoorArt.has_symbol_file(symbol_id) and not DoorStyle.is_branch_symbol(symbol_id):
		_symbol.modulate = SYMBOL_TINT
	if _is_side():
		# On the wall top above the torch of the brick front, clear of its flame (playtest 14.10.2026:
		# a sign must never cover a torch).
		_symbol.position = Vector2(TILE * 0.5, SIDE_SYMBOL_Y)
	elif mode_icon != null:
		# The mode floats over the arch (05_tueren.md), clear of the keystone ornament.
		var arch_top := -float(style.leaf_offset.y) * PIXEL_SCALE
		_symbol.position = Vector2(TILE * 0.5, arch_top - MODE_SYMBOL_GAP - texture.get_height() * PIXEL_SCALE * 0.5)
	else:
		# Hangs on the arch top, centred over the door.
		var frame_top := -float(style.leaf_offset.y) * PIXEL_SCALE
		_symbol.position = Vector2(TILE * 0.5, frame_top + 6.0 * PIXEL_SCALE)
	_symbol.z_index = 1
	add_child(_symbol)


func get_symbol_sprite() -> Sprite2D:
	return _symbol


## The way behind this branch door was not taken (D-105): the sign fades, the torch and the light
## cone go out.
func show_sealed() -> void:
	show_state(false)
	_sealed = true
	if _symbol != null:
		var tween := _symbol.create_tween() if _symbol.is_inside_tree() else null
		if tween != null:
			tween.tween_property(_symbol, "modulate:a", 0.25, 0.6)
		else:
			_symbol.modulate.a = 0.25
	if _cone != null:
		var cone_tween := _cone.create_tween() if _cone.is_inside_tree() else null
		if cone_tween != null:
			cone_tween.tween_property(_cone, "modulate:a", 0.0, CONE_FADE_TIME)
		else:
			_cone.modulate.a = 0.0
	if _way_light != null:
		_way_light.intensity = 0.0
	for torch in _torches:
		torch.visible = false
	if _torch_light != null:
		_torch_light.intensity = 0.0


func _is_side() -> bool:
	return side == RoomTiles.DoorSide.WEST or side == RoomTiles.DoorSide.EAST


## West/east wall door (A10): the leaf seen from above in the corridor (mirrored for the east wall),
## a torch on the brick front above the corridor, the sign over it. M2: the corridor behind it is one
## tile, the wall of the next room.
func _apply_side_style() -> void:
	if _leaf != null:
		var strip := DoorArt.get_side_leaf_strip(style)
		# Square frames as tall as the strip (32x32; the boss leaf is turned to its height).
		var frame_size := Vector2i(strip.get_height(), strip.get_height())
		var frames := SpriteStrip.make_frames(strip, frame_size, 1.0, false, &"closed")
		while frames.get_frame_count(&"closed") > 1:
			frames.remove_frame(&"closed", frames.get_frame_count(&"closed") - 1)
		SpriteStrip.add_strip(frames, &"open", strip, frame_size, style.side_leaf_fps, false)
		_leaf.sprite_frames = frames
		_leaf.flip_h = side == RoomTiles.DoorSide.EAST
		_leaf.position = Vector2.ZERO
		_leaf.modulate = Color.WHITE
	var strip_path := style.torch_strip_path
	if not strip_path.is_empty() and ResourceLoader.exists(strip_path):
		var torch := AnimatedProp.new()
		torch.name = "Torch0"
		torch.frame_size = Vector2i(32, 32)
		torch.fps = 8.0
		torch.pivot = Vector2(16, 31) if style.torch_mode == DoorStyle.TORCH_BRAZIER else Vector2(16, 18)
		torch.strip = load(strip_path) as Texture2D
		torch.scale = Vector2.ONE * PIXEL_SCALE
		torch.position = Vector2(TILE * 0.5, SIDE_TORCH_Y)
		add_child(torch)
		_torches.append(torch)
	_add_torch_light()
	_torch_light.position = Vector2(TILE * 0.5, -TILE * 0.5) + get_inward() * (TILE * 0.5 + TORCH_LIGHT_DROP)
	set_symbol(style.symbol)
	_build_way_light()
	if style.glow_mode == DoorStyle.GLOW_THREAT:
		_threat_light = LightSource.new()
		_threat_light.name = "ThreatLight"
		_threat_light.radius = THREAT_LIGHT_RADIUS
		_threat_light.position = Vector2(TILE * 0.5, TILE * 0.5)
		add_child(_threat_light)


func get_frame_sprite() -> Sprite2D:
	return _frame


func get_glow_sprite() -> Sprite2D:
	return _glow


func get_torches() -> Array[AnimatedProp]:
	return _torches


func get_threat_light() -> LightSource:
	return _threat_light


## Light cone of the way in front of the door (R5); null without one.
func get_cone_sprite() -> Sprite2D:
	return _cone


func get_way_light() -> LightSource:
	return _way_light


## Unit vector from the door into the room it belongs to (the cone points there): south for a north
## door, east for a west door, west for an east door.
func get_inward() -> Vector2:
	match side:
		RoomTiles.DoorSide.WEST:
			return Vector2.RIGHT
		RoomTiles.DoorSide.EAST:
			return Vector2.LEFT
		RoomTiles.DoorSide.SOUTH:
			return Vector2.UP
	return Vector2.DOWN


## Pebbles and moss at the foot of the mouth or arch (M2 §12), from the biome's overlay sheet.
func _build_mouth_deco() -> void:
	for entry: Dictionary in MOUTH_DECO:
		var texture := DoorArt.get_overlay(style.biome_id, style.soft, entry["cell"])
		if texture == null:
			continue
		var deco := Sprite2D.new()
		deco.name = "Mouth%s%d" % [String(entry["cell"]).capitalize(), _mouth_deco.size()]
		deco.texture = texture
		deco.scale = Vector2.ONE * PIXEL_SCALE * float(entry["scale"]) * 0.5
		deco.flip_h = entry["flip"]
		deco.position = entry["pos"]
		deco.z_index = MOUTH_DECO_Z
		deco.z_as_relative = false
		add_child(deco)
		_mouth_deco.append(deco)


func get_mouth_deco() -> Array[Sprite2D]:
	return _mouth_deco


## Rubble in a blocked entrance (shown while the entrance is shut, see show_state).
func _build_rubble() -> void:
	for entry: Dictionary in BLOCKED_RUBBLE:
		var prop := DecoProp.new()
		prop.name = String(entry["item"]).to_pascal_case()
		prop.item = entry["item"]
		prop.position = entry["pos"]
		prop.visible = false
		add_child(prop)
		_rubble.append(prop)


func get_rubble() -> Array[Node2D]:
	return _rubble


## Shows a state without effects (setup, streaming).
func show_state(open: bool) -> void:
	_door_open = open
	_cone_share = 1.0 if open else CONE_CLOSED_SHARE
	for piece in _rubble:
		piece.visible = not open
	if _leaf == null or _leaf.sprite_frames == null:
		return
	if open:
		_leaf.play(&"open")
		_leaf.frame = _leaf.sprite_frames.get_frame_count(&"open") - 1
		_leaf.pause()
	else:
		_leaf.play(&"closed")
	_glow_strength = _target_glow()


## Door.state_changed: animates and plays effects unless instant.
func on_state_changed(open: bool, instant: bool) -> void:
	if instant or is_entrance:
		show_state(open)
		return
	var changed := open != _door_open
	_door_open = open
	if _leaf != null and _leaf.sprite_frames != null:
		if open:
			_leaf.play(&"open")
		else:
			_leaf.play_backwards(&"open")
	if changed:
		if open:
			_play_open_effects()
		else:
			_play_close_effects()


func _on_leaf_finished() -> void:
	if not _door_open and _leaf.animation == &"open":
		_leaf.play(&"closed")


func _process(delta: float) -> void:
	if style == null:
		return
	_time += delta
	var target := _target_glow()
	if style.glow_mode == DoorStyle.GLOW_FLICKER:
		target += (randf() - 0.5) * GLOW_FLICKER_AMPLITUDE * 0.4
	if style.glow_mode == DoorStyle.GLOW_THREAT and _door_open:
		# The gate's threat fades out once it opens.
		_glow_strength = move_toward(_glow_strength, 0.0, GLOW_FADE_SPEED * delta)
	else:
		_glow_strength = target
	if _glow != null:
		_glow.modulate.a = clampf(_glow_strength, 0.0, 1.0)
	if _threat_light != null:
		var pulse := 0.5 + 0.5 * sin(_time * GLOW_THREAT_SPEED)
		_threat_light.intensity = 0.0 if _door_open else lerpf(THREAT_LIGHT_MIN, THREAT_LIGHT_MAX, pulse)
	if not _sealed:
		# Shut gate: a hint of the way; open: full light (M2).
		var share_target := 1.0 if _door_open else CONE_CLOSED_SHARE
		_cone_share = move_toward(_cone_share, share_target, delta * (1.0 - CONE_CLOSED_SHARE) / CONE_SHARE_TIME)
		if _cone != null:
			_cone.modulate.a = (CONE_ALPHA + CONE_PULSE * sin(_time * CONE_PULSE_SPEED)) * _cone_share
		if _way_light != null:
			_way_light.intensity = WAY_LIGHT_INTENSITY * _cone_share


## Share of the way's light shown right now (CONE_CLOSED_SHARE shut, 1 open).
func get_cone_share() -> float:
	return _cone_share


func _target_glow() -> float:
	match style.glow_mode:
		DoorStyle.GLOW_PULSE:
			return GLOW_PULSE_BASE + GLOW_PULSE_AMPLITUDE * sin(_time * GLOW_PULSE_SPEED)
		DoorStyle.GLOW_FLICKER:
			return GLOW_FLICKER_BASE + GLOW_FLICKER_AMPLITUDE * 0.5 * sin(_time * 7.0)
		DoorStyle.GLOW_THREAT:
			if _door_open:
				return 0.0
			return GLOW_THREAT_BASE + GLOW_THREAT_AMPLITUDE * (0.5 + 0.5 * sin(_time * GLOW_THREAT_SPEED))
	return 0.0


func _play_open_effects() -> void:
	if not is_inside_tree():
		return
	var centre := to_global(Vector2(TILE * 0.5, TILE * 0.5))
	var lintel := to_global(Vector2(TILE * 0.5, 6.0))
	var floor_line := to_global(Vector2(TILE * 0.5, TILE - 4.0))
	Burst.spawn(self, lintel, style.particle_color, 14, style.particle_speed, 0.7, 4.0)
	Burst.spawn(self, floor_line, style.particle_color.darkened(0.2), 10, style.particle_speed * 0.7, 0.5, 3.0)
	LightSource.flash(self, centre, style.flash_radius, FLASH_DURATION)
	if not _is_side() and style.is_gate():
		# The slab grinds into the floor (dust at its foot), the bars rattle up (grit from the slot).
		if style.gate == DoorStyle.GATE_SLAB:
			Burst.spawn(self, floor_line, style.tint.darkened(0.35), 16, 90.0, 0.6, 4.0)
		else:
			Burst.spawn(self, to_global(Vector2(TILE * 0.5, -TILE * 0.4)), DoorArt.METAL_MID, 12, 140.0, 0.45, 3.0)
		if sounds_enabled:
			Sfx.play_at(self, style.open_sound, centre)
		return
	match style.leaf_kind:
		DoorStyle.LEAF_PORTCULLIS:
			Burst.spawn(self, floor_line, Color("ff8a3c"), 18, 240.0, 0.5, 3.0)
		DoorStyle.LEAF_VEIL:
			Burst.spawn(self, centre, Color("dcbcff"), 16, 140.0, 0.8, 3.0)
		DoorStyle.LEAF_VINES:
			Burst.spawn(self, centre, Color("b4f09c"), 10, 70.0, 0.9, 3.0)
		DoorStyle.LEAF_DOUBLE:
			Burst.spawn(self, centre, DoorArt.METAL_MID, 14, 220.0, 0.6, 4.0)
			Burst.spawn(self, centre, style.glow_color, 12, 160.0, 0.5, 3.0)
	if sounds_enabled:
		Sfx.play_at(self, style.side_open_sound if _is_side() else style.open_sound, centre)


func _play_close_effects() -> void:
	if not is_inside_tree():
		return
	var floor_line := to_global(Vector2(TILE * 0.5, TILE - 4.0))
	Burst.spawn(self, floor_line, style.particle_color.darkened(0.25), 8, style.particle_speed * 0.6, 0.45, 3.0)
	if sounds_enabled and style.close_sound != &"":
		Sfx.play_at(self, style.close_sound, to_global(Vector2(TILE * 0.5, TILE * 0.5)))


func _build_torches() -> void:
	var strip_path := style.torch_strip_path
	# The delivered boss gate has its torches painted on the pillars: only the light is added.
	var painted_torches := style.is_boss() and DoorArt.has_frame_file(style)
	if strip_path.is_empty() or not ResourceLoader.exists(strip_path) or painted_torches:
		_add_torch_light()
		return
	var strip := load(strip_path) as Texture2D
	var spots: Array[Vector2] = []
	var pivot := Vector2(16, 18)
	if style.is_boss():
		# On the holders of the pillars (frame art x 8 / 56, y 22).
		var frame_pos := -Vector2(style.leaf_offset) * PIXEL_SCALE
		spots = [frame_pos + Vector2(8, 22) * PIXEL_SCALE, frame_pos + Vector2(56, 22) * PIXEL_SCALE]
		pivot = Vector2(16, 24)
	elif style.torch_mode == DoorStyle.TORCH_BRAZIER:
		# Braziers stand at the wall foot beside the frame.
		var half := float(style.frame_size.x) * 0.5 * PIXEL_SCALE
		spots = [Vector2(TILE * 0.5 - half - 22.0, TILE), Vector2(TILE * 0.5 + half + 22.0, TILE)]
		pivot = Vector2(16, 31)
	else:
		var half := float(style.frame_size.x) * 0.5 * PIXEL_SCALE
		spots = [Vector2(TILE * 0.5 - half - 12.0, 28.0), Vector2(TILE * 0.5 + half + 12.0, 28.0)]
	for i in spots.size():
		var torch := AnimatedProp.new()
		torch.name = "Torch%d" % i
		torch.frame_size = Vector2i(32, 32)
		torch.fps = 8.0
		torch.pivot = pivot
		torch.strip = strip
		torch.scale = Vector2.ONE * PIXEL_SCALE
		torch.position = spots[i]
		add_child(torch)
		# Torches beside one door should not flicker in sync.
		torch.frame = i * 2
		_torches.append(torch)
	_add_torch_light()


## Light cone and soft light of the way (R5): door_glow.png tinted with the way colour, its top edge
## on the door's inner edge, pointing into the room. Not for entrance doors or doors without a way.
func _build_way_light() -> void:
	if is_entrance or style == null or not style.has_way_light():
		return
	var inward := get_inward()
	# Inner edge of the door tile, in the middle of the opening.
	var edge := Vector2(TILE * 0.5, TILE * 0.5) + inward * TILE * 0.5
	var texture := load(CONE_PATH) as Texture2D if ResourceLoader.exists(CONE_PATH) else null
	if texture != null:
		_cone = Sprite2D.new()
		_cone.name = "Cone"
		_cone.texture = texture
		_cone.centered = false
		# Pivot top centre (door_modes.json): the art hangs down from the door edge.
		_cone.offset = Vector2(-texture.get_width() * 0.5, 0.0)
		_cone.scale = Vector2.ONE * PIXEL_SCALE * CONE_SCALE
		_cone.position = edge
		_cone.rotation = Vector2.DOWN.angle_to(inward)
		_cone.z_index = CONE_Z
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_cone.material = additive
		_cone.modulate = Color(style.way_color, CONE_ALPHA * _cone_share)
		add_child(_cone)
	_way_light = LightSource.new()
	_way_light.name = "WayLight"
	_way_light.radius = WAY_LIGHT_RADIUS
	_way_light.intensity = WAY_LIGHT_INTENSITY * _cone_share
	_way_light.color = Color(style.way_color, 1.0)
	_way_light.position = edge + inward * TILE * 0.8
	add_child(_way_light)


func _add_torch_light() -> void:
	_torch_light = LightSource.new()
	_torch_light.name = "TorchLight"
	_torch_light.radius = TORCH_LIGHT_RADIUS_BOSS if style.is_boss() else TORCH_LIGHT_RADIUS
	_torch_light.intensity = TORCH_LIGHT_INTENSITY
	_torch_light.flicker = TORCH_LIGHT_FLICKER
	# The torches light the room in front of the gate, not the corridor behind it (M2 playtest).
	_torch_light.position = Vector2(TILE * 0.5, TILE + TORCH_LIGHT_DROP)
	add_child(_torch_light)


func _make_sprite(node_name: String, texture: Texture2D, pos: Vector2, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * PIXEL_SCALE
	# Sort point on the frame's floor line, lifted like every prop (SortLift): the node sits at the
	# bottom, the texture is drawn upwards via offset, so the picture does not move.
	var sort_y := texture.get_height() * PIXEL_SCALE - Player.FEET_OFFSET.y
	sprite.position = pos + Vector2(0, sort_y)
	sprite.offset = Vector2(0, -sort_y / PIXEL_SCALE)
	sprite.z_index = z
	add_child(sprite)
	return sprite


func _clear() -> void:
	# Gone at once: apply_style runs several times while a room is prepared (configure, set_destination,
	# show_way), queued copies would pile up until the end of the frame.
	for child in get_children():
		remove_child(child)
		child.free()
	_frame = null
	_glow = null
	_symbol = null
	_torches.clear()
	_torch_light = null
	_threat_light = null
	_cone = null
	_way_light = null
	_mouth_deco.clear()
	_rubble.clear()
