class_name TrialSpikes
extends TrialHazard
## Spike plates across a whole lane column (the biomes' spike trap art, SPRITES_V2 §2): retracted,
## warning, extended. The player has to time the gap, there is no way around.

## Timing (TESTWERTE).
const IDLE_RANGE := Vector2(1.0, 2.0)
const WARN_TIME := 0.6
const ACTIVE_TIME := 0.7
const WARN_TINT := Color(1.5, 0.85, 0.75)

var _sprites: Array[Sprite2D] = []


## rect: content-local column (one tile wide, all lane rows).
func build(rect: Rect2) -> void:
	hit_rect = rect
	position = rect.get_center()
	z_index = -9
	var rows := maxi(1, roundi(rect.size.y / RoomTiles.TILE_WORLD))
	for row in rows:
		var sprite := Sprite2D.new()
		sprite.texture = TrialArt.get_texture(TrialArt.SPIKES)
		sprite.hframes = TrialArt.get_frame_count(TrialArt.SPIKES)
		sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		sprite.position = Vector2(0.0, -rect.size.y * 0.5 + RoomTiles.TILE_WORLD * (row + 0.5))
		add_child(sprite)
		_sprites.append(sprite)


func _on_phase_changed() -> void:
	for sprite in _sprites:
		sprite.frame = mini(int(phase), sprite.hframes - 1)
		sprite.modulate = WARN_TINT if phase == Phase.WARN else Color.WHITE
	if phase == Phase.ACTIVE and is_inside_tree():
		Sfx.play_at(self, &"trap", global_position, -10.0)
