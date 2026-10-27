class_name SoulGate
extends SpecialContent
## Soul gate (KE3, KONZEPT §2; formerly the exit portal, D-006): stands at place 4 of a cycle
## (RoomSequence.roll_portal), at every campfire (D-103) and where a return stone opens one (KE5,
## open_return_gate). E opens the decision "Jetzt sichern" against "Weiter" (DungeonUI.choose_soul_gate);
## securing ends the run with 100 % for everybody (D-126: any player may use it, on a client the host
## ends the run, DungeonManager.end_run). The file keeps its old name: RoomController preloads
## exit_portal.tscn. Art: soul_gate_*.png (SPRITES_V13 §B4); until delivered the old exit portal.

const IDLE_PATH := "res://art/environment/props/soul_gate_idle_8f.png"
const OPEN_PATH := "res://art/environment/props/soul_gate_open_6f.png"
const ENTER_PATH := "res://art/effects/soul_gate_enter_8f.png"
const RETURN_STONE_PATH := "res://art/effects/return_stone_cast_8f.png"
## Delivered gate (§B4, art/environment/props/soul_gate.json): 48×64 frames, pivot bottom centre,
## idle 8 fps, opening 10 fps. Effects 48×48 (enter, return stone; delivered without JSON): pivot
## (24,40), 12 fps.
const GATE_FRAME := Vector2i(48, 64)
const GATE_PIVOT := Vector2(24, 63)
const OPEN_FPS := 10.0
const EFFECT_FRAME := Vector2i(48, 48)
const EFFECT_PIVOT := Vector2(24, 40)
const EFFECT_FPS := 12.0
## Placeholder until §B4 is delivered: the old exit portal strip (32×48).
const PORTAL_TEXTURE: Texture2D = preload("res://art/environment/props/exit_portal_6f.png")
const PORTAL_FRAME := Vector2i(32, 48)
const PORTAL_PIVOT := Vector2(16, 46)
const FPS := 8.0
const OPEN_ANIMATION: StringName = &"open"
## Bug report 23.10.2026 #b28a0f5e ("sieht so 2D aus"): the gate stands on the floor - a soft shadow
## as wide as its pillars at its foot and the swirl's light on the floor in front of it (the light cone
## of a way, DoorView.way_cone_texture, additive, under the characters). TESTWERTE
const SHADOW_HALF_WIDTH := 46.0
const FLOOR_GLOW_COLOR := Color(0.74, 0.46, 1.0)
const FLOOR_GLOW_ALPHA := 0.4
const FLOOR_GLOW_SCALE := Vector2(2.2, 2.4)
const FLOOR_GLOW_Z := -7

## The decision of this gate is open on this machine (one dialog at a time).
var _deciding := false
var _look: AnimatedProp = null


func _on_prepare() -> void:
	add_light(170.0, Vector2(0, -40))
	var delivered := ResourceLoader.exists(IDLE_PATH)
	if delivered:
		_look = add_animated(load(IDLE_PATH), GATE_FRAME, FPS, GATE_PIVOT)
	else:
		# M2: the dark fill above the swirl is see-through (DoorArt.open_fill).
		_look = add_animated(DoorArt.open_fill(PORTAL_TEXTURE, DoorArt.PORTAL_FILL), PORTAL_FRAME, FPS, PORTAL_PIVOT)
	if delivered and _appears_in_view():
		_play_open()
	DropShadow.attach(self, SHADOW_HALF_WIDTH, 0.0)
	_add_floor_glow()
	var interactable := add_interactable(DungeonTexts.t(&"PORTAL_PROMPT"), 48.0, Vector2(0, -30))
	interactable.interacted.connect(_on_interacted)
	var frame_height := (GATE_FRAME.y if delivered else PORTAL_FRAME.y) * SpriteStrip.PIXEL_SCALE
	add_caption(Loc.t(&"GATE_CAPTION"), Vector2(0, -frame_height - 20.0))


## The light of the swirl on the floor in front of the gate (see SHADOW_HALF_WIDTH); none without the art.
func _add_floor_glow() -> void:
	var texture := DoorView.way_cone_texture()
	if texture == null:
		return
	var glow := Sprite2D.new()
	glow.name = "FloorGlow"
	glow.texture = texture
	glow.centered = false
	# Pivot top centre: the light falls from the gate's foot into the room.
	glow.offset = Vector2(-texture.get_width() * 0.5, 0.0)
	glow.scale = FLOOR_GLOW_SCALE
	glow.z_index = FLOOR_GLOW_Z
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	glow.modulate = Color(FLOOR_GLOW_COLOR, FLOOR_GLOW_ALPHA)
	add_child(glow)


## The room is entered: the first soul gate ever, Flint explains it to the local player (WK8).
func _on_setup() -> void:
	for player in get_players():
		if player.is_local:
			FlintExplanations.soul_gate(player)


## true while the decision dialog of this gate is open here.
func is_deciding() -> bool:
	return _deciding


func _on_interacted(player: Player) -> void:
	if _deciding or player == null or context == null or context.ui == null:
		return
	_deciding = true
	var room_number := room.room_index if room != null else RunManager.get_current_room()
	var amounts := SoulGateRules.secure_amounts(RunManager.get_run_gold(), RunManager.get_run_crystals(), RunManager.get_danger_level())
	var secured: bool = await context.ui.choose_soul_gate(player, amounts.x, amounts.y,
			SoulGateRules.onward_bonus_percent(room_number),
			SoulGateRules.rooms_to_next_gate(room_number, DungeonManager.CAMPFIRE_EXIT_PORTAL))
	_deciding = false
	if not secured or not is_instance_valid(self) or context.manager == null:
		return
	Sfx.play_ui(self, &"portal")
	_play_effect(ENTER_PATH, player.global_position)
	context.manager.end_run(RunManager.EndReason.EXIT)


## Return stone (KE5 hook, KONZEPT §2): opens a gate in room if SoulGateRules allows it (once per
## run, not in a boss, champion or arena fight, not where one stands). The host calls it and sends
## the event; clients call it when the event arrives (D-126: the return stone works over the host).
## at: global position of the player who broke the stone (effect only). Returns the new gate or null.
static func open_return_gate(room: RoomController, already_used: bool, at := Vector2.INF) -> SoulGate:
	if not SoulGateRules.can_open_return_gate(room, already_used):
		return null
	room.spawn_exit_portal()
	var gate := find_in(room)
	if gate != null:
		gate._play_effect(RETURN_STONE_PATH, at if at != Vector2.INF else gate.global_position)
		if gate.context != null and gate.context.ui != null:
			gate.context.ui.show_banner(Loc.t(&"GATE_APPEARED_TITLE"), Loc.t(&"GATE_APPEARED_SUB"), UiKit.COLOR_CRYSTAL)
	return gate


## The soul gate standing in room, or null.
static func find_in(room: Node) -> SoulGate:
	if room == null:
		return null
	for child in room.get_children():
		if child is SoulGate:
			return child as SoulGate
	return null


## The gate comes up in front of the players (boss room, return stone), not in a room prepared ahead.
func _appears_in_view() -> bool:
	return room != null and (room.state == RoomController.State.ACTIVE or room.state == RoomController.State.CLEARED)


## Opening strip once, then the idle loop (only with the delivered art).
func _play_open() -> void:
	if _look == null or not ResourceLoader.exists(OPEN_PATH) or _look.sprite_frames == null:
		return
	SpriteStrip.add_strip(_look.sprite_frames, OPEN_ANIMATION, load(OPEN_PATH), GATE_FRAME, OPEN_FPS, false)
	_look.play(OPEN_ANIMATION)
	_look.animation_finished.connect(_look.play.bind(&"default"), CONNECT_ONE_SHOT)


## One-shot effect strip (enter, return stone) once it is delivered; nothing until then.
func _play_effect(path: String, global_pos: Vector2) -> void:
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var effect := SpriteStrip.spawn_effect(get_parent(), global_pos, load(path), EFFECT_FRAME, EFFECT_FPS, EFFECT_PIVOT)
	effect.scale = Vector2.ONE * SpriteStrip.PIXEL_SCALE
