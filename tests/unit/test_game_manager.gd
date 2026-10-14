extends GutTest
## Multiple independent pause reasons (D-043).


func after_each() -> void:
	GameManager.clear_pause_reasons()


func test_pause_holds_until_all_reasons_released() -> void:
	GameManager.request_pause(GameManager.PAUSE_SHOP)
	GameManager.request_pause(GameManager.PAUSE_MENU)
	assert_true(GameManager.is_game_paused())
	assert_true(get_tree().paused)

	GameManager.release_pause(GameManager.PAUSE_SHOP)
	assert_true(GameManager.is_game_paused(), "Pause menu reason is still active")

	GameManager.release_pause(GameManager.PAUSE_MENU)
	assert_false(GameManager.is_game_paused())
	assert_false(get_tree().paused)


func test_releasing_unknown_reason_is_harmless() -> void:
	GameManager.release_pause(&"never_requested")
	assert_false(GameManager.is_game_paused())


func test_clear_drops_stale_reasons() -> void:
	GameManager.request_pause(GameManager.PAUSE_UPGRADE_OVERVIEW)
	GameManager.clear_pause_reasons()
	assert_false(get_tree().paused)
