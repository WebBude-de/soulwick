extends GutTest
## WK12 "Dorftiere zum Anfassen" (D-196): chickens are fed, the cat is petted (E). The animal stands
## and looks at the player, a pixel heart rises, the chicken hops and gets grain, the call ("Gack!",
## "Schnurr …") shows; Flint comments the first time per account and kind. Only a player at this
## machine gets a reaction, nothing in the save or the wallet changes. Test folder only
## (SaveManager.set_storage_root, AccountProgress in it), never the real save or progress.cfg.

const ROOT := "user://test_village_animal"
const VILLAGE_SCENE := "res://world/village/village.tscn"
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

var _old_locale: String
var _old_save_path: String
var _old_saves_dir: String
var _old_settings_path: String
var _old_legacy_path: String


func before_all() -> void:
	_old_locale = TranslationServer.get_locale()
	_old_save_path = SaveManager.save_path
	_old_saves_dir = SaveManager.saves_dir
	_old_settings_path = SaveManager.settings_path
	_old_legacy_path = SaveManager.legacy_save_path


func before_each() -> void:
	_wipe()
	SaveManager.set_storage_root(ROOT)
	SaveManager.load_game()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	Loc.apply(&"de")


func after_each() -> void:
	VillageTour.force_in_scripts = false
	GameManager.clear_pause_reasons()


func after_all() -> void:
	_wipe()
	AccountProgress.path_override = ""
	AccountProgress.reset()
	SaveManager.saves_dir = _old_saves_dir
	SaveManager.settings_path = _old_settings_path
	SaveManager.legacy_save_path = _old_legacy_path
	SaveManager.save_path = _old_save_path
	SaveManager.load_settings()
	SaveManager.load_game()
	TranslationServer.set_locale(_old_locale)


func _wipe() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	for dir_path in [root.path_join("saves"), root]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			DirAccess.remove_absolute(dir_path.path_join(file))
	DirAccess.make_dir_recursive_absolute(root.path_join("saves"))


## An animal of kind standing at (100, 100) (two-point route, it waits there first).
func _animal(kind: StringName) -> Villager:
	var villager := Villager.new()
	villager.route = PackedVector2Array([Vector2(100, 100), Vector2(300, 100)])
	villager.art_name = String(kind)
	villager.optional = true
	villager.dodge_sound = &""
	villager.animal = kind
	add_child_autofree(villager)
	return villager


## A player next to the animal (left of it); its guide is stepped by hand.
func _player(near: Villager, local := true) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.is_local = local
	add_child_autofree(player)
	player.global_position = near.get_feet_global() - Villager.FEET_OFFSET + Vector2(-40, 0)
	if local:
		FlintGuide.for_player(player).set_process(false)
	return player


func test_every_kind_has_texts_in_both_languages() -> void:
	var translations := Loc.load_csv(Loc.CSV_PATH)
	for kind: StringName in VillageAnimal.KINDS:
		var info: Dictionary = VillageAnimal.KINDS[kind]
		for field in ["prompt", "call", "flint"]:
			var key: StringName = info[field]
			assert_true(String(key).begins_with("VILLAGE_ANIMAL_"), "%s.%s: %s" % [kind, field, key])
			for language: StringName in Loc.LANGUAGES:
				var text := String((translations[language] as Translation).get_message(key))
				assert_false(text.is_empty() or text == String(key), "%s has %s" % [key, language])
	assert_eq(Loc.t(&"VILLAGE_ANIMAL_FEED"), "Füttern")
	assert_eq(Loc.t(&"VILLAGE_ANIMAL_PET"), "Streicheln")


func test_flint_comments_fit_his_bubble() -> void:
	var translations := Loc.load_csv(Loc.CSV_PATH)
	var font := UiKit.get_font()
	var width := UiKit.px(FlintGuideView.BUBBLE_WIDTH)
	var size := UiKit.font_px(FlintGuideView.TEXT_SIZE)
	for kind: StringName in VillageAnimal.KINDS:
		var comment := VillageAnimal.flint_comment(kind)
		assert_true(comment.is_valid(), "%s" % [comment.problems()])
		assert_eq(comment.style, FlintExplanation.Style.HINT, "no camera, no lock")
		assert_true(comment.once, "once per account")
		assert_true(String(comment.id).begins_with(FlintExplanation.ID_PREFIX), String(comment.id))
		var key := comment.steps[0].text_key
		for language: StringName in Loc.LANGUAGES:
			var text := String((translations[language] as Translation).get_message(key))
			assert_lte(FlintGuideRules.line_count(text, font, size, width), FlintGuideRules.MAX_LINES,
					"%s (%s) fits two lines: %s" % [key, language, text])


func test_a_chicken_is_fed_and_a_cat_is_petted() -> void:
	var chicken := _animal(&"chicken")
	var cat := _animal(&"cat")
	assert_not_null(chicken.get_animal(), "the chicken reacts")
	assert_not_null(cat.get_animal(), "the cat reacts")
	assert_eq(chicken.get_animal().prompt, "VILLAGE_ANIMAL_FEED")
	assert_eq(cat.get_animal().prompt, "VILLAGE_ANIMAL_PET")
	assert_true(chicken.get_animal() is Interactable, "E like a door")
	assert_eq(chicken.get_animal().collision_layer, PhysicsLayers.INTERACTION)


func test_villagers_without_a_kind_have_no_reaction() -> void:
	var villager := Villager.new()
	villager.route = PackedVector2Array([Vector2.ZERO, Vector2(10, 0)])
	villager.art_name = "villager_1"
	villager.fallback_frames = load("res://art/characters/npcs/smith_frames.tres")
	add_child_autofree(villager)
	assert_null(villager.get_animal())


func test_feeding_a_chicken_hops_scatters_grain_clucks_and_shows_a_heart() -> void:
	var chicken := _animal(&"chicken")
	var player := _player(chicken)
	var animal := chicken.get_animal()
	assert_true(animal.react(player))
	assert_true(chicken.is_holding(), "stands for the player")
	assert_true(chicken.get_sprite().flip_h, "looks left at the player")
	assert_eq(animal.get_heart_count(), 1, "a heart")
	assert_not_null(animal.get_grain(), "grain on the ground")
	assert_not_null(animal.get_call(), "the call shows")
	assert_eq(animal.get_call().text, "VILLAGE_ANIMAL_CLUCK")
	assert_eq(tr(animal.get_call().text), "Gack!")
	var highest := Villager.FEET_OFFSET.y
	for i in 30:
		await wait_process_frames(1)
		highest = minf(highest, chicken.get_sprite().position.y)
	assert_lt(highest, Villager.FEET_OFFSET.y - 1.0, "a hop")
	# It stands while the reaction lasts: it does not walk its route.
	var feet := chicken.get_feet_global()
	await wait_seconds(1.0)
	assert_almost_eq(chicken.get_feet_global().x, feet.x, 0.5, "stands still")


func test_petting_the_cat_purrs_with_two_hearts_and_no_hop() -> void:
	var cat := _animal(&"cat")
	var player := _player(cat)
	var animal := cat.get_animal()
	assert_true(animal.react(player))
	assert_eq(animal.get_call().text, "VILLAGE_ANIMAL_PURR")
	assert_null(animal.get_grain(), "no grain for the cat")
	for i in 20:
		await wait_process_frames(1)
		assert_almost_eq(cat.get_sprite().position.y, Villager.FEET_OFFSET.y, 0.01, "the cat does not hop")
	await wait_seconds(VillageAnimal.HEART_GAP + 0.05)
	assert_eq(animal.get_heart_count(), 2, "two hearts")


func test_hearts_rise_in_whole_pixels_and_go() -> void:
	var cat := _animal(&"cat")
	var animal := cat.get_animal()
	animal.react(_player(cat))
	await wait_seconds(0.4)
	for child in cat.get_children():
		var heart := child as Sprite2D
		if heart == null or heart.name.begins_with("Heart") == false or not heart.visible:
			continue
		assert_eq(fmod(heart.position.x, VillageArt.SCALE), 0.0, "x on the art grid")
		assert_eq(heart.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp pixels")
	await wait_seconds(VillageAnimal.HEART_TIME + VillageAnimal.HEART_GAP)
	assert_eq(animal.get_heart_count(), 0, "hearts are gone")


func test_a_new_reaction_waits_for_the_cooldown() -> void:
	var chicken := _animal(&"chicken")
	var player := _player(chicken)
	var animal := chicken.get_animal()
	assert_true(animal.react(player))
	assert_false(animal.react(player), "not twice at once")
	await wait_seconds(VillageAnimal.COOLDOWN + 0.1)
	assert_true(animal.react(player), "again after the cooldown")
	assert_eq(animal.get_reactions(), 2)


func test_a_player_at_another_machine_gets_no_reaction() -> void:
	var chicken := _animal(&"chicken")
	var guest := _player(chicken, false)
	var animal := chicken.get_animal()
	assert_false(animal.react(guest), "the remote copy of a guest")
	assert_false(chicken.is_holding())
	assert_eq(animal.get_heart_count(), 0)
	assert_null(animal.get_call())


func test_flint_comments_the_first_time_per_kind_only() -> void:
	VillageTour.force_in_scripts = true
	var chicken := _animal(&"chicken")
	var player := _player(chicken)
	var guide := FlintGuide.of(player)
	assert_true(chicken.get_animal().react(player))
	var id := VillageAnimal.flint_id(&"chicken")
	assert_eq(id, &"flint_village_animal_chicken")
	assert_true(guide.is_known(id), "Flint comments the first feeding")
	for i in 600:
		if guide.phase == FlintGuide.Phase.IDLE:
			break
		guide.advance(1.0 / 60.0)
	assert_eq(guide.phase, FlintGuide.Phase.IDLE, "the hint closes by itself")
	assert_true(AccountSeen.has_seen(id), "seen for the account")
	await wait_seconds(VillageAnimal.COOLDOWN + 0.1)
	assert_true(chicken.get_animal().react(player))
	assert_false(guide.is_known(id), "not again")


func test_script_runs_get_no_flint_comment() -> void:
	var cat := _animal(&"cat")
	var player := _player(cat)
	assert_true(cat.get_animal().react(player))
	assert_false(FlintGuide.of(player).is_known(VillageAnimal.flint_id(&"cat")), "only when forced in tests")


func test_reactions_have_no_game_effect() -> void:
	var gold := SaveManager.get_permanent_gold()
	var crystals := SaveManager.get_permanent_crystals()
	var chicken := _animal(&"chicken")
	var player := _player(chicken)
	chicken.get_animal().react(player)
	await wait_seconds(0.2)
	assert_eq(SaveManager.get_permanent_gold(), gold, "no gold")
	assert_eq(SaveManager.get_permanent_crystals(), crystals, "no crystals")
	assert_eq(player.health.get_health(), player.health.max_health, "no heal or damage")


func test_the_village_animals_all_react() -> void:
	var village: Village = (load(VILLAGE_SCENE) as PackedScene).instantiate()
	add_child_autofree(village)
	var kinds := {}
	for node in village.get_node("Villagers").get_children():
		var walker := node as Villager
		if walker == null or walker.is_queued_for_deletion():
			continue
		if walker.art_name in ["chicken", "cat", "dog"]:
			assert_ne(walker.animal, &"", "%s has a kind" % walker.name)
			assert_not_null(walker.get_animal(), "%s reacts" % walker.name)
			kinds[walker.animal] = true
	assert_true(kinds.has(&"chicken"), "chickens in the yard")
	assert_true(kinds.has(&"cat"), "the cat")


func test_pressing_e_next_to_the_cat_pets_it() -> void:
	var cat := _animal(&"cat")
	var player := _player(cat)
	player.global_position = cat.get_feet_global() - Villager.FEET_OFFSET + Vector2(-30, 0)
	await wait_physics_frames(4)
	var input := RemoteInput.new()
	player.input = input
	input.tap(&"interact")
	await wait_physics_frames(3)
	assert_eq(cat.get_animal().get_reactions(), 1, "E pets the cat")
