class_name CameraShake
extends RefCounted
## Adds screen shake to the active camera. strength ~2 = light hit, ~6 = player hit, ~10 = boss slam.

const STRENGTH_TO_TRAUMA := 0.06

## Player option "Bildschirmwackeln" (GameOptions, settings.cfg); false = no shake at all.
static var enabled := true


static func shake(context: Node, strength: float) -> void:
	if not enabled or context == null or not context.is_inside_tree():
		return
	var camera := context.get_viewport().get_camera_2d()
	if camera != null and camera.has_method(&"add_trauma"):
		camera.add_trauma(strength * STRENGTH_TO_TRAUMA)
