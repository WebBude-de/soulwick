class_name CharacterData
extends Resource
## A playable character (MM1): look, menu texts and the clothing colours a player can pick at home.
## Data-driven so more characters are just new .tres files in res://characters/ (listed in
## CharacterCatalog). Gameplay values (start weapon, stats) are not part of it yet.
##
## Hook for the player (integrator): CharacterCatalog.apply_active(sprite) or
## character.apply_to(sprite, color) recolours an AnimatedSprite2D with the tint mask shader and
## keeps the mask in sync with the current animation.

const TINT_SHADER: Shader = preload("res://characters/character_tint.gdshader")
## Sprite meta keys used by apply_to / refresh_tint.
const META_DATA := &"character_data"
const META_CONNECTED := &"character_tint_connected"

@export var id: StringName = &""
@export var display_name := ""
## One short German line for the character choice ("du"-form).
@export_multiline var description := ""
@export var sprite_frames: SpriteFrames
## Animation name -> clothing mask strip (white = clothing), same size as that animation's sheet.
## Animations without a mask keep their original colours.
@export var tint_masks: Dictionary[StringName, Texture2D] = {}
## Clothing colour as drawn in the art; tinting keeps the shading relative to it.
@export var base_color := Color("#3690da")
@export var default_color := Color("#3690da")
## Clothing colours offered in the wardrobe at home (TESTWERT: HANDOUT P1-P4 plus two palette
## colours) and their German names (same order).
@export var color_choices := PackedColorArray()
@export var color_names := PackedStringArray()
## Weapon the figure holds in the main menu scene (look only), pivot = grip in texture pixels.
@export var menu_weapon: Texture2D
@export var menu_weapon_pivot := Vector2(6, 16)


func has_tint() -> bool:
	return not tint_masks.is_empty()


func get_mask(animation: StringName) -> Texture2D:
	return tint_masks.get(animation, null)


## German name of a colour choice ("Blau"), empty if unnamed.
func get_color_name(index: int) -> String:
	return color_names[index] if index >= 0 and index < color_names.size() else ""


## Index of color in color_choices (nearest match), 0 if the list is empty.
func get_color_index(color: Color) -> int:
	var best := 0
	var best_distance := INF
	for i in color_choices.size():
		var c := color_choices[i]
		var distance := Vector3(c.r - color.r, c.g - color.g, c.b - color.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Gives sprite this character's frames and clothing colour. Safe to call again (e.g. live preview);
## the mask follows animation changes automatically.
func apply_to(sprite: AnimatedSprite2D, color: Color) -> void:
	if sprite == null:
		return
	if sprite_frames != null and sprite.sprite_frames != sprite_frames:
		var animation := sprite.animation
		var was_playing := sprite.is_playing()
		sprite.sprite_frames = sprite_frames
		if sprite_frames.has_animation(animation):
			sprite.animation = animation
			if was_playing:
				sprite.play(animation)
	var material := sprite.material as ShaderMaterial
	# In game the sprite already has the SpriteFx material (flash, dissolve), which knows the same
	# tint parameters: keep it instead of replacing it. Only plain sprites (menu preview) get TINT_SHADER.
	if material == null or (material.shader != TINT_SHADER and material.shader != SpriteFx.SHADER):
		material = ShaderMaterial.new()
		material.shader = TINT_SHADER
		sprite.material = material
	material.set_shader_parameter(&"base_color", base_color)
	material.set_shader_parameter(&"tint_color", color)
	sprite.set_meta(META_DATA, self)
	if not sprite.has_meta(META_CONNECTED):
		sprite.set_meta(META_CONNECTED, true)
		sprite.animation_changed.connect(func() -> void: CharacterData.refresh_tint(sprite))
	refresh_tint(sprite)


## Only changes the clothing colour of a sprite prepared with apply_to.
static func set_tint_color(sprite: AnimatedSprite2D, color: Color) -> void:
	var material := sprite.material as ShaderMaterial if sprite != null else null
	if material != null:
		material.set_shader_parameter(&"tint_color", color)


## Picks the mask of the sprite's current animation.
static func refresh_tint(sprite: AnimatedSprite2D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var data := sprite.get_meta(META_DATA, null) as CharacterData
	var material := sprite.material as ShaderMaterial
	if data == null or material == null:
		return
	var mask := data.get_mask(sprite.animation)
	material.set_shader_parameter(&"tint_mask", mask)
	material.set_shader_parameter(&"use_mask", mask != null)
