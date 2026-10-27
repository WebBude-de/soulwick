class_name DoorView
extends Node2D
## Everything you see and hear of a Door (ROADMAP D1): leaf animation, frame, torches,
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
## Flush lintel (playtest 14.10.2026, 32/35/36.png): the wall runs closed over the passage like a
## tunnel - over a north exit three tiles of the crown as it is drawn beside the door (its light edge
## included) cover the corridor tile; the front tiles right beside the door are drawn as plain fronts
## (their light top line runs up to the frame, no rounded ends); the top of the arch or mouth stays
## in front of the crown with a dark tunnel inside. Over a side door the next room's wall covers the
## corridor tile. The players walk under it (it turns see-through while one is below). The sign
## hangs on the lintel. Not for the boss gate: D-206 (Projektmitglied 22.10.2026, "da müsste Boden
## sein") - its passage is no tunnel; since bug report 23.10.2026 #876edf4a the crown runs closed over
## it with the opening of the arch cut out, so its floor is seen through the arch (_build_boss_passage),
## no dark in it, nobody darkened.
## G2 (playtest 15.10.2026): the arch of a north gate keeps its look while a player walks through; the
## player himself darkens with the depth (ARCH_VISIBLE_ENTRY .. ARCH_VISIBLE_DEEP) and is seen only
## through the opening (the rock and the wall around it are drawn over him, cut to the opening), until
## he is hidden under the closed crown. A side gate is a notch in the side wall drawn by the terrain
## (rounded corners), running into the dark of the tunnel. A blocked entrance is closed by the room's
## own wall with rubble at its foot (no cut-off corridor). In a room between two biomes (campfire) the
## rock over a passage takes the look of the wall around it (the biome blend).
## Positions are world px relative to the door's tile origin (top-left of the door tile).

## The rock over the passage (PassageCover) lies above the characters.
const LINTEL_Z := 1
## Door views whose passage is a tunnel (is_in_tunnel).
const TUNNEL_GROUP := &"door_tunnels"
## Door views with rock drawn over the figures (is_under_rock): every tunnel and the boss gate's roof.
const COVER_GROUP := &"door_covers"
## A player in a passage darkens or brightens this fast (colour share per second).
const SHADE_FADE_SPEED := 8.0
## G2 (Projektmitglied 15.10.2026, notes 8 and 20: "Schatten nicht abdunkeln ... Spieler einfach dunkel
## machen"): share of a player's colour in the arch of a north gate, where he steps in and where the
## crown begins; the arch itself keeps its look. Under the crown he is hidden. TESTWERTE
const ARCH_VISIBLE_ENTRY := 0.6
const ARCH_VISIBLE_DEEP := 0.45
## The part of a side passage's cover that stays behind the characters: the notch's front and crown
## on the room side (seen from the front). Bug report 23.10.2026 #0bfc40e0 ("Hier muss Flint noch
## unter dem Tunnel sein. Mach den Tunnel einfach immer on top layer"): the rest of the cover - the
## rock of the tunnel deeper in and below the notch - always lies over every figure (LINTEL_Z: players,
## enemies, Flint and his shadow), not only while a player is in the passage (G2 note 19 used to keep
## it under the characters then).
const SIDE_COVER_LOW_Z := -3
## Bug report 22.10.2026 #bcff6539 ("hart direkt draußen ... mach den Layer doch einfach an der
## Kante"): a player stepping out of a side passage into the room behind it keeps its rock over him
## until his picture has left the wall, so the wall cuts him at its edge instead of putting all of him
## in front at once when his feet cross it. Half the width of a player's picture, hair included (world
## px, 11 art px). Since #0bfc40e0 the rock lies over him anyway; the lane still counts as "in the
## passage" for the see-through share (lintel_under_alpha). TESTWERT
const SIDE_EXIT_REACH := 22.0
## The closed side gate lies on the mouth of the notch, under the players in front of it.
const SIDE_LEAF_Z := -1
## Bug report 17.10.2026 (#e1279990, #b153783c: "der Eingang ist so tief eingelassen ... nicht so
## cutted"): the notch of a side gate is only this share of its tile deep (the room side); the rest
## of the door tile is the rock of the side wall, the notch's back wall, its front and its foot drawn
## that much closer to the room. 1.0 = the whole door tile (G2). TESTWERT
const SIDE_NOTCH_OPEN := 0.5
## Art px at the room side of the notch's pieces kept where they are (the room wall's light edge and
## its corners there).
const SIDE_NOTCH_ROOM_EDGE := 8
## Rows (relative to the door tile) of the notch drawn closer to the room: crown, front, floor, foot.
const SIDE_NOTCH_ROWS := [-2, -1, 0, 1]
## The fronts beside a north gate, the floor seen in its opening (above the fronts, below the gate).
const FRONT_PATCH_Z := -2
const OPENING_FLOOR_Z := -1
## While a player walks under it the lintel shows this much. Projektmitglied 15.10.2026: the player
## is hidden in the tunnel (1.0, solid); 0.4 would keep him half visible.
const LINTEL_UNDER_ALPHA := 1.0
const LINTEL_FADE_SPEED := 4.0
## Tools may switch the see-through off (1.0) to compare.
static var lintel_under_alpha := LINTEL_UNDER_ALPHA
## Tile sheets as images (cut pieces and the floor in the opening, _sheet_image), per texture RID: the
## ground, wall and rock sheets of all four biomes fit, so it is not cleared on every biome change.
const SHEET_CACHE_MAX := 24
static var _sheets: Dictionary = {}
## Textures made from door images (the opening sprites over the passage, cut cover pieces) by key:
## the gate of a style is built again in every room, the images and their upload once (feedback
## 16.10.2026, hitch on entering a room). A null entry: nothing to draw.
const TEXTURE_CACHE_MAX := 256
static var _textures: Dictionary = {}
## The first share of the light cone fades in from its start edge (no hard edge at the door, 31.png).
const CONE_FADE_IN := 0.45
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
## L1 (15.10.2026): 0.8 glared on light floors and showed hard cut edges. TESTWERT
const CONE_ALPHA := 0.5
## G2 (note 5.3): the way of a side door is seen from the side; its cone a little stronger. TESTWERT
const SIDE_CONE_ALPHA := 0.65
const CONE_PULSE := 0.12
const CONE_PULSE_SPEED := 1.3
const CONE_FADE_TIME := 0.6
## Above the floor tiles (z -10) and the floor decals, below the characters.
const CONE_Z := -7
const WAY_LIGHT_RADIUS := 130.0
const WAY_LIGHT_INTENSITY := 0.8
## The way light sits this many tiles inside the room from the door edge. TESTWERT
const WAY_LIGHT_INSET := 1.6
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
## Rubble in an entrance that leads nowhere any more (DecoProp items), spilled over the wall line in
## front of the closed gap: "along" world px along the wall from the middle of the door tile, "inward"
## world px into the room from the wall line. TESTWERTE
const BLOCKED_RUBBLE := [
	{"item": &"rubble_2", "along": -8.0, "inward": 4.0},
	{"item": &"rubble_1", "along": 14.0, "inward": -2.0},
	{"item": &"rubble_1", "along": -24.0, "inward": -4.0},
]
## The wall drawn over a blocked entrance (PassageCover.sealed_plan): above the floor and its decals,
## below the rubble and the characters.
const SEAL_Z := -6
const RUBBLE_Z := -5
## The mode symbol hangs this far above the arch (world px) and a little lighter than the mode
## colour, so dark modes (Lichtfeuer, Flamme) read on the rock.
const MODE_SYMBOL_GAP := 2.0
## Gap of a sign on the crown to the crown's top edge and to the arch below it (world px).
const SYMBOL_CROWN_GAP := 2.0
const MODE_SYMBOL_LIGHTEN := 0.25
const PIXEL_SCALE := 2.0
const TILE := 64.0
## Side doors: the sign sits on the closed side wall right above the door tile (no torch in a
## passage, 40.png).
const SIDE_SYMBOL_Y := -TILE * 0.5
## The side leaf (bars across the passage, art centre at x 16 of 32) is moved onto the light edge
## of the closed side wall, at the room side of the door tile. TESTWERT
const SIDE_LEAF_SHIFT := 27.0

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
## Rooms the lintel is taken from (the door's room and the room behind it), kept across apply_style.
var _lintel_rooms: Array[Node2D] = []
var _lintel: Array[Sprite2D] = []
## The top of the frame over the cover, the tunnel fade and shade.
var _lintel_extras: Array[Sprite2D] = []
## The rock beside the passage of the boss gate (D-206) and the roof over it with the arch cut out
## (bug report 23.10.2026 #876edf4a), both over the characters.
var _passage_walls: Array[Sprite2D] = []
var _passage_roof: Array[Sprite2D] = []
var _passage_rects: Array[Rect2] = []
## Players darkened by this passage: instance id -> player (restored when they leave it).
var _dimmed: Dictionary = {}
## The side passage's rock lies over the players (somebody is in it).
var _side_over := false
## The dark of the tunnel above the door tile (DoorArt.opening_top_image).
var _shade_top: Sprite2D = null
## Crown pieces over the opening of a north gate and their twins with the opening cut out (G2): while
## a player stands in the arch the full piece lies under him and the cut twin over him.
var _crown_full: Array[Sprite2D] = []
var _crown_cut: Array[Sprite2D] = []
var _arch_view := false
## The wall over a blocked entrance (_build_seal), built once the room's tiles are there.
var _seal: Array[Sprite2D] = []
var _seal_pending := false
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
		# A gate stands on the floor line of its tile and reaches up into the crown (gates.json). In an
		# opening wider than the gate (a cave mouth: 38 px) it is stretched to the opening, centred.
		var stretch := 1.0
		if not _is_side() and style.is_gate():
			stretch = maxf(1.0, float(DoorArt.opening_width(style)) / float(style.leaf_size.x))
		_leaf.scale = Vector2(PIXEL_SCALE * stretch, PIXEL_SCALE)
		_leaf.position = Vector2(TILE * 0.5 * (1.0 - stretch), float(32 - style.leaf_size.y) * PIXEL_SCALE)
		_leaf.modulate = style.tint if style.is_gate() else Color.WHITE
		_leaf.z_index = 0
	if _is_side():
		_apply_side_style()
		return
	var frame_pos := -Vector2(style.leaf_offset) * PIXEL_SCALE
	# The passage of the frame is transparent (DoorArt.open_passage); the gate sits in it, and a
	# player walking through is drawn behind the arch or the mouth.
	_frame = _make_sprite("Frame", DoorArt.get_frame(style), frame_pos, 0)
	if not style.is_boss():
		_build_mouth_deco()
	if not _lintel_rooms.is_empty():
		_build_lintel()
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
		# On the closed side wall above the gate, over the open share of the notch.
		_symbol.position = Vector2(side_notch_center_x(), SIDE_SYMBOL_Y)
		_symbol.z_index = LINTEL_Z + 2
	elif not _lintel.is_empty():
		# On the crown above the arch, under its light edge, clear of the arch (32/38.png). The tall
		# V9 arch leaves less room there: the sign shrinks to fit (never below the art's own size).
		var arch_top := (DoorArt.frame_top_row(style) - style.leaf_offset.y) * PIXEL_SCALE
		var room := arch_top + TILE - 2.0 * SYMBOL_CROWN_GAP
		var symbol_scale := clampf(room / float(texture.get_height()), 1.0, PIXEL_SCALE)
		_symbol.scale = Vector2.ONE * symbol_scale
		_symbol.position = Vector2(TILE * 0.5, -TILE + SYMBOL_CROWN_GAP + texture.get_height() * symbol_scale * 0.5)
		_symbol.z_index = LINTEL_Z + 2
	elif mode_icon != null:
		# The mode floats over the arch (05_tueren.md), clear of the keystone ornament.
		var arch_top := -float(style.leaf_offset.y) * PIXEL_SCALE
		_symbol.position = Vector2(TILE * 0.5, arch_top - MODE_SYMBOL_GAP - texture.get_height() * PIXEL_SCALE * 0.5)
	else:
		# Hangs on the arch top, centred over the door.
		var frame_top := -float(style.leaf_offset.y) * PIXEL_SCALE
		_symbol.position = Vector2(TILE * 0.5, frame_top + 6.0 * PIXEL_SCALE)
	if _symbol.z_index < 1:
		_symbol.z_index = 1
	add_child(_symbol)


func get_symbol_sprite() -> Sprite2D:
	return _symbol


## Lays the rock over the passage behind this exit (PassageCover: the walls of both rooms as if the
## passage were not there; the door's room and the room behind it). Kept when the style is applied
## again.
func build_lintel(rooms: Array[Node2D]) -> void:
	if style == null or is_entrance:
		return
	_lintel_rooms = rooms.duplicate()
	_build_lintel()
	set_symbol(style.symbol)


func get_lintel() -> Array[Sprite2D]:
	return _lintel


## The rock drawn beside the passage of the boss gate (D-206); empty for a tunnel.
func get_passage_walls() -> Array[Sprite2D]:
	return _passage_walls


## The roof over the passage of the boss gate, the opening of its arch cut out (#876edf4a); empty for
## a tunnel.
func get_passage_roof() -> Array[Sprite2D]:
	return _passage_roof


## Does the passage behind this gate run under the rock (D-143)? Not for the boss gate (D-206).
func is_tunnel() -> bool:
	return is_in_group(TUNNEL_GROUP)


## Door-local rectangles of the passage tiles (door tile first); a player inside one is in the tunnel.
func get_passage_rects() -> Array[Rect2]:
	return _passage_rects


## Door-local rectangles where a player is hidden under the rock: the passage without the door tile
## (the arch of a north gate or the notch of a side gate shows him, G2).
func get_hidden_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for rect in _passage_rects:
		if rect.position != Vector2.ZERO:
			rects.append(rect)
	return rects


## Hook (bug report 23.10.2026 #0bfc40e0, for Flint's glow): does the world point lie under rock that
## a gate's cover draws over every figure (z LINTEL_Z and up: the crown over a north passage, the
## tunnel rock of a side passage, the boss gate's roof)? Pure optics, tile pieces of the cover.
static func is_under_rock(tree: SceneTree, point: Vector2) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(COVER_GROUP):
		var view := node as DoorView
		if view == null or not view.is_inside_tree():
			continue
		var local := view.to_local(point)
		for piece in view._lintel + view._passage_roof + view._passage_walls:
			if not is_instance_valid(piece) or not piece.visible or piece.z_index < LINTEL_Z:
				continue
			var rect := piece.get_rect()
			if Rect2(piece.position + rect.position * piece.scale, rect.size * piece.scale).has_point(local):
				return true
	return false


## Is this world point inside the passage of any gate with a tunnel, where the rock hides a player?
## Things a player carries (the relic) hide with him (pure optics); in the arch or the notch of a gate
## he is seen (G2), so they are too.
static func is_in_tunnel(tree: SceneTree, point: Vector2) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(TUNNEL_GROUP):
		var view := node as DoorView
		if view == null or not view.is_inside_tree():
			continue
		var local := view.to_local(point)
		for rect: Rect2 in view.get_hidden_rects():
			if rect.grow(-4.0).has_point(local):
				return true
	return false


func _build_lintel() -> void:
	for piece in _lintel + _lintel_extras + _passage_walls + _passage_roof:
		if is_instance_valid(piece):
			remove_child(piece)
			piece.free()
	_lintel.clear()
	_lintel_extras.clear()
	_passage_walls.clear()
	_passage_roof.clear()
	_passage_rects.clear()
	_shade_top = null
	_crown_full.clear()
	_crown_cut.clear()
	_arch_view = false
	_side_over = false
	if not is_inside_tree() or _lintel_rooms.size() < 2:
		return
	var rooms: Array = []
	for room in _lintel_rooms:
		if is_instance_valid(room):
			rooms.append(room)
	var own_tiles := (rooms[0] as Node).get_node_or_null("Tiles") as RoomTiles if not rooms.is_empty() else null
	if rooms.size() < 2 or own_tiles == null:
		return
	var outward := -Vector2i(get_inward())
	var door_cell := PassageSeam.origin_of(rooms[0]) + own_tiles.local_to_map(own_tiles.to_local(global_position + Vector2.ONE * TILE * 0.5))
	for cell in PassageCover.passage_cells(door_cell, outward, rooms[1]):
		_passage_rects.append(Rect2(Vector2(cell - door_cell) * TILE, Vector2.ONE * TILE))
	# D-206: no tunnel before the boss gate (the room before the boss is always left to the north).
	if style.is_boss() and not _is_side():
		if is_in_group(TUNNEL_GROUP):
			remove_from_group(TUNNEL_GROUP)
		_build_boss_passage(rooms, door_cell, outward)
		if not _passage_roof.is_empty():
			add_to_group(COVER_GROUP)
		return
	if not _passage_rects.is_empty():
		add_to_group(TUNNEL_GROUP)
		add_to_group(COVER_GROUP)
	# A side gate is a notch in the side wall: its door tile stays floor, the terrain draws the wall
	# round it (G2 note 18). A north gate shows its arch and gate on the door tile: there the front is
	# drawn only around the opening (no floor of the door tile beside the arch).
	var north := not _is_side()
	var plan := PassageCover.plan(rooms, door_cell, outward, not north, not north)
	var notch: Dictionary = {}
	if not north:
		notch = _side_notch_cells(rooms, door_cell, outward, plan)
		plan = notch["plan"]
	for entry: Dictionary in plan:
		var cell: Vector2i = entry["cell"]
		var on_door := north and cell == door_cell
		var piece := _cover_sprite(entry, door_cell, on_door)
		if piece == null:
			continue
		if not north:
			# In front of a player in the notch: the rock deeper in the passage and below the notch;
			# its wall face above stays behind him (seen from the front).
			var rel := cell - door_cell
			var over := rel.x * outward.x + rel.y * outward.y > 0 or rel.y > 0
			piece.set_meta(&"over_player", over)
			piece.z_index = LINTEL_Z if over else SIDE_COVER_LOW_Z
		elif cell.y == door_cell.y:
			# The fronts beside a north gate stay behind its torches, the opening and the players.
			piece.z_index = FRONT_PATCH_Z
		elif north:
			# Over the opening: a twin with the opening cut out, shown while a player is in the arch.
			var cut := _cover_sprite(entry, door_cell, true)
			if cut != null:
				cut.name = "LintelCut%d" % _crown_cut.size()
				cut.visible = false
				_lintel_extras.append(cut)
				_crown_cut.append(cut)
				_crown_full.append(piece)
		_lintel.append(piece)
	if _is_side():
		for entry: Dictionary in PassageCover.notch_floor(rooms, door_cell, outward):
			var floor_piece := _cover_sprite(entry, door_cell)
			if floor_piece != null:
				floor_piece.name = "NotchFloor%d" % _lintel_extras.size()
				floor_piece.z_index = SIDE_COVER_LOW_Z - 1
				_lintel_extras.append(floor_piece)
		_build_notch_rows(door_cell, outward, notch)
		_build_side_notch()
	else:
		_build_frame_top()


## The passage of the boss gate. D-206 (Projektmitglied 22.10.2026, "da müsste Boden sein") kept it
## open; bug report 23.10.2026 #876edf4a ("Hier oben mach ruhig zu. Aber schneid halt da beim
## Torbogen aus"): the crown runs closed over it again like over every north gate (PassageCover.plan,
## the rooms' own fronts beside the gate stay), but the opening of the arch is cut out of the rock over
## the way, so the floor and the boss room are seen through the arch; the top of the frame stands in
## front of the crown. No tunnel: no dark in the arch, nobody darkened (a player under the roof beside
## the opening is hidden like under any rock).
func _build_boss_passage(rooms: Array, door_cell: Vector2i, outward: Vector2i) -> void:
	for entry: Dictionary in PassageCover.plan(rooms, door_cell, outward, false, false):
		var cell: Vector2i = entry["cell"]
		if cell.y == door_cell.y:
			continue
		var on_way := cell.x == door_cell.x
		var piece := _cover_sprite(entry, door_cell, true) if on_way else null
		if piece == null:
			piece = _cover_sprite(entry, door_cell)
		if piece == null:
			continue
		if on_way:
			piece.name = "PassageRoof%d" % _passage_roof.size()
			_passage_roof.append(piece)
		else:
			piece.name = "PassageWall%d" % _passage_walls.size()
			_passage_walls.append(piece)
	if _passage_roof.is_empty() or _frame == null:
		return
	var top_texture := _frame_top_texture(style)
	if top_texture != null:
		var top := _opening_sprite("FrameTop", top_texture, LINTEL_Z + 1)
		top.modulate = _frame.modulate


## The dark of the tunnel in the notch of a side gate (DoorArt.side_notch_image): clear at the mouth,
## dark where the passage runs on into the rock; over the players, so one walking in fades into it.
## Only over the open share of the door tile (SIDE_NOTCH_OPEN).
func _build_side_notch() -> void:
	var notch := Sprite2D.new()
	notch.name = "SideNotch"
	notch.texture = DoorArt.get_side_notch()
	notch.centered = false
	var open_share := clampf(SIDE_NOTCH_OPEN, 0.1, 1.0)
	notch.scale = Vector2(open_share, 1.0) * TILE / float(notch.texture.get_width())
	# Drawn for an east wall (the room on the left); a west wall mirrors it and starts further in.
	notch.flip_h = side == RoomTiles.DoorSide.WEST
	if side == RoomTiles.DoorSide.WEST:
		notch.position.x = TILE * (1.0 - open_share)
	# The picture starts DoorArt.NOTCH_RISE art px above the door tile (soft over the front).
	notch.position.y = -float(DoorArt.NOTCH_RISE) * notch.scale.y
	notch.z_index = LINTEL_Z + 1
	add_child(notch)
	_lintel_extras.append(notch)


## The notch of a side gate only SIDE_NOTCH_OPEN deep. Of the cover plan the cells of the door
## column and the column behind it in SIDE_NOTCH_ROWS are taken out: the column behind is drawn as
## if the passage were closed (no light edge where the notch's back wall used to be), the door column
## by _build_notch_rows as the notch moved towards the room. Returns {"plan": the rest of the cover,
## "open": cell -> entry of the notch plan, "fillet": the fillet entry of the notch floor or {}}; the
## plain plan with SIDE_NOTCH_OPEN 1.
func _side_notch_cells(rooms: Array, door_cell: Vector2i, outward: Vector2i, open_plan: Array[Dictionary]) -> Dictionary:
	var result := {"plan": open_plan, "open": {}, "fillet": {}}
	if SIDE_NOTCH_OPEN >= 1.0:
		return result
	var open: Dictionary = {}
	for entry: Dictionary in open_plan:
		open[entry["cell"]] = entry
	var closed: Dictionary = {}
	for entry: Dictionary in PassageCover.plan(rooms, door_cell, outward, false, false):
		closed[entry["cell"]] = entry
	var taken: Dictionary = {}
	for row: int in SIDE_NOTCH_ROWS:
		taken[door_cell + Vector2i(0, row)] = true
		taken[door_cell + outward + Vector2i(0, row)] = true
	var rest: Array[Dictionary] = []
	for entry: Dictionary in open_plan:
		if not taken.has(entry["cell"]):
			rest.append(entry)
	# The column behind the door tile: closed rock (its own outer side unchanged).
	for row: int in SIDE_NOTCH_ROWS:
		var behind: Vector2i = door_cell + outward + Vector2i(0, row)
		if closed.has(behind):
			rest.append(closed[behind])
		elif open.has(behind):
			rest.append(open[behind])
	result["plan"] = rest
	result["open"] = open
	for entry: Dictionary in PassageCover.notch_floor(rooms, door_cell, outward):
		var atlas: Vector3i = entry["atlas"]
		var tiles := (entry["room"] as Node).get_node_or_null("Tiles") as RoomTiles
		if tiles != null and tiles.is_terrain_drawn() and atlas.z == RockTerrain.rock_source(tiles.get_look()):
			result["fillet"] = entry
	return result


## The door column of a shallower notch (_side_notch_cells), one sprite per row: every art column
## u (counted from the door tile's outer side towards the room) shows the notch plan's picture at
## u - shift (shift = the closed share), so the back wall, the corners of the notch's front and foot
## and its fillet come that much closer to the room; the last SIDE_NOTCH_ROOM_EDGE columns keep
## their own picture (the room wall's light edge). Above the players like the other pieces.
func _build_notch_rows(door_cell: Vector2i, outward: Vector2i, notch: Dictionary) -> void:
	if notch.is_empty() or (notch["open"] as Dictionary).is_empty():
		return
	var open: Dictionary = notch["open"]
	for row: int in SIDE_NOTCH_ROWS:
		var cell: Vector2i = door_cell + Vector2i(0, row)
		var own: Dictionary = open.get(cell, {})
		if row == 0:
			own = notch["fillet"]
		var behind: Dictionary = open.get(cell + outward, {})
		var owner: Dictionary = own if not own.is_empty() else behind
		if owner.is_empty():
			continue
		var tiles := (owner["room"] as Node).get_node_or_null("Tiles") as RoomTiles
		if tiles == null:
			continue
		var texture := _notch_row_texture(own, behind, row)
		if texture == null:
			continue
		# The rock beside the notch's floor and its foot lie over a player in the passage, its front
		# and crown above stay behind him (as _build_lintel). Above the floor only the open share is
		# the notch's front: the closed share is the rock of the tunnel and lies over him too (bug
		# reports 22.10.2026 #09ae5f43 "mein Kopf schaut hier raus", #d43c7121: head and body of a
		# player deeper in the passage stuck out over the door column).
		if row >= 0:
			_add_notch_piece(texture, row, Rect2(), true, tiles)
			continue
		var size := float(texture.get_width())
		var closed := roundf(size * (1.0 - clampf(SIDE_NOTCH_OPEN, 0.0, 1.0)))
		var west := side == RoomTiles.DoorSide.WEST
		# The closed share is the outer side of the door tile: left on a west wall, right on an east wall.
		var closed_rect := Rect2(0.0 if west else size - closed, 0.0, closed, size)
		var open_rect := Rect2(closed if west else 0.0, 0.0, size - closed, size)
		if open_rect.size.x > 0.0:
			_add_notch_piece(texture, row, open_rect, false, tiles)
		if closed_rect.size.x > 0.0:
			_add_notch_piece(texture, row, closed_rect, true, tiles)


## One sprite of a notch row (region: part of its picture, empty = all of it).
func _add_notch_piece(texture: Texture2D, row: int, region: Rect2, over_player: bool, tiles: RoomTiles) -> void:
	var piece := Sprite2D.new()
	piece.name = ("NotchRow%dClosed" if region.has_area() and over_player else "NotchRow%d") % (row + 2)
	piece.texture = texture
	piece.centered = false
	var piece_scale := TILE / float(texture.get_width())
	piece.scale = Vector2.ONE * piece_scale
	piece.position = Vector2(0.0, row * TILE)
	if region.has_area():
		piece.region_enabled = true
		piece.region_rect = region
		piece.position.x = region.position.x * piece_scale
	piece.material = tiles.material
	piece.modulate = tiles.modulate
	piece.z_index = LINTEL_Z if over_player else SIDE_COVER_LOW_Z
	piece.set_meta(&"over_player", over_player)
	add_child(piece)
	_lintel.append(piece)


## The picture of one row of a shallower notch (see _build_notch_rows), cached; null without art.
func _notch_row_texture(own: Dictionary, behind: Dictionary, row: int) -> Texture2D:
	var own_image := _entry_image(own)
	var behind_image := _entry_image(behind)
	var size := own_image.get_width() if own_image != null else (behind_image.get_width() if behind_image != null else 0)
	if size <= 0:
		return null
	var shift := roundi(size * (1.0 - clampf(SIDE_NOTCH_OPEN, 0.0, 1.0)))
	var keep := mini(SIDE_NOTCH_ROOM_EDGE, size)
	var west := side == RoomTiles.DoorSide.WEST
	var key := "notch|%s|%s|%d|%d|%d|%s" % [_entry_key(own), _entry_key(behind), shift, keep, row, west]
	return _cached_texture(key, func() -> Image:
		var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		for u in size:
			var from := u - shift if u < size - keep else u
			var source := own_image
			if from < 0:
				source = behind_image
				from += size
			if source == null or source.get_width() != size:
				continue
			# u counts from the outer side: x = u on a west wall (outer side left), mirrored on an east wall.
			var x := u if west else size - 1 - u
			var source_x := from if west else size - 1 - from
			image.blit_rect(source, Rect2i(source_x, 0, 1, size), Vector2i(x, 0))
		return image)


## The art of a cover entry ({"room", "atlas"}) as an image (its region of the sheet), null for none.
func _entry_image(entry: Dictionary) -> Image:
	if entry.is_empty():
		return null
	var tiles := (entry["room"] as Node).get_node_or_null("Tiles") as RoomTiles
	var atlas: Vector3i = entry["atlas"]
	if tiles == null or tiles.tile_set == null or not tiles.tile_set.has_source(atlas.z):
		return null
	var source := tiles.tile_set.get_source(atlas.z) as TileSetAtlasSource
	if source == null or source.texture == null or not source.has_tile(Vector2i(atlas.x, atlas.y)):
		return null
	var sheet := _sheet_image(source.texture)
	return sheet.get_region(source.get_tile_texture_region(Vector2i(atlas.x, atlas.y))) if sheet != null else null


## Cache key of a cover entry: its sheet texture and atlas cell. Bug reports 22.10.2026 (#da48eb51,
## #09ae5f43, #d43c7121, "Texturen aus falschem Biom"): a TileSet has no RID (get_rid() is 0 for every
## biome's set), so the notch of the first biome was reused in every later one; the sheet texture
## differs per biome.
func _entry_key(entry: Dictionary) -> String:
	if entry.is_empty():
		return "-"
	var tiles := (entry["room"] as Node).get_node_or_null("Tiles") as RoomTiles
	var atlas: Vector3i = entry["atlas"]
	var sheet_id := 0
	if tiles != null and tiles.tile_set != null and tiles.tile_set.has_source(atlas.z):
		var source := tiles.tile_set.get_source(atlas.z) as TileSetAtlasSource
		if source != null and source.texture != null:
			sheet_id = source.texture.get_rid().get_id()
	return "%d:%s" % [sheet_id, atlas]


## Door-local x of the middle of a side gate's notch (the open share at the room side).
func side_notch_center_x() -> float:
	var open_share := clampf(SIDE_NOTCH_OPEN, 0.1, 1.0)
	if side == RoomTiles.DoorSide.WEST:
		return TILE * (1.0 - open_share * 0.5)
	if side == RoomTiles.DoorSide.EAST:
		return TILE * open_share * 0.5
	return TILE * 0.5


func get_side_notch() -> Sprite2D:
	return get_node_or_null(^"SideNotch") as Sprite2D


## One cover piece as a sprite above the characters: the atlas region of the owner room's tileset,
## its rock material (world-space stones) and its biome tint. cut_opening: the opening of the frame is
## cut out of the piece (DoorArt.cut_opening); null if the piece does not reach into it.
func _cover_sprite(entry: Dictionary, door_cell: Vector2i, cut_opening := false) -> Sprite2D:
	var tiles := (entry["room"] as Node).get_node_or_null("Tiles") as RoomTiles
	var atlas: Vector3i = entry["atlas"]
	if tiles == null or tiles.tile_set == null or not tiles.tile_set.has_source(atlas.z):
		return null
	var source := tiles.tile_set.get_source(atlas.z) as TileSetAtlasSource
	if source == null or source.texture == null or not source.has_tile(Vector2i(atlas.x, atlas.y)):
		return null
	var region := Rect2(source.get_tile_texture_region(Vector2i(atlas.x, atlas.y)))
	var piece_pos := Vector2((entry["cell"] as Vector2i) - door_cell) * TILE
	var piece_scale := TILE / region.size.x
	var piece := Sprite2D.new()
	piece.name = "Lintel%d" % _lintel.size()
	if not _set_piece_texture(piece, source, region, cut_opening, piece_pos, piece_scale):
		piece.free()
		return null
	piece.material = tiles.material
	piece.modulate = tiles.modulate
	piece.centered = false
	piece.scale = Vector2.ONE * piece_scale
	piece.position = piece_pos
	piece.z_index = LINTEL_Z
	add_child(piece)
	# A room between two biomes (campfire, A6): the second look over it through the same world-space
	# mask as the room's blend layer, so the rock matches the wall around it (G2 note 27).
	var blend := tiles.get_blend_layer() if tiles.has_biome_blend() else null
	if blend != null and blend.tile_set != null and blend.tile_set.has_source(atlas.z):
		var blend_source := blend.tile_set.get_source(atlas.z) as TileSetAtlasSource
		if blend_source != null and blend_source.texture != null and blend_source.has_tile(Vector2i(atlas.x, atlas.y)):
			var twin := Sprite2D.new()
			twin.name = "Blend"
			var blend_region := Rect2(blend_source.get_tile_texture_region(Vector2i(atlas.x, atlas.y)))
			if _set_piece_texture(twin, blend_source, blend_region, cut_opening, piece_pos, piece_scale):
				twin.material = blend.material
				twin.modulate = blend.modulate
				twin.centered = false
				twin.scale = region.size / blend_region.size
				piece.add_child(twin)
			else:
				twin.free()
	return piece


## The texture of a cover piece: the region of the sheet, or with the opening of the frame cut out
## (DoorArt.cut_opening). False if a cut piece does not reach into the opening.
func _set_piece_texture(sprite: Sprite2D, source: TileSetAtlasSource, region: Rect2, cut_opening: bool, piece_pos: Vector2, piece_scale: float) -> bool:
	if cut_opening:
		if style == null:
			return false
		var key := "cut|%d|%s|%s|%s|%s" % [source.texture.get_rid().get_id(), region, style.get_key(), piece_pos, piece_scale]
		var texture := _cached_texture(key, func() -> Image:
			var sheet := _sheet_image(source.texture)
			if sheet == null:
				return null
			var cut := DoorArt.cut_opening(sheet.get_region(Rect2i(region)), style, piece_pos, piece_scale, PIXEL_SCALE)
			return cut["image"] if int(cut["cut"]) > 0 else null)
		if texture == null:
			return false
		sprite.texture = texture
		return true
	# The region of the sheet, clipped at its edges: no seam of the neighbouring piece between two
	# cover tiles at any zoom.
	sprite.texture = source.texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.region_filter_clip_enabled = true
	return true


## The part of the frame above the door tile drawn over the cover, its passage a dark tunnel: the
## arch or mouth keeps its shape in front of the closed crown (36.png). Below it the dark runs on
## softly into the door tile (no hard shadow edge, 39.png). Nothing in the opening changes while a
## player walks through (G2 note 20: he darkens himself, _dim_players).
func _build_frame_top() -> void:
	if style == null or _frame == null:
		return
	# The dark of the tunnel over the crown above the cover, under the top of the frame (the delivered
	# inner shadow of V9 or the opening's own); its part over the door tile on the floor, under the
	# gate and the players.
	var top_shade := _top_shade_texture(style)
	if top_shade != null:
		_shade_top = _opening_sprite("ShadeTop", top_shade, LINTEL_Z + 1)
	var top_texture := _frame_top_texture(style)
	if top_texture != null:
		var top := _opening_sprite("FrameTop", top_texture, LINTEL_Z + 1)
		top.modulate = _frame.modulate
	# Everything seen in the opening is cut to the arch (44.png): the floor where the arch is wider
	# than the door tile, the soft dark at its top, the shade that hides a player in the arch.
	var tiles := _lintel_rooms[0].get_node_or_null("Tiles") as RoomTiles
	var floor_texture := _opening_floor_texture(false)
	if floor_texture != null:
		var opening_floor := _opening_sprite("OpeningFloor", floor_texture, OPENING_FLOOR_Z)
		opening_floor.material = tiles.material
		opening_floor.modulate = tiles.modulate
		# The floor of the second biome where the room blends into it (campfire).
		var blend_texture := _opening_floor_texture(true)
		if blend_texture != null:
			var twin := Sprite2D.new()
			twin.name = "Blend"
			twin.texture = blend_texture
			twin.centered = false
			twin.material = tiles.get_blend_layer().material
			twin.modulate = tiles.get_blend_layer().modulate
			opening_floor.add_child(twin)
	if DoorArt.get_delivered_shade(style) != null:
		_opening_sprite("ShadeFloor", _floor_shade_texture(style), OPENING_FLOOR_Z)
	else:
		_opening_sprite("TunnelFade", _floor_shade_texture(style), 0)


## Door pictures of a biome built ahead (every style of DoorArt.styles_of, the signs, the light
## cone): no gate builds them while its room is prepared (feedback 16.10.2026).
static func warm_up(biome_id: StringName) -> void:
	for style in DoorArt.styles_of(biome_id):
		warm_style(style)
	DoorArt.warm_symbols()
	_cone_texture()


## The pictures of one door style (frame, gates, glow, opening, mouth deco) and its opening sprites,
## built ahead.
static func warm_style(style: DoorStyle) -> void:
	for step in warm_steps(style):
		step.call()


## warm_style in small steps (one picture each, a few ms), for the DungeonManager's idle frames.
static func warm_steps(style: DoorStyle) -> Array[Callable]:
	var steps: Array[Callable] = []
	steps.append(func() -> void: DoorArt.get_frame(style))
	steps.append(func() -> void: DoorArt.get_leaf_strip(style))
	steps.append(func() -> void: DoorArt.get_side_leaf_strip(style))
	steps.append(func() -> void: DoorArt.get_glow(style))
	steps.append(func() -> void: DoorArt.passage_mask(style))
	steps.append(func() -> void: DoorArt.frame_top_row(style))
	for cell: StringName in DoorArt.OVERLAY_CELLS:
		steps.append(func() -> void: DoorArt.get_overlay(style.biome_id, style.soft, cell))
	steps.append(func() -> void: _top_shade_texture(style))
	steps.append(func() -> void: _frame_top_texture(style))
	steps.append(func() -> void: _floor_shade_texture(style))
	return steps


## The dark of the tunnel above the door tile (DoorArt.opening_top_image), null for none.
static func _top_shade_texture(style: DoorStyle) -> Texture2D:
	return _cached_texture("shade_top|" + style.get_key(), func() -> Image: return DoorArt.opening_top_image(style))


## The frame above the door tile (DoorArt.frame_top_image), null for none.
static func _frame_top_texture(style: DoorStyle) -> Texture2D:
	return _cached_texture("frame_top|" + style.get_key(), func() -> Image: return DoorArt.frame_top_image(style))


## The dark in the opening over the door tile: the delivered inner shadow's lower rows, else the
## fade of the tunnel (DoorArt.tunnel_fade_image).
static func _floor_shade_texture(style: DoorStyle) -> Texture2D:
	var delivered := DoorArt.get_delivered_shade(style)
	if delivered != null:
		return _cached_texture("shade_floor|" + style.get_key(),
				func() -> Image: return DoorArt.rows_of(delivered, style.leaf_offset.y, delivered.get_height()))
	return _cached_texture("tunnel_fade|" + style.get_key(), func() -> Image: return DoorArt.tunnel_fade_image(style))


## The light cone of a way (DoorArt.soft_cone of door_glow.png), null without the art.
## The soft light cone of a way (CONE_PATH, sides faded), null without the art: also the light of the
## soul gate on the floor in front of it (SoulGate).
static func way_cone_texture() -> Texture2D:
	return _cone_texture()


static func _cone_texture() -> Texture2D:
	var raw := load(CONE_PATH) as Texture2D if ResourceLoader.exists(CONE_PATH) else null
	if raw == null:
		return null
	# At its base the cone is as wide as the opening (one tile), its sides fade out (L1, 15.10.2026).
	var base_share := TILE / (PIXEL_SCALE * CONE_SCALE * raw.get_width())
	return DoorArt.soft_cone(raw, CONE_FADE_IN, base_share)


## The door tile's floor seen through the opening (DoorArt.opening_floor_image), per style and floor
## piece; null without a floor there.
func _opening_floor_texture(blend: bool) -> Texture2D:
	var floor_source := _door_floor_source(Vector2i.ZERO, blend)
	if floor_source.is_empty():
		return null
	var texture: Texture2D = floor_source[0]
	var region: Rect2i = floor_source[1]
	return _cached_texture("floor|%s|%d|%s" % [style.get_key(), texture.get_rid().get_id(), region], func() -> Image:
		var sheet := _sheet_image(texture)
		return DoorArt.opening_floor_image(style, sheet.get_region(region)) if sheet != null else null)


## Texture of the image build makes (Callable() -> Image, null = nothing), made once per key.
static func _cached_texture(key: String, build: Callable) -> Texture2D:
	if not _textures.has(key):
		if _textures.size() >= TEXTURE_CACHE_MAX:
			_textures.clear()
		var image: Image = build.call()
		_textures[key] = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	return _textures[key]


## A frame-sized sprite on the frame's place (art px at the pixel scale).
func _opening_sprite(node_name: String, texture: Texture2D, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * PIXEL_SCALE
	sprite.position = -Vector2(style.leaf_offset) * PIXEL_SCALE
	sprite.z_index = z
	add_child(sprite)
	_lintel_extras.append(sprite)
	return sprite


## Sheet and region of the floor tile the door's room paints on the door tile (plus offset tiles; art
## px), empty without one. blend: the same tile in the room's second biome (biome blend).
func _door_floor_source(offset: Vector2i, blend := false) -> Array:
	var tiles := _lintel_rooms[0].get_node_or_null("Tiles") as RoomTiles if not _lintel_rooms.is_empty() and is_instance_valid(_lintel_rooms[0]) else null
	if tiles == null or tiles.tile_set == null:
		return []
	var tile_set := tiles.tile_set
	if blend:
		if not tiles.has_biome_blend() or tiles.get_blend_layer().tile_set == null:
			return []
		tile_set = tiles.get_blend_layer().tile_set
	var cell := tiles.local_to_map(tiles.to_local(global_position + Vector2.ONE * TILE * 0.5)) + offset
	var source_id := tiles.get_cell_source_id(cell)
	if source_id == -1 or not tile_set.has_source(source_id):
		return []
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.texture == null:
		return []
	# The sheet comes from _sheet_image (cached): get_image() reads the whole atlas back from the GPU.
	return [source.texture, source.get_tile_texture_region(tiles.get_cell_atlas_coords(cell))]


func _update_lintel(delta: float) -> void:
	if _lintel.is_empty():
		return
	var in_arch := _arch_depths()
	var beyond := _player_in_passage_beyond_door()
	var under := beyond or not in_arch.is_empty()
	if _is_side():
		_set_side_over(under)
	else:
		# G2: the rock over the arch is cut to the opening while players stand in the arch only (one
		# further in would show through the cut).
		_set_arch_view(not in_arch.is_empty() and not beyond)
		_dim_players(delta)
	var target := lintel_under_alpha if under else 1.0
	for piece in _lintel + _crown_cut:
		if piece.z_index >= LINTEL_Z:
			piece.modulate.a = move_toward(piece.modulate.a, target, delta * LINTEL_FADE_SPEED)


## Share of a player's colour seen in the arch (G2) at depth 0 (where he steps in from the room) .. 1
## (where the crown begins).
static func arch_visibility(depth: float) -> float:
	return lerpf(ARCH_VISIBLE_ENTRY, ARCH_VISIBLE_DEEP, clampf(depth, 0.0, 1.0))


## Bug report 17.10.2026 (#0db1e7b0, "warum ist man hier noch dunkel beim Rauskommen"): the last tile
## of a passage is the wall of the room behind it; a player whose feet are in it already stands with
## his body in that room. His colour comes back over that tile: down 0 (its far edge, the room's
## floor) = full colour .. 1 (where the tunnel is) = ARCH_VISIBLE_DEEP.
static func exit_visibility(down: float) -> float:
	return lerpf(1.0, ARCH_VISIBLE_DEEP, clampf(down, 0.0, 1.0))


## Depths (0 at the room side .. 1 at the crown) of the living players whose feet stand in the door
## tile of a north gate (the sprite rises from the feet: once they are under the crown, all of him
## is); empty for a side gate (its door tile lies under the rock).
func _arch_depths() -> Array[float]:
	var depths: Array[float] = []
	if _is_side() or _passage_rects.is_empty() or not is_inside_tree():
		return depths
	var rect: Rect2 = _passage_rects[0]
	for player in EnemyTargeting.living_players(get_tree()):
		var feet := to_local(player.global_position + Player.FEET_OFFSET)
		if _in_door_lane(rect, feet):
			depths.append(clampf(1.0 - (feet.y - rect.position.y) / rect.size.y, 0.0, 1.0))
	return depths


## Is a living player in the passage beyond the arch (his feet under the crown; for a side gate
## anywhere in it, its door tile lies in the closed side wall)?
func _player_in_passage_beyond_door() -> bool:
	var first := 0 if _is_side() else 1
	if _passage_rects.size() <= first or not is_inside_tree():
		return false
	var last := _passage_rects.size() - 1
	for player in EnemyTargeting.living_players(get_tree()):
		var feet := to_local(player.global_position + Player.FEET_OFFSET)
		for i in range(first, _passage_rects.size()):
			var rect: Rect2 = _passage_rects[i]
			if i == last and _is_side():
				rect = side_exit_rect(rect)
			if _in_door_lane(rect, feet):
				return true
	return false


## The last tile of a side passage reaching SIDE_EXIT_REACH into the room behind it (#bcff6539): the
## feet of a player there still have his picture over the wall.
func side_exit_rect(rect: Rect2) -> Rect2:
	var outward := -get_inward()
	return rect.expand(rect.get_center() + outward * (rect.size.x * 0.5 + SIDE_EXIT_REACH))


## point inside rect; for a north gate a little in from its sides along the way (the feet of a player
## brushing past the arch). A side passage has rock above and below it, so feet anywhere in its row
## are in it: bug report 22.10.2026 #331603b8 ("da stimmt der Layer komplett nicht") - a player
## walking along its south side has his feet less than 4 px above that rock and was drawn over it.
func _in_door_lane(rect: Rect2, point: Vector2) -> bool:
	if _is_side():
		return rect.has_point(point)
	return point.y >= rect.position.y and point.y < rect.end.y and point.x > rect.position.x + 4.0 and point.x < rect.end.x - 4.0


## Players in the arch (on): they are seen only through the opening - the full crown pieces over the
## opening lie under them with the dark of the tunnel, the cut twins above them, and the fronts
## around the opening, the frame and its torches are drawn over them (G2 note 20: nothing of a player,
## his weapon neither, reaches past the arch). Off: everything as it was.
func _set_arch_view(on: bool) -> void:
	if on == _arch_view:
		return
	_arch_view = on
	var door_row_y := 0.0
	for piece in _lintel:
		if is_equal_approx(piece.position.y, door_row_y):
			piece.z_index = LINTEL_Z if on else FRONT_PATCH_Z
	for sprite: Node2D in [_frame, _glow]:
		if sprite != null:
			sprite.z_index = LINTEL_Z + 1 if on else 0
	for torch in _torches:
		torch.z_index = LINTEL_Z + 1 if on else 0
	# A cave mouth opens no higher than its door tile: nothing to cut, the crown stays over him.
	for i in _crown_cut.size():
		var full := _crown_full[i]
		full.z_index = FRONT_PATCH_Z if on else LINTEL_Z
		if on:
			full.modulate.a = 1.0
		_crown_cut[i].visible = on
		_crown_cut[i].modulate.a = full.modulate.a
	if _shade_top != null and not _crown_cut.is_empty():
		_shade_top.z_index = OPENING_FLOOR_Z if on else LINTEL_Z + 1


## G2 note 20: a player in the passage of a north gate darkens with the depth (arch_visibility; under
## the crown the deepest share) and brightens again once he is out of it. Optics only, per player:
## the colour of his node, which nothing else sets.
func _dim_players(delta: float) -> void:
	if _passage_rects.is_empty() or not is_inside_tree():
		return
	var seen: Dictionary = {}
	for player in EnemyTargeting.living_players(get_tree()):
		var feet := to_local(player.global_position + Player.FEET_OFFSET)
		var share := -1.0
		var last := _passage_rects.size() - 1
		for i in _passage_rects.size():
			if _in_door_lane(_passage_rects[i], feet):
				var rect: Rect2 = _passage_rects[i]
				var down := clampf((feet.y - rect.position.y) / rect.size.y, 0.0, 1.0)
				if i == 0:
					share = arch_visibility(1.0 - down)
				elif i == last:
					share = exit_visibility(down)
				else:
					share = ARCH_VISIBLE_DEEP
				break
		if share < 0.0:
			continue
		seen[player.get_instance_id()] = true
		_dimmed[player.get_instance_id()] = player
		_shade_player(player, share, delta)
	for id: int in _dimmed.keys():
		if seen.has(id):
			continue
		var player := _dimmed[id] as Node2D
		if not is_instance_valid(player):
			_dimmed.erase(id)
			continue
		if _shade_player(player, 1.0, delta):
			_dimmed.erase(id)


## Moves a player's colour towards share (grey level); true once it is there.
static func _shade_player(player: Node2D, share: float, delta: float) -> bool:
	var value := move_toward(player.modulate.r, share, delta * SHADE_FADE_SPEED)
	player.modulate = Color(value, value, value, player.modulate.a)
	return is_equal_approx(value, share)


## Gives every player this passage darkened his colour back (the door leaves the tree).
func _restore_players() -> void:
	for id: int in _dimmed.keys():
		var player := _dimmed[id] as Node2D
		if is_instance_valid(player):
			player.modulate = Color(1, 1, 1, player.modulate.a)
	_dimmed.clear()


func _exit_tree() -> void:
	_restore_players()


## A player in the side passage (on). The tunnel's rock lies over every figure either way (#0bfc40e0,
## SIDE_COVER_LOW_Z); only its see-through share (lintel_under_alpha) follows a player inside.
func _set_side_over(on: bool) -> void:
	if on == _side_over:
		return
	_side_over = on
	for piece in _lintel:
		var over := bool(piece.get_meta(&"over_player", true))
		piece.z_index = LINTEL_Z if over else SIDE_COVER_LOW_Z
		if over and on:
			piece.modulate.a = 1.0


## Are players standing in the arch (seen through the opening, the rock over it cut to it, G2)?
func is_arch_view() -> bool:
	return _arch_view


## Image of a tile sheet (decompressed, RGBA8), cached per texture.
static func _sheet_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var key := texture.get_rid()
	if not _sheets.has(key):
		if _sheets.size() >= SHEET_CACHE_MAX:
			_sheets.clear()
		var image := texture.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		_sheets[key] = image
	return _sheets[key]


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
## the sign above it. M2: the corridor behind it is one tile, the wall of the next room; G2: the door
## tile is a notch in the side wall (PassageCover, open door tile) running into the dark of the
## tunnel, the rest of the passage lies under the rock, the leaf closes the notch's mouth. No torch
## and no torch light in a passage (40.png): the way light shows the way.
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
		_leaf.position = Vector2(-SIDE_LEAF_SHIFT if side == RoomTiles.DoorSide.EAST else SIDE_LEAF_SHIFT, 0.0)
		_leaf.modulate = Color.WHITE
		# On the mouth of the notch, above its floor and under the players in front of it.
		_leaf.z_index = SIDE_LEAF_Z
	set_symbol(style.symbol)
	_build_way_light()
	if style.glow_mode == DoorStyle.GLOW_THREAT:
		_threat_light = LightSource.new()
		_threat_light.name = "ThreatLight"
		_threat_light.radius = THREAT_LIGHT_RADIUS
		_threat_light.position = Vector2(TILE * 0.5, TILE * 0.5)
		add_child(_threat_light)
	if not _lintel_rooms.is_empty():
		_build_lintel()


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


## Rubble in a blocked entrance (shown while the entrance is shut, see show_state): over the wall line
## in front of the closed gap, above the wall drawn over it.
func _build_rubble() -> void:
	var inward := get_inward()
	var along := Vector2(absf(inward.y), absf(inward.x))
	var wall_line := Vector2(TILE * 0.5, TILE * 0.5) + inward * TILE * 0.5
	for entry: Dictionary in BLOCKED_RUBBLE:
		var prop := DecoProp.new()
		prop.name = String(entry["item"]).to_pascal_case()
		prop.item = entry["item"]
		prop.position = wall_line + along * float(entry["along"]) + inward * float(entry["inward"])
		prop.visible = false
		# DecoProp puts floor decals under everything in its _ready.
		prop.ready.connect(func() -> void: prop.z_index = RUBBLE_Z, CONNECT_ONE_SHOT)
		add_child(prop)
		_rubble.append(prop)


func get_rubble() -> Array[Node2D]:
	return _rubble


## The wall drawn over a blocked entrance (empty while it is open or before it was built).
func get_seal() -> Array[Sprite2D]:
	return _seal


## Closes a blocked entrance with the room's own wall (PassageCover.sealed_plan): the wall line runs
## straight past the gap, its corridor turns back into rock. Needs the room's tiles (the door's
## parent); false while they are not there yet.
func _build_seal() -> bool:
	_free_sprites(_seal)
	var door := get_parent() as Node2D
	var room := door.get_parent() as Node2D if door != null else null
	var tiles := room.get_node_or_null("Tiles") as RoomTiles if room != null else null
	if tiles == null or tiles.tile_set == null or not is_inside_tree():
		return false
	var door_tile := tiles.local_to_map(tiles.to_local(global_position + Vector2.ONE * TILE * 0.5))
	var outward := -Vector2i(get_inward())
	for entry: Dictionary in PassageCover.sealed_plan(room, door_tile, outward):
		var piece := _cover_sprite(entry, door_tile)
		if piece == null:
			continue
		piece.name = "Seal%d" % _seal.size()
		piece.z_index = SEAL_Z
		_seal.append(piece)
		# The south wall's row over the closed gap is a lip like the wall beside it (bug report
		# 17.10.2026 #5d991188): drawn once more in the y-sort at its foot, so a player walking on the
		# wall's top edge goes behind it there too (RoomTiles lip sprites, Door._fit_shape).
		if outward == Vector2i.DOWN and (entry["cell"] as Vector2i).y == door_tile.y:
			var lip := _cover_sprite(entry, door_tile)
			if lip != null:
				lip.name = "SealLip%d" % _seal.size()
				lip.z_index = 0
				lip.position.y += TILE - RoomTiles.LIP_SORT_FEET
				lip.offset.y = -(TILE - RoomTiles.LIP_SORT_FEET) / lip.scale.y
				for twin in lip.get_children():
					(twin as Sprite2D).offset.y = lip.offset.y / (twin as Sprite2D).scale.y
				_seal.append(lip)
	return true


## Shows or hides the wall over a blocked entrance; it is built once the room's tiles are there.
func _show_seal(shut: bool) -> void:
	_seal_pending = false
	if not is_entrance:
		return
	if shut and _seal.is_empty() and not _build_seal():
		_seal_pending = true
	for piece in _seal:
		piece.visible = shut


func _free_sprites(sprites: Array[Sprite2D]) -> void:
	for sprite in sprites:
		if is_instance_valid(sprite):
			remove_child(sprite)
			sprite.free()
	sprites.clear()


## Shows a state without effects (setup, streaming).
func show_state(open: bool) -> void:
	_door_open = open
	_cone_share = 1.0 if open else CONE_CLOSED_SHARE
	for piece in _rubble:
		piece.visible = not open
	_show_seal(not open)
	if _leaf == null or _leaf.sprite_frames == null:
		return
	if open:
		_leaf.play(&"open")
		_leaf.frame = _leaf.sprite_frames.get_frame_count(&"open") - 1
		_leaf.pause()
	else:
		_leaf.play(&"closed")
	_leaf.visible = not (open and _is_side())
	_glow_strength = _target_glow()


## Door.state_changed: animates and plays effects unless instant.
func on_state_changed(open: bool, instant: bool) -> void:
	if instant or is_entrance:
		show_state(open)
		return
	var changed := open != _door_open
	_door_open = open
	if _leaf != null and _leaf.sprite_frames != null:
		_leaf.visible = true
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
	elif _door_open and _is_side():
		# The rest of the drawn-up leaf would float on the closed side wall.
		_leaf.visible = false


func _process(delta: float) -> void:
	if style == null:
		return
	_time += delta
	if _seal_pending:
		_show_seal(true)
	_update_lintel(delta)
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
			_cone.modulate.a = (_cone_alpha() + CONE_PULSE * sin(_time * CONE_PULSE_SPEED)) * _cone_share
		if _way_light != null:
			_way_light.intensity = WAY_LIGHT_INTENSITY * _cone_share


func _cone_alpha() -> float:
	return SIDE_CONE_ALPHA if _is_side() else CONE_ALPHA


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
		# On the holders of the pillars (frame art x 8 / 56, y 22 of the tall frame, lowered with it).
		var frame_pos := -Vector2(style.leaf_offset) * PIXEL_SCALE
		var holder_y := DoorArt.lowered_row(style, 22)
		spots = [frame_pos + Vector2(8, holder_y) * PIXEL_SCALE, frame_pos + Vector2(56, holder_y) * PIXEL_SCALE]
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
	var texture := _cone_texture()
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
		_cone.modulate = Color(style.way_color, _cone_alpha() * _cone_share)
		add_child(_cone)
	_way_light = LightSource.new()
	_way_light.name = "WayLight"
	_way_light.radius = WAY_LIGHT_RADIUS
	_way_light.intensity = WAY_LIGHT_INTENSITY * _cone_share
	_way_light.color = Color(style.way_color, 1.0)
	# Only on the room side: well inside the room, so it does not light the corridor (35.png).
	_way_light.position = edge + inward * TILE * WAY_LIGHT_INSET
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
	_lintel.clear()
	_lintel_extras.clear()
	_passage_walls.clear()
	_passage_roof.clear()
	_passage_rects.clear()
	_shade_top = null
	_crown_full.clear()
	_crown_cut.clear()
	_arch_view = false
	_side_over = false
	_seal.clear()
	_seal_pending = false
