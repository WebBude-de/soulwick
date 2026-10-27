class_name TutorialGate
extends Area2D
## The end of the practice run (WK10): the gate "Dungeon" (tutorial_gate.png) in the north wall of
## the hall. The first player who walks into its doorway passes it (the run then fades into room 1).
## The node origin is the middle of the gate's foot line (the north edge of the floor); the doorway
## reaches one tile and a half to the north, rock stops anyone behind it.

signal passed(player: Player)

const TILE := 64.0
## Trigger in the doorway: width and depth (px) north of the foot line.
const TRIGGER_SIZE := Vector2(48, 64)

var is_used := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.PLAYER
	monitorable = false
	var picture := TutorialArt.sprite(&"gate")
	picture.name = "Sprite"
	# Drawn over the wall front, under the characters walking in.
	picture.z_index = -1
	add_child(picture)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = TRIGGER_SIZE
	shape.shape = rect
	shape.position = Vector2(0, -TRIGGER_SIZE.y * 0.5 - 8.0)
	add_child(shape)
	var back := StaticBody2D.new()
	back.name = "Back"
	back.collision_layer = PhysicsLayers.WORLD
	var back_shape := CollisionShape2D.new()
	var back_rect := RectangleShape2D.new()
	back_rect.size = Vector2(TILE, 16)
	back_shape.shape = back_rect
	back_shape.position = Vector2(0, -TILE * 1.6)
	back.add_child(back_shape)
	add_child(back)
	var caption := Label.new()
	caption.name = "CaptionGate"
	caption.text = Loc.t(&"TUTORIAL_GATE")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 16)
	caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	caption.add_theme_constant_override(&"outline_size", 4)
	caption.size = Vector2(220, 24)
	caption.position = Vector2(-110, -TILE * 1.9)
	caption.z_index = 30
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if is_used or player == null or not player.is_alive():
		return
	is_used = true
	passed.emit(player)
