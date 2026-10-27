class_name EnemyBadges
extends Node2D
## Small 12×12 symbols above special enemies (next to the health bar) so the player sees at a
## glance what an enemy can do: elite kind, champion crown and abilities (stun, blind, summons,
## explodes, splits). Uses art/ui/badge_<name>.png when present (docs/design/sprites/delivered/SPRITES_V2.md §5),
## otherwise procedurally drawn pixel icons.

const ICON_SIZE := 12
const ICON_SCALE := 2.0
const SPACING := 2.0
const ART_PATH := "res://art/ui/badge_%s.png"

const SWIFT := &"swift"
const ARMORED := &"armored"
const VOLATILE := &"volatile"
const CHAMPION := &"champion"
const STUN := &"stun"
const BLIND := &"blind"
const SUMMONER := &"summoner"
const EXPLODE := &"explode"
const SPLIT := &"split"
const ALL: Array[StringName] = [SWIFT, ARMORED, VOLATILE, CHAMPION, STUN, BLIND, SUMMONER, EXPLODE, SPLIT]

## Accent colour per badge (hint cards, boss bar).
const COLORS := {
	SWIFT: Color(0.35, 0.9, 1.0),
	ARMORED: Color(0.6, 0.72, 0.95),
	VOLATILE: Color(1.0, 0.55, 0.15),
	CHAMPION: Color(1.0, 0.82, 0.3),
	STUN: Color(1.0, 0.9, 0.3),
	BLIND: Color(0.75, 0.55, 1.0),
	SUMMONER: Color(0.55, 1.0, 0.6),
	EXPLODE: Color(1.0, 0.5, 0.2),
	SPLIT: Color(0.5, 1.0, 0.45),
}

## Pixel maps for the procedural fallback; '.' is transparent, 'k' the dark outline.
const PALETTE := {
	"k": Color(0.06, 0.05, 0.08),
	"w": Color(1.0, 1.0, 1.0),
	"c": Color(0.35, 0.9, 1.0),
	"s": Color(0.6, 0.7, 0.88),
	"d": Color(0.22, 0.2, 0.28),
	"o": Color(1.0, 0.55, 0.15),
	"y": Color(1.0, 0.9, 0.3),
	"g": Color(1.0, 0.78, 0.25),
	"r": Color(0.95, 0.2, 0.25),
	"p": Color(0.72, 0.5, 1.0),
	"b": Color(0.92, 0.9, 0.82),
	"l": Color(0.5, 1.0, 0.45),
}
const MAPS := {
	SWIFT: [
		".......kkk..",
		"......kcck..",
		".....kcck...",
		"....kcck....",
		"...kcwcckk..",
		"..kccccccck.",
		"..kkkkcwck..",
		".....kcck...",
		"....kcck....",
		"...kcck.....",
		"...kck......",
		"...kk.......",
	],
	ARMORED: [
		".kkkkkkkkkk.",
		".kwwwssssskk",
		".kwssssssssk",
		".kwssssssssk",
		".kssssssssk.",
		".kssssssssk.",
		".kssssssssk.",
		"..kssssssk..",
		"..kssssssk..",
		"...kssssk...",
		"....kssk....",
		".....kk.....",
	],
	VOLATILE: [
		"........y.y.",
		".......k.y..",
		"......k.....",
		"....kkkk....",
		"..kkddddkk..",
		".kddwdddddk.",
		".kdwddddddk.",
		"kddddddddddk",
		"kddddddddddk",
		".kddddddddk.",
		"..kkddddkk..",
		"....kkkk....",
	],
	CHAMPION: [
		"............",
		"............",
		"k....kk....k",
		"kk..kggk..kk",
		"kgk.kggk.kgk",
		"kggkkggkkggk",
		"kggggggggggk",
		"kgrggggggrgk",
		"kggggrrggggk",
		"kggggggggggk",
		"kkkkkkkkkkkk",
		"............",
	],
	STUN: [
		"..k......k..",
		".kyk....kyk.",
		"kyyyk..kyyyk",
		".kyk....kyk.",
		"..k......k..",
		"............",
		".....kk.....",
		"....kyyk....",
		"...kyyyyk...",
		"....kyyk....",
		".....kk.....",
		"............",
	],
	BLIND: [
		"............",
		"............",
		"............",
		"kk........kk",
		"kppk....kppk",
		".kpppkkpppk.",
		"..kppppppk..",
		"...kkkkkk...",
		"..kp.kk.pk..",
		".kp..kk..pk.",
		".k...kk...k.",
		"............",
	],
	SUMMONER: [
		"...kkkkkk...",
		"..kbbbbbbk..",
		".kbbbbbbbbk.",
		".kbkkbbkkbk.",
		".kbkkbbkkbk.",
		".kbbbbbbbbk.",
		"..kbbkkbbk..",
		"...kbbbbk...",
		"...kbkbkbk..",
		"...kkkkkk...",
		"............",
		"............",
	],
	EXPLODE: [
		".....kk.....",
		"..k.kyyk.k..",
		".kyk.kyk.kyk",
		"..kykyykyk..",
		"kkkyyooyykkk",
		"kyyyowwoyyyk",
		"kkkyyooyykkk",
		"..kykyykyk..",
		".kyk.kyk.kyk",
		"..k.kyyk.k..",
		".....kk.....",
		"............",
	],
	SPLIT: [
		"............",
		"..kkk..kkk..",
		".klllk.klllk",
		"klwlllkklwlk",
		"klllllkklllk",
		"klllllkklllk",
		".klllk..kllk",
		"..kkk...kkk.",
		"............",
		"..k..kk..k..",
		".k...kk...k.",
		"............",
	],
}

static var _textures: Dictionary[StringName, Texture2D] = {}

var _badges: Array[StringName] = []


## Badges an enemy shows. Bosses show theirs in the boss bar, so this only describes the enemy.
static func badges_for(data: EnemyData, elite: int, is_champion: bool) -> Array[StringName]:
	var result: Array[StringName] = []
	if data == null:
		return result
	if is_champion:
		result.append(CHAMPION)
	match elite:
		Enemy.Elite.SWIFT:
			result.append(SWIFT)
		Enemy.Elite.ARMORED:
			result.append(ARMORED)
		Enemy.Elite.VOLATILE:
			result.append(VOLATILE)
	if data.stun_duration > 0.0 and data.special == EnemyData.Special.SHIELD_CHARGE:
		result.append(STUN)
	if data.blind_duration > 0.0:
		result.append(BLIND)
	if data.summon_data != null and data.summon_every > 0:
		result.append(SUMMONER)
	if data.special == EnemyData.Special.SELF_DESTRUCT or data.special == EnemyData.Special.ERUPTION:
		result.append(EXPLODE)
	if data.death_spawn != null and data.death_spawn_count > 0:
		result.append(SPLIT)
	return result


## Art file if it exists, else the procedural pixel icon. Cached.
static func get_texture(badge: StringName) -> Texture2D:
	if _textures.has(badge):
		return _textures[badge]
	var texture: Texture2D = null
	var path := ART_PATH % badge
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		texture = build_icon(badge)
	_textures[badge] = texture
	return texture


static func build_icon(badge: StringName) -> ImageTexture:
	var image := Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var rows: Array = MAPS.get(badge, [])
	for y in mini(rows.size(), ICON_SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), ICON_SIZE):
			var key := row[x]
			if PALETTE.has(key):
				image.set_pixel(x, y, PALETTE[key])
	return ImageTexture.create_from_image(image)


func set_badges(badges: Array[StringName]) -> void:
	_badges = badges.duplicate()
	queue_redraw()


func get_badges() -> Array[StringName]:
	return _badges


## Width of the badge row in local pixels.
func get_row_width() -> float:
	if _badges.is_empty():
		return 0.0
	return _badges.size() * ICON_SIZE * ICON_SCALE + (_badges.size() - 1) * SPACING


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Draws the row centred on the node origin, bottom edge on y = 0.
func _draw() -> void:
	var size := ICON_SIZE * ICON_SCALE
	var x := -get_row_width() * 0.5
	for badge in _badges:
		draw_texture_rect(get_texture(badge), Rect2(x, -size, size, size), false)
		x += size + SPACING
