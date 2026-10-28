class_name VillageGoal
extends RefCounted
## The goal line of the village and the home (P1-2, D-220 point 3, FS6): one rule for "what should I
## do next?", shown at the top left of the village (VillageUI.show_goal) and of the home
## (HomeInterior, P3-9 of the newcomer run: the line must not vanish behind the door).
## - Before the first run: "Steig in den Dungeon hinab" (while VillageGuide.is_active()).
## - After it the next forge goal, the cheapest open step like the run end shows it
##   (RunRecap.next_forge_step): "Noch einmal hinab · noch 33 Gold bis Schildplatte I" while the
##   gold is missing, "Ab zur Schmiede · Schildplatte I" once it is there; after a purchase the next.
## - Nothing once every open forge step is bought.
## Koop: reads the local save only (this player's world and wallet); nothing is sent.
## Texts: the descend goal is the bare key (the label translates itself), the forge goals are built
## in the current language (rebuild them on NOTIFICATION_TRANSLATION_CHANGED).

const DESCEND: StringName = &"VILLAGE_GOAL_DESCEND"
## "Off to the forge · %s" (the step's name).
const FORGE: StringName = &"VILLAGE_GOAL_FORGE"
## "Down once more · %d more gold for %s" (missing gold, the step's name).
const SAVE: StringName = &"VILLAGE_GOAL_SAVE"
const EYEBROW: StringName = &"VILLAGE_GOAL_EYEBROW"
const LADDER_ICON: Texture2D = preload("res://art/ui/symbol_ladder.png")
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
## Top left of the screen (px), like VillageUI.GOAL_MARGIN.
const MARGIN := Vector2(16, 16)
const GuideScript := preload("res://world/village/village_guide.gd")


## The goal due now: {"kind": DESCEND | FORGE | SAVE, "text", "icon", "step" (forge goals)}; {} when
## there is none.
static func current() -> Dictionary:
	if GuideScript.is_active():
		return {"kind": DESCEND, "text": String(DESCEND), "icon": LADDER_ICON}
	var step := RunRecap.next_forge_step()
	if step.is_empty():
		return {}
	var step_name := String(step.get("name", ""))
	var missing := int(step.get("missing", 0))
	if missing <= 0:
		var sign := VillageBuildings.get_sign_texture(VillageBuildings.FORGE)
		return {"kind": FORGE, "text": Loc.t(FORGE, [step_name]), "icon": sign if sign != null else GOLD_ICON, "step": step}
	return {"kind": SAVE, "text": Loc.t(SAVE, [missing, step_name]), "icon": LADDER_ICON, "step": step}


## The goal card (symbol, "Ziel", text) in the look of VillageUI.show_goal, for worlds without a
## VillageUI (the home). Named "Goal" with the text label "GoalText".
static func build_card(text: String, icon: Texture2D) -> PanelContainer:
	var card := UiKit.panel(&"dark")
	card.name = "Goal"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(8)
	var symbol := UiKit.icon(icon if icon != null else LADDER_ICON, 24.0)
	symbol.name = "GoalIcon"
	row.add_child(symbol)
	var caption := UiKit.label(EYEBROW, 15, UiKit.MUTED_COLOR)
	caption.uppercase = true
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var label := UiKit.label(text, 18, UiKit.ACCENT_COLOR)
	label.name = "GoalText"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	card.add_child(row)
	card.position = MARGIN
	return card
