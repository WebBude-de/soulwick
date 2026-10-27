class_name LostVillager
extends Node2D
## The lost villager of the escort mode (RAEUME §3.3, R4a) - or, rarely, a chicken with a
## lantern. Body and look only: EscortMode decides where he walks, when he stops and when he is safe;
## this node counts his hearts (one per enemy hit, EscortHurtbox) and shows everything (walk, idle and
## scared animation, warm lantern light, help bubble, hearts over his head).
## Decoy contract (EnemyDecoy, EnemyTargeting.is_alive): is_alive() and a hurtbox on PLAYER_HURTBOX;
## the origin is the body centre like a player's (base line + Player.FEET_OFFSET), so enemies aim at
## his middle and he sorts against the feet of players and enemies. No collision body: he walks
## through players and enemies alike, so nobody can block his way.

## A heart was lost (after the invulnerability check).
signal hit(villager: LostVillager, damage: DamageData)
## The last heart is gone.
signal fell(villager: LostVillager)

enum Look { IDLE, WALK, SCARED, CHEER }

const FRAMES_PATH := "res://art/characters/npcs/lost_villager_frames.tres"
const FRAME := Vector2i(32, 32)
const PIVOT := Vector2(16, 30)
## Lantern in the hand (lost_villager.json anchor, art pixels from the frame's top left).
const LANTERN_ANCHOR := Vector2(20, 20)
## Placeholder until a chicken with a lantern exists (SPRITES_V3): the village chicken, a small
## drawn lantern at its neck.
const CHICKEN_FRAMES_PATH := "res://art/characters/npcs/chicken_frames.tres"
const CHICKEN_FRAME := Vector2i(16, 16)
const CHICKEN_PIVOT := Vector2(8, 14)
const CHICKEN_LANTERN_ANCHOR := Vector2(12, 9)
## Cloak colours (Modulate, lost_villager.json "Varianten per Modulate"): picked per room, the village
## may use the same list for its rescued (R7).
const CLOAK_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0), Color(0.86, 0.94, 1.0), Color(1.0, 0.9, 0.82), Color(0.9, 1.0, 0.88), Color(0.96, 0.88, 1.0),
]
## Warm lantern light, about 3 tiles (lost_villager.json). TESTWERT
const LIGHT_RADIUS := 192.0
const HURT_RADIUS := 16.0
const SHADOW_RADIUS := 13.0
const BUBBLE_TIME := 1.6
const HEART_COLOR := Color("#e0463a")
const HEART_EMPTY := Color(0.18, 0.12, 0.16, 0.85)
const INVULNERABLE_HIT := &"escort_hit"

var chicken := false
var hearts := 1
var max_hearts := 1
## Safe at the exit: no longer a target.
var rescued := false
var look: Look = Look.IDLE
var hurtbox: EscortHurtbox = null

var _sprite: AnimatedSprite2D = null
var _light: LightSource = null
var _bubble: Label = null
var _bubble_left := 0.0
var _hearts_row: HeartRow = null
var _invulnerable_left := 0.0
var _built := false


## Builds children and hearts; call once, before or after entering the tree.
func build(is_chicken: bool, heart_count: int, tint := Color.WHITE) -> void:
	if _built:
		return
	_built = true
	chicken = is_chicken
	max_hearts = maxi(1, heart_count)
	hearts = max_hearts
	var base := Player.FEET_OFFSET
	DropShadow.attach(self, SHADOW_RADIUS * (0.7 if chicken else 1.0), base.y - 2.0)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	var frames_path := CHICKEN_FRAMES_PATH if chicken else FRAMES_PATH
	_sprite.sprite_frames = load(frames_path) as SpriteFrames if ResourceLoader.exists(frames_path) else null
	_sprite.offset = SpriteStrip.pivot_offset(CHICKEN_FRAME if chicken else FRAME, CHICKEN_PIVOT if chicken else PIVOT)
	_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
	_sprite.position = base
	_sprite.self_modulate = tint
	add_child(_sprite)
	var anchor := CHICKEN_LANTERN_ANCHOR if chicken else LANTERN_ANCHOR
	var pivot := CHICKEN_PIVOT if chicken else PIVOT
	var lantern_offset := base + (anchor - pivot) * SpriteStrip.PIXEL_SCALE
	if chicken:
		var glyph := Sprite2D.new()
		glyph.name = "LanternGlyph"
		glyph.texture = _lantern_glyph()
		# Child of the scaled sprite: art pixels relative to the pivot.
		glyph.position = (anchor - pivot) + Vector2(0, 1)
		_sprite.add_child(glyph)
	_light = LightSource.new()
	_light.name = "LampLight"
	_light.radius = LIGHT_RADIUS
	_light.intensity = 0.95
	_light.flicker = 0.06
	_light.color = LightPalette.WARM
	_light.counts_as_light = true
	_light.position = lantern_offset
	_light.ground_offset = Vector2(0, base.y - lantern_offset.y)
	add_child(_light)
	hurtbox = EscortHurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.villager = self
	var circle := CircleShape2D.new()
	circle.radius = HURT_RADIUS * (0.75 if chicken else 1.0)
	var shape := CollisionShape2D.new()
	shape.shape = circle
	shape.position = Vector2(0, 4 if chicken else -4)
	hurtbox.add_child(shape)
	add_child(hurtbox)
	_hearts_row = HeartRow.new()
	_hearts_row.name = "Hearts"
	_hearts_row.position = Vector2(0, -44 if chicken else -66)
	_hearts_row.z_index = 20
	add_child(_hearts_row)
	_bubble = UiKit.label("", 15, Color("#fff4d6"))
	_bubble.name = "HelpBubble"
	_bubble.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.06))
	_bubble.add_theme_constant_override("outline_size", 5)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.size = Vector2(120, 22)
	_bubble.position = Vector2(-60, -100 if not chicken else -78)
	_bubble.z_index = 21
	_bubble.visible = false
	add_child(_bubble)
	_refresh_hearts()
	set_look(Look.SCARED)


## Decoy contract: a target while he has hearts and is not yet safe.
func is_alive() -> bool:
	return hearts > 0 and not rescued


## Co-op: a fresh count of hearts once the group is known (before the first hit).
func set_max_hearts(count: int) -> void:
	max_hearts = maxi(1, count)
	hearts = max_hearts
	_refresh_hearts()


func is_down() -> bool:
	return hearts <= 0


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## An enemy hit landed (EscortHurtbox): one heart, then HIT_INVULNERABILITY seconds of safety.
func take_hit(damage: DamageData) -> void:
	if not is_alive() or is_invulnerable():
		return
	hearts -= 1
	_invulnerable_left = EscortRules.HIT_INVULNERABILITY
	if hurtbox != null:
		hurtbox.set_invulnerable(INVULNERABLE_HIT, true)
	_refresh_hearts()
	hit.emit(self, damage)
	if is_inside_tree():
		SpriteFx.flash(_sprite, Color(1.0, 0.45, 0.45), 0.14)
		Burst.spawn(get_parent(), global_position + Vector2(0, -10), HEART_COLOR, 8, 100.0)
		Sfx.play_at(self, &"hit_player", global_position, -6.0)
	if hearts <= 0:
		_fall()


## Safe at the exit: no target any more, the lantern glows up.
func set_rescued() -> void:
	if rescued or is_down():
		return
	rescued = true
	_invulnerable_left = 0.0
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", false)
	_hearts_row.visible = false
	set_look(Look.CHEER)
	if is_inside_tree():
		Burst.spawn(get_parent(), global_position + Vector2(0, -20), LightPalette.GOLD, 18, 140.0, 0.6)
		var tween := _light.create_tween()
		tween.tween_property(_light, "radius", LIGHT_RADIUS * 1.4, 0.4)
		tween.tween_property(_light, "radius", LIGHT_RADIUS, 0.6)


## Looks: walk, idle, scared (waving for help), cheer. facing_left flips the art.
func set_look(next: Look, facing_left := false) -> void:
	look = next
	if _sprite == null or _sprite.sprite_frames == null:
		return
	_sprite.flip_h = facing_left
	var animation := &"idle"
	var speed := 1.0
	match next:
		Look.WALK:
			animation = &"walk"
		Look.SCARED:
			if chicken:
				# The chicken has no scared strip: it flaps on the spot.
				animation = &"walk"
				speed = 2.0
			else:
				animation = &"scared"
	if not _sprite.sprite_frames.has_animation(animation):
		animation = &"idle"
	_sprite.speed_scale = speed
	if _sprite.animation != animation or not _sprite.is_playing():
		_sprite.play(animation)


## A short line over his head ("Hilfe!", "Danke!").
func say(text: String, seconds := BUBBLE_TIME) -> void:
	if _bubble == null:
		return
	_bubble.text = text
	_bubble.visible = true
	_bubble.modulate.a = 1.0
	_bubble_left = seconds


func get_bubble_text() -> String:
	return _bubble.text if _bubble != null and _bubble.visible else ""


## Lantern light for tools and tests.
func get_light() -> LightSource:
	return _light


## Fades out (walked through the exit, or fallen) and frees itself.
func fade_out(duration := 0.8) -> void:
	if not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left -= delta
		if _sprite != null:
			_sprite.modulate.a = 0.55 if fmod(_invulnerable_left, 0.2) < 0.1 else 1.0
		if _invulnerable_left <= 0.0:
			_invulnerable_left = 0.0
			if _sprite != null:
				_sprite.modulate.a = 1.0
			if hurtbox != null:
				hurtbox.set_invulnerable(INVULNERABLE_HIT, false)
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left < 0.3:
			_bubble.modulate.a = maxf(0.0, _bubble_left / 0.3)
		if _bubble_left <= 0.0:
			_bubble.visible = false


func _fall() -> void:
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", false)
	_hearts_row.visible = false
	set_look(Look.SCARED)
	fell.emit(self)
	if not is_inside_tree():
		return
	Burst.spawn(get_parent(), global_position, Color(0.75, 0.7, 0.65), 22, 150.0, 0.7)
	CameraShake.shake(self, 3.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(_sprite, "rotation", PI * 0.5 * (-1.0 if _sprite.flip_h else 1.0), 0.35)
	tween.tween_property(_sprite, "modulate", Color(0.5, 0.5, 0.55, 0.7), 0.6)
	tween.tween_property(_light, "intensity", 0.15, 0.8)
	tween.tween_property(_light, "radius", 60.0, 0.8)


func _refresh_hearts() -> void:
	if _hearts_row != null:
		_hearts_row.set_hearts(hearts, max_hearts)


## Small lantern of the chicken placeholder (5x7 art pixels, a dark frame around a warm core).
static func _lantern_glyph() -> Texture2D:
	var image := Image.create(5, 7, false, Image.FORMAT_RGBA8)
	var frame := Color("#3a2a20")
	var core := Color("#ffd166")
	for y in 7:
		for x in 5:
			var edge := x == 0 or x == 4 or y == 1 or y == 6
			if y == 0:
				image.set_pixel(x, y, frame if x == 2 else Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, frame if edge else core)
	return ImageTexture.create_from_image(image)


## Hearts over the villager's head: filled red, lost ones dark. Pixel hearts (D-218): HEART rows
## of art pixels (PixelDraw.WORLD_PIXEL each).
class HeartRow extends Node2D:
	const HEART: PackedStringArray = ["##.##", "#####", ".###.", "..#.."]
	## One heart in world px (5 x 4 art pixels) and the gap between two.
	const SIZE := 10.0
	const HEIGHT := 8.0
	const GAP := 2.0

	var hearts := 0
	var max_hearts := 0

	func set_hearts(current: int, maximum: int) -> void:
		hearts = current
		max_hearts = maximum
		queue_redraw()

	func _draw() -> void:
		var width := max_hearts * SIZE + maxi(0, max_hearts - 1) * GAP
		var x := -width * 0.5
		for i in max_hearts:
			var color := LostVillager.HEART_COLOR if i < hearts else LostVillager.HEART_EMPTY
			PixelDraw.bitmap(self, Vector2(x, -HEIGHT * 0.5), HEART, color)
			x += SIZE + GAP
