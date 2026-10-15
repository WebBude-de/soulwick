class_name DecoProp
extends Node2D
## One piece of decoration from a room plan (R1, D-120, docs/design/claude_design_antwort/02_grundrisse.md
## "Deko mit Absicht"): a fallen pillar, candles, a coffin, a drip from the ceiling, a niche in a
## wall front. tools/generate_room_templates.py writes these nodes into a template's Props and
## decides everything (item, place, offset, flip, which tiles it blocks), deterministically per
## template; this node only draws. Groups of them tell a small story (pillar plus rubble fan,
## candles plus bones plus a gravestone), there is no random scatter at runtime.
## Standing props have their origin on the base line (y-sorted against the characters' feet via
## SortLift); floor decals and wall fixtures sit below the characters.
## A missing art file draws a small placeholder of the same size, so a new item works before its
## art is delivered (briefing in the R1 report / SPRITES_V8).

enum Layer { STANDING, FLOOR, WALL }

## Item table: texture, frame size and count, fps, pivot (art px), draw layer, solid footprint in
## world px (zero = walkable), light radius (0 = none), light offset above the origin (world px).
const ITEMS := {
	&"coffin": {"path": "res://art/environment/rooms/coffin.png", "frame": Vector2i(32, 40), "pivot": Vector2(16, 38), "layer": Layer.STANDING, "solid": Vector2(46, 22)},
	&"pillar_fallen": {"path": "res://art/environment/deco/pillar_fallen.png", "frame": Vector2i(64, 32), "pivot": Vector2(32, 30), "layer": Layer.STANDING, "solid": Vector2(112, 22)},
	&"candles": {"path": "res://art/environment/deco/candles_cluster.png", "frame": Vector2i(32, 24), "pivot": Vector2(16, 22), "layer": Layer.FLOOR, "light": 110.0, "light_y": 22.0},
	&"drip": {"path": "res://art/environment/deco/drip_4f.png", "frame": Vector2i(16, 32), "frames": 4, "fps": 5.0, "pivot": Vector2(8, 31), "layer": Layer.FLOOR},
	&"puddle": {"path": "", "frame": Vector2i(32, 32), "frames": 4, "fps": 3.0, "pivot": Vector2(16, 18), "layer": Layer.FLOOR},
	&"stairs": {"path": "res://art/environment/deco/stairs_down.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 16), "layer": Layer.FLOOR},
	&"wall_niche": {"path": "res://art/environment/deco/wall_niche.png", "frame": Vector2i(32, 48), "pivot": Vector2(16, 47), "layer": Layer.WALL, "light": 90.0, "light_y": 40.0},
	&"chains": {"path": "res://art/environment/props/chains.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 31), "layer": Layer.WALL},
	&"bones_1": {"path": "res://art/environment/props/bones_1.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 24), "layer": Layer.FLOOR},
	&"bones_2": {"path": "res://art/environment/props/bones_2.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 24), "layer": Layer.FLOOR},
	&"bone_pile": {"path": "res://art/environment/rooms/bone_pile.png", "frame": Vector2i(32, 20), "pivot": Vector2(16, 18), "layer": Layer.FLOOR},
	&"cobweb": {"path": "res://art/environment/rooms/cobweb_corner.png", "frame": Vector2i(32, 32), "pivot": Vector2(0, 0), "layer": Layer.WALL},
	&"rubble_1": {"path": "res://art/environment/rooms/rubble_1.png", "frame": Vector2i(32, 24), "pivot": Vector2(16, 20), "layer": Layer.FLOOR, "scale": 0.7},
	&"rubble_2": {"path": "res://art/environment/rooms/rubble_2.png", "frame": Vector2i(32, 24), "pivot": Vector2(16, 20), "layer": Layer.FLOOR, "scale": 0.6},
	&"gravestone": {"path": "res://art/environment/spawn/spawn_grave_6f.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 28), "layer": Layer.STANDING},
	&"mushrooms": {"path": "res://art/environment/props/mushrooms.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 31), "layer": Layer.FLOOR, "light": 70.0, "light_y": 16.0},
	&"crystal_cluster": {"path": "res://art/environment/props/crystal_cluster.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 31), "layer": Layer.STANDING, "solid": Vector2(30, 14), "light": 100.0, "light_y": 24.0},
	&"anvil": {"path": "res://art/environment/props/anvil_broken.png", "frame": Vector2i(32, 32), "pivot": Vector2(16, 31), "layer": Layer.STANDING, "solid": Vector2(40, 18)},
	&"brazier": {"path": "res://art/environment/props/brazier_4f.png", "frame": Vector2i(32, 32), "frames": 4, "fps": 8.0, "pivot": Vector2(16, 31), "layer": Layer.STANDING, "solid": Vector2(34, 16), "light": 190.0, "light_y": 44.0},
	&"bedroll": {"path": "res://art/environment/campfire/bedroll.png", "frame": Vector2i(32, 16), "pivot": Vector2(16, 12), "layer": Layer.FLOOR},
	&"log": {"path": "res://art/environment/campfire/log_seat.png", "frame": Vector2i(32, 16), "pivot": Vector2(16, 14), "layer": Layer.FLOOR},
	&"pack": {"path": "res://art/environment/campfire/pack.png", "frame": Vector2i(16, 16), "pivot": Vector2(8, 15), "layer": Layer.FLOOR},
	&"torch_stand_unlit": {"path": "res://art/environment/variants/torch_stand_unlit.png", "frame": Vector2i(16, 40), "pivot": Vector2(8, 39), "layer": Layer.STANDING, "solid": Vector2(24, 14)},
	# Moving points of a cave room (M1, Makeover 2 "Bewegung im Bild"): a slow wisp of fog on the
	# floor (the abyss mist, faint) until fog_floor_4f is delivered (SPRITES_V9).
	&"mist": {"path": "res://art/environment/props/abyss_mist_4f.png", "frame": Vector2i(32, 32), "frames": 4, "fps": 2.5, "pivot": Vector2(16, 20), "layer": Layer.FLOOR, "alpha": 0.4, "additive": true},
}
## Free-standing lights built as LightIsland (A3 ingredient look, LightQuery counts them).
const LIGHT_ISLANDS := {
	&"light_crystal": IngredientSet.LightStyle.CRYSTAL,
	&"torch_stand": IngredientSet.LightStyle.TORCH_STAND,
}
## Floor decals draw over the room tiles (z -10) and under the props; wall fixtures over the brick
## fronts, under the torches (z -4).
const FLOOR_Z := -9
const WALL_Z := -8
const PLACEHOLDER := Color(0.42, 0.4, 0.46)

## Key of ITEMS.
@export var item: StringName = &"bones_1"
@export var flip := false
@export var tint := Color.WHITE
## Floor tiles of the room this prop blocks for walking and navigation (generator); empty = none.
@export var blocked_tiles: Array[Vector2i] = []
## Frame shown of a multi-frame strip that does not animate (gravestone = first frame of a source).
@export var still_frame := -1
## Biome of the room (generator): the puddle's water palette (WaterArt).
@export var biome: StringName = &""

var sprite: Node2D = null
var light: LightSource = null


func _ready() -> void:
	if LIGHT_ISLANDS.has(item):
		# Crystal and torch stand of a plan (cells 'C', 't'): the ingredient light island, tinted
		# with the biome's light colour (tint).
		add_child(LightIsland.create(LIGHT_ISLANDS[item], tint))
		SortLift.lift(self)
		return
	var data: Dictionary = ITEMS.get(item, {})
	if data.is_empty():
		push_warning("DecoProp: unknown item %s" % item)
		return
	_build_sprite(data)
	var footprint: Vector2 = data.get("solid", Vector2.ZERO)
	if footprint != Vector2.ZERO:
		_build_body(footprint)
	var radius: float = data.get("light", 0.0)
	if radius > 0.0:
		light = LightSource.new()
		light.name = "Light"
		light.radius = radius
		light.intensity = 0.75
		light.flicker = 0.06
		light.position = Vector2(0, -float(data.get("light_y", 16.0)))
		light.ground_offset = -light.position
		add_child(light)
	match int(data.get("layer", Layer.STANDING)):
		Layer.FLOOR:
			z_index = FLOOR_Z
		Layer.WALL:
			z_index = WALL_Z
		_:
			SortLift.lift(self)


## Is this a solid prop (blocks walking)?
func is_solid() -> bool:
	return not blocked_tiles.is_empty()


## Floor tiles the prop blocks (RoomController takes the navigation off them).
func get_blocked_tiles() -> Array[Vector2i]:
	return blocked_tiles.duplicate()


static func has_item(id: StringName) -> bool:
	return ITEMS.has(id) or LIGHT_ISLANDS.has(id)


func _build_sprite(data: Dictionary) -> void:
	var frame: Vector2i = data["frame"]
	var frames: int = data.get("frames", 1)
	var texture := _puddle_texture() if item == &"puddle" else _texture(String(data["path"]), frame * Vector2i(frames, 1))
	var pivot: Vector2 = data["pivot"]
	var art_scale: float = data.get("scale", 1.0)
	if frames > 1 and still_frame < 0:
		var animated := AnimatedProp.new()
		animated.frame_size = frame
		animated.fps = data.get("fps", 6.0)
		animated.pivot = pivot
		animated.strip = texture
		sprite = animated
	else:
		var still := Sprite2D.new()
		still.texture = texture
		still.region_enabled = true
		still.region_rect = Rect2(Vector2(maxi(still_frame, 0) * frame.x, 0), Vector2(frame))
		still.centered = false
		still.offset = -pivot
		sprite = still
	sprite.name = "Sprite"
	sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE * art_scale
	if flip:
		sprite.scale.x = -sprite.scale.x
	sprite.modulate = tint
	sprite.modulate.a *= data.get("alpha", 1.0)
	if data.get("additive", false):
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = additive
	add_child(sprite)
	if sprite is AnimatedProp:
		# Not all drips and puddles in step.
		(sprite as AnimatedProp).frame = absi(hash(position)) % frames


func _build_body(footprint: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = footprint
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -footprint.y * 0.5)
	body.add_child(collision)
	add_child(body)
	DropShadow.attach(self, footprint.x * 0.4, -2.0)


## A small organic puddle in the biome's water palette (WaterArt), its shape from the position.
func _puddle_texture() -> Texture2D:
	var shape_seed := absi(int(position.x) * 7 + int(position.y) * 13)
	return WaterArt.puddle_strip(biome if biome != &"" else WaterArt.DEFAULT_BIOME, shape_seed)


## The delivered file, or a flat placeholder of the same size.
static func _texture(path: String, size: Vector2i) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	var image := Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	var top := floori(size.y / 3.0)
	image.fill_rect(Rect2i(Vector2i(2, top), Vector2i(maxi(size.x - 4, 1), maxi(size.y - top - 2, 1))), PLACEHOLDER)
	return ImageTexture.create_from_image(image)
