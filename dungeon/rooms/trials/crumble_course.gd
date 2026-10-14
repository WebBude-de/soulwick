class_name CrumbleCourse
extends TrialCourse
## Bröckelboden (KONZEPT_RAEUME §6.1) – prepared interface only, built after A4 (abyss):
## floor tiles of the parcours crack shortly after a player stepped on them and become pits behind
## him; sprint, dash, choose a way. Falling follows the A4 rule (one heart, back to the last safe
## spot), so the course itself deals no damage: get_damage() stays 0 and the fall counts as a
## mistake through the content's register_mistake().
##
## Needed from A4 (then is_available() returns true and SpecialTable.crumble_weight may be > 0):
##   - RoomTiles pit API to turn a floor tile into a pit at runtime (e.g. add_pit_tiles()),
##   - the player's fall signal (or a query "is falling") to report the mistake,
##   - art crumbling_floor_6f (SPRITES_V5 §4) for the crack -> break -> gone animation.
## Plan: build() picks crumble tiles along the lanes with the dungeon RNG (both lane rows, never
## two full columns in a row without a dashable gap of at most RoomTiles.MAX_DASH_GAP), advance()
## counts down each tile stepped on (TESTWERT ~0.6 s) and calls the pit API.


static func is_available() -> bool:
	return false


func build(_rng: RandomNumberGenerator) -> void:
	push_warning("CrumbleCourse needs the abyss of A4; the trial content falls back to the gauntlet.")
