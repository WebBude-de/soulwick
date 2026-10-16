class_name CharacterData
extends Resource
## A playable character (MM1): look, menu texts and the clothing colours a player can pick at home.
## Data-driven so more characters are just new .tres files in res://characters/ (listed in
## CharacterCatalog). Gameplay values (start weapon, stats) are not part of it yet.
##
## Hook for the player (integrator): CharacterCatalog.apply_active(sprite) or
## character.apply_to(sprite, color) recolours an AnimatedSprite2D with the tint mask shader and
## keeps the mask in sync with the current animation.
## D-152: apply_look(sprite, look) gives the sprite the figure in all four colours of a PlayerLook
## (frames recoloured once per look, no mask needed). Figures without own art yet use the base
## figure's frames plus a placeholder mark (placeholder_mark); art_frames_path wins once it exists.
## display_name and description are translation keys (D-111).

const TINT_SHADER: Shader = preload("res://characters/character_tint.gdshader")
## Sprite meta keys used by apply_to / refresh_tint.
const META_DATA := &"character_data"
const META_CONNECTED := &"character_tint_connected"
## Set on sprites that show a recoloured look (apply_look): the tint mask stays off.
const META_BAKED := &"character_look_baked"
## Own art of a figure as strips (SPRITES_V10 §7): animation -> [file part, frames]. File:
## <folder of art_frames_path>/<id>_<part>_<frames>f.png, 32×32 frames like the player.
const STRIP_ANIMATIONS := {
	&"idle": ["idle", 4], &"walk": ["walk", 6], &"dash": ["dash", 3], &"death": ["death", 6],
	&"side_jump": ["jump", 3], &"side_land": ["land", 2], &"side_climb": ["climb", 4],
}
const STRIP_FRAME := Vector2i(32, 32)

@export var id: StringName = &""
@export var display_name := ""
## One short German line for the character choice ("du"-form).
@export_multiline var description := ""
@export var sprite_frames: SpriteFrames
## The figure's own art (SpriteFrames .tres); used instead of sprite_frames once the file exists.
@export var art_frames_path := ""
## Placeholder silhouette mark of PlayerLook.PLACEHOLDER_MARKS while the own art is missing.
@export var placeholder_mark: StringName = &""
## Animation name -> clothing mask strip (white = clothing), same size as that animation's sheet.
## Animations without a mask keep their original colours.
@export var tint_masks: Dictionary[StringName, Texture2D] = {}
## Clothing colour as drawn in the art; tinting keeps the shading relative to it.
@export var base_color := Color("#3690da")
@export var default_color := Color("#3690da")
## Clothing colours offered in the wardrobe at home (TESTWERT: HANDOUT P1-P4 plus two palette
## colours) and their names as translation keys (same order, LOOK_OUTFIT_<n>).
@export var color_choices := PackedColorArray()
@export var color_names := PackedStringArray()
## Weapon the figure holds in the main menu scene (look only), pivot = grip in texture pixels.
@export var menu_weapon: Texture2D
@export var menu_weapon_pivot := Vector2(6, 16)


## The frames to draw: the own art if it exists (a SpriteFrames .tres at art_frames_path, or strips
## <id>_<animation>_<n>f.png next to it; a missing strip keeps the base figure's animation), else
## sprite_frames (placeholder: the base figure).
func get_frames() -> SpriteFrames:
	if not art_frames_path.is_empty() and ResourceLoader.exists(art_frames_path):
		var own := load(art_frames_path) as SpriteFrames
		if own != null:
			return own
	if _strip_frames == null and _has_strip(&"idle"):
		_strip_frames = _frames_from_strips()
	return _strip_frames if _strip_frames != null else sprite_frames


func has_own_art() -> bool:
	if art_frames_path.is_empty():
		return false
	return ResourceLoader.exists(art_frames_path) or _has_strip(&"idle")


var _strip_frames: SpriteFrames = null


func _strip_path(animation: StringName) -> String:
	var part: Array = STRIP_ANIMATIONS.get(animation, [])
	if part.is_empty() or art_frames_path.is_empty():
		return ""
	return art_frames_path.get_base_dir().path_join("%s_%s_%df.png" % [id, part[0], part[1]])


func _has_strip(animation: StringName) -> bool:
	var path := _strip_path(animation)
	return not path.is_empty() and ResourceLoader.exists(path)


## The base figure's animations, each replaced by the own strip where one exists (same speed and loop).
func _frames_from_strips() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for animation in sprite_frames.get_animation_names():
		var fps := sprite_frames.get_animation_speed(animation)
		var loop := sprite_frames.get_animation_loop(animation)
		if _has_strip(animation):
			SpriteStrip.add_strip(frames, animation, load(_strip_path(animation)) as Texture2D, STRIP_FRAME, fps, loop)
			continue
		frames.add_animation(animation)
		frames.set_animation_speed(animation, fps)
		frames.set_animation_loop(animation, loop)
		for i in sprite_frames.get_frame_count(animation):
			frames.add_frame(animation, sprite_frames.get_frame_texture(animation, i), sprite_frames.get_frame_duration(animation, i))
	for animation: StringName in STRIP_ANIMATIONS:
		if not frames.has_animation(animation) and _has_strip(animation):
			SpriteStrip.add_strip(frames, animation, load(_strip_path(animation)) as Texture2D, STRIP_FRAME, 10.0, animation == &"side_climb")
	return frames


## The mark drawn on the base figure until the own art exists (&"" = none).
func get_placeholder_mark() -> StringName:
	return &"" if has_own_art() else placeholder_mark


## The figure in the colours of look (PlayerLook): recoloured frames, tint mask off. Safe to call
## again (live preview, a remote player's new look).
func apply_look(sprite: AnimatedSprite2D, look: Dictionary) -> void:
	if sprite == null:
		return
	var frames := PlayerLook.frames_for(self, look)
	if frames == null:
		apply_to(sprite, PlayerLook.outfit_color(look))
		return
	_set_frames(sprite, frames)
	var material := _ensure_material(sprite)
	material.set_shader_parameter(&"base_color", base_color)
	material.set_shader_parameter(&"tint_color", base_color)
	sprite.set_meta(META_DATA, self)
	sprite.set_meta(META_BAKED, true)
	_connect_refresh(sprite)
	refresh_tint(sprite)


func has_tint() -> bool:
	return not tint_masks.is_empty()


func get_mask(animation: StringName) -> Texture2D:
	return tint_masks.get(animation, null)


## Name of a colour choice in the current language ("Blue"), empty if unnamed. color_names holds
## translation keys (LOOK_OUTFIT_<n>, D-111).
func get_color_name(index: int) -> String:
	return Loc.t(StringName(color_names[index])) if index >= 0 and index < color_names.size() else ""


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
	_set_frames(sprite, get_frames())
	var material := _ensure_material(sprite)
	material.set_shader_parameter(&"base_color", base_color)
	material.set_shader_parameter(&"tint_color", color)
	sprite.set_meta(META_DATA, self)
	sprite.set_meta(META_BAKED, false)
	_connect_refresh(sprite)
	refresh_tint(sprite)


## Swaps the frames and keeps the animation (and whether it plays).
static func _set_frames(sprite: AnimatedSprite2D, frames: SpriteFrames) -> void:
	if frames == null or sprite.sprite_frames == frames:
		return
	var animation := sprite.animation
	var frame := sprite.frame
	var progress := sprite.frame_progress
	var was_playing := sprite.is_playing()
	sprite.sprite_frames = frames
	if frames.has_animation(animation):
		sprite.animation = animation
		if was_playing:
			sprite.play(animation)
		sprite.set_frame_and_progress(mini(frame, frames.get_frame_count(animation) - 1), progress)


## In game the sprite already has the SpriteFx material (flash, dissolve), which knows the same tint
## parameters: keep it instead of replacing it. Only plain sprites (menu preview) get TINT_SHADER.
static func _ensure_material(sprite: AnimatedSprite2D) -> ShaderMaterial:
	var material := sprite.material as ShaderMaterial
	if material == null or (material.shader != TINT_SHADER and material.shader != SpriteFx.SHADER):
		material = ShaderMaterial.new()
		material.shader = TINT_SHADER
		sprite.material = material
	return material


static func _connect_refresh(sprite: AnimatedSprite2D) -> void:
	if not sprite.has_meta(META_CONNECTED):
		sprite.set_meta(META_CONNECTED, true)
		sprite.animation_changed.connect(func() -> void: CharacterData.refresh_tint(sprite))


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
	# A recoloured look (apply_look) is already coloured: no mask.
	var mask: Texture2D = null if sprite.get_meta(META_BAKED, false) else data.get_mask(sprite.animation)
	material.set_shader_parameter(&"tint_mask", mask)
	material.set_shader_parameter(&"use_mask", mask != null)
