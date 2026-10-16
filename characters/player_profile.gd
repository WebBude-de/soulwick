class_name PlayerProfile
extends RefCounted
## The player's profile (D-152): one name and one look (PlayerLook) for the whole account, the same
## in every world (save slot). Save slots are only worlds now and no longer name the player.
## Stored on this machine in profile.cfg next to settings.cfg (user://profile.cfg; game instance N
## of several windows: profile_<n>.cfg, like online_<n>.cfg). Runs started with a script (-s: tests
## and tools) on the real user folder use script_profile*.cfg, so they never touch the real profile
## (AGENTS.md rule 4); SaveManager.set_storage_root() moves the file along with the settings.
## Not an autoload (D-044): PlayerProfile.current() loads it on first use.
##
## Every change emits SaveManager.profile_changed (the player sprite and menus follow it).
## Online (OnlineSession): name_dirty and look_dirty mark what the server does not know yet; they
## go out with the next login or PATCH /me and are cleared then. The server's profile wins at login
## while nothing is dirty here (see OnlineSession.sync_profile).
## First start: is_set_up is false until the player confirmed name and figure once (main menu
## "Wie heißt du?") or the server's profile was taken over.

const FILE_NAME := "profile.cfg"
const INSTANCE_FILE_NAME := "profile_%d.cfg"
const SCRIPT_PREFIX := "script_"
const SECTION := "profile"
const VERSION := 1
## TESTWERT: longest name here (contracts PlayerName allows 24; name tag and lobby slot fit 16).
const NAME_MAX_LENGTH := 16
## contracts PlayerName: at least 2 characters.
const NAME_MIN_LENGTH := 2

## Tests may point the profile at a file of their own ("" = default_path()).
static var path_override := ""
static var _current: PlayerProfile = null
static var _instance := 0

## File of this profile.
var path := ""
## "" until the player chose a name (get_display_name() shows a default then).
var player_name := ""
var look: Dictionary = PlayerLook.default_look()
var is_set_up := false
## Changed here, not yet on the server (PATCH /me).
var name_dirty := false
var look_dirty := false
## Account (PlayerSelf.id) the profile was last in sync with, "" = never online.
var synced_player_id := ""
## Unix seconds until the server takes a new name again (429 name_change_limited), 0 = no limit known.
var name_locked_until := 0


## The profile of this player, loaded on first use (and again when the storage folder changed).
static func current() -> PlayerProfile:
	var wanted := default_path()
	if _current == null or _current.path != wanted:
		_current = load_from(wanted)
		_notify()
	return _current


## Forgets the loaded profile (tests): the next current() reads the file again.
static func reset() -> void:
	_current = null


## profile.cfg next to SaveManager.settings_path (profile_<n>.cfg for game instance n > 1).
static func default_path() -> String:
	if not path_override.is_empty():
		return path_override
	var folder := SaveManager.settings_path.get_base_dir()
	var file := FILE_NAME if get_instance() <= 1 else INSTANCE_FILE_NAME % get_instance()
	if folder == SaveManager.DEFAULT_SETTINGS_PATH.get_base_dir() and is_script_run():
		file = SCRIPT_PREFIX + file
	return folder.path_join(file)


## Game instance of the command line (instance=N, like OnlineConfig), 1 normally.
static func get_instance() -> int:
	if _instance <= 0:
		var args := OnlineConfig.parse_args(OS.get_cmdline_user_args())
		_instance = clampi(int(str(args.get("instance", args.get("player", "1")))), 1, 99)
	return _instance


## Started with -s (GUT, tools) instead of as the game.
static func is_script_run() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")


static func load_from(file_path: String) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.path = file_path
	profile._read()
	return profile


func _read() -> void:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return
	var stored_name: Variant = config.get_value(SECTION, "name", "")
	player_name = sanitize_name(str(stored_name)) if typeof(stored_name) == TYPE_STRING else ""
	look = PlayerLook.normalize({
		"character": config.get_value(SECTION, "character", PlayerLook.DEFAULT_CHARACTER),
		"colors": {
			"hair": config.get_value(SECTION, "hair", null),
			"outfit": config.get_value(SECTION, "outfit", null),
			"skin": config.get_value(SECTION, "skin", null),
			"accent": config.get_value(SECTION, "accent", null),
		},
	})
	is_set_up = config.get_value(SECTION, "set_up", false) == true
	name_dirty = config.get_value("sync", "name_dirty", false) == true
	look_dirty = config.get_value("sync", "look_dirty", false) == true
	synced_player_id = str(config.get_value("sync", "player_id", ""))
	var locked: Variant = config.get_value("sync", "name_locked_until", 0)
	name_locked_until = maxi(0, int(locked)) if typeof(locked) == TYPE_INT else 0


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	config.set_value(SECTION, "name", player_name)
	config.set_value(SECTION, "character", String(look.character))
	for slot in PlayerLook.SLOTS:
		config.set_value(SECTION, String(slot), int(look.colors[String(slot)]))
	config.set_value(SECTION, "set_up", is_set_up)
	config.set_value("sync", "name_dirty", name_dirty)
	config.set_value("sync", "look_dirty", look_dirty)
	config.set_value("sync", "player_id", synced_player_id)
	config.set_value("sync", "name_locked_until", name_locked_until)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := config.save(path)
	if err != OK:
		push_error("PlayerProfile: could not write %s (%s)." % [path, error_string(err)])
	return err


## True while the player has not chosen name and figure yet (first start).
func needs_setup() -> bool:
	return not is_set_up


## The name to show: the chosen one, else "Spieler" / "Player".
func get_display_name() -> String:
	return player_name if not player_name.is_empty() else Loc.t(&"PROFILE_DEFAULT_NAME")


## Sets the name (memory; save() writes). false if it is too short after cleaning (then nothing
## changes). Marks it for the server when it really changed.
func set_player_name(text: String) -> bool:
	var clean := sanitize_name(text)
	if clean.length() < NAME_MIN_LENGTH:
		return false
	if clean != player_name:
		player_name = clean
		name_dirty = true
		_notify()
	return true


## Sets the look (memory; save() writes) and marks it for the server when it changed.
func set_look(value: Dictionary) -> void:
	var normalized := PlayerLook.normalize(value)
	if normalized == look:
		return
	look = normalized
	look_dirty = true
	_notify()


func set_color(slot: StringName, index: int) -> void:
	set_look(PlayerLook.with_color(look, slot, index))


## Name and look of the first start (or the editor), saved at once. false if the name is too short.
func complete_setup(text: String, value: Dictionary) -> bool:
	if not set_player_name(text):
		return false
	set_look(value)
	is_set_up = true
	save()
	_notify()
	return true


## The server's profile (PlayerSelf) wins (OnlineSession.sync_profile): takes its name and, if it
## has one, its look; nothing is dirty afterwards. Saves. Returns true if something changed here.
func take_server_profile(self_data: Dictionary) -> bool:
	var changed := false
	var server_name := str(self_data.get("name", "")).strip_edges()
	if server_name.length() >= NAME_MIN_LENGTH and server_name != player_name:
		player_name = server_name.left(OnlineSession.NAME_MAX)
		changed = true
	var appearance: Variant = self_data.get("appearance", null)
	if appearance is Dictionary:
		var server_look := PlayerLook.normalize(appearance)
		if server_look != look:
			look = server_look
			changed = true
	name_dirty = false
	look_dirty = false
	is_set_up = true
	synced_player_id = str(self_data.get("id", synced_player_id))
	save()
	if changed:
		_notify()
	return changed


## After a successful PATCH /me or login: what was sent is on the server now.
func mark_synced(player_id: String, name_sent: bool, look_sent: bool) -> void:
	if name_sent:
		name_dirty = false
	if look_sent:
		look_dirty = false
	if not player_id.is_empty():
		synced_player_id = player_id
	save()


## Seconds until the server takes a new name again (0 = now).
func get_name_wait_seconds(now := -1) -> int:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	return maxi(0, name_locked_until - now)


## Keeps letters, digits, space, _ . - (contracts PlayerName), single spaces, at most NAME_MAX_LENGTH.
static func sanitize_name(text: String) -> String:
	var regex := RegEx.create_from_string("[^\\p{L}\\p{N} _.-]")
	var cleaned := regex.sub(text, "", true).strip_edges()
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	return cleaned.left(NAME_MAX_LENGTH).strip_edges()


static func is_valid_name(text: String) -> bool:
	return sanitize_name(text).length() >= NAME_MIN_LENGTH


## Name and look of the save slots of older builds (D-152 migration, once): the slot of
## "Weiterspielen" first, then the others. {} if no slot had a name. Used as the suggestion of the
## first start; nothing is changed in the slots.
static func legacy_suggestion() -> Dictionary:
	var order: Array[int] = []
	var first := SaveManager.get_continue_slot()
	if first > 0:
		order.append(first)
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		if not order.has(slot):
			order.append(slot)
	for slot in order:
		if not SaveManager.has_slot(slot):
			continue
		var legacy := SaveSlots.read_legacy_profile(SaveManager.slot_path(slot))
		var legacy_name := sanitize_name(str(legacy.get("name", "")))
		if legacy_name.length() >= NAME_MIN_LENGTH:
			return {"name": legacy_name, "look": PlayerLook.from_legacy(legacy.get("character", ""), legacy.get("color", Color(0, 0, 0, 0)))}
	return {}


static func _notify() -> void:
	SaveManager.profile_changed.emit()
