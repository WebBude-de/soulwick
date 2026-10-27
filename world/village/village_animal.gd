class_name VillageAnimal
extends Interactable
## WK12 "Dorftiere zum Anfassen" (D-196 point 6, KONZEPT §8): the chickens, the cat and later
## animals of the village react when a player speaks to them (E): the chicken is fed (grain on the
## ground, a hop, "Gack!"), the cat is petted (it stands still, purrs, hearts). A heart rises above
## every animal that was spoken to. The first time per account and animal kind Flint comments it
## (a HINT in his corner, AccountSeen "flint_village_animal_<kind>", like the building
## explanations of VillageTour).
## Optics only, no game effect: nothing is paid, saved (except Flint's seen flag) or sent. Co-op
## (D-088): only a player at this machine gets a reaction, on this machine; the other machines do
## not see it, no randomness of the dungeon RNG is used (the grain spread is fixed).
## Art (SPRITES_V13 Teil C): art/environment/village/animal_heart.png (8×7) and an optional
## art/characters/npcs/<animal>_react_<n>f.png strip (played while the animal reacts,
## VillageArt.get_character_frames); until then a drawn pixel heart and the idle animation.
## Sounds audio/sfx/chicken_cluck.wav, cat_purr.wav, dog_woof.wav (synthesised by tools/generate_audio.py).
## Created by Villager for every villager with an animal kind (tools/generate_village.py).

enum Style { FEED, PET }

## Animal kind -> what speaking to it does. prompt: door-prompt key; call: the sound as text above
## the head; sound: audio/sfx/<name>.wav; hop: hop height (world px, 0 = none); hearts: how many
## rise; flint: Flint's first-time comment.
const KINDS := {
	&"chicken": {"style": Style.FEED, "prompt": &"VILLAGE_ANIMAL_FEED", "call": &"VILLAGE_ANIMAL_CLUCK",
		"sound": &"chicken_cluck", "hop": 8.0, "hearts": 1, "flint": &"VILLAGE_ANIMAL_FLINT_CHICKEN"},
	&"cat": {"style": Style.PET, "prompt": &"VILLAGE_ANIMAL_PET", "call": &"VILLAGE_ANIMAL_PURR",
		"sound": &"cat_purr", "hop": 0.0, "hearts": 2, "flint": &"VILLAGE_ANIMAL_FLINT_CAT"},
	&"dog": {"style": Style.PET, "prompt": &"VILLAGE_ANIMAL_PET", "call": &"VILLAGE_ANIMAL_WOOF",
		"sound": &"dog_woof", "hop": 6.0, "hearts": 1, "flint": &"VILLAGE_ANIMAL_FLINT_DOG"},
}
## Seen id of Flint's comment: prefix + kind (starts with FlintExplanation.ID_PREFIX).
const FLINT_PREFIX := "flint_village_animal_"
## TESTWERTE: the animal stands and looks at the player this long (s); a new reaction after
## COOLDOWN s; the reach of an animal (world px around its body, plus the player's 44 px).
const REACT_TIME := 2.4
const COOLDOWN := 0.9
const AREA_RADIUS := 16.0
const AREA_OFFSET := Vector2(0, -8)
## TESTWERTE: hearts rise HEART_RISE art px in HEART_TIME s, one every HEART_GAP s; the call shows
## CALL_TIME s; grain lies GRAIN_TIME s.
const HEART_RISE := 12
const HEART_TIME := 1.1
const HEART_GAP := 0.3
const CALL_TIME := 1.4
const CALL_RISE := 6.0
const GRAIN_TIME := 2.6
const ALPHA_STEPS := 4.0
const SOUND_VOLUME_DB := -6.0
## Grain in front of the beak (art px from the feet, fixed: no randomness).
const GRAIN_SPOTS: Array[Vector2i] = [Vector2i(5, 0), Vector2i(8, -1), Vector2i(6, 2), Vector2i(10, 1),
	Vector2i(4, -2), Vector2i(9, 3)]
const GRAIN_COLORS: Array[Color] = [Color("#f2cf4a"), Color("#e0b84a"), Color("#c99a2e")]
## Under characters, above the ground (like VillageDecor.FLAT_Z).
const GRAIN_Z := -3
## Above roofs and props in front of the animal (like the villager's "?").
const FX_Z := 10
const HEART_ART := "animal_heart"
const HEART_PINK := Color("#f0648c")
const HEART_LIGHT := Color("#ffc2d4")
const CALL_COLOR := Color(1.0, 0.94, 0.7)
const CALL_OUTLINE := Color(0.1, 0.08, 0.15)
## 8×7 pixel heart: # outline, o fill, + light.
const HEART_ROWS: Array[String] = [
	".##..##.",
	"#+o##oo#",
	"#oooooo#",
	"#oooooo#",
	".#oooo#.",
	"..#oo#..",
	"...##...",
]

static var _heart_texture: Texture2D = null

var kind: StringName = &""
var _villager: Villager = null
var _cooldown := 0.0
## Rising hearts: {"sprite": Sprite2D, "age": float}; ages below 0 wait for their turn.
var _hearts: Array[Dictionary] = []
var _call: Label = null
var _call_left := 0.0
var _grain: Node2D = null
var _grain_left := 0.0
var _reactions := 0


## Adds the reaction to a villager (an animal of kind). Null for an unknown kind.
static func attach(villager: Villager, animal_kind: StringName) -> VillageAnimal:
	if villager == null or not KINDS.has(animal_kind):
		return null
	var animal := VillageAnimal.new()
	animal.name = "Animal"
	animal.kind = animal_kind
	animal._villager = villager
	animal.prompt = String(KINDS[animal_kind]["prompt"])
	animal.position = Villager.FEET_OFFSET + AREA_OFFSET
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = AREA_RADIUS
	shape.shape = circle
	animal.add_child(shape)
	villager.add_child(animal)
	return animal


## Seen id of Flint's first comment on an animal kind.
static func flint_id(animal_kind: StringName) -> StringName:
	return StringName(FLINT_PREFIX + String(animal_kind))


## Flint's first-time comment on an animal kind (a hint: no camera, no lock), null if unknown.
static func flint_comment(animal_kind: StringName) -> FlintExplanation:
	if not KINDS.has(animal_kind):
		return null
	var step := FlintGuideStep.say(KINDS[animal_kind]["flint"], FlintGuideStep.Mood.HAPPY)
	return FlintExplanation.hint(flint_id(animal_kind), [step])


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_update_hearts(delta)
	_update_call(delta)
	_update_grain(delta)


## E on the animal (Player._update_interaction): the reaction for that player.
func interact(player: Player) -> void:
	super(player)
	react(player)


## The animal reacts to player: stands and looks at them, its kind's reaction, a heart, the sound;
## Flint comments the first time. False (nothing happens) for a player at another machine, while
## the last reaction cools down or without a villager.
func react(player: Player) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_local:
		return false
	if _cooldown > 0.0 or _villager == null or not is_instance_valid(_villager):
		return false
	_cooldown = COOLDOWN
	_reactions += 1
	var info: Dictionary = KINDS[kind]
	var player_feet := player.global_position + Villager.FEET_OFFSET
	_villager.hold(player_feet, REACT_TIME)
	if float(info["hop"]) > 0.0:
		_villager.hop_in_place(float(info["hop"]))
	if info["style"] == Style.FEED:
		_scatter_grain(player_feet)
	for i in int(info["hearts"]):
		_add_heart(-HEART_GAP * i)
	_show_call(info["call"])
	Sfx.play_at(self, info["sound"], _villager.get_feet_global(), SOUND_VOLUME_DB)
	_comment(player)
	return true


## How often this animal reacted (for tests and tools).
func get_reactions() -> int:
	return _reactions


## Hearts rising right now (for tests and tools).
func get_heart_count() -> int:
	return _hearts.size()


## The call text ("Gack!", "Schnurr …") while it shows, else null.
func get_call() -> Label:
	return _call if _call != null and _call.visible else null


## The grain on the ground while it lies there, else null.
func get_grain() -> Node2D:
	return _grain if _grain != null and is_instance_valid(_grain) else null


func _comment(player: Player) -> void:
	if VillageTour.may_explain(player):
		FlintGuide.explain(player, flint_comment(kind))


# --- Hearts ---

## The heart texture: the delivered file or a drawn 8×7 pixel heart.
static func heart_texture() -> Texture2D:
	if VillageArt.has_art(HEART_ART):
		return VillageArt.get_texture(HEART_ART)
	if _heart_texture == null:
		_heart_texture = ImageTexture.create_from_image(heart_image())
	return _heart_texture


static func heart_image() -> Image:
	var image := Image.create(HEART_ROWS[0].length(), HEART_ROWS.size(), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in HEART_ROWS.size():
		for x in HEART_ROWS[y].length():
			match HEART_ROWS[y][x]:
				"#":
					image.set_pixel(x, y, VillageArt.OUTLINE)
				"o":
					image.set_pixel(x, y, HEART_PINK)
				"+":
					image.set_pixel(x, y, HEART_LIGHT)
	return image


func _add_heart(start_age: float) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Heart"
	sprite.texture = heart_texture()
	sprite.scale = Vector2.ONE * VillageArt.SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = FX_Z
	sprite.visible = start_age >= 0.0
	_villager.add_child(sprite)
	_hearts.append({"sprite": sprite, "age": start_age, "side": 1 if _hearts.size() % 2 == 0 else -1})
	_place_heart(_hearts.back())


## Hearts rise in whole art pixels with a small sway and fade out in steps.
func _update_hearts(delta: float) -> void:
	for i in range(_hearts.size() - 1, -1, -1):
		var heart: Dictionary = _hearts[i]
		heart["age"] = float(heart["age"]) + delta
		var sprite: Sprite2D = heart["sprite"]
		if float(heart["age"]) >= HEART_TIME or not is_instance_valid(sprite):
			if is_instance_valid(sprite):
				sprite.queue_free()
			_hearts.remove_at(i)
			continue
		_place_heart(heart)


func _place_heart(heart: Dictionary) -> void:
	var sprite: Sprite2D = heart["sprite"]
	var age := float(heart["age"])
	sprite.visible = age >= 0.0
	if not sprite.visible:
		return
	var t := age / HEART_TIME
	var px := VillageArt.SCALE
	var sway := roundf(sin(t * TAU) * 2.0) * int(heart["side"])
	var rise := roundf(t * HEART_RISE)
	sprite.position = Vector2(sway, -rise) * px + Vector2(0, _villager.get_head_y() - 4.0 * px)
	sprite.modulate.a = ceilf(clampf((1.0 - t) * 1.6, 0.0, 1.0) * ALPHA_STEPS) / ALPHA_STEPS


# --- Call ("Gack!", "Schnurr …") ---

func _show_call(key: StringName) -> void:
	if _call == null:
		_call = Label.new()
		_call.name = "Call"
		_call.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_call.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_call.add_theme_font_override("font", UiKit.bold_font())
		_call.add_theme_font_size_override("font_size", 14)
		_call.add_theme_color_override("font_color", CALL_COLOR)
		_call.add_theme_color_override("font_outline_color", CALL_OUTLINE)
		_call.add_theme_constant_override("outline_size", 5)
		_call.z_index = FX_Z
		_villager.add_child(_call)
	# The key: the label translates itself (also after a language switch).
	_call.text = key
	_call.reset_size()
	_call_left = CALL_TIME
	_call.visible = true
	_place_call()


func _update_call(delta: float) -> void:
	if _call == null or not _call.visible:
		return
	_call_left -= delta
	if _call_left <= 0.0:
		_call.visible = false
		return
	_place_call()


## Beside the head (the hearts rise above it), rising a little and fading out at the end.
func _place_call() -> void:
	var t := 1.0 - _call_left / CALL_TIME
	var side := -1.0 if _villager.get_sprite() != null and _villager.get_sprite().flip_h else 1.0
	var x := 10.0 if side > 0.0 else -10.0 - _call.size.x
	_call.position = Vector2(x, _villager.get_head_y() - _call.size.y * 0.5 - roundf(t * CALL_RISE))
	_call.modulate.a = clampf(_call_left / 0.25, 0.0, 1.0)


# --- Grain (feeding) ---

## A few grains on the ground between the chicken and the player (in front of its beak).
func _scatter_grain(player_feet: Vector2) -> void:
	if _grain != null and is_instance_valid(_grain):
		_grain.queue_free()
	var feet := _villager.get_feet_global()
	var facing := 1.0 if player_feet.x >= feet.x else -1.0
	_grain = Node2D.new()
	_grain.name = "Grain"
	# Lies where it fell while the chicken moves on (and goes with it when the village is freed).
	_grain.top_level = true
	_grain.z_index = GRAIN_Z
	_grain.draw.connect(_draw_grain.bind(_grain, facing))
	_villager.add_child(_grain)
	_grain.global_position = VillageTour.snap_to_art(feet)
	_grain_left = GRAIN_TIME


func _draw_grain(node: Node2D, facing: float) -> void:
	var px := VillageArt.SCALE
	var alpha := ceilf(clampf(_grain_left / 0.6, 0.0, 1.0) * ALPHA_STEPS) / ALPHA_STEPS
	for i in GRAIN_SPOTS.size():
		var spot := GRAIN_SPOTS[i]
		var cell := Vector2(spot.x * facing, spot.y) * px
		node.draw_rect(Rect2(cell, Vector2(px, px)), Color(GRAIN_COLORS[i % GRAIN_COLORS.size()], alpha))


func _update_grain(delta: float) -> void:
	if _grain == null:
		return
	if not is_instance_valid(_grain):
		_grain = null
		return
	_grain_left -= delta
	if _grain_left <= 0.0:
		_grain.queue_free()
		_grain = null
		return
	_grain.queue_redraw()


func _exit_tree() -> void:
	if _grain != null and is_instance_valid(_grain):
		_grain.queue_free()
	_grain = null
