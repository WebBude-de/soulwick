class_name AccountTalents
extends RefCounted
## The solo character's talent distribution (KE1 + KE6, KONZEPT §9): one per account, stored in
## AccountProgress under STATE_KEY next to the seen flags. Read back sanitized against the points of
## the account level, so an old or edited file never gives more than the level allows. Solo runs put
## it on the player (DungeonManager), quick games send it in the lobby profile and the host puts it
## on every player (NetPlayers); guild runs will use the guild character instead (MP8b).
## AccountProgress.spent_points_source points here, so the free points of the account card count it.

const STATE_KEY := "talents"


## The stored distribution of progress (default: this machine's account), valid for its level.
static func load_state(progress: AccountProgress = null) -> TalentState:
	var account := progress if progress != null else AccountProgress.current()
	var points := TalentState.points_for_level(account.get_level())
	return TalentState.from_dict(account.get_state(STATE_KEY)).sanitized(points)


## Stores state for progress (default: this machine's account) and writes the file at once.
static func save_state(state: TalentState, progress: AccountProgress = null) -> Error:
	var account := progress if progress != null else AccountProgress.current()
	return account.set_state(STATE_KEY, state.to_dict() if state != null else {})


## Points spent in the stored distribution of this machine's account (AccountProgress hook).
static func spent_points() -> int:
	return load_state().get_spent_points()
