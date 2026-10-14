class_name RoomVariants
extends RefCounted
## Entry point of A7 for the DungeonManager and the RoomController (hooks for the integrator):
##   - VariantTable.roll() decides "variant, wager altar or nothing" for a normal combat room,
##   - attach() hangs the result onto the prepared room,
##   - get_variant_id() / has_wager_altar() read it back (UX2 genre banner, RoomGenre),
##   - holds_completion() lets a variant keep the room shut (soul flame raid time).
## Everything else follows the room's own signals; the DungeonManager treats variant rooms like
## every combat room.


## Attaches the draw of VariantTable.roll() to a prepared normal combat room (after add_child and
## after set_encounter_group). Draws exactly one number from rng when the pick is not empty, none
## otherwise. Returns the variant id that is now in the room (&"" for none or a wager altar) - the
## DungeonManager keeps it as "previous variant" (never two in a row, D-101).
static func attach(room: RoomController, pick: VariantTable.Pick, rng: RandomNumberGenerator) -> StringName:
	if room == null or pick == null or pick.is_empty() or rng == null:
		return VariantTable.NONE
	if pick.has_variant():
		var variant := CombatVariant.attach_to(room, pick.variant_id, rng.randi())
		return variant.variant_id if variant != null else VariantTable.NONE
	WagerAltar.attach_to(room, rng.randf())
	return VariantTable.NONE


## Combat variant of a room (&"soul_flame", &"rifts", &"gravedigger", &"bounty", A9: &"stone_guardian",
## &"lantern", &"torch_room"; &"" = none).
static func get_variant_id(room: Node) -> StringName:
	var variant := CombatVariant.of(room)
	return variant.variant_id if variant != null else VariantTable.NONE


static func has_wager_altar(room: Node) -> bool:
	return WagerAltar.of(room) != null


## True while a variant keeps the room shut although no enemy is left.
static func holds_completion(room: Node) -> bool:
	var variant := CombatVariant.of(room)
	return variant != null and variant.holds_completion()


## Light circle the DungeonManager gives this room (DungeonManager._apply_vision): base radius,
## extra dark rooms smaller, times the biome factor and the pact curse of the player. Variants that
## change the light (flame out, wager curse) start from it and give it back.
static func room_vision_radius(room: RoomController) -> float:
	if room == null:
		return DungeonManager.VISION_RADIUS
	var biome := room.spawner.get_biome(room.room_index)
	var radius := DungeonManager.EXTRA_DARK_VISION_RADIUS if room.is_extra_dark else DungeonManager.VISION_RADIUS
	var biome_factor := biome.vision_factor if biome != null else 1.0
	var player := room.context.player if room.context != null else null
	return radius * biome_factor * PlayerCurses.vision_factor(player)
