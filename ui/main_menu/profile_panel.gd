class_name ProfilePanel
extends MenuPanel
## "Wie heißt du?" (first start) and "Figur" in the main menu (D-152): the ProfileEditor in a menu
## panel. The first start cannot be skipped (Esc does nothing); it suggests the name and colour of
## the save slots of older builds once (PlayerProfile.legacy_suggestion), otherwise the profile.
## The scene figure behind the menu follows the editor (look_changed). On the first start "Los geht's"
## also starts the game when there is no world yet (MainMenu creates Welt 1, P1-1).
## Invite by link (MP2b, D-190): the same page says who is waiting ("Einladung · Wie heißt du?" and
## the room code); "Los geht's" goes straight into that room (MainMenu.join_invite).

signal saved
signal look_changed(look: Dictionary)

const WIDTH := 262.0

var first_start := false
## Room code of the invite link of this start ("" = an ordinary first start).
var invite_code := ""
var editor: ProfileEditor = null


static func create(is_first_start := false, invite := "") -> ProfilePanel:
	var panel := ProfilePanel.new()
	panel.first_start = is_first_start
	panel.invite_code = invite if is_first_start else ""
	return panel


func _ready() -> void:
	set_width(WIDTH)
	if first_start and not invite_code.is_empty():
		add_header(&"INVITE_FIRST_EYEBROW", &"PROFILE_FIRST_TITLE")
	elif first_start:
		add_header(&"PROFILE_FIRST_EYEBROW", &"PROFILE_FIRST_TITLE")
	else:
		add_header(&"PROFILE_EYEBROW", &"PROFILE_TITLE")
	var profile := PlayerProfile.current()
	var start_name := profile.player_name
	var start_look := profile.look
	if profile.needs_setup():
		var suggestion := PlayerProfile.legacy_suggestion()
		if not suggestion.is_empty():
			start_name = str(suggestion.get("name", ""))
			start_look = suggestion.get("look", start_look)
	if first_start:
		var hint := tr(&"PROFILE_FIRST_HINT") if invite_code.is_empty() else tr(&"INVITE_FIRST_HINT") % invite_code
		var intro := UiKit.wrapped_text(hint, WIDTH - MenuPanel.PADDING.y * 2.0, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		intro.name = "Intro"
		content.add_child(intro)
	editor = ProfileEditor.create(start_name, start_look, first_start, WIDTH - MenuPanel.PADDING.y * 2.0)
	# D-188 (KF2): the account level above the editor ("Figur", not the first start).
	editor.show_level = true
	editor.saved.connect(_on_saved)
	editor.cancelled.connect(close)
	editor.look_changed.connect(look_changed.emit)
	content.add_child(editor)
	set_footer(&"PROFILE_FOOTER_FIRST" if first_start else &"PROFILE_FOOTER",
			&"PROFILE_FOOTER_FIRST_PAD" if first_start else &"PROFILE_FOOTER_PAD")


func handle_input(event: InputEvent) -> bool:
	if editor.handle_input(event):
		return true
	# The first start has no way back; every other key is swallowed so the menu list stays put.
	return first_start and event.is_action_type()


## The first start has no way back (no X on touch screens either).
func can_close() -> bool:
	return not first_start


func _on_saved() -> void:
	saved.emit()
	closed.emit()
