extends SceneTree
## Loads every script, scene and resource of the project and instantiates every scene once.
## Usage: godot --headless -s tools/validate_project.gd
## Parse and load errors are printed by Godot; the summary line counts failed loads.

const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://tools"]
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]


func _init() -> void:
	# Autoload singletons (EventBus, ...) only exist once the tree runs.
	process_frame.connect(_validate, CONNECT_ONE_SHOT)


func _validate() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	var failed := 0
	for path in files:
		var resource := load(path)
		if resource == null:
			failed += 1
			printerr("FAILED to load: ", path)
			continue
		if resource is PackedScene:
			var instance := (resource as PackedScene).instantiate()
			if instance == null:
				failed += 1
				printerr("FAILED to instantiate: ", path)
			else:
				instance.free()
	print("validate_project: %d files checked, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path in SKIP_DIRS or dir_path.trim_suffix("/") in SKIP_DIRS:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		# Hidden folders (.godot, .userdata for isolated test runs) are never project files.
		if sub.begins_with("."):
			continue
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.get_extension() in EXTENSIONS:
			out.append(dir_path.path_join(file))
