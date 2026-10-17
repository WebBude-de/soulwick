class_name WebKeepAlive
extends RefCounted
## Browser only (D-183): keeps the game running while its tab is hidden, as long as this machine is
## in a relay room. A hidden tab gets no requestAnimationFrame any more, so the host's whole game
## (simulation, network, snapshots) stood still and every client waited or was pulled back.
## deploy/web/shell.html wraps requestAnimationFrame: visible = the browser's own frames, hidden
## with the keep-alive on = ticks of a small worker (window.soulwickShell, setKeepAlive / isHidden /
## stats). Godot's main loop asks for every frame with the global requestAnimationFrame, so nothing
## in the engine changes. While the page is hidden nothing is drawn (render loop off).
## Static helpers, no autoload (D-044): LobbyClient switches it with its state and calls update()
## every frame. Everywhere else (desktop, mobile apps, single player, tests) it does nothing.

## TESTWERT: seconds between two looks at the page's visibility.
const POLL_SECONDS := 0.25
const SHELL := "window.soulwickShell"

static var _enabled := false
static var _hidden := false
static var _poll_left := 0.0


## The browser build with JavaScript (the shell decides whether the keep-alive really exists).
static func is_supported() -> bool:
	return OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge")


## On in a relay room (host and client: a hidden client would also miss the host's stream), off
## outside. No effect outside the browser.
static func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	_poll_left = 0.0
	if not on:
		_set_hidden(false)
	if not is_supported():
		return
	JavaScriptBridge.eval("%s && %s.setKeepAlive(%s)" % [SHELL, SHELL, "true" if on else "false"], true)


static func is_enabled() -> bool:
	return _enabled


## The page is hidden (as last seen; false outside the browser).
static func is_page_hidden() -> bool:
	return _hidden


## Every frame while enabled: a hidden page draws nothing (saves the graphics card; the simulation
## and the network keep running), a visible one draws again.
static func update(delta: float) -> void:
	if not _enabled or not is_supported():
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_SECONDS
	var hidden: Variant = JavaScriptBridge.eval("!!(%s && %s.isHidden())" % [SHELL, SHELL], true)
	_set_hidden(hidden == true)


## The shell's numbers for logs and the F9 report ({} outside the browser): ticks while hidden,
## the longest gap between two of them (ms), whether a worker drives them.
static func stats() -> Dictionary:
	if not is_supported():
		return {}
	var text: Variant = JavaScriptBridge.eval("JSON.stringify(%s ? %s.stats() : {})" % [SHELL, SHELL], true)
	var parsed: Variant = JSON.parse_string(str(text)) if text != null else null
	return parsed if parsed is Dictionary else {}


static func _set_hidden(hidden: bool) -> void:
	if hidden == _hidden:
		return
	_hidden = hidden
	RenderingServer.render_loop_enabled = not hidden
