extends Node
## MusicPreloader (no class_name: used through MusicPlayer.MusicPreloader, a preload constant).
## Loads music files ahead of time so entering a new biome does not stall a frame (a music file
## took ~30 ms on the main thread). MusicPlayer asks for the files of the coming biome; this
## node keeps them referenced, so MusicRules.load_stream's plain load() finds them in the
## resource cache. Anything not ready yet simply loads the normal way (fallback).
##
## With threads: one ResourceLoader.load_threaded_request at a time, polled every frame. Without
## threads (web build without SharedArrayBuffer): one plain load() per IDLE_LOAD_INTERVAL, so the
## cost is spread over calm frames instead of hitting the first frame of the new biome.

## Real seconds between two blocking loads in a build without threads (TESTWERT).
const IDLE_LOAD_INTERVAL := 0.5

## Paths still to load, in order.
var _queue: Array[String] = []
## Loaded resources, kept alive by this reference (path -> Resource).
var _held: Dictionary[String, Resource] = {}
## Threaded request in flight ("" when none).
var _in_flight := ""
var _threaded := OS.has_feature("threads")
var _next_load_usec := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_process(not _queue.is_empty())


## Queues paths (duplicates, already loaded and missing files are skipped).
func request(paths: Array[String]) -> void:
	for path in paths:
		if path.is_empty() or _held.has(path) or path == _in_flight or _queue.has(path):
			continue
		if not ResourceLoader.exists(path):
			continue
		_queue.append(path)
	set_process(not _queue.is_empty() or not _in_flight.is_empty())


## Lets go of everything except keep (players that still play a file hold it themselves).
func release_except(keep: Array[String]) -> void:
	for path: String in _held.keys():
		if not keep.has(path):
			_held.erase(path)
	var kept: Array[String] = []
	for path in _queue:
		if keep.has(path):
			kept.append(path)
	_queue = kept


func is_loaded(path: String) -> bool:
	return _held.has(path)


func is_idle() -> bool:
	return _queue.is_empty() and _in_flight.is_empty()


## Paths held right now (tests, debugging).
func get_loaded_paths() -> Array[String]:
	var paths: Array[String] = []
	paths.assign(_held.keys())
	return paths


## Forces the threaded mode on or off (tests; the build decides otherwise).
func set_threaded(threaded: bool) -> void:
	_threaded = threaded


## Loads everything queued right now, blocking (tests, debugging).
func finish_now() -> void:
	while not is_idle():
		_step(true)


func _process(_delta: float) -> void:
	_step(false)
	if is_idle():
		set_process(false)


func _step(blocking: bool) -> void:
	if not _in_flight.is_empty():
		_poll_in_flight(blocking)
		return
	if _queue.is_empty():
		return
	if _threaded:
		var path: String = _queue.pop_front()
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_in_flight = path
		return
	var now := Time.get_ticks_usec()
	if not blocking and now < _next_load_usec:
		return
	_next_load_usec = now + int(IDLE_LOAD_INTERVAL * 1000000.0)
	var plain: String = _queue.pop_front()
	_keep(plain, load(plain))


func _poll_in_flight(blocking: bool) -> void:
	var status := ResourceLoader.load_threaded_get_status(_in_flight)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not blocking:
		return
	var path := _in_flight
	_in_flight = ""
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# load_threaded_get waits for a load still in progress (blocking only).
		_keep(path, ResourceLoader.load_threaded_get(path))
	# FAILED / INVALID_RESOURCE: dropped, the music loads the file the normal way when it plays.


func _keep(path: String, resource: Resource) -> void:
	if resource != null:
		_held[path] = resource


func _exit_tree() -> void:
	# Collect a request still in flight, otherwise the loader keeps its result forever.
	if not _in_flight.is_empty():
		var path := _in_flight
		_in_flight = ""
		ResourceLoader.load_threaded_get(path)
	_queue.clear()
