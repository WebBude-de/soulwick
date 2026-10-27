class_name ObstacleRunPlans
extends RefCounted
## The obstacle runs (Hindernislauf, D-216): every section between two rooms is a small jump'n'run
## level of about a minute (the bot needs SideRules.RUN_SECONDS_RANGE), put together from checked
## pieces in way order - an opening (a plan of rounds 1-3, SidePlans), a two-way piece (upper way
## hard with more coins, lower way safe, slopes and ramps, SideTwoWayPlans), a lantern, the hard part
## (a jump trial plan of SV2 with its elements, SideTrialPlans) and its final jump to the door. Four
## runs per biome, one for each jump trial plan; the run's tier is its hard part's (SideRules.tier_for
## picks). Why pieces: every piece keeps its own plan rules and was played by the bot; the seams are
## simple (compose), so a run needs no new ASCII level and the pieces stay editable.
## compose() stitches the rows: the walls between two pieces go, the next piece's start becomes a
## lantern (safe return spot) and sits on the row of the previous door, shorter pieces get rock
## above and their bottom row repeated below (pits stay pits). One golden coin (the hard part's), one
## chest niche (the first piece's), every SideRules.RUN_COIN_KEEP_EVERY-th coin (a run pays about a
## combat room, D-144). check() holds the run rules; the bot makes every run (side_check.gd).

const PIECE_OPENING := 0
const PIECE_TWO_WAY := 1
const PIECE_HARD := 2

## Run id -> its pieces in way order (opening, two-way piece, hard part). TESTWERT (D-216).
const RUNS: Dictionary[StringName, Array] = {
	&"crypt_run_lift": [&"crypt_steps", &"crypt_twoway_halls", &"crypt_lift"],
	&"crypt_run_springs": [&"crypt_gallery", &"crypt_twoway_bones", &"crypt_springs"],
	&"crypt_run_seesaw": [&"crypt_cistern", &"crypt_twoway_vaults", &"crypt_seesaw"],
	&"crypt_run_gauntlet": [&"crypt_ossuary", &"crypt_twoway_halls", &"crypt_gauntlet"],
	&"grotto_run_bridge": [&"grotto_pads", &"grotto_twoway_slide", &"grotto_bridge"],
	&"grotto_run_saws": [&"grotto_pools", &"grotto_twoway_drops", &"grotto_saws"],
	&"grotto_run_climb": [&"grotto_drip", &"grotto_twoway_caves", &"grotto_climb"],
	&"grotto_run_torrent": [&"grotto_sump", &"grotto_twoway_slide", &"grotto_torrent"],
	&"shadow_run_leap": [&"shadow_ledges", &"shadow_twoway_void", &"shadow_leap"],
	&"shadow_run_shaft": [&"shadow_rift", &"shadow_twoway_spires", &"shadow_shaft"],
	&"shadow_run_drift": [&"shadow_stairs", &"shadow_twoway_echo", &"shadow_drift"],
	&"shadow_run_tower": [&"shadow_mire", &"shadow_twoway_void", &"shadow_tower"],
	&"ember_run_bellows": [&"ember_vents", &"ember_twoway_vents", &"ember_bellows"],
	&"ember_run_rails": [&"ember_anvils", &"ember_twoway_rails", &"ember_rails"],
	&"ember_run_crucible": [&"ember_chimney", &"ember_twoway_bellows", &"ember_crucible"],
	&"ember_run_spire": [&"ember_quench", &"ember_twoway_vents", &"ember_spire"],
}

const BIOME_RUNS: Dictionary[StringName, Array] = {
	&"crypt": [&"crypt_run_lift", &"crypt_run_springs", &"crypt_run_seesaw", &"crypt_run_gauntlet"],
	&"slime_grotto": [&"grotto_run_bridge", &"grotto_run_saws", &"grotto_run_climb", &"grotto_run_torrent"],
	&"shadow_realm": [&"shadow_run_leap", &"shadow_run_shaft", &"shadow_run_drift", &"shadow_run_tower"],
	&"ember_forge": [&"ember_run_bellows", &"ember_run_rails", &"ember_run_crucible", &"ember_run_spire"],
}

# --- Run rules (check, TESTWERTE D-216) ---
## Rows of a run (the pieces stacked at their seams) and columns.
const ROW_RANGE := Vector2i(11, 30)
const WIDTH_RANGE := Vector2i(200, 320)
## Coins of a whole run (both ways) after the thinning, and at least this many lanterns.
const COIN_RANGE := Vector2i(9, 18)
const MIN_LANTERNS := 2


## Test aid: every picked run sets its turrets up (SidePlans.force_turrets_for_tests does the same
## for the pieces). Never in the game.
static func forces_turrets() -> bool:
	return SidePlans.force_turrets_for_tests


## Run ids of a biome from min_tier up to max_tier (the crypt's for unknown biomes).
static func ids_for(biome_id: StringName, max_tier := SideRules.MAX_TIER, min_tier := 1) -> Array[StringName]:
	var ids: Array[StringName] = []
	for run_id: StringName in BIOME_RUNS.get(biome_id, BIOME_RUNS[&"crypt"]):
		var tier := tier_of(run_id)
		if tier <= max_tier and tier >= min_tier:
			ids.append(run_id)
	return ids


## Every run id (tests, the check tool).
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(RUNS.keys())
	return ids


static func has_run(run_id: StringName) -> bool:
	return RUNS.has(run_id)


## The pieces of a run in way order.
static func pieces_of(run_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(RUNS.get(run_id, []))
	return ids


## Tier of a run: its hardest piece's (SidePlans.tier_of; the two-way pieces are tier 1).
static func tier_of(run_id: StringName) -> int:
	var tier := 1
	for piece in pieces_of(run_id):
		if not SideTwoWayPlans.has_plan(piece):
			tier = maxi(tier, SidePlans.tier_of(piece))
	return tier


## The biome a run belongs to.
static func biome_of(run_id: StringName) -> StringName:
	for biome in BIOME_RUNS:
		if (BIOME_RUNS[biome] as Array).has(run_id):
			return biome
	return &"crypt"


## One of the runs of the biome at a tier (the runs of the tier and the one before,
## SidePlans.pick_min_tier), plain or mirrored: one draw; a second draw decides whether its turrets
## are set up (SideRules.TURRET_CHANCE). Every run has its chest niche, so the ladder way draws the
## same way (chest_enabled is the caller's).
static func pick(biome_id: StringName, rng: RandomNumberGenerator, max_tier := SideRules.MAX_TIER) -> SideLayout:
	var ids := ids_for(biome_id, max_tier, SidePlans.pick_min_tier(max_tier))
	if ids.is_empty():
		ids = ids_for(biome_id)
	var index := rng.randi_range(0, ids.size() * 2 - 1) if rng != null else 0
	var layout := build(ids[index % ids.size()], index >= ids.size(), biome_id)
	var roll := rng.randf() if rng != null else 1.0
	layout.turrets_enabled = roll < SideRules.TURRET_CHANCE or forces_turrets()
	return layout


## The parsed layout of a run, mirrored on request.
static func build(run_id: StringName, mirrored := false, biome_id: StringName = &"") -> SideLayout:
	var layout := SideLayout.parse(compose(pieces_of(run_id)), run_id)
	layout.pieces = pieces_of(run_id)
	layout.tier = tier_of(run_id)
	if mirrored:
		layout = layout.mirrored()
	layout.biome_id = biome_id if biome_id != &"" else biome_of(run_id)
	return layout


static func _piece_rows(piece: StringName) -> PackedStringArray:
	if SideTwoWayPlans.has_plan(piece):
		return SideTwoWayPlans.get_rows(piece)
	return SidePlans.get_rows(piece)


# --- Composing ---

## The rows of a run made of the pieces (way order, all running to the right). See the head comment.
static func compose(piece_ids: Array[StringName]) -> PackedStringArray:
	var parts: Array[PackedStringArray] = []
	var tops: Array[int] = []
	var top := 0
	var previous_door_row := -1
	for i in piece_ids.size():
		var original := _piece_rows(piece_ids[i])
		if i > 0:
			top = previous_door_row - _find(original, SideLayout.START).y
		tops.append(top)
		parts.append(_prepare(original, i, piece_ids.size()))
		previous_door_row = _find(original, SideLayout.DOOR).y + top
	var lowest_top := tops.min() as int
	var height := 0
	for i in parts.size():
		tops[i] -= lowest_top
		height = maxi(height, tops[i] + parts[i].size())
	var composed := PackedStringArray()
	for row in height:
		var line := ""
		for i in parts.size():
			line += _row_of(parts[i], row - tops[i])
		composed.append(line)
	return _thin_coins(composed)


## A piece made ready for its place: the wall towards a neighbour goes, the start of a later piece
## becomes a lantern, the door of an earlier one air; one golden coin (the last piece's) and one
## chest niche (the first piece's).
static func _prepare(rows: PackedStringArray, index: int, count: int) -> PackedStringArray:
	var prepared := PackedStringArray()
	for line in rows:
		if index > 0:
			line = line.substr(1).replace(SideLayout.START, SideLayout.LANTERN)
			line = line.replace(SideLayout.CHEST, SideLayout.ROCK)
		if index < count - 1:
			line = line.substr(0, line.length() - 1).replace(SideLayout.DOOR, SideLayout.AIR)
			line = line.replace(SideLayout.GOLDEN_COIN, SideLayout.COIN)
		prepared.append(line)
	return prepared


## Row offset row of a piece's rows: rock above it, its bottom row repeated (rock and pits only) below.
static func _row_of(rows: PackedStringArray, row: int) -> String:
	var width := rows[0].length()
	if row < 0:
		return SideLayout.ROCK.repeat(width)
	if row < rows.size():
		return rows[row]
	var bottom := rows[rows.size() - 1]
	var line := ""
	for column in width:
		line += SideLayout.ROCK if bottom[column] == SideLayout.ROCK else SideLayout.AIR
	return line


## Keeps every SideRules.RUN_COIN_KEEP_EVERY-th coin in way order (columns left to right, rows top
## down), the others become air.
static func _thin_coins(rows: PackedStringArray) -> PackedStringArray:
	var thinned := PackedStringArray(rows)
	var count := 0
	for column in rows[0].length():
		for row in rows.size():
			if rows[row][column] != SideLayout.COIN:
				continue
			if count % SideRules.RUN_COIN_KEEP_EVERY != 0:
				var line := thinned[row]
				thinned[row] = line.substr(0, column) + SideLayout.AIR + line.substr(column + 1)
			count += 1
	return thinned


static func _find(rows: PackedStringArray, character: String) -> Vector2i:
	for row in rows.size():
		var column := rows[row].find(character)
		if column >= 0:
			return Vector2i(column, row)
	return Vector2i(-1, -1)


# --- Run rules ---

## Errors of an obstacle run against the rules (empty = fine): size, start and door, reachability
## without dead ends, one golden coin that needs the double jump, the chest niche, coins in reach and
## their number, enemies standing, lanterns, the elements' own rules and no blind jump. The tier's
## element count is the pieces' rule (SideLayout.check of each), not the run's.
static func check(layout: SideLayout) -> PackedStringArray:
	var errors := PackedStringArray()
	var id := layout.plan_id
	if layout.size.y < ROW_RANGE.x or layout.size.y > ROW_RANGE.y:
		errors.append("%s: %d rows instead of %d-%d" % [id, layout.size.y, ROW_RANGE.x, ROW_RANGE.y])
	if layout.size.x < WIDTH_RANGE.x or layout.size.x > WIDTH_RANGE.y:
		errors.append("%s: width %d instead of %d-%d" % [id, layout.size.x, WIDTH_RANGE.x, WIDTH_RANGE.y])
	for line in layout.rows:
		if line.length() != layout.size.x:
			errors.append("%s: ragged row" % id)
			return errors
	if layout.start.x < 0 or layout.door.x < 0:
		errors.append("%s: start or door missing" % id)
		return errors
	if not layout.is_standable(layout.start) or not layout.is_standable(layout.door):
		errors.append("%s: start or door floats" % id)
	var reach := layout.reachable_from(layout.start, true)
	if not reach.has(layout.door):
		errors.append("%s: door not reachable" % id)
	var to_door := cells_reaching(layout, layout.door)
	for cell in reach:
		if not to_door.has(cell):
			errors.append("%s: dead end at %s" % [id, cell])
			break
	if layout.coins.size() < COIN_RANGE.x or layout.coins.size() > COIN_RANGE.y:
		errors.append("%s: %d coins (%d-%d)" % [id, layout.coins.size(), COIN_RANGE.x, COIN_RANGE.y])
	for coin in layout.coins:
		if not layout.item_in_reach(coin, reach, SideLayout.ITEM_REACH_ROWS_DOUBLE):
			errors.append("%s: coin at %s out of reach" % [id, coin])
	if layout.golden_coin.x < 0:
		errors.append("%s: no golden coin" % id)
	elif not layout.item_in_reach(layout.golden_coin, reach, SideLayout.ITEM_REACH_ROWS_DOUBLE):
		errors.append("%s: golden coin out of reach" % id)
	elif layout.item_in_reach(layout.golden_coin, reach, SideLayout.ITEM_REACH_ROWS):
		errors.append("%s: golden coin needs no double jump" % id)
	if layout.lanterns.size() < MIN_LANTERNS:
		errors.append("%s: %d lanterns (at least %d)" % [id, layout.lanterns.size(), MIN_LANTERNS])
	for enemy in layout.enemy_cells():
		var chain: Array[SideEnemyChain.Placement] = [SideEnemyChain.Placement.new(enemy.z as SideEnemy.Kind)]
		for problem in SideEnemyChain.fits(layout, chain, Vector2i(enemy.x, enemy.y)):
			errors.append("%s: %s" % [id, problem])
	for problem in layout.run_part_errors():
		errors.append(problem)
	return errors


## Every stand cell from which goal can be reached (one walk over the reversed jump graph; a dead-end
## check for long layouts).
static func cells_reaching(layout: SideLayout, goal: Vector2i) -> Dictionary[Vector2i, bool]:
	var reverse: Dictionary[Vector2i, Array] = {}
	for cell in layout.reachable_from(layout.start, true):
		for next in layout.neighbours(cell, true):
			if not reverse.has(next):
				reverse[next] = []
			reverse[next].append(cell)
	var seen: Dictionary[Vector2i, bool] = {goal: true}
	var queue: Array[Vector2i] = [goal]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for previous: Vector2i in reverse.get(current, []):
			if not seen.has(previous):
				seen[previous] = true
				queue.append(previous)
	return seen
