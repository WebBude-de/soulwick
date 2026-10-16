class_name QuietRun
extends RefCounted
## Quiet runs for agents and tools (AGENTS.md §7): with the environment variable SOULWICK_QUIET=1
## the game mutes every bus and its window never takes the focus, stays below other windows and
## leaves only a small corner visible bottom right, so a screenshot run does not interrupt the project member
## while they play: the window is pushed almost completely off the screen (it keeps rendering at its
## full size, so screenshots stay sharp). A normal start (editor, exported build) is never affected.
## Sound is best switched off at the driver as well: `--audio-driver Dummy` (no mixer thread).

const ENV := "SOULWICK_QUIET"
## How much of a quiet window stays visible in the bottom-right corner (to find it again).
const VISIBLE_CORNER := Vector2i(160, 90)


static func is_quiet() -> bool:
	return OS.get_environment(ENV) == "1"


static func apply(tree: SceneTree) -> void:
	if not is_quiet() or tree == null:
		return
	for bus in AudioServer.bus_count:
		AudioServer.set_bus_mute(bus, true)
	if DisplayServer.get_name() == "headless":
		return
	var window := tree.root
	window.set_flag(Window.FLAG_NO_FOCUS, true)
	window.always_on_top = false
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.position = screen.end - VISIBLE_CORNER
