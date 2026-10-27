class_name SideTilt
extends SideCrumble
## A tilting platform of the jump trial (Kippplattform, SV2, D-195, plan "//"): two tiles wide, it
## wobbles as soon as a player stands on it, tips over after SideElementRules.TILT_DELAY seconds
## and falls, and is back after TILT_RESPAWN once nobody is in the way. A SideCrumble with its own
## timing and look, so the decision, the co-op sync (NetSide via SideSegment.get_crumbles) and the
## tests are the crumble's. Art: tilt_platform_<biome>_4f.png (4 × 64×16: still, wobbling, tipping,
## falling), else the ledge pieces tinted darker. The picture is lifted by the empty rows above its
## slab (SidePixels.surface_row), so the feet stand on the drawn top (FS1).

const ART_PATH := "res://art/environment/side/tilt_platform_%s_4f.png"
const ART_FRAME := Vector2i(64, 16)
## Tilt of the falling platform (radians) and the wobble while it shakes.
const FALL_TILT := 0.5
const WOBBLE := 0.06
const PLACEHOLDER_TINT := Color(0.8, 0.72, 0.62)
## Surface row of the delivered art when the picture cannot be read.
const SURFACE_ROW_FALLBACK := 4

var _sprite: Sprite2D = null


func shake_time() -> float:
	return SideElementRules.TILT_DELAY


func respawn_time() -> float:
	return SideElementRules.TILT_RESPAWN


func _build_look() -> void:
	var path := ART_PATH % biome_id
	if not ResourceLoader.exists(path):
		path = ART_PATH % SideTiles.FALLBACK_BIOME
	if ResourceLoader.exists(path):
		_sprite = Sprite2D.new()
		_sprite.name = "Art"
		_sprite.texture = load(path) as Texture2D
		_sprite.hframes = 4
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		# Pivot (32, 8) of the art = the middle of the two cells' top strip, lifted to the slab.
		var lift := SidePixels.surface_row(_sprite.texture, Rect2i(Vector2i.ZERO, ART_FRAME), SURFACE_ROW_FALLBACK)
		_sprite.position = Vector2(cells * SideRules.TILE * 0.5, (ART_FRAME.y * 0.5 - lift) * SpriteStrip.PIXEL_SCALE)
		_pieces.add_child(_sprite)
		return
	super._build_look()
	_pieces.modulate = PLACEHOLDER_TINT


func _look_step() -> void:
	if _sprite == null:
		return
	match state:
		State.SOLID:
			_sprite.frame = 0
			_sprite.rotation = 0.0
		State.SHAKING:
			_sprite.frame = 1 if shake_progress() < 0.5 else 2
			_sprite.rotation = sin(shake_progress() * 30.0) * WOBBLE
		State.FALLEN:
			_sprite.frame = 3
			_sprite.rotation = FALL_TILT
