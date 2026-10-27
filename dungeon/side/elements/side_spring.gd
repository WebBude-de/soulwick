class_name SideSpring
extends Node2D
## A spring of the jump trial (Sprungfeder, SV2, D-195, plan "j"): a player whose feet come down
## on it (or walk onto it) is thrown SideElementRules.SPRING_HEIGHT_TILES (4.5) tiles straight up;
## the double jump stays free for the top. The origin is the floor line in the middle of its cell.
## A static rule like the pools: every machine decides it for every player it moves (the player at
## the keyboard, the host's copies), so the predicted jump of a client's own player and the host's
## copy agree; launched drives the look (frames, sound). Art: spring_4f.png (4 × 32×32, pivot
## (16,30): still, pressed, shooting up, swinging), else a drawn coil.

## A player was thrown up (the decision; the look follows).
signal launched(spring: SideSpring, player: Player)

const ART_PATH := "res://art/environment/side/spring_4f.png"
const ART_FRAME := Vector2i(32, 32)
const ART_PIVOT := Vector2(16, 30)
const ART_FPS := 12.0
const SOUND := &"side_spring"
const SOUND_FALLBACK := &"slime_hop"
const COIL_COLOR := Color(0.75, 0.78, 0.85)
const PAD_COLOR := Color(0.95, 0.55, 0.25)
## A jump off the spring rises ~15 px per frame: its feet still count this far above the floor line
## (two frames at JUMP_VELOCITY). TESTWERT
const JUMP_OFF_REACH := 40.0

var segment: SideSegment = null
## Players thrown during this segment (tools, tests).
var launches := 0

## Player instance id -> seconds until the spring may throw them again.
var _rearm: Dictionary[int, float] = {}
var _sprite: AnimatedSprite2D = null
var _bounce := 0.0


func _ready() -> void:
	z_index = -1
	if ResourceLoader.exists(ART_PATH):
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "Art"
		_sprite.sprite_frames = SpriteStrip.make_frames(load(ART_PATH) as Texture2D, ART_FRAME, ART_FPS, false)
		_sprite.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
		_sprite.offset = SpriteStrip.pivot_offset(ART_FRAME, ART_PIVOT)
		_sprite.frame = 0
		add_child(_sprite)


func _physics_process(delta: float) -> void:
	for id: int in _rearm.keys():
		_rearm[id] -= delta
		if _rearm[id] <= 0.0:
			_rearm.erase(id)
	_bounce = maxf(0.0, _bounce - delta)
	if _sprite == null:
		queue_redraw()
	if segment == null:
		return
	for player in segment.get_players():
		if presses(player):
			launch(player)


## Whether player stands on the spring right now (landed or walked onto it) or jumps off it in this
## moment (the spring throws anyway, PlayerSideMotion.launch ends the jump): feet over it, active in
## the segment, not just thrown.
func presses(player: Player) -> bool:
	if not is_instance_valid(player) or not player.is_alive() or _rearm.has(player.get_instance_id()):
		return false
	var motion := player.side_motion
	if motion == null or not motion.is_active() or motion.is_in_pit() or motion.is_climbing():
		return false
	var standing := motion.is_on_floor() and player.velocity.y >= -1.0
	var jumping_off := motion.is_jumping() and player.velocity.y < 0.0
	if not standing and not jumping_off:
		return false
	var feet := player.get_feet_position() - global_position
	var reach := SideElementRules.SPRING_TRIGGER_HEIGHT if standing else JUMP_OFF_REACH
	return absf(feet.x) <= SideElementRules.SPRING_HALF_WIDTH and feet.y >= -reach and feet.y <= 4.0


## Throws player up (decision): the launch speed (a running jump ends, so the rise is never cut),
## the look.
func launch(player: Player) -> void:
	if player.side_motion != null:
		player.side_motion.launch(-SideElementRules.spring_velocity())
	else:
		player.velocity.y = -SideElementRules.spring_velocity()
	_rearm[player.get_instance_id()] = SideElementRules.SPRING_REARM
	launches += 1
	_bounce = 0.35
	if _sprite != null:
		_sprite.frame = 1
		_sprite.play(&"default")
	if is_inside_tree():
		Sfx.play_at(self, SideRules.sound_or(SOUND, SOUND_FALLBACK), global_position, -4.0)
	launched.emit(self, player)


## Placeholder until spring_4f.png: a coil with a pad, stretched while it swings.
func _draw() -> void:
	if _sprite != null:
		return
	var height := 18.0 + _bounce * 40.0
	for i in 4:
		var y := -4.0 - i * height / 4.0
		SidePixels.line(self, Vector2(-14, y), Vector2(14, y - height / 8.0), COIL_COLOR, 2)
	SidePixels.rect(self, Rect2(-20.0, -height - 8.0, 40.0, 6.0), PAD_COLOR)
	SidePixels.rect(self, Rect2(-18.0, -4.0, 36.0, 4.0), COIL_COLOR.darkened(0.4))
