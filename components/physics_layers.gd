class_name PhysicsLayers
extends RefCounted
## Bit values of the named 2D physics layers in project.godot.
## Friendly fire is prevented purely by layers: enemy attacks only see PLAYER_HURTBOX and vice versa.

const WORLD := 1
const PLAYER := 2
const ENEMIES := 4
const PLAYER_HURTBOX := 8
const ENEMY_HURTBOX := 16
const INTERACTION := 32
