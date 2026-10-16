class_name OnlinePanel
extends MenuPanel
## "Online spielen" in the main menu (D-147): the shared OnlineMenu (Schnelles Spiel and Gilden) in
## a main menu panel. There is no game scene here to hold a room, so creating or joining one emits
## launch_requested; the main menu loads the save and the village of the new game runs the wish
## (LobbyClient.request_launch). Guilds are managed right here. Esc goes one step back inside the
## menu, at the top it closes the panel.

signal launch_requested(launch: Dictionary)

const WIDTH := 258.0

var menu: OnlineMenu = null


func _ready() -> void:
	# The login uses the name of the save that "Weiterspielen" starts (a new guest account is named
	# after it), so that save is loaded first.
	var slot := SaveManager.get_continue_slot()
	if slot > 0 and SaveManager.get_active_slot() != slot:
		SaveManager.load_slot(slot)
	set_width(WIDTH)
	add_header(&"ONLINE_MENU_EYEBROW", &"ONLINE_MENU_TITLE")
	menu = OnlineMenu.create(null, null, WIDTH - MenuPanel.PADDING.y * 2.0)
	menu.launch_requested.connect(launch_requested.emit)
	content.add_child(menu)
	set_footer(&"ONLINE_MENU_FOOTER")


func handle_input(event: InputEvent) -> bool:
	if menu.handle_input(event):
		return true
	if MenuInput.is_back(event):
		close()
		return true
	return false
