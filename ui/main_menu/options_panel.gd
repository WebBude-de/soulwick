class_name OptionsPanel
extends MenuPanel
## "Optionen" in the main menu: the shared OptionsView (language, volumes, window mode, game feel,
## key overview), the same as in the pause menu. Global settings, not per save slot. Esc (or
## "Zurück") closes the panel unless the view uses it (reset question); volumes are saved when it
## closes or a slider is released.

## Kept for callers and tests: one ←/→ step of a volume slider.
const STEP := OptionsView.STEP
const WIDTH := 236.0

var view: OptionsView = null


func _ready() -> void:
	set_width(WIDTH)
	view = OptionsView.new()
	view.back_requested.connect(close)
	content.add_child(view)


func handle_input(event: InputEvent) -> bool:
	if view.handle_input(event):
		return true
	if MenuInput.is_back(event):
		close()
		return true
	return false


func get_volume_slider(bus: StringName) -> HSlider:
	return view.get_volume_slider(bus)


func close() -> void:
	view.save_volumes()
	UiSound.back(self)
	closed.emit()
