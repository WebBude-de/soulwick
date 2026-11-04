class_name AccountPanel
extends Modal
## The account panel (KF6, D-188, D-224, KONZEPT §10): opened from the options ("Konto", main menu
## and pause menu). One dialog with views:
## - Übersicht: without an account "Konto sichern" / "Anmelden"; a guest account (only devices)
##   asks to secure it; a secured one lists its logins per provider with "Trennen", "Anmeldung
##   hinzufügen", username and password, "Auf diesem Gerät angemeldet bleiben" when the device is not
##   on the account; the cloud line ("Jetzt abgleichen", "Welten & Sicherungen") and "Konto löschen".
##   A signed-out account (its session ended, LOGIN_ACCOUNT) offers "Anmelden" or "Als Gast spielen".
## - Wege: in the browser (Google, Apple, Discord, Steam, e-mail; only what GET /public/config
##   names) or with username and password.
## - Browser: the user code "ABC-DEF" to type on the website, waiting / confirm in the browser /
##   errors, "Seite öffnen", "Link kopieren"; neither the request code nor the browser secret is shown.
## - Benutzername & Passwort: sign in, or add / change them on the own account.
## - Zusammenführen: this device's guest account has progress too (D-122): both accounts, merge or
##   "Nicht jetzt".
## - Cloud-Welten: active worlds with their backups, the archive with "Zurückholen"; a backup is
##   restored after a question; with three active worlds the player picks which one goes to the
##   archive. Not in a run (D-222).
## - Konto löschen: the one-time deletion code for the website and "Jetzt endgültig löschen" after a
##   question.
## The logic is AccountService (and WebLoginFlow); the panel never awaits a call, it starts it with
## service.run() and moves on in action_finished, so closing it mid-call is safe.
## Sits on its own CanvasLayer as the last child of the root (like PadKeyboard), so it reads keys
## before the options under it, and swallows every key it does not use. It never pauses anything
## itself (the pause menu under it may; online the game goes on, D-088).
## Keyboard, gamepad and touch: Modal's focus frame over the buttons (arrows / D-pad, Enter / A),
## Esc / B one step back (on the overview: close). Text fields sit inside a button: Enter or a click
## types on the keyboard, A with a gamepad opens the on-screen keyboard (PadKeyboard, D-192), Y too.
## Texts are translation keys (en + de, D-111), rebuilt on a language change.

enum View { MAIN, METHODS, WEB, PASSWORD, MERGE, WORLDS, BACKUPS, LIMIT, DELETE, CONFIRM }
## Why the player chose a way to sign in: secure the (guest) account, sign in to an existing one,
## add a login to a secured account, change username and password.
enum Purpose { SECURE, SIGN_IN, ADD, CHANGE }

const PadKeyboard := preload("res://ui/widgets/pad_keyboard.gd")
## Below the bug report overlay (120) and the on-screen keyboard (126).
const LAYER := 110
const WIDTH := 300.0
## Scroll height of the world and backup lists (mockup pixels).
const LIST_HEIGHT := 112.0
const SMALL_BUTTON_WIDTH := 58.0
## Rows a list shows without a scroll bar.
const SHORT_LIST := 3
## Width of the muted second line of a row (mockup pixels): leaves room for its button.
const DETAIL_WIDTH := 170.0
const FIELD_WIDTH := 170.0
const FIELD_HEIGHT := 14.0
const PROVIDER_KEYS := {
	"device": &"ACCOUNT_PROVIDER_DEVICE", "password": &"ACCOUNT_PROVIDER_PASSWORD", "email": &"ACCOUNT_PROVIDER_EMAIL",
	"google": &"ACCOUNT_PROVIDER_GOOGLE", "apple": &"ACCOUNT_PROVIDER_APPLE", "discord": &"ACCOUNT_PROVIDER_DISCORD",
	"steam": &"ACCOUNT_PROVIDER_STEAM", "google_play": &"ACCOUNT_PROVIDER_GOOGLE_PLAY", "game_center": &"ACCOUNT_PROVIDER_GAME_CENTER",
}
const REASON_KEYS := {
	"merge": &"ACCOUNT_BACKUP_MERGE", "restore": &"ACCOUNT_BACKUP_RESTORE", "account_merge": &"ACCOUNT_BACKUP_ACCOUNT_MERGE",
}
## Error code -> text (the rest: ACCOUNT_ERR_GENERIC with the code).
const ERROR_KEYS := {
	"unreachable": &"ACCOUNT_ERR_OFFLINE", "timeout": &"ACCOUNT_ERR_OFFLINE",
	"invalid_credentials": &"ACCOUNT_ERR_CREDENTIALS", "username_taken": &"ACCOUNT_ERR_USERNAME_TAKEN",
	"rate_limited": &"ACCOUNT_ERR_RATE_LIMITED", "banned": &"ACCOUNT_ERR_BANNED",
	"merge_blocked_banned": &"ACCOUNT_ERR_MERGE_BANNED", "account_gone": &"ACCOUNT_ERR_ACCOUNT_GONE",
	"provider_error": &"ACCOUNT_ERR_PROVIDER", "cancelled": &"ACCOUNT_ERR_CANCELLED",
	"email_unavailable": &"ACCOUNT_ERR_EMAIL", "last_identity": &"ACCOUNT_ERR_LAST_LOGIN",
	"username_invalid": &"ACCOUNT_ERR_USERNAME", "password_too_short": &"ACCOUNT_ERR_PASSWORD",
	"in_run": &"ACCOUNT_ERR_IN_RUN", "no_room": &"ACCOUNT_ERR_NO_ROOM", "busy": &"ACCOUNT_ERR_BUSY",
	"newer_version": &"ACCOUNT_ERR_NEWER", "signed_out": &"ACCOUNT_SIGNED_OUT_TEXT",
	"update_required": &"ACCOUNT_ERR_UPDATE", "validation_error": &"ACCOUNT_ERR_VALIDATION",
	"web_login_not_found": &"ACCOUNT_WEB_EXPIRED", "expired": &"ACCOUNT_WEB_EXPIRED",
	"provider_not_configured": &"ACCOUNT_ERR_NOT_HERE", "unauthorized": &"ACCOUNT_SIGNED_OUT_TEXT",
	"already_running": &"ACCOUNT_ERR_SYNC_RUNNING", "too_many_attempts": &"ACCOUNT_ERR_TOO_MANY",
}

var service: AccountService = null
var view := View.MAIN
var purpose := Purpose.SIGN_IN
## Line under the view: the outcome of the last action ("" = none).
var notice := ""
var notice_is_error := false

var _layer: CanvasLayer = null
var _eyebrow: Label = null
var _title: Label = null
var _body: VBoxContainer = null
var _username_edit: LineEdit = null
var _password_edit: LineEdit = null
## World of the backup view (WorldMeta).
var _world: Dictionary = {}
## Question view: {text, yes, action (Callable), back (View), danger}.
var _confirm: Dictionary = {}
var _rebuild_queued := false
## Name of the button the gamepad frame should stay on across rebuilds (only taken from a view that
## was not busy: busy views disable their buttons and move the frame away).
var _focus_name := ""
## What the password form holds while it is shown ({username, password}); cleared when it is left.
var _form: Dictionary = {}
## Name of the text field that had the keyboard before a rebuild (&"" = none).
var _focus_edit: StringName = &""
var _built_busy := false


## Opens the panel over everything (opener: the options view; the panel closes with it). session:
## the game's OnlineSession (found or created without logging in when null).
static func open_for(opener: Node, session: OnlineSession = null) -> AccountPanel:
	if opener == null or not opener.is_inside_tree():
		return null
	var online := session if session != null else OnlineSession.of(opener)
	var panel := AccountPanel.new(online)
	var layer := CanvasLayer.new()
	layer.name = "AccountPanelLayer"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	opener.get_tree().root.add_child(layer)
	panel._layer = layer
	panel.finished.connect(func(_result: Variant) -> void:
		if is_instance_valid(layer):
			layer.queue_free())
	opener.tree_exiting.connect(panel.finish.bind(null), CONNECT_ONE_SHOT)
	panel.show_on(layer)
	panel.refresh()
	return panel


## The panel open right now (null if none), for hosts and tests.
static func get_open() -> AccountPanel:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	for child in tree.root.get_children():
		if child is CanvasLayer and child.name == "AccountPanelLayer":
			for node in child.get_children():
				if node is AccountPanel and not node.is_queued_for_deletion():
					return node
	return null


func _init(session: OnlineSession = null) -> void:
	pause_reason = &"account"
	pauses = false
	_build(&"normal")
	name = "AccountPanel"
	frame.add_theme_stylebox_override("panel", UiKit.padded_style(&"normal", UiDialog.PADDING.x, UiDialog.PADDING.y))
	set_width(WIDTH)
	accent = UiKit.COLOR_GOLD
	cancel_allowed = true
	input_handler = _handle_input
	service = AccountService.new(session)
	service.changed.connect(_queue_rebuild)
	service.web.changed.connect(_queue_rebuild)
	service.action_finished.connect(_on_action_finished)
	finished.connect(func(_result: Variant) -> void: service.web.cancel())
	_eyebrow = UiKit.eyebrow(Loc.t(&"ACCOUNT_EYEBROW"), UiKit.COLOR_MUTED)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_eyebrow)
	_title = UiKit.title("", UiKit.SIZE_TITLE, UiKit.COLOR_GOLD)
	_title.name = "Title"
	content.add_child(_title)
	content.add_child(UiKit.accent_line(UiKit.COLOR_GOLD))
	_body = UiKit.vbox(int(UiKit.px(4)))
	_body.name = "Body"
	content.add_child(_body)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _body != null:
		_queue_rebuild()


## Loads the account's state (no login of its own, D-224).
func refresh() -> void:
	service.run(&"refresh", service.refresh)


## Shows a view (keeps the outcome line).
func show_view(new_view: View) -> void:
	view = new_view
	_queue_rebuild()


## Every key goes to this panel while it is open (the options under it must not move).
func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if not is_visible_in_tree() or get_viewport() == null or get_viewport().is_input_handled():
		return
	if is_swallowed(event):
		get_viewport().set_input_as_handled()


## Keys, gamepad and actions never reach the menus under the panel (mouse and touch hit its dim).
static func is_swallowed(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction


func _handle_input(event: InputEvent) -> bool:
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focused is LineEdit and frame.is_ancestor_of(focused):
		if event.is_action_pressed(&"ui_cancel"):
			focused.release_focus()
			return true
		return false
	if PadKeyboard.is_open_event(event):
		var edit := _field_of(get_focused_button())
		if edit != null:
			PadKeyboard.open_for(edit)
			return true
	if event.is_action_pressed(&"ui_cancel") and view != View.MAIN:
		UiSound.back(self)
		go_back()
		return true
	return false


## One step back: the web login stops, questions go to where they came from, the rest to the overview.
func go_back() -> void:
	notice = ""
	match view:
		View.WEB:
			service.web.cancel()
			view = View.METHODS if purpose != Purpose.CHANGE else View.MAIN
		View.BACKUPS:
			view = View.WORLDS
		View.LIMIT:
			service.limit_offer = {}
			view = View.WORLDS
		View.CONFIRM:
			view = _confirm.get("back", View.MAIN)
		View.MERGE:
			service.decline_merge()
			view = View.MAIN
		View.PASSWORD:
			view = View.METHODS if purpose in [Purpose.SECURE, Purpose.SIGN_IN] and _method_count() > 1 else View.MAIN
		_:
			view = View.MAIN
	_queue_rebuild()


# --- Actions ---

func choose(new_purpose: Purpose) -> void:
	purpose = new_purpose
	notice = ""
	if new_purpose == Purpose.CHANGE:
		show_view(View.PASSWORD)
	elif _method_count() == 1:
		# Only one way in this environment: straight to it.
		if service.has_web_login():
			start_web()
		else:
			show_view(View.PASSWORD)
	else:
		show_view(View.METHODS)


func start_web() -> void:
	notice = ""
	view = View.WEB
	_queue_rebuild()
	service.run(&"web", service.web_login.bind(purpose != Purpose.SIGN_IN, get_tree()))


func submit_password() -> void:
	var username := _username_edit.text if _username_edit != null else str(_form.get("username", ""))
	var password := _password_edit.text if _password_edit != null else str(_form.get("password", ""))
	_form = {"username": username, "password": password}
	notice = ""
	if purpose == Purpose.SIGN_IN:
		service.run(&"password_sign_in", service.sign_in_with_password.bind(username, password))
	else:
		service.run(&"password_save", service.save_password_login.bind(username, password))


func keep_device(confirm := false) -> void:
	service.run(&"keep_device", service.keep_device.bind(confirm))


func sync_now() -> void:
	notice = ""
	service.run(&"sync", func() -> ApiResult:
		var report: Dictionary = await service.sync_worlds()
		await service.load_worlds()
		if report.is_empty():
			return ApiResult.failure(AccountService.ERROR_IN_RUN if RunManager.is_run_active() else "already_running")
		return ApiResult.success(200, report) if report.get("ok", false) else ApiResult.failure(str(report.get("error", "")) if not str(report.get("error", "")).is_empty() else "unreachable"))


func open_worlds() -> void:
	notice = ""
	show_view(View.WORLDS)
	service.run(&"worlds", service.load_worlds)


func open_backups(world: Dictionary) -> void:
	_world = world
	notice = ""
	show_view(View.BACKUPS)
	service.run(&"backups", service.load_backups.bind(str(world.get("worldId", ""))))


func ask_restore(backup: Dictionary) -> void:
	var world_id := str(_world.get("worldId", ""))
	var backup_id := str(backup.get("id", ""))
	_ask(Loc.t(&"ACCOUNT_RESTORE_QUESTION", [world_name(_world.get("summary", {})), date_text(backup.get("createdAt", ""))]),
			Loc.t(&"ACCOUNT_RESTORE_YES"), func() -> void:
				view = View.BACKUPS
				_queue_rebuild()
				service.run(&"restore", service.restore_backup.bind(world_id, backup_id)),
			View.BACKUPS)


func unarchive(world: Dictionary) -> void:
	notice = ""
	service.run(&"restore", service.unarchive_world.bind(str(world.get("worldId", ""))))


## World limit: the picked active world goes to the archive instead.
func archive_instead(world: Dictionary) -> void:
	var offer := service.limit_offer
	var archive_id := str(world.get("worldId", ""))
	view = View.WORLDS
	_queue_rebuild()
	if str(offer.get("backup_id", "")).is_empty():
		service.run(&"restore", service.unarchive_world.bind(str(offer.get("world_id", "")), archive_id))
	else:
		service.run(&"restore", service.restore_backup.bind(str(offer.get("world_id", "")), str(offer.get("backup_id", "")), archive_id))


func ask_remove(provider: String) -> void:
	var key: StringName = &"ACCOUNT_REMOVE_DEVICE_QUESTION" if provider == AccountService.PROVIDER_DEVICE else &"ACCOUNT_REMOVE_QUESTION"
	_ask(Loc.t(key, [provider_name(provider)]), Loc.t(&"ACCOUNT_REMOVE_YES"), func() -> void:
		view = View.MAIN
		_queue_rebuild()
		service.run(&"remove", service.remove_login.bind(provider)), View.MAIN, true)


func ask_delete() -> void:
	_ask(Loc.t(&"ACCOUNT_DELETE_QUESTION"), Loc.t(&"ACCOUNT_DELETE_YES"), func() -> void:
		view = View.DELETE
		_queue_rebuild()
		service.run(&"delete", service.delete_account), View.DELETE, true)


func _ask(text: String, yes: String, action: Callable, back: View, danger := false) -> void:
	_confirm = {"text": text, "yes": yes, "action": action, "back": back, "danger": danger}
	show_view(View.CONFIRM)


func _on_action_finished(action: StringName, result: ApiResult) -> void:
	if result == null:
		_queue_rebuild()
		return
	match action:
		&"web":
			if result.error == AccountService.WEB_CANCELLED:
				return
			if result.ok:
				_finish_sign_in(Loc.t(&"ACCOUNT_DONE_LINKED") if purpose != Purpose.SIGN_IN else Loc.t(&"ACCOUNT_DONE_SIGNED_IN", [service.session.get_player_name()]))
				return
			# The web view shows failed / expired itself; other errors (start) as a line.
			if service.web.status != WebLoginFlow.Status.FAILED and service.web.status != WebLoginFlow.Status.EXPIRED:
				_set_notice(error_text(result.error), true)
		&"password_sign_in":
			if result.ok:
				_finish_sign_in(Loc.t(&"ACCOUNT_DONE_SIGNED_IN", [service.session.get_player_name()]))
			else:
				_set_notice(error_text(result.error), true)
		&"password_save":
			if result.ok:
				_finish_sign_in(Loc.t(&"ACCOUNT_DONE_PASSWORD"))
			else:
				_set_notice(error_text(result.error), true)
		&"keep_device":
			if result.ok:
				_set_notice(Loc.t(&"ACCOUNT_DONE_DEVICE"), false, View.MAIN)
				service.run(&"after", service.after_sign_in)
			elif not service.merge_offer.is_empty():
				show_view(View.MERGE)
			else:
				_set_notice(error_text(result.error), true, View.MAIN)
		&"remove":
			_set_notice(Loc.t(&"ACCOUNT_DONE_REMOVED") if result.ok else error_text(result.error), not result.ok)
		&"delete":
			if result.ok:
				_set_notice(Loc.t(&"ACCOUNT_DONE_DELETED"), false, View.MAIN)
			else:
				_set_notice(error_text(result.error), true)
		&"deletion_code":
			if not result.ok:
				_set_notice(error_text(result.error), true)
		&"restore":
			if result.ok:
				var applied := str(result.get_field("applied", ""))
				var done := applied == CloudSave.DOWNLOADED
				_set_notice(Loc.t(&"ACCOUNT_DONE_RESTORED") if done else error_text(applied), not done, View.WORLDS)
			elif not service.limit_offer.is_empty():
				show_view(View.LIMIT)
			else:
				_set_notice(error_text(result.error), true)
		&"sync":
			if result.ok:
				_set_notice(CloudSave.report_text(service.sync_report), false)
			else:
				_set_notice(error_text(result.error), true)
		_:
			_queue_rebuild()


## A sign-in or securing went through: the merge question if the device's guest account has
## progress, else the overview with the outcome.
func _finish_sign_in(text: String) -> void:
	if not service.merge_offer.is_empty():
		notice = text
		notice_is_error = false
		show_view(View.MERGE)
		return
	_set_notice(text, false, View.MAIN)


func _set_notice(text: String, is_error: bool, new_view := -1) -> void:
	notice = text
	notice_is_error = is_error
	if new_view >= 0:
		view = new_view as View
	_queue_rebuild()


# --- Texts ---

## A sentence for an error code (API or local).
static func error_text(code: String) -> String:
	if ERROR_KEYS.has(code):
		return Loc.t(ERROR_KEYS[code])
	return Loc.t(&"ACCOUNT_ERR_GENERIC", [code])


static func provider_name(provider: String) -> String:
	return Loc.t(PROVIDER_KEYS[provider]) if PROVIDER_KEYS.has(provider) else provider


## "Welt 2" for an empty name.
static func world_name(summary: Variant) -> String:
	var text := str(summary.get("name", "")).strip_edges() if summary is Dictionary else ""
	return text if not text.is_empty() else Loc.t(&"ACCOUNT_WORLD_UNNAMED")


## "Raum 12 · Schmiede 4/20 · 3 h".
static func world_line(summary: Variant) -> String:
	if not (summary is Dictionary):
		return ""
	var hours := int(summary.get("playTimeSeconds", 0)) / 3600
	var minutes := (int(summary.get("playTimeSeconds", 0)) % 3600) / 60
	var time := Loc.t(&"ACCOUNT_PLAYTIME_HOURS", [hours]) if hours > 0 else Loc.t(&"ACCOUNT_PLAYTIME_MINUTES", [minutes])
	return Loc.t(&"ACCOUNT_WORLD_LINE", [int(summary.get("deepestRoom", 0)), int(summary.get("forgeLevel", 0)), int(summary.get("forgeMax", 0)), time])


## ISO time as local "03.11.2026 14:05" ("" if unreadable).
static func date_text(iso: Variant) -> String:
	var unix := OnlineConfig.parse_iso_time(iso)
	if unix <= 0:
		return ""
	var local := unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	return Loc.t(&"ACCOUNT_DATE", [d.day, d.month, d.year, d.hour, d.minute])


## Whole days until an ISO time (at least 0).
static func days_until(iso: Variant) -> int:
	var unix := OnlineConfig.parse_iso_time(iso)
	if unix <= 0:
		return 0
	return maxi(0, ceili((unix - Time.get_unix_time_from_system()) / 86400.0))


# --- Building ---

func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if _body == null:
		return
	var owner_focus := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	_focus_edit = owner_focus.name if owner_focus is LineEdit and frame.is_ancestor_of(owner_focus) else &""
	if view != View.PASSWORD:
		_form = {}
	var current := get_focused_button()
	if current != null and not _built_busy:
		_focus_name = String(current.name)
	_built_busy = service.is_busy()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_username_edit = null
	_password_edit = null
	_eyebrow.text = Loc.t(&"ACCOUNT_EYEBROW").to_upper()
	match view:
		View.MAIN:
			_build_main()
		View.METHODS:
			_build_methods()
		View.WEB:
			_build_web()
		View.PASSWORD:
			_build_password()
		View.MERGE:
			_build_merge()
		View.WORLDS:
			_build_worlds()
		View.BACKUPS:
			_build_backups()
		View.LIMIT:
			_build_limit()
		View.DELETE:
			_build_delete()
		View.CONFIRM:
			_build_confirm()
	if service.is_busy():
		_body.add_child(_line(Loc.t(&"ACCOUNT_BUSY"), UiKit.COLOR_MUTED))
	elif not notice.is_empty():
		var line := _line(notice, UiKit.COLOR_DANGER_SOFT if notice_is_error else UiKit.COLOR_SUCCESS)
		line.name = "Notice"
		_body.add_child(line)
	_refocus.call_deferred(_focus_name)


## Keeps the gamepad frame on the button of the same name, else on the view's default button.
func _refocus(focus_name: String) -> void:
	if not is_inside_tree() or not InputGlyphs.is_gamepad():
		return
	var targets := focus_targets()
	if targets.is_empty():
		focus_button(null)
		return
	for button in targets:
		if String(button.name) == focus_name:
			focus_button(button)
			return
	for button in targets:
		if button.has_meta(Modal.META_PAD_DEFAULT):
			focus_button(button)
			return
	focus_button(targets[0])


func _build_main() -> void:
	_title.text = Loc.t(&"ACCOUNT_TITLE")
	match service.get_state():
		AccountService.State.NONE:
			_body.add_child(_text(Loc.t(&"ACCOUNT_NONE_TEXT")))
			_body.add_child(_option(&"Secure", Loc.t(&"ACCOUNT_SECURE"), Loc.t(&"ACCOUNT_SECURE_SUB"), choose.bind(Purpose.SECURE), true))
			_body.add_child(_option(&"SignIn", Loc.t(&"ACCOUNT_SIGN_IN"), Loc.t(&"ACCOUNT_SIGN_IN_SUB"), choose.bind(Purpose.SIGN_IN)))
			_body.add_child(_button_row([_small(&"Close", Loc.t(&"ACCOUNT_CLOSE"), finish.bind(null))]))
		AccountService.State.SIGNED_OUT:
			_body.add_child(_text(Loc.t(&"ACCOUNT_SIGNED_OUT_TEXT")))
			_body.add_child(_option(&"SignIn", Loc.t(&"ACCOUNT_SIGN_IN"), Loc.t(&"ACCOUNT_SIGN_IN_AGAIN_SUB"), choose.bind(Purpose.SIGN_IN), true))
			_body.add_child(_option(&"AsGuest", Loc.t(&"ACCOUNT_AS_GUEST"), Loc.t(&"ACCOUNT_AS_GUEST_SUB"), func() -> void:
				service.play_as_guest()
				_set_notice(Loc.t(&"ACCOUNT_DONE_GUEST"), false, View.MAIN)))
			_body.add_child(_button_row([_small(&"Close", Loc.t(&"ACCOUNT_CLOSE"), finish.bind(null))]))
		AccountService.State.GUEST:
			_body.add_child(_status_line(false))
			_body.add_child(_text(Loc.t(&"ACCOUNT_GUEST_TEXT")))
			_body.add_child(_option(&"Secure", Loc.t(&"ACCOUNT_SECURE"), Loc.t(&"ACCOUNT_SECURE_SUB"), choose.bind(Purpose.SECURE), true))
			_body.add_child(_option(&"SignIn", Loc.t(&"ACCOUNT_SIGN_IN_OTHER"), Loc.t(&"ACCOUNT_SIGN_IN_OTHER_SUB"), choose.bind(Purpose.SIGN_IN)))
			_add_cloud_section()
			_body.add_child(_button_row([_small(&"Delete", Loc.t(&"ACCOUNT_DELETE"), show_view.bind(View.DELETE), false, true),
					_small(&"Close", Loc.t(&"ACCOUNT_CLOSE"), finish.bind(null))]))
		AccountService.State.SECURED:
			_body.add_child(_status_line(true))
			_add_logins_section()
			_add_cloud_section()
			_body.add_child(_button_row([_small(&"Delete", Loc.t(&"ACCOUNT_DELETE"), show_view.bind(View.DELETE), false, true),
					_small(&"Close", Loc.t(&"ACCOUNT_CLOSE"), finish.bind(null), true)]))


## "Lumen · Level 7" and "gesichert" / "nicht gesichert".
func _status_line(secured: bool) -> Control:
	var row := UiKit.hbox(int(UiKit.px(6)))
	row.name = "Status"
	var player := service.session.player
	var name_label := UiKit.text_label(str(player.get("name", "")), UiKit.SIZE_CARD_NAME, UiKit.COLOR_TEXT, true)
	row.add_child(name_label)
	if player.has("level"):
		row.add_child(UiKit.text_label(Loc.t(&"ACCOUNT_LEVEL", [int(player.get("level", 1))]), UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true))
	var state := UiKit.text_label(Loc.t(&"ACCOUNT_STATE_SECURED") if secured else Loc.t(&"ACCOUNT_STATE_GUEST"), UiKit.SIZE_BODY,
			UiKit.COLOR_SUCCESS if secured else UiKit.COLOR_EFFECT)
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(state)
	return row


func _add_logins_section() -> void:
	_body.add_child(_section(&"ACCOUNT_SECTION_LOGINS"))
	for group in service.login_groups():
		var provider := str(group["provider"])
		var detail := str(group["label"])
		if provider == AccountService.PROVIDER_DEVICE:
			detail = Loc.t(&"ACCOUNT_DEVICES", [int(group["count"])])
			if group["this_device"]:
				detail += " · " + Loc.t(&"ACCOUNT_THIS_DEVICE")
		var button: Button = null
		if service.can_remove(provider):
			button = _small(StringName("Remove_" + provider), Loc.t(&"ACCOUNT_REMOVE"), ask_remove.bind(provider))
		_body.add_child(_item_row(provider_name(provider), detail, button))
	if not service.keeps_device():
		_body.add_child(_text(Loc.t(&"ACCOUNT_DEVICE_NOT_KEPT"), UiKit.COLOR_MUTED))
	var buttons: Array[Control] = []
	if not service.keeps_device():
		buttons.append(_small(&"KeepDevice", Loc.t(&"ACCOUNT_KEEP_DEVICE"), keep_device.bind(false)))
	if service.has_web_login():
		buttons.append(_small(&"AddLogin", Loc.t(&"ACCOUNT_ADD_LOGIN"), choose.bind(Purpose.ADD), true))
	if service.has_password_login():
		var key: StringName = &"ACCOUNT_CHANGE_PASSWORD" if service.has_password() else &"ACCOUNT_ADD_PASSWORD"
		buttons.append(_small(&"Password", Loc.t(key), choose.bind(Purpose.CHANGE)))
	if not buttons.is_empty():
		_body.add_child(_button_row(buttons))


func _add_cloud_section() -> void:
	_body.add_child(_section(&"ACCOUNT_SECTION_CLOUD"))
	var report := CloudSave.report_text(CloudSave.last_report)
	if report.is_empty():
		report = Loc.t(&"ACCOUNT_CLOUD_NOT_YET")
	var active: Variant = service.worlds.get("items", [])
	var archived: Variant = service.worlds.get("archived", [])
	var counts := ""
	if not service.worlds.is_empty():
		counts = Loc.t(&"ACCOUNT_CLOUD_COUNTS", [(active as Array).size() if active is Array else 0, (archived as Array).size() if archived is Array else 0])
	var info := _text(report + ("\n" + counts if not counts.is_empty() else ""), UiKit.COLOR_TEXT_SOFT)
	info.name = "CloudLine"
	_body.add_child(info)
	var in_run := RunManager.is_run_active()
	var sync := _small(&"Sync", Loc.t(&"ACCOUNT_SYNC_NOW"), sync_now)
	sync.disabled = in_run or CloudSave.is_running()
	_body.add_child(_button_row([sync, _small(&"Worlds", Loc.t(&"ACCOUNT_WORLDS"), open_worlds)]))
	if in_run:
		_body.add_child(_text(Loc.t(&"ACCOUNT_ERR_IN_RUN"), UiKit.COLOR_MUTED))


func _build_methods() -> void:
	_title.text = _purpose_title()
	_body.add_child(_text(Loc.t(&"ACCOUNT_SECURE_TEXT") if purpose == Purpose.SECURE else Loc.t(&"ACCOUNT_METHODS_TEXT")))
	if service.has_web_login():
		_body.add_child(_option(&"WebMethod", Loc.t(&"ACCOUNT_METHOD_WEB"), Loc.t(&"ACCOUNT_METHOD_WEB_SUB"), start_web, true))
	if service.has_password_login():
		_body.add_child(_option(&"PasswordMethod", Loc.t(&"ACCOUNT_METHOD_PASSWORD"), Loc.t(&"ACCOUNT_METHOD_PASSWORD_SUB"), show_view.bind(View.PASSWORD), not service.has_web_login()))
	if _method_count() == 0:
		_body.add_child(_text(Loc.t(&"ACCOUNT_NO_METHODS"), UiKit.COLOR_MUTED))
	_body.add_child(_button_row([_small(&"Back", Loc.t(&"COMMON_BACK"), go_back)]))


func _build_web() -> void:
	_title.text = _purpose_title()
	var web := service.web
	var waiting := web.is_waiting()
	if web.status == WebLoginFlow.Status.STARTING or web.status == WebLoginFlow.Status.IDLE:
		_body.add_child(_text(Loc.t(&"ACCOUNT_WEB_STARTING"), UiKit.COLOR_MUTED))
	elif waiting or web.status == WebLoginFlow.Status.COMPLETED:
		_body.add_child(_text(Loc.t(&"ACCOUNT_WEB_OPENED")))
		var code := UiKit.title(web.display_code(), UiKit.SIZE_TITLE_LARGE, UiKit.COLOR_GOLD)
		code.name = "Code"
		_body.add_child(code)
		var status := Loc.t(&"ACCOUNT_WEB_WAITING", [maxi(1, ceili(web.seconds_left() / 60.0))])
		if web.status == WebLoginFlow.Status.CONFIRM:
			status = Loc.t(&"ACCOUNT_WEB_CONFIRM")
		elif web.status == WebLoginFlow.Status.COMPLETED:
			status = Loc.t(&"ACCOUNT_BUSY")
		elif web.offline:
			status = Loc.t(&"ACCOUNT_WEB_OFFLINE")
		var line := _text(status, UiKit.COLOR_TEXT_SOFT)
		line.name = "WebStatus"
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(line)
	else:
		var text := Loc.t(&"ACCOUNT_WEB_EXPIRED") if web.status == WebLoginFlow.Status.EXPIRED else _web_error_text(web)
		var failed := _text(text, UiKit.COLOR_DANGER_SOFT)
		failed.name = "WebStatus"
		_body.add_child(failed)
	if waiting:
		_body.add_child(_button_row([_small(&"Reopen", Loc.t(&"ACCOUNT_WEB_REOPEN"), func() -> void: web.open_browser(), true),
				_small(&"CopyLink", Loc.t(&"ACCOUNT_WEB_COPY"), func() -> void:
					if web.copy_link():
						_set_notice(Loc.t(&"ACCOUNT_WEB_COPIED"), false)),
				_small(&"Cancel", Loc.t(&"COMMON_CANCEL"), go_back)]))
	elif web.status in [WebLoginFlow.Status.FAILED, WebLoginFlow.Status.EXPIRED, WebLoginFlow.Status.CANCELLED]:
		_body.add_child(_button_row([_small(&"Retry", Loc.t(&"ACCOUNT_WEB_RETRY"), start_web, true), _small(&"Back", Loc.t(&"COMMON_BACK"), go_back)]))


static func _web_error_text(web: WebLoginFlow) -> String:
	var text := error_text(web.error)
	if web.error == ApiResult.BANNED:
		if not web.ban_reason.is_empty():
			text += " " + Loc.t(&"ACCOUNT_BAN_REASON", [web.ban_reason])
		if web.ban_expires_at > 0:
			text += " " + Loc.t(&"ACCOUNT_BAN_UNTIL", [date_text(CloudSave.iso_time(web.ban_expires_at))])
	return text


func _build_password() -> void:
	var sign_in := purpose == Purpose.SIGN_IN
	_title.text = Loc.t(&"ACCOUNT_PASSWORD_SIGN_IN_TITLE") if sign_in else Loc.t(&"ACCOUNT_PASSWORD_TITLE")
	_body.add_child(_text(Loc.t(&"ACCOUNT_PASSWORD_SIGN_IN_TEXT") if sign_in else Loc.t(&"ACCOUNT_PASSWORD_TEXT"), UiKit.COLOR_MUTED))
	_username_edit = _edit(&"Username", Loc.t(&"ACCOUNT_USERNAME"), false)
	_username_edit.max_length = 64 if sign_in else AccountService.USERNAME_MAX
	_username_edit.text = str(_form.get("username", "" if sign_in else service.password_username()))
	_password_edit = _edit(&"Password", Loc.t(&"ACCOUNT_PASSWORD_NEW") if service.has_password() and not sign_in else Loc.t(&"ACCOUNT_PASSWORD"), true)
	_password_edit.max_length = AccountService.PASSWORD_MAX
	_password_edit.text = str(_form.get("password", ""))
	# Rebuilt views (busy, an error line) keep what was typed.
	_username_edit.text_changed.connect(func(value: String) -> void: _form["username"] = value)
	_password_edit.text_changed.connect(func(value: String) -> void: _form["password"] = value)
	_body.add_child(_field_row(Loc.t(&"ACCOUNT_USERNAME"), _username_edit))
	_body.add_child(_field_row(Loc.t(&"ACCOUNT_PASSWORD"), _password_edit))
	_username_edit.focus_next = _username_edit.get_path_to(_password_edit)
	_password_edit.focus_previous = _password_edit.get_path_to(_username_edit)
	if _focus_edit in [&"Username", &"Password"]:
		(_username_edit if _focus_edit == &"Username" else _password_edit).grab_focus.call_deferred()
	_username_edit.text_submitted.connect(func(_text_value: String) -> void: _password_edit.grab_focus())
	_password_edit.text_submitted.connect(func(_text_value: String) -> void: submit_password())
	if not sign_in and service.has_password():
		_body.add_child(_text(Loc.t(&"ACCOUNT_PASSWORD_KEEP"), UiKit.COLOR_DISABLED))
	var submit := _small(&"Submit", Loc.t(&"ACCOUNT_SIGN_IN") if sign_in else Loc.t(&"ACCOUNT_SAVE"), submit_password, true)
	submit.disabled = service.is_busy()
	_body.add_child(_button_row([submit, _small(&"Back", Loc.t(&"COMMON_BACK"), go_back)]))


func _build_merge() -> void:
	_title.text = Loc.t(&"ACCOUNT_MERGE_TITLE")
	_body.add_child(_text(Loc.t(&"ACCOUNT_MERGE_TEXT")))
	var offer := service.merge_offer
	_body.add_child(_account_card(offer.get("remaining", {}), Loc.t(&"ACCOUNT_MERGE_STAYS")))
	_body.add_child(_account_card(offer.get("removed", {}), Loc.t(&"ACCOUNT_MERGE_JOINS")))
	_body.add_child(_button_row([_small(&"Merge", Loc.t(&"ACCOUNT_MERGE_YES"), keep_device.bind(true), true),
			_small(&"NotNow", Loc.t(&"ACCOUNT_MERGE_NO"), go_back)]))


func _account_card(summary: Variant, role: String) -> Control:
	var data: Dictionary = summary if summary is Dictionary else {}
	var guilds: Variant = data.get("guilds", [])
	var line := Loc.t(&"ACCOUNT_SUMMARY_LINE", [int(data.get("level", 1)), int(data.get("runCount", 0)),
			int(data.get("worlds", 0)), (guilds as Array).size() if guilds is Array else 0])
	return _item_row(str(data.get("name", "")), line + " · " + role, null)


func _build_worlds() -> void:
	_title.text = Loc.t(&"ACCOUNT_WORLDS_TITLE")
	var in_run := RunManager.is_run_active()
	var list := UiKit.vbox(int(UiKit.px(3)))
	var active: Variant = service.worlds.get("items", [])
	var archived: Variant = service.worlds.get("archived", [])
	if active is Array and not (active as Array).is_empty():
		list.add_child(_section(&"ACCOUNT_SECTION_ACTIVE"))
		for world: Variant in active:
			if not (world is Dictionary):
				continue
			var count := int(world.get("backupCount", 0))
			var button := _small(StringName("Backups_" + str(world.get("worldId", ""))), Loc.t(&"ACCOUNT_BACKUPS", [count]), open_backups.bind(world))
			button.disabled = count == 0
			list.add_child(_item_row(world_name(world.get("summary", {})), world_line(world.get("summary", {})), button))
	if archived is Array and not (archived as Array).is_empty():
		list.add_child(_section(&"ACCOUNT_SECTION_ARCHIVE"))
		for world: Variant in archived:
			if not (world is Dictionary):
				continue
			var button := _small(StringName("Unarchive_" + str(world.get("worldId", ""))), Loc.t(&"ACCOUNT_UNARCHIVE"), unarchive.bind(world))
			button.disabled = in_run or service.is_busy()
			list.add_child(_item_row(world_name(world.get("summary", {})), Loc.t(&"ACCOUNT_ARCHIVE_LEFT", [days_until(world.get("expiresAt", ""))]), button))
	if list.get_child_count() == 0:
		list.add_child(_text(Loc.t(&"ACCOUNT_WORLDS_EMPTY") if not service.worlds.is_empty() else Loc.t(&"ACCOUNT_BUSY"), UiKit.COLOR_MUTED))
	_body.add_child(_list_scroll(list))
	_body.add_child(_text(Loc.t(&"ACCOUNT_ERR_IN_RUN") if in_run else Loc.t(&"ACCOUNT_WORLDS_NOTE"), UiKit.COLOR_DISABLED))
	_body.add_child(_button_row([_small(&"Back", Loc.t(&"COMMON_BACK"), go_back, true)]))


func _build_backups() -> void:
	var world_id := str(_world.get("worldId", ""))
	_title.text = Loc.t(&"ACCOUNT_BACKUPS_TITLE", [world_name(_world.get("summary", {}))])
	var list := UiKit.vbox(int(UiKit.px(3)))
	var items: Variant = service.backups.get(world_id, null)
	var in_run := RunManager.is_run_active()
	if items is Array:
		for backup: Variant in items:
			if not (backup is Dictionary):
				continue
			var button := _small(StringName("Restore_" + str(backup.get("id", ""))), Loc.t(&"ACCOUNT_RESTORE"), ask_restore.bind(backup))
			button.disabled = in_run or service.is_busy()
			var reason: StringName = REASON_KEYS.get(str(backup.get("reason", "")), &"ACCOUNT_BACKUP_MERGE")
			list.add_child(_item_row(date_text(backup.get("createdAt", "")), Loc.t(reason) + " · " + world_line(backup.get("summary", {})), button))
		if (items as Array).is_empty():
			list.add_child(_text(Loc.t(&"ACCOUNT_BACKUPS_EMPTY"), UiKit.COLOR_MUTED))
	else:
		list.add_child(_text(Loc.t(&"ACCOUNT_BUSY"), UiKit.COLOR_MUTED))
	_body.add_child(_list_scroll(list))
	_body.add_child(_text(Loc.t(&"ACCOUNT_BACKUPS_NOTE"), UiKit.COLOR_DISABLED))
	_body.add_child(_button_row([_small(&"Back", Loc.t(&"COMMON_BACK"), go_back, true)]))


func _build_limit() -> void:
	_title.text = Loc.t(&"ACCOUNT_LIMIT_TITLE")
	_body.add_child(_text(Loc.t(&"ACCOUNT_LIMIT_TEXT")))
	var list := UiKit.vbox(int(UiKit.px(3)))
	var items: Variant = service.limit_offer.get("items", [])
	if items is Array:
		for world: Variant in items:
			if world is Dictionary:
				var button := _small(StringName("Archive_" + str(world.get("worldId", ""))), Loc.t(&"ACCOUNT_TO_ARCHIVE"), archive_instead.bind(world))
				list.add_child(_item_row(world_name(world.get("summary", {})), world_line(world.get("summary", {})), button))
	_body.add_child(_list_scroll(list))
	_body.add_child(_button_row([_small(&"Back", Loc.t(&"COMMON_CANCEL"), go_back, true)]))


func _build_delete() -> void:
	_title.text = Loc.t(&"ACCOUNT_DELETE_TITLE")
	if service.get_state() == AccountService.State.NONE or service.get_state() == AccountService.State.SIGNED_OUT:
		_body.add_child(_text(Loc.t(&"ACCOUNT_DELETE_NONE")))
		_body.add_child(_button_row([_small(&"Back", Loc.t(&"COMMON_BACK"), go_back, true)]))
		return
	_body.add_child(_text(Loc.t(&"ACCOUNT_DELETE_TEXT")))
	_body.add_child(_section(&"ACCOUNT_SECTION_DELETION_CODE"))
	if service.deletion_code.is_empty():
		_body.add_child(_text(Loc.t(&"ACCOUNT_DELETION_CODE_TEXT", [service.deletion_page()]), UiKit.COLOR_MUTED))
	else:
		var code := UiKit.title(WebLoginFlow.format_code(str(service.deletion_code.get("code", ""))), UiKit.SIZE_TITLE_LARGE, UiKit.COLOR_GOLD)
		code.name = "DeletionCode"
		_body.add_child(code)
		_body.add_child(_text(Loc.t(&"ACCOUNT_DELETION_CODE_SHOWN", [service.deletion_page(), date_text(service.deletion_code.get("expiresAt", ""))]), UiKit.COLOR_MUTED))
	_body.add_child(_button_row([
		_small(&"DeleteCode", Loc.t(&"ACCOUNT_DELETION_CODE_NEW") if not service.deletion_code.is_empty() else Loc.t(&"ACCOUNT_DELETION_CODE"),
				func() -> void: service.run(&"deletion_code", service.create_deletion_code)),
		_small(&"DeleteNow", Loc.t(&"ACCOUNT_DELETE_NOW"), ask_delete, false, true),
		_small(&"Back", Loc.t(&"COMMON_BACK"), go_back, true),
	]))


func _build_confirm() -> void:
	_body.add_child(_text(str(_confirm.get("text", ""))))
	var yes := _small(&"Confirm", str(_confirm.get("yes", "")), func() -> void:
		var action: Callable = _confirm.get("action", Callable())
		if action.is_valid():
			action.call(), false, bool(_confirm.get("danger", false)))
	_body.add_child(_button_row([yes, _small(&"Cancel", Loc.t(&"COMMON_CANCEL"), go_back, true)]))


func _purpose_title() -> String:
	match purpose:
		Purpose.SECURE:
			return Loc.t(&"ACCOUNT_SECURE")
		Purpose.ADD:
			return Loc.t(&"ACCOUNT_ADD_LOGIN")
		Purpose.CHANGE:
			return Loc.t(&"ACCOUNT_PASSWORD_TITLE")
	return Loc.t(&"ACCOUNT_SIGN_IN")


func _method_count() -> int:
	return int(service.has_web_login()) + int(service.has_password_login())


# --- Small pieces ---

func _text(content: String, color := UiKit.COLOR_TEXT_SOFT) -> Label:
	return UiKit.wrapped_text(content, WIDTH - UiDialog.PADDING.y * 2.0, UiKit.SIZE_BODY, color)


func _line(content: String, color: Color) -> Label:
	var label := _text(content, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _section(key: StringName) -> Label:
	return UiKit.eyebrow(Loc.t(key), UiKit.COLOR_DISABLED)


## A big option with a sub line (gamepad focus, the default one framed first).
func _option(button_name: StringName, text: String, sub: String, on_pressed: Callable, is_default := false) -> Button:
	var button := UiDialog.option_button(text, sub, "", on_pressed, is_default)
	button.name = button_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = service.is_busy()
	return button


## A small button for rows and footers.
func _small(button_name: StringName, text: String, on_pressed: Callable, is_default := false, danger := false) -> Button:
	var button := UiDialog.option_button(text, "", "", on_pressed, is_default)
	button.name = button_name
	button.custom_minimum_size.x = UiKit.px(SMALL_BUTTON_WIDTH)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if danger:
		button.add_theme_color_override("font_color", UiKit.COLOR_DANGER_SOFT)
		button.add_theme_color_override("font_hover_color", UiKit.COLOR_DANGER_SOFT.lightened(0.2))
	if service.is_busy() and button_name not in [&"Close", &"Back", &"Cancel"]:
		button.disabled = true
	return button


func _button_row(buttons: Array) -> HBoxContainer:
	var row := UiKit.hbox(int(UiKit.px(5)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for button: Control in buttons:
		row.add_child(button)
	return row


## "Discord · lumen ....... [Trennen]".
func _item_row(caption: String, detail: String, button: Control) -> Control:
	var row := UiKit.hbox(int(UiKit.px(5)))
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.text_label(caption, UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT, true))
	if not detail.is_empty():
		var sub := UiKit.text_label(detail, UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = UiKit.px(DETAIL_WIDTH)
		text.add_child(sub)
	row.add_child(text)
	if button != null:
		row.add_child(button)
	return row


## Short lists stay as they are; longer ones scroll in LIST_HEIGHT (their wrapped lines cannot be
## measured before the layout, so the height is fixed).
func _list_scroll(list: Control) -> Control:
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if list.get_child_count() <= SHORT_LIST:
		return list
	var scroll := ScrollContainer.new()
	scroll.name = "List"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	scroll.custom_minimum_size.y = UiKit.px(LIST_HEIGHT)
	return scroll


## A text field inside a button: the button takes the gamepad frame (A opens the on-screen keyboard
## with a gamepad, else the field takes the keyboard); a click or tap goes straight into the field.
func _edit(edit_name: StringName, placeholder: String, secret: bool) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = edit_name
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.add_theme_font_size_override("font_size", UiKit.font_px(UiKit.SIZE_KEY_HINT))
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else LineEdit.KEYBOARD_TYPE_DEFAULT
	edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit.caret_blink = true
	return edit


func _field_row(caption: String, edit: LineEdit) -> Control:
	var row := UiKit.hbox(int(UiKit.px(6)))
	var label := UiKit.text_label(caption, UiKit.SIZE_KEY_HINT, UiKit.COLOR_TEXT_SOFT, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var holder := Button.new()
	holder.name = StringName("Field" + String(edit.name))
	holder.focus_mode = Control.FOCUS_NONE
	holder.flat = true
	holder.custom_minimum_size = Vector2(UiKit.px(FIELD_WIDTH), UiKit.px(FIELD_HEIGHT))
	holder.set_meta(Modal.META_PAD_OPTION, true)
	holder.add_child(edit)
	holder.pressed.connect(func() -> void:
		if InputGlyphs.is_gamepad():
			PadKeyboard.open_for(edit)
		else:
			edit.grab_focus())
	row.add_child(holder)
	return row


## The text field inside a field button (null for other buttons).
static func _field_of(button: Button) -> LineEdit:
	if button == null:
		return null
	for child in button.get_children():
		if child is LineEdit:
			return child
	return null


func get_username_edit() -> LineEdit:
	return _username_edit


func get_password_edit() -> LineEdit:
	return _password_edit


## A button of the current view by name (tests, screenshots), null if none.
func find_button(button_name: String) -> Button:
	return frame.find_child(button_name, true, false) as Button
