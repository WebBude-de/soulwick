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
## Abyss tiles (A4, D-086): enemies collide with it like with a wall, players and projectiles not.
const PIT := 64
## Height (M3): cliffs of plateaus and the edges between a plateau and the ground below it. Players
## and enemies collide with it like with a wall; projectiles, hit areas and sight rays do not (they
## fly over the cliff, a shot from above hits below).
const CLIFF := 128
## Ladders (M3): only enemies collide with it (they never climb), players walk through.
const LADDER := 256
