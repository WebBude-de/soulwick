class_name FlintSparks
extends Node2D
## The sparks rising from Flint's flame (D-217, FlintShine, website `.wick-sparks`): a child of his
## sprite drawn over it, at his flame (FlintCompanion moves it with the frame's anchor); pixels of
## the figure's size climbing RISE art pixels and fading. Nothing on "Lichteffekte: Niedrig".
## Optics only, local on every machine.

## TESTWERT: how high a spark climbs (art pixels of the sprite).
const RISE := 14.0

var time := 0.0


func _init() -> void:
	name = "FlintSparks"


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	FlintShine.draw_sparks(self, Vector2.ZERO, 1.0, RISE, time)
