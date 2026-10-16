extends SpecialContent
## Regular exit portal (30 % of special rooms, D-006): E + confirmation ends the run with 100 % gold.

const PORTAL_TEXTURE: Texture2D = preload("res://art/environment/props/exit_portal_6f.png")


func _on_prepare() -> void:
	add_light(170.0, Vector2(0, -40))
	# M2: the dark fill above the swirl is see-through (DoorArt.open_fill).
	add_animated(DoorArt.open_fill(PORTAL_TEXTURE, DoorArt.PORTAL_FILL), Vector2i(32, 48), 8.0, Vector2(16, 46))
	var interactable := add_interactable(DungeonTexts.t(&"PORTAL_PROMPT"), 48.0, Vector2(0, -30))
	interactable.interacted.connect(_on_interacted)
	add_caption(DungeonTexts.t(&"PORTAL_CAPTION"), Vector2(0, -116))


func _on_interacted(_player: Player) -> void:
	var gold := RunManager.get_run_gold()
	var confirmed: bool = await context.ui.confirm(
		DungeonTexts.t(&"PORTAL_QUESTION"),
		DungeonTexts.t(&"PORTAL_TEXT", [gold]),
		DungeonTexts.t(&"PORTAL_LEAVE"), DungeonTexts.t(&"PORTAL_STAY"),
		[[Loc.t(&"GAME_UI_RUN_GOLD"), str(gold), UiKit.COLOR_GOLD], [DungeonTexts.t(&"RUNEND_PAYOUT", ["100 %"]), str(gold), UiKit.COLOR_SUCCESS]])
	if confirmed:
		Sfx.play_ui(self, &"portal")
		context.manager.end_run(RunManager.EndReason.EXIT)
