class_name SideElementHints
extends Node2D
## Drawn hints for the elements that have no node of their own (SV2, D-195): scratch marks up the
## walls of a wall-jump shaft (climb by jumping from wall to wall). Looks only, the same on every
## machine (from the layout). Pixel lines (D-218).

const SCRATCH_COLOR := Color(0.95, 0.9, 0.8, 0.22)

var layout: SideLayout = null


static func create(segment_layout: SideLayout) -> SideElementHints:
	var hints := SideElementHints.new()
	hints.name = "ElementHints"
	hints.layout = segment_layout
	hints.z_index = -3
	return hints


func _draw() -> void:
	if layout == null:
		return
	var tile := SideRules.TILE
	for shaft in layout.shafts:
		for row in range(shaft.position.y + 1, shaft.end.y):
			var top := row * tile + 12.0
			for wall_x: float in [shaft.position.x * tile + 2.0, shaft.end.x * tile - 2.0]:
				var inward := 1.0 if wall_x < (shaft.position.x + shaft.size.x * 0.5) * tile else -1.0
				for k in 3:
					var start := Vector2(wall_x, top + k * 9.0)
					SidePixels.line(self, start, start + Vector2(inward * 8.0, 14.0), SCRATCH_COLOR)
