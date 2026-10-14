extends SceneTree
## Captures screenshots of key screens for visual review (needs a window, not --headless).
## Usage: godot --path . -s tools/screenshots.gd -- <output_dir>

## Test folder for slots, settings and the pre-slot save (SaveManager.set_storage_root).
const STORAGE_ROOT := "user://screenshot_storage"

var _out_dir := "user://screenshots"


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Slots, settings and the old save live in a test folder: the real save is never touched.
	# Buttons are found by their German texts; English is the default language (D-111).
	TranslationServer.set_locale("de")
	var save_manager := root.get_node("SaveManager")
	_wipe(STORAGE_ROOT)
	save_manager.set_storage_root(STORAGE_ROOT)
	save_manager.set_option(&"language", "de")
	save_manager.create_slot(1, "Lena", &"hero")
	save_manager.add_permanent_gold(240)
	save_manager.add_permanent_crystals(3)
	save_manager.record_stat_max(&"deepest_room", 23)
	save_manager.add_stat(&"play_time", 3900.0)
	save_manager.save_game()

	change_scene_to_file("res://scenes/main.tscn")
	# Real time: the menu fades in, frames may run uncapped.
	await _seconds(2.0)
	_shot("01_main_menu")
	var menu: Node = current_scene.get("menu")
	menu.open_slots()
	await _seconds(0.3)
	_shot("01b_slots")
	var create: Node = menu.open_create(2)
	await _frames(5)
	create.set_profile_name("Mira")
	await _seconds(0.3)
	_shot("01c_create_slot")
	create.close()
	await _frames(5)
	# Continue with slot 1 like the player: fade out, then game.tscn.
	menu.close_panel()
	menu.play_slot(1)
	await _seconds(1.2)
	await _frames(30)
	_shot("02_village")

	# Zuhause: explanation on the first visit, then the wardrobe with a new colour.
	var village: Node = current_scene.get_node("WorldController").get_world()
	village.enter_building(&"home")
	await _seconds(0.4)
	_shot("02b_home_intro")
	village.ui.get_intro_modal().finish()
	await _frames(5)
	village.ui.put_on_color(1)
	village.ui._request_refresh()
	await _seconds(0.4)
	_shot("02c_wardrobe")
	village.ui.get_building_modal().finish()
	await _frames(10)

	var controller := current_scene.get_node("WorldController")
	controller.enter_dungeon()
	await _frames(70)
	_shot("03_dungeon_room1")

	var player: Node = controller.get_player()
	var dungeon: Node = controller.get_world()
	# Aim and attack once so the swing effect is visible.
	Input.action_press(&"attack")
	await _frames(4)
	_shot("04_attack")
	Input.action_release(&"attack")
	await _frames(60)
	_shot("05_combat")

	# Screen effects in the dark room: hit (chromatic aberration) with stun (tilt + wobble).
	var hit := DamageData.new()
	hit.amount = 1.0
	hit.stun_duration = 0.8
	player.hurtbox.receive_hit(hit)
	await _frames(3)
	_shot("08_hit")
	await _frames(14)
	_shot("09_stunned")
	await _frames(60)

	# Jump to the special room (room 4) via rooms 2 and 3.
	for index in [2, 3, 4]:
		var room: Node = dungeon.get_room(index)
		for enemy in dungeon.get_room(index - 1).enemy_container.get_children():
			if enemy.has_method("is_dead") and not enemy.is_dead():
				enemy.health.take_damage(9999.0)
		await _frames(30)
		_close_modals(root)
		await _frames(10)
		player.global_position = room.to_global(room.get_node("Tiles").get_floor_rect().get_center() + Vector2(0, 120))
		player.get_node("Camera2D").reset_smoothing()
		await _frames(50)
	_shot("06_special_room")
	var ui: Node = dungeon.get_node("DungeonUI")
	ui.show_upgrade_overview()
	await _frames(10)
	_shot("07_upgrade_overview")
	_close_modals(root)
	await _frames(5)

	# Wait for the delayed reward dialog of the previous room and close everything.
	await _settle()
	# Blindness (blur + fog) and low HP (desaturation, heartbeat) in the lit special room.
	player.blind(4.0)
	await _seconds(0.6)
	_shot("10_blinded")
	await _seconds(4.5)
	player.health.take_damage(player.health.get_health() - 1.0)
	await _seconds(0.8)
	await _settle()
	_shot("11_low_hp")
	player.health.heal(5.0)
	# Biome look: ember forge darkness colour and ember particles in a dark room.
	var vision: Node = current_scene.get_node("VisionOverlay")
	vision.set_vision(0.97, 300.0, true)
	vision.set_biome(load("res://dungeon/biomes/ember_forge.tres"), true)
	await _seconds(1.0)
	_shot("12_biome_ember")
	quit()


func _wipe(folder: String) -> void:
	var absolute := ProjectSettings.globalize_path(folder)
	for dir_path in [absolute.path_join("saves"), absolute]:
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(absolute)


func _close_modals(node: Node) -> void:
	for child in node.get_children():
		if child.get_script() != null and child.get_script().get_global_name() == &"Modal":
			for button in _buttons(child):
				if button.text in ["Wählen", "Schließen"]:
					button.pressed.emit()
					break
			if child.cancel_allowed:
				child.finish(child.cancel_result)
		else:
			_close_modals(child)


func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons(child))
	return result


func _shot(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(_out_dir.path_join(name + ".png"))
	print("saved ", name)


## Closes dialogs that pop up with a delay (D-070) until none is left.
func _settle() -> void:
	for i in 6:
		_close_modals(root)
		await _seconds(0.4)


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame
