extends SpecialContent
## Regular exit portal (30 % of special rooms, D-006): E + confirmation ends the run with 100 % gold.

const PORTAL_TEXTURE: Texture2D = preload("res://art/environment/props/exit_portal_6f.png")


func _on_setup() -> void:
	add_light(170.0, Vector2(0, -40))
	add_animated(PORTAL_TEXTURE, Vector2i(32, 48), 8.0, Vector2(16, 46))
	var interactable := add_interactable("Dungeon verlassen", 48.0, Vector2(0, -30))
	interactable.interacted.connect(_on_interacted)
	add_caption("Ausgang", Vector2(0, -116))


func _on_interacted(_player: Player) -> void:
	var gold := RunManager.get_run_gold()
	var confirmed: bool = await context.ui.confirm(
		"Dungeon verlassen?",
		"Der Run endet. Du nimmst 100 %% deines Run-Goldes mit (%d Gold)." % gold,
		"Verlassen", "Weiterspielen",
		[["Run-Gold", str(gold), UiKit.COLOR_GOLD], ["Gutschrift (100 %)", str(gold), UiKit.COLOR_SUCCESS]])
	if confirmed:
		Sfx.play_ui(self, &"portal")
		context.manager.end_run(RunManager.EndReason.EXIT)
