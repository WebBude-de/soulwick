class_name HomeAltar
extends Node2D
## The candle altar in the home (KE8, KONZEPT §6): three candles in the path colours (Wind türkis,
## Glut orange, Seele violett) with a small light each; E opens the talent tree (HomeInterior). It
## burns brighter while talent points are free (candle_altar_ready_4f, stronger lights), else calm
## (candle_altar_idle_6f). Art px from home_props.json, drawn at HomeLayout.SCALE; the node origin is
## the foot point (HomeInterior lifts it for the y-sort).

signal used(player: Player)

const IDLE := &"candle_altar_idle"
const READY := &"candle_altar_ready"
const USE_RADIUS := 34.0

var is_ready := false
var sprite: AnimatedSprite2D = null
var door: Interactable = null
var lights: Array[LightSource] = []


static func create() -> HomeAltar:
	var altar := HomeAltar.new()
	altar.name = "Altar"
	return altar


func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2.ONE * HomeLayout.SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	var colours: Array[Color] = [TalentTreeArt.path_color(TalentDef.PATH_WIND),
		TalentTreeArt.path_color(TalentDef.PATH_EMBER), TalentTreeArt.path_color(TalentDef.PATH_SOUL)]
	for index in HomeLayout.ALTAR_CANDLES.size():
		var light := LightSource.new()
		light.name = "Candle%d" % (index + 1)
		light.color = colours[index % colours.size()]
		light.radius = HomeLayout.tiles_to_world(HomeLayout.ALTAR_LIGHT_RADIUS_TILES)
		light.flicker = 0.05
		light.position = HomeLayout.ALTAR_CANDLES[index] * HomeLayout.SCALE
		light.ground_offset = Vector2(0, -light.position.y)
		add_child(light)
		lights.append(light)
	door = Interactable.new()
	door.name = "Door"
	door.prompt = Loc.t(&"HOME_ALTAR_PROMPT")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = USE_RADIUS
	shape.shape = circle
	door.add_child(shape)
	door.position = Vector2(0, 12)
	add_child(door)
	door.interacted.connect(func(player: Player) -> void: used.emit(player))
	set_ready(is_ready)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and door != null:
		door.prompt = Loc.t(&"HOME_ALTAR_PROMPT")


## Brighter while talent points are free (KE8).
func set_ready(value: bool) -> void:
	is_ready = value
	if sprite == null:
		return
	var art := String(READY if value else IDLE)
	var spec := HomeArt.prop_spec(art)
	sprite.sprite_frames = HomeArt.prop_frames(art)
	sprite.centered = true
	sprite.offset = SpriteStrip.pivot_offset(HomeArt.frame_size(spec), HomeArt.pivot(spec))
	sprite.play(&"default")
	for light in lights:
		light.intensity = HomeLayout.ALTAR_LIGHT_READY if value else HomeLayout.ALTAR_LIGHT_IDLE


## Free talent points of this machine's account decide the glow.
func refresh_from_account() -> void:
	set_ready(AccountProgress.current().get_free_points() > 0)
