class_name LightingQuality
extends RefCounted
## Player option "Lichteffekte: Hoch / Niedrig" (L1) as state for the effects that read it. High (the
## default) draws glow halos around light sources, biome colour grading, vignette and drifting mist
## in the light (vision.gdshader), ambient particles (AmbientParticles) and coloured flashes of
## bursts (Burst). Low switches these off for weak computers; the light circles, their colours and
## the darkness stay, so what is lit for gameplay (LightQuery) looks and works the same.
## GameOptions stores the choice and calls set_high(); everything else only reads is_high().

static var _high := true


static func is_high() -> bool:
	return _high


## Applies the level at once: running ambient particles stop or start again.
static func set_high(on: bool) -> void:
	if on == _high:
		return
	_high = on
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group(AmbientParticles.GROUP):
		(node as AmbientParticles).refresh_quality()
