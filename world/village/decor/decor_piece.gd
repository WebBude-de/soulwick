class_name DecorPiece
extends Node2D
## One placed piece of decoration or furniture (WK5, WK7): its picture with the pivot on the foot
## point, mirrored for the opposite side (DecorItem rotation), the animation strip over it or as the
## picture (fireplace fire, village water), a LightSource at the JSON's light point
## (DecorCatalog.light_radius_tiles), and a static body over the footprint when it blocks. Flat
## pieces (rugs, paving) and wall pieces lie under the players (z_index of the layer), the others
## sort with them by their foot line (SortLift). Also the editor's see-through ghost (ghost = true:
## no light, no collision).

const VISUAL := &"Visual"
const SOLID := &"Solid"
const LIGHT := &"Light"
## TESTWERT: flicker of flame lights (fireplace, stove, fire bowl, torch, candles).
const FLAME_FLICKER := 0.03
const FLAME_KINDS: Array[String] = ["fireplace", "stove", "fire_bowl", "torch_post", "candlestick", "flint_candleholder"]
## Pieces tinted with the guild's colour (V13e: "Modulate = Gildenfarbe").
const GUILD_KINDS: Array[String] = ["guild_banner"]

## Koop hook (WK5): colour of the world's guild for GUILD_KINDS; white = the delivered colours (no
## guild). The online code sets it from the guild of the host (MP8) before the village is built.
static var guild_color := Color.WHITE

var item: DecorItem = null
var cell := Vector2i.ZERO
var rot := 0
## Index in DecorState.placements of its space (-1 for the ghost).
var index := -1
var light: LightSource = null
var _scale := 2.0


## A piece of item at cell with rot on grid; ghost = editor preview (no light, no collision, not lifted).
static func create(piece_item: DecorItem, piece_cell: Vector2i, piece_rot: int, grid: DecorGrid, ghost := false) -> DecorPiece:
	var piece := DecorPiece.new()
	piece.item = piece_item
	piece.cell = piece_cell
	piece.rot = piece_item.normalized_rotation(piece_rot)
	piece.name = "Decor_%s_%d_%d" % [piece_item.id, piece_cell.x, piece_cell.y]
	piece._scale = grid.tile / float(DecorGrid.TILE)
	piece.position = grid.foot_of(piece_item, piece_cell, piece.rot)
	piece._build(grid, ghost)
	return piece


func _build(grid: DecorGrid, ghost: bool) -> void:
	var visual := Node2D.new()
	visual.name = VISUAL
	visual.scale = Vector2(-_scale if item.is_flipped(rot) else _scale, _scale)
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(visual)
	if GUILD_KINDS.has(item.kind):
		visual.modulate = guild_color
	var offset := -(item.pivot(rot) + Vector2(0, 1))
	var strip := DecorCatalog.strip_texture(item, rot)
	var frame_size := item.frame_size(rot)
	if DecorCatalog.uses_strip_as_picture(item, rot):
		visual.add_child(_animated(strip, frame_size, offset))
	else:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = DecorCatalog.texture_for(item, rot)
		sprite.centered = false
		sprite.offset = offset
		visual.add_child(sprite)
		if strip != null:
			var overlay := _animated(strip, frame_size, offset)
			overlay.name = "Anim"
			visual.add_child(overlay)
	if ghost:
		return
	if item.blocks():
		_add_solid(grid)
	_add_light(grid)


func _animated(strip: Texture2D, frame_size: Vector2i, offset: Vector2) -> AnimatedSprite2D:
	var animated := AnimatedSprite2D.new()
	animated.name = "Sprite"
	var frames := DecorItem.frames_of(item.anim_file(rot))
	var size := Vector2i(int(strip.get_width() / float(frames)), strip.get_height()) if frames > 1 else frame_size
	animated.sprite_frames = SpriteStrip.make_frames(strip, size, DecorCatalog.ANIM_FPS, true)
	animated.centered = false
	animated.offset = offset
	animated.play(&"default")
	return animated


## Static body over the footprint (inset by DecorGrid.SOLID_INSET) on the world layer.
func _add_solid(grid: DecorGrid) -> void:
	var body := StaticBody2D.new()
	body.name = SOLID
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var rect := grid.rect_of(item, cell, rot).grow(-DecorGrid.SOLID_INSET)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center() - position
	body.add_child(shape)
	add_child(body)


## LightSource at the JSON's light point (frame px from the top left), its lit circle on the floor
## under it.
func _add_light(grid: DecorGrid) -> void:
	var data := item.light()
	if data.is_empty():
		return
	var local: Vector2 = (data["at"] as Vector2) - item.pivot(rot) - Vector2(0, 1)
	if item.is_flipped(rot):
		local.x = -local.x
	light = LightSource.new()
	light.name = LIGHT
	light.color = data["color"]
	light.radius = DecorCatalog.light_radius_tiles(item) * grid.tile
	light.flicker = FLAME_FLICKER if FLAME_KINDS.has(item.kind) else 0.0
	light.position = local * _scale
	light.ground_offset = Vector2(0, -light.position.y)
	add_child(light)


## Picture node (Sprite2D or AnimatedSprite2D) for tests and tools.
func get_sprite() -> Node2D:
	return get_node_or_null(NodePath("%s/Sprite" % VISUAL)) as Node2D


func is_mirrored() -> bool:
	var visual := get_node_or_null(NodePath(VISUAL)) as Node2D
	return visual != null and visual.scale.x < 0.0


func get_solid() -> StaticBody2D:
	return get_node_or_null(NodePath(SOLID)) as StaticBody2D
