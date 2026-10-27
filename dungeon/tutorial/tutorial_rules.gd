class_name TutorialRules
extends RefCounted
## Rules of the practice run (Übungsgang, WK10, KONZEPT §7.2): when it is offered, its four stations
## in order, what finishes a station, what a hit on a dummy does, the XP of the first completion and
## the co-op tip bubbles. Pure: no nodes, no randomness (D-088); TutorialRun and its parts apply them.
## Offered once per account (AccountSeen SEEN_ID), only alone: in a group game nobody waits for a
## practice run, a player who has not done it gets short tips in the first rooms instead and the
## practice run on the next solo start. All numbers are TESTWERTE.

enum Station { ATTACK, DASH, JUMP, SPECIAL }
## What a hit does to a dummy.
enum Hit { COUNTED, BREAKS, BLOCKED, SHIELD_BREAKS, IGNORED }

const STATIONS: Array[Station] = [Station.ATTACK, Station.DASH, Station.JUMP, Station.SPECIAL]
## Seen flag per account (AccountSeen); set when the run is finished or skipped.
const SEEN_ID: StringName = &"flint_tutorial"
## XP for finishing it the first time (KONZEPT §7.2: +25). TESTWERT
const XP_FIRST_COMPLETION := 25
## Id of that XP credit (AccountProgress hook, counted once per account like a run id).
const XP_CREDIT_ID := "tutorial"
## Name of the AccountProgress method that credits it (integrator hook, see credit_xp).
const XP_HOOK: StringName = &"add_bonus_xp"
## Hits until a straw dummy falls. TESTWERT
const DUMMY_HITS := 3
## Damage tag of a special attack (WeaponController._create_damage).
const SPECIAL_TAG: StringName = &"special"
## Co-op tips in the first rooms (room 1 .. COOP_TIP_ROOMS). TESTWERT
const COOP_TIP_ROOMS := 3
const COOP_TIPS: Array[StringName] = [&"FLINT_TUTORIAL_TIP_1", &"FLINT_TUTORIAL_TIP_2", &"FLINT_TUTORIAL_TIP_3"]
## Light of the hall: logical darkness (0 bright .. 1 only lights), light radius (px) and the drawn
## ambient (LightingProfile: the overlay draws min(logical, ambient)). TESTWERTE
const DARKNESS := 0.3
const VISION_RADIUS := 360.0
const AMBIENT := 0.45
## The hall lies far south of room 1 (rooms grow north, west and east of it, side segments lie at
## SideSegment.WORLD_ORIGIN), so it never meets a room.
const ORIGIN := Vector2(0, 80000)
## Seed of the side-view stretch: a fixed number, never a draw from the dungeon RNG, so the run's
## room stream is the same with and without the practice run.
const JUMP_SEED := 1010
## Black fade between the hall, the side-view stretch and room 1 (s).
const FADE_TIME := 0.3
## Station title per station (on the black before the side view, in the progress strip).
const TITLE_KEYS: Array[StringName] = [
	&"TUTORIAL_STATION_ATTACK", &"TUTORIAL_STATION_DASH", &"TUTORIAL_STATION_JUMP", &"TUTORIAL_STATION_SPECIAL",
]
## Flint's welcome at the start (one sentence as a hint, the first door is open meanwhile): he
## introduces himself only to who has not met him in the village tour (WK9, VillageTour.TOUR_ID).
const WELCOME_INTRO_KEY: StringName = &"FLINT_TUTORIAL_WELCOME_1"
const WELCOME_KNOWN_KEY: StringName = &"FLINT_TUTORIAL_WELCOME_2"
## What Flint says when a station begins (hint ids "flint_tutorial_<name>"): one sentence of at most
## two lines each, said while the player already plays (WK10b: nobody waits for Flint).
const EXPLANATIONS: Array[Array] = [
	[&"FLINT_TUTORIAL_ATTACK_1"],
	[&"FLINT_TUTORIAL_DASH_1"],
	[&"FLINT_TUTORIAL_JUMP_1"],
	[&"FLINT_TUTORIAL_SPECIAL_1"],
]
const NAMES: Array[StringName] = [&"attack", &"dash", &"jump", &"special"]
## ... and when it is done.
const DONE_KEYS: Array[StringName] = [
	&"FLINT_TUTORIAL_ATTACK_DONE", &"FLINT_TUTORIAL_DASH_DONE", &"FLINT_TUTORIAL_JUMP_DONE", &"FLINT_TUTORIAL_SPECIAL_DONE",
]
## Input actions each station practises (the HUD and the signs show their symbols per device).
const ACTIONS: Array[Array] = [
	[&"attack"],
	[&"dash"],
	[&"dash"],
	[&"special_attack"],
]
## In the side view the jump is the dash key (PlayerSideMotion.JUMP_ACTION).
const SIDE_VIEW_STATIONS: Array[Station] = [Station.JUMP]


## Whether this player gets the practice run on this dungeon start: alone and not done or skipped
## before (force: tools and tests). Never in a group game, not even forced.
static func should_offer(seen: bool, group_game: bool, force := false) -> bool:
	if group_game:
		return false
	return force or not seen


## Flint's welcome sentence: without the village tour he introduces himself, after it just "kurz üben".
static func welcome_key(village_tour_seen: bool) -> StringName:
	return WELCOME_KNOWN_KEY if village_tour_seen else WELCOME_INTRO_KEY


## Whether a group game shows this player the co-op tips (not done alone yet).
static func wants_coop_tips(seen: bool, group_game: bool) -> bool:
	return group_game and not seen


## The tip of a room in a group game (&"" after the first rooms).
static func coop_tip_for_room(room_index: int) -> StringName:
	if room_index < 1 or room_index > mini(COOP_TIP_ROOMS, COOP_TIPS.size()):
		return &""
	return COOP_TIPS[room_index - 1]


## Hint id of a station's explanation (FlintExplanation ids start with "flint_").
static func explanation_id(station: Station) -> StringName:
	return StringName("flint_tutorial_" + String(NAMES[station]))


static func title_key(station: Station) -> StringName:
	return TITLE_KEYS[station]


## The station after this one, -1 after the last.
static func next_station(station: int) -> int:
	return station + 1 if station + 1 < STATIONS.size() else -1


## Number shown to players (1..4).
static func station_number(station: Station) -> int:
	return int(station) + 1


## What a hit with these damage tags does to a dummy that took hits_before hits.
## Straw dummy: every hit counts, the DUMMY_HITS-th breaks it. Shield dummy: normal hits bounce off,
## a special breaks the shield and the dummy with it.
static func hit_result(shielded: bool, broken: bool, hits_before: int, tags: Array[StringName]) -> Hit:
	if broken:
		return Hit.IGNORED
	if shielded:
		return Hit.SHIELD_BREAKS if tags.has(SPECIAL_TAG) else Hit.BLOCKED
	return Hit.BREAKS if hits_before + 1 >= DUMMY_HITS else Hit.COUNTED


## Station 2 is done once the feet stand on safe ground east of the abyss (not falling, not dashing
## any more).
static func is_dash_done(feet_x: float, pit_east_x: float, falling: bool, dashing: bool) -> bool:
	return not falling and not dashing and feet_x > pit_east_x


## XP the run credits: the first completion only, a skip gives nothing.
static func xp_for(completed: bool, credited_before: bool) -> int:
	return XP_FIRST_COMPLETION if completed and not credited_before else 0


## Hook for the XP of the first completion: AccountProgress gets
## add_bonus_xp(id: String, amount: int) -> bool (true when it counted, once per id), which the
## integrator adds there (and the platform contract, the server recomputes XP from runs). Returns
## whether the progress took it; without the hook nothing is credited (the seen flag still stops a
## second practice run).
static func credit_xp(progress: Object, amount: int) -> bool:
	if progress == null or amount <= 0 or not progress.has_method(XP_HOOK):
		return false
	return bool(progress.call(XP_HOOK, XP_CREDIT_ID, amount))
