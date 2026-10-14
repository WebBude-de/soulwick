class_name RoomVariants
extends RefCounted
## Entry point of the room modes for the DungeonManager and the RoomController (R4, D-120; hooks for
## the integrator):
##   - VariantTable.roll() decides "minigame, wager altar or nothing" for a normal combat room and
##     names the plan mode (Pick.plan_mode); plan_mode_for() checks a plan of it fits the room,
##   - attach() hangs the result onto the prepared room (and the crypt's gravedigger trait),
##   - get_variant_id() / has_wager_altar() read it back (genre banner, RoomGenre, LightingProfile),
##   - holds_completion() lets a mode keep the room shut (flame raid time, relic not on the altar),
##   - spawn_first_wave() gives a mode's own first wave (guards of the plan, the crowned one).
## Everything else follows the room's own signals; the DungeonManager treats mode rooms like every
## combat room.


## Attaches the draw of VariantTable.roll() to a prepared normal combat room (after add_child and
## after set_encounter_group). Draws exactly one number from rng when the pick is not empty, none
## otherwise. Returns the mode id that is now in the room (&"" for none or a wager altar) - the
## DungeonManager keeps it as "previous variant" (never the same mode twice in a row).
## Crypt rooms also get the gravedigger trait here (skeletons rise once, GravediggerTrait); it draws
## nothing from rng.
static func attach(room: RoomController, pick: VariantTable.Pick, rng: RandomNumberGenerator) -> StringName:
	if room != null and is_instance_valid(room):
		GravediggerTrait.attach_if_crypt(room)
	if room == null or pick == null or pick.is_empty() or rng == null:
		return VariantTable.NONE
	if pick.has_variant():
		var variant := CombatVariant.attach_to(room, pick.variant_id, rng.randi())
		return variant.variant_id if variant != null else VariantTable.NONE
	WagerAltar.attach_to(room, rng.randf())
	return VariantTable.NONE


## Plan mode the DungeonManager hands to RoomCatalog.pick for this room: the pick's plan mode when the
## catalog has a plan of it for the room (kind, solo sizes, biome, room, entrance wall), else &"" (any
## combat plan; the mode then finds its own spots). Draws nothing.
static func plan_mode_for(plan_mode: StringName, catalog: RoomCatalog, kind: int, room_index: int, entrance_side := -1) -> StringName:
	if plan_mode == &"" or catalog == null:
		return &""
	if catalog.has_kind(kind, RoomSequence.SOLO_ROOM_SIZES, &"", room_index, entrance_side, plan_mode):
		return plan_mode
	if catalog.has_kind(-1, RoomSequence.SOLO_ROOM_SIZES, &"", room_index, entrance_side, plan_mode):
		return plan_mode
	return &""


## Mode of a room (&"flame", &"relic", &"rifts", &"hunt", &"lightfire", R4a's modes, &"elite_nest";
## &"" = none).
static func get_variant_id(room: Node) -> StringName:
	var variant := CombatVariant.of(room)
	return variant.variant_id if variant != null else VariantTable.NONE


static func has_wager_altar(room: Node) -> bool:
	return WagerAltar.of(room) != null


## True while a mode keeps the room shut although no enemy is left.
static func holds_completion(room: Node) -> bool:
	var variant := CombatVariant.of(room)
	return variant != null and variant.holds_completion()


## RoomController hook (start_encounter): the first wave a mode brings itself - empty when the room
## spawns its first wave out of the sources as usual. The room tracks the returned enemies as wave 1.
static func spawn_first_wave(room: Node) -> Array[Enemy]:
	var mode := CombatVariant.of(room) as RoomMode
	if mode == null:
		return []
	return mode.spawn_first_wave()


## Light circle the DungeonManager gives this room (DungeonManager._apply_vision): base radius,
## extra dark rooms smaller, times the biome factor and the pact curse of the player. Modes that
## change the light (flame out, lightfire, wager curse) start from it and give it back.
static func room_vision_radius(room: RoomController) -> float:
	if room == null:
		return DungeonManager.VISION_RADIUS
	var biome := room.spawner.get_biome(room.room_index)
	var radius := DungeonManager.EXTRA_DARK_VISION_RADIUS if room.is_extra_dark else DungeonManager.VISION_RADIUS
	var biome_factor := biome.vision_factor if biome != null else 1.0
	var player := room.context.player if room.context != null else null
	return radius * biome_factor * PlayerCurses.vision_factor(player)
