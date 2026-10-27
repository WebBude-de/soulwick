class_name RingWave
extends RefCounted
## Old name of the expanding, fading ring of weapon specials. Since FS2b (D-218) it only forwards
## to PixelRingWave (components/visual/), the pixel-art ring with the same arguments; new code
## calls PixelRingWave.spawn directly.


static func spawn(parent: Node, global_pos: Vector2, radius: float, color: Color, duration := 0.35, ring_width := 5.0, start_scale := 0.2) -> PixelRingWave:
	return PixelRingWave.spawn(parent, global_pos, radius, color, duration, ring_width, start_scale)
