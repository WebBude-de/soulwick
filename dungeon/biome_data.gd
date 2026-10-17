class_name BiomeData
extends Resource
## A dungeon theme for 15 rooms (D-075): look, light and which enemies appear how often.
## Until own tilesets exist, the crypt tiles are tinted.

@export var id: StringName
@export var display_name := ""
## Multiplied onto the floor/wall tiles.
@export var tile_tint := Color.WHITE
## Darkness colour of the vision overlay.
@export var darkness_color := Color(0.012, 0.008, 0.025)
## Vision radius factor (shadow realm < 1).
@export var vision_factor := 1.0
@export var enemies: Array[EnemyData] = []
@export var weights: Array[float] = []

@export_group("Floor hazards")
## Hazard placed by BiomeHazards (toxic puddle, lava crack); null = none.
@export var hazard_scene: PackedScene
## Inclusive min/max hazards in combat and miniboss rooms.
@export var hazard_count := Vector2i.ZERO
## Hazards in the boss room of this biome.
@export var boss_hazard_count := 0
## Extra hazard per full cycle of the four biomes (room 61+, 121+, ...).
@export var hazards_per_cycle := 1

@export_group("Music")
## Dungeon track in audio/music/ without extension (D-092); "" or a missing file = "dungeon".
## "<track>_intense" plays in champion rooms if it exists (MusicRules).
@export var music_track := ""
## Boss track in audio/music/; "" or a missing file = "boss". "<track>_p2" plays in phase two.
@export var boss_music_track := ""
## Quiet loop in audio/ambient/ under the music; "" = no ambient bed.
@export var ambient_track := ""
## One-shot stinger in audio/music/ when the biome is entered (the loop follows after it);
## "" or a missing file = the loop just fades in.
@export var transition_track := ""
## One-shot stinger in audio/music/ when the biome's boss falls; "" = the boss music just fades.
@export var victory_track := ""


## Enemy types allowed in this room (min_room) with their weights.
func get_table(room_index: int) -> Array:
	var types: Array[EnemyData] = []
	var type_weights: Array[float] = []
	for i in enemies.size():
		if enemies[i].min_room <= room_index:
			types.append(enemies[i])
			type_weights.append(weights[i] if i < weights.size() else 1.0)
	return [types, type_weights]


## Number of floor hazards for a room (D-075). Special rooms stay safe.
func get_hazard_count(room_index: int, room_type: RoomSequence.RoomType, rng: RandomNumberGenerator) -> int:
	if hazard_scene == null or room_type == RoomSequence.RoomType.SPECIAL:
		return 0
	var cycle := floori(float(room_index - 1) / float(RoomSequence.BOSS_INTERVAL * RoomSequence.BIOME_COUNT))
	if room_type == RoomSequence.RoomType.BOSS:
		return boss_hazard_count + cycle * hazards_per_cycle if boss_hazard_count > 0 else 0
	if hazard_count.y <= 0:
		return 0
	return rng.randi_range(hazard_count.x, hazard_count.y) + cycle * hazards_per_cycle
