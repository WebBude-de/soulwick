extends Node
## Global, cross-system signals only. Holds no gameplay state (D-044, D-046).
## Local events (health_changed, died, ...) stay on their owning nodes.

signal run_started
## reason is a RunManager.EndReason value; payout is the permanent gold credited (once).
signal run_ended(reason: int, remaining_run_gold: int, payout: int)
signal room_entered(room_index: int)
signal room_completed(room_index: int)
signal weapon_changed(slot: int, weapon: WeaponData)
signal upgrade_acquired(upgrade_id: StringName, stacks: int)
## Every effective hit on an enemy; upgrade effects (explosions, ON_KILL) react to it.
signal enemy_damaged(enemy: Node2D, result: DamageResult, damage: DamageData)
