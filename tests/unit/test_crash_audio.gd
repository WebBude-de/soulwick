extends GutTest
## Segfault of the balance bot (Oct 2026): Godot's AudioServer frees replaced bus data of a playback
## two frames later, while its mixer thread may still copy it (AudioServer::_mix_step reads a freed
## StringName). Positional sound effects replace that data every frame; at the bot's uncapped frame
## rate two frames are far less than a mixing step, so about every third bow/staff process crashed.
## The bot therefore runs without sound (tools/balance_sim.gd, audio=0): it marks every sound effect
## as missing in the Sfx cache. These tests pin the Sfx behaviour that relies on.

const SFX_DIR := "res://audio/sfx/"


var _context: Node2D
var _added: Array[Node] = []


func before_each() -> void:
	_context = Node2D.new()
	add_child_autofree(_context)
	_added.clear()
	get_tree().node_added.connect(_on_node_added)


func after_each() -> void:
	get_tree().node_added.disconnect(_on_node_added)
	for node in _added:
		if is_instance_valid(node):
			node.queue_free()


func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer2D or node is AudioStreamPlayer:
		_added.append(node)


## The same listing the bot uses (tools/balance_sim.gd, _silence_sfx).
func _sound_names() -> Array[StringName]:
	var names: Array[StringName] = []
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return names
	for file in dir.get_files():
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension() == "wav" and not names.has(StringName(name.get_basename())):
			names.append(StringName(name.get_basename()))
	return names


func test_the_bot_finds_the_sound_effects() -> void:
	var names := _sound_names()
	assert_gt(names.size(), 10, "audio/sfx lists the effects")
	assert_true(names.has(&"bow_shot"), "the bow shot is one of them")


func test_a_sound_cached_as_missing_creates_no_player() -> void:
	var sound := &"bow_shot"
	var had := Sfx._cache.has(sound)
	var previous: Variant = Sfx._cache.get(sound)
	Sfx._last_played.erase(sound)
	Sfx.play_at(_context, sound, Vector2.ZERO)
	assert_eq(_added.size(), 1, "normally a positional player plays the sound")
	Sfx._cache[sound] = null
	Sfx._last_played.erase(sound)
	Sfx.play_at(_context, sound, Vector2.ZERO)
	Sfx.play_ui(_context, sound)
	assert_eq(_added.size(), 1, "a sound marked missing creates no player")
	if had:
		Sfx._cache[sound] = previous
	else:
		Sfx._cache.erase(sound)
	Sfx._last_played.erase(sound)
