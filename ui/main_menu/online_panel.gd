class_name OnlinePanel
extends MenuPanel
## "Online spielen" in the main menu (D-147): the shared OnlineMenu (Schnelles Spiel and Gilden) in
## a main menu panel. There is no game scene here to hold a room, so creating or joining one emits
## launch_requested; the main menu loads the world of "Weiterspielen" (without any world it creates
## the first one) and the village of the new game runs the wish (LobbyClient.request_launch). Guilds
## are managed right here; no world is needed for that (name and look are the profile, D-152). Esc
## goes one step back inside the menu, at the top it closes the panel.

signal launch_requested(launch: Dictionary)

const PadNav := preload("res://ui/widgets/pad_nav.gd")

const WIDTH := 258.0
## Most height of the menu's content in mockup pixels: taller views (a guild's page with its open
## rooms and members) scroll, so the panel stays on a 270 px high screen like the village dialog.
const CONTENT_HEIGHT := 160.0

var menu: OnlineMenu = null


func _ready() -> void:
	# Name and look come from the player's profile (D-152); rooms start in the world of
	# "Weiterspielen", so that world is loaded first.
	var slot := SaveManager.get_continue_slot()
	if slot > 0 and SaveManager.get_active_slot() != slot:
		SaveManager.load_slot(slot)
	set_width(WIDTH)
	add_header(&"ONLINE_MENU_EYEBROW", &"ONLINE_MENU_TITLE")
	menu = OnlineMenu.create(null, null, WIDTH - MenuPanel.PADDING.y * 2.0, CONTENT_HEIGHT)
	menu.launch_requested.connect(launch_requested.emit)
	content.add_child(menu)
	set_footer(&"ONLINE_MENU_FOOTER", &"ONLINE_MENU_FOOTER_PAD")


## Gamepad: the menu moves with Godot's focus; D-pad and stick take one debounced step (PadNav).
func _input(event: InputEvent) -> void:
	if menu != null and PadNav.step_gui_focus(event, menu):
		get_viewport().set_input_as_handled()


func handle_input(event: InputEvent) -> bool:
	if menu.handle_input(event):
		return true
	if MenuInput.is_back(event):
		close()
		return true
	return false
