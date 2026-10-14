class_name SideExit
extends Node2D
## The door at the end of a side segment (M5): frame and leaf of the biome's door, a warm light, the
## leaf swings open when a player comes close. The origin is the floor line under the door.
## SideSegment decides when a player walks in (is_entered_by).

const DOORS_DIR := "res://art/environment/doors/"
const FALLBACK_BIOME := &"crypt"
const FRAME_PIVOT := Vector2(24, 48)
const LEAF_FRAME := Vector2i(32, 32)
const LEAF_PIVOT := Vector2(16, 32)
const OPEN_DISTANCE := 190.0
const ENTER_DISTANCE := 26.0
const ENTER_HEIGHT := 40.0

var biome_id: StringName = FALLBACK_BIOME
var is_open := false

var _leaf: AnimatedSprite2D = null


func _ready() -> void:
	z_index = -2
	var frame_texture := _texture("door_frame_%s.png")
	if frame_texture != null:
		var frame := Sprite2D.new()
		frame.name = "Frame"
		frame.texture = frame_texture
		frame.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		frame.offset = SpriteStrip.pivot_offset(Vector2i(frame_texture.get_size()), FRAME_PIVOT)
		add_child(frame)
	var leaf_texture := _texture("door_%s_open_4f.png")
	if leaf_texture != null:
		_leaf = AnimatedSprite2D.new()
		_leaf.name = "Leaf"
		_leaf.sprite_frames = SpriteStrip.make_frames(leaf_texture, LEAF_FRAME, 8.0, false)
		_leaf.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_leaf.offset = SpriteStrip.pivot_offset(LEAF_FRAME, LEAF_PIVOT)
		_leaf.frame = 0
		add_child(_leaf)
	var glow := LightSource.new()
	glow.name = "Glow"
	glow.radius = 170.0
	glow.intensity = 0.8
	glow.flicker = 0.04
	glow.position = Vector2(0, -48)
	add_child(glow)


## Opens once (look and sound).
func open() -> void:
	if is_open:
		return
	is_open = true
	if _leaf != null:
		_leaf.play(&"default")
	if is_inside_tree():
		Sfx.play_at(self, SideRules.SOUND_DOOR, global_position, -4.0)


func is_near(feet: Vector2) -> bool:
	return feet.distance_to(global_position) <= OPEN_DISTANCE


## A player whose feet stand in the doorway walks through.
func is_entered_by(feet: Vector2) -> bool:
	return absf(feet.x - global_position.x) <= ENTER_DISTANCE and absf(feet.y - global_position.y) <= ENTER_HEIGHT


func _texture(pattern: String) -> Texture2D:
	for biome in [biome_id, FALLBACK_BIOME]:
		var path := DOORS_DIR + pattern % biome
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null
