class_name SafeSave
extends RefCounted
## Crash-safe writing of ConfigFiles (P1-8): saves, global settings and, through hooks, the player
## profile. A crash or a full disk while saving must never destroy the last good file.
##
## write_config(): the new content goes to <file>.tmp first and is read back byte for byte; only a
## file that came out complete replaces the real one (DirAccess.rename_absolute). The file being
## replaced is kept as <file>.prev.bak when it still parses (the last good copy, rewritten on every
## save). load_config(): when the file is unreadable, the last good copy is used (with a warning).
## recover(): after a crash between "copy" and "rename" the real file may be missing while a checked
## .tmp exists; the .tmp then becomes the file. A .tmp next to an existing file is a half-written
## leftover and is removed.
##
## Name of the copy: D-059 already uses <file>.bak for a rejected (broken) file and <file>.v<n>.bak
## for the untouched file before a migration; the rolling copy needs a name of its own so none of
## them overwrites another.
##
## Web build (user:// lives in IndexedDB): Godot only marks the browser storage for syncing when a
## file opened for writing is closed, not after a rename. There the file is written directly after
## the .tmp check (copy and write both close a file, so both are synced). The same direct write is
## the fallback whenever a rename fails.

const TMP_SUFFIX := ".tmp"
## Last good copy of a file (rolling, one per file).
const BACKUP_SUFFIX := ".prev.bak"

## Tests: behave like the web build (direct write after the .tmp check).
static var force_direct_write := false
## Tests: simulate a failing rename (exercises the direct-write fallback).
static var force_rename_failure := false


static func tmp_path(path: String) -> String:
	return path + TMP_SUFFIX


static func backup_path(path: String) -> String:
	return path + BACKUP_SUFFIX


## True where the .tmp file is renamed into place (desktop, mobile); false in the web build.
static func uses_rename() -> bool:
	return not force_direct_write and not OS.has_feature("web")


## Writes config to path crash-safely (see class comment). keep_backup false: the current file is
## not copied to .prev.bak (e.g. it was rejected on load and must not replace the good copy).
## Returns OK or the first error; on an error the existing file is left as it was.
static func write_config(config: ConfigFile, path: String, keep_backup := true) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var expected := config.encode_to_text()
	var tmp := tmp_path(path)
	var err := config.save(tmp)
	if err == OK and FileAccess.get_file_as_string(tmp) != expected:
		err = ERR_FILE_CORRUPT
	if err != OK:
		push_error("SafeSave: could not write %s (%s); %s is unchanged." % [tmp, error_string(err), path])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return err
	if keep_backup and is_readable(path):
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path(path)))
		if copied != OK:
			push_warning("SafeSave: could not keep %s (%s)." % [backup_path(path), error_string(copied)])
	if uses_rename() and _move_into_place(tmp, path) == OK:
		return OK
	# Web build or a failed rename: write directly (the content was checked in the .tmp already).
	err = config.save(path)
	if err == OK and FileAccess.get_file_as_string(path) != expected:
		err = ERR_FILE_CORRUPT
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	if err != OK:
		push_error("SafeSave: could not write %s (%s); last good copy: %s." % [path, error_string(err), backup_path(path)])
	return err


## Loads path into config; an unreadable file falls back to its last good copy (.prev.bak, with a
## warning). Returns the result for path itself (ERR_FILE_NOT_FOUND when it is missing), OK when the
## copy was used instead; from_backup (optional, one bool) tells which.
static func load_config(config: ConfigFile, path: String, from_backup: Array = []) -> Error:
	recover(path)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err := config.load(path)
	if err == OK:
		return OK
	var backup := backup_path(path)
	if FileAccess.file_exists(backup):
		config.clear()
		if config.load(backup) == OK:
			push_warning("SafeSave: %s is unreadable (%s); using the last good copy %s." % [path, error_string(err), backup])
			if not from_backup.is_empty():
				from_backup[0] = true
			return OK
		config.clear()
	return err


## True if path exists and parses as a ConfigFile.
static func is_readable(path: String) -> bool:
	return FileAccess.file_exists(path) and ConfigFile.new().load(path) == OK


## Crash leftovers of write_config(): a checked .tmp whose file went missing becomes the file, a .tmp
## next to an existing file is removed (it was never checked). Returns true if the file was restored.
static func recover(path: String) -> bool:
	var tmp := tmp_path(path)
	if not FileAccess.file_exists(tmp):
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	if not is_readable(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	if _move_into_place(tmp, path) != OK:
		return false
	push_warning("SafeSave: %s was missing after an interrupted save; restored from %s." % [path, tmp])
	return true


## Removes the .tmp and the last good copy of path (a deleted save slot must not come back).
static func remove_companions(path: String) -> void:
	for companion in [tmp_path(path), backup_path(path)]:
		if FileAccess.file_exists(companion):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(companion))


## Renames from onto to (to may exist). Some platforms refuse to rename onto an existing file: then
## the old file is removed first (only after the new one was checked).
static func _move_into_place(from: String, to: String) -> Error:
	if force_rename_failure:
		return FAILED
	var source := ProjectSettings.globalize_path(from)
	var target := ProjectSettings.globalize_path(to)
	var err := DirAccess.rename_absolute(source, target)
	if err != OK and FileAccess.file_exists(to):
		DirAccess.remove_absolute(target)
		err = DirAccess.rename_absolute(source, target)
	if err != OK:
		push_warning("SafeSave: could not rename %s to %s (%s); writing directly." % [from, to, error_string(err)])
	return err
