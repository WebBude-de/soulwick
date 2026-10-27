class_name SideBridge
extends SideCrumble
## One piece of a collapsing bridge of the jump trial (einstürzende Brücke, SV2, D-195, plan "_"):
## every piece cracks as soon as a player steps on it and falls SideElementRules.BRIDGE_DELAY
## seconds later, so the bridge breaks right behind the runner and drives them on; the pieces are
## back after BRIDGE_RESPAWN once nobody is in the way. A one-cell SideCrumble with its own timing
## and look (decision, co-op sync and tests are the crumble's). Art:
## collapse_bridge_<biome>_6f.png (6 × 32×16: whole, cracking 1-3, breaking 4-5), else the ledge
## piece with planks drawn over it. The picture is lifted by the empty rows above its planks
## (SidePixels.surface_row), so the feet stand on the drawn bridge (FS1).

const ART_PATH := "res://art/environment/side/collapse_bridge_%s_6f.png"
const ART_FRAMES := 6
const PLANK_COLOR := Color(0.35, 0.24, 0.16, 0.9)
## Surface row of the delivered art when the picture cannot be read.
const SURFACE_ROW_FALLBACK := 3

var _sprite: Sprite2D = null


func shake_time() -> float:
	return SideElementRules.BRIDGE_DELAY


func respawn_time() -> float:
	return SideElementRules.BRIDGE_RESPAWN


func _build_look() -> void:
	var path := ART_PATH % biome_id
	if not ResourceLoader.exists(path):
		path = ART_PATH % SideTiles.FALLBACK_BIOME
	if ResourceLoader.exists(path):
		_sprite = Sprite2D.new()
		_sprite.name = "Art"
		_sprite.texture = load(path) as Texture2D
		_sprite.hframes = ART_FRAMES
		_sprite.centered = false
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		var frame := Vector2i(_sprite.texture.get_width() / ART_FRAMES, _sprite.texture.get_height())
		_sprite.position.y = -SidePixels.surface_row(_sprite.texture, Rect2i(Vector2i.ZERO, frame), SURFACE_ROW_FALLBACK) * SpriteStrip.PIXEL_SCALE
		_pieces.add_child(_sprite)
		return
	super._build_look()
	var planks := _Planks.new()
	planks.cells = cells
	_pieces.add_child(planks)


func _look_step() -> void:
	if _sprite == null:
		return
	match state:
		State.SOLID:
			_sprite.frame = 0
		State.SHAKING:
			_sprite.frame = 1 + mini(2, floori(shake_progress() * 3.0))
		State.FALLEN:
			_sprite.frame = 4 if _fall_offset < 40.0 else 5


## Planks over the placeholder piece, so it reads as a bridge and not as a crumbling ledge.
class _Planks:
	extends Node2D
	var cells := 1

	func _draw() -> void:
		for i in cells:
			var x := i * SideRules.TILE
			for k in 4:
				SidePixels.rect(self, Rect2(x + 4.0 + k * 16.0, 2.0, 12.0, 14.0), SideBridge.PLANK_COLOR)
