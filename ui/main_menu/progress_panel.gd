class_name ProgressPanel
extends MenuPanel
## "Fortschritt" in the main menu (D-188, KF1): the ProgressView of the world "Weiterspielen"
## continues (read from its file, nothing is loaded), so the player sees how far they are without
## searching. Esc (or B) closes it.

const WIDTH := 252.0

var view: ProgressView = null


func _ready() -> void:
	set_width(WIDTH)
	add_header(&"PROGRESS_EYEBROW", &"PROGRESS_TITLE")
	view = ProgressView.for_continue_world(WIDTH - MenuPanel.PADDING.y * 2.0)
	content.add_child(view)
	set_footer(&"PROGRESS_FOOTER", &"PROGRESS_FOOTER_PAD")


func handle_input(event: InputEvent) -> bool:
	if MenuInput.is_back(event):
		close()
		return true
	return false
