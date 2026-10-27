class_name VillageUI
extends CanvasLayer
## Village building dialogs (D-078): Schmiede (permanent upgrades), Handelsposten (Proviant and
## trade levels for crystals, KE5; no crystal exchange since D-087), Chronik (statistics), Gilde (the online menu of D-147, OnlineMenu:
## quick game with a room code on the relay and the player's guilds with guild rooms; the same menu
## as "Online spielen" in the main menu) and Zuhause with the profile editor (D-152: name, figure and
## colours of the player, the same editor as the mirror next to it, the first start and the lobby).
## Created by Village; every dialog is a Modal and pauses the village while open (single player
## only: in a room the world runs on, GameMode.pauses_for_menus).
## D-087, WK9: on the first visit Flint explains the building before its dialog opens
## (explain_building, VillageTour: role and a tip, once per account; the old explanation card is gone),
## the role sentence stays as dialog subtitle and the info button next to the title asks Flint again
## (the dialog closes while he talks, single player pauses the village, and opens again after him).
## Locked forge upgrades (MetaUnlocks) are not shown; one line with a lock says when more open.
## KE4 (KONZEPT §5.1): the forge is one compact row per weapon ("Waffe schmieden" I–V with the real
## damage "Schaden 15 → 16,2", the Arsenal entry or the start choice) and one per equipment
## (Schildplatte, Laterne, Zweiter Startplatz); after the v5 migration a box on top says once what
## changed (refund, Schildplatte, unlocked weapons).
## The chronicle shows "Dein Fortschritt" (ProgressView, D-188 KF1) next to its statistics.
## Short non-blocking notices (show_notice): "Neu freigeschaltet" and "Öffnet nach …" at locked doors.
## Texts come from localization/translations.csv (D-111) and are resolved when a dialog is built.
## P1-2 (VillageGuide decides when): the goal line top left ("Steig in den Dungeon hinab",
## show_goal) until the first run. The chronicler's opening words are replaced by Flint's village
## tour (WK9, VillageTour, started by Village.on_player_spawned).
## P1-3 "Was kann ich mir leisten?": affordable forge levels and Proviant get a gold card and a
## "Leistbar" tag, the others say what is missing ("Noch 28 Gold"). show_goal takes an icon (the
## forge goal of Village). Gamepad (P1-3): the building dialogs move a visible focus with the D-pad
## or stick, A presses, B closes (Modal, ui_cancel); keyboard arrows do the same. The focus starts on
## the first affordable entry when the gamepad is in use, otherwise with the first arrow key.
## Reports 17.10.2026: every button of the dialogs is a UiKit.dialog_button (bold, the dialog size of
## the online menu, #181dfb78); affordable cards change only their frame colour, and the line under a
## card stays (invisible) once bought or maxed, so the dialog keeps its size after a purchase
## (#bf9c698d); the forge keeps level and "Noch N Gold" on one line and fits a 720 px high screen
## without scrolling (#0efb405c).
## KE1 (D-196, KONZEPT §3): near the dungeon entrance a card shows rank, danger level and loot bonus,
## only for show (the level is never picked). Solo it is the own level; in a group the level the
## host computed (set_group_danger, KE2). When the village asks for the dungeon (dungeon_requested)
## the shown level goes to RunManager.set_danger_level before the run starts.
## Report #d1a7f411 (23.10.2026, "Man sollte nicht runter scrollen müssen zum Close-Button"): only
## the body of a building dialog scrolls (BodyScroll, as tall as the screen allows); title,
## currencies and "Schließen" stay visible. The D-pad focus scrolls the body (follow_focus), the
## right stick scrolls it (Modal.scroll_target), touch drags it.

const PAUSE_VILLAGE_DIALOG: StringName = &"village_dialog"
## P1-3: what the village marks as affordable (preloaded: works before the class cache knows it).
const AffordableScript := preload("res://world/village/village_affordable.gd")
const CARD_WIDTH := 240.0
## Width of "Dein Fortschritt" next to the chronicle's statistics (mockup px, D-188 KF1).
const CHRONICLE_PROGRESS_WIDTH := 210.0
## Width of the profile editor in the village dialogs (mockup px).
const PROFILE_EDITOR_WIDTH := 262.0
const GOLD_ICON: Texture2D = preload("res://art/ui/gold_icon.png")
const CRYSTAL_ICON: Texture2D = preload("res://art/ui/crystal_icon.png")
const INFO_ICON: Texture2D = preload("res://art/ui/icon_info.png")
const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
## Notice at the top of the screen: seconds visible (plus fade), fade time, top margin in px
## (R7, 07_ui.md: below the HUD row, whose gold panel ends at about 90 px).
const NOTICE_TIME := 4.0
const NOTICE_FADE := 0.4
const NOTICE_TOP := 104.0
const NOTICE_TEXT_WIDTH := 520.0
const LADDER_ICON: Texture2D = preload("res://art/ui/symbol_ladder.png")
## Goal line at the top left (px; the village HUD has its currencies top right, records bottom left).
const GOAL_MARGIN := Vector2(16, 16)
## P1-3: affordable cards and the gamepad focus frame (px).
const AFFORDABLE_COLOR := UiKit.COLOR_GOLD
const MISSING_COLOR := UiKit.COLOR_DANGER_SOFT
const FOCUS_BORDER := 3
## The colour of the focused button text and its frame.
const FOCUS_COLOR := Color("#fff1a8")
## Width of "Schließen", "Verstanden" and the weapon choice (mockup px): like the online menu's buttons.
const BUTTON_WIDTH := OnlineMenu.BUTTON_WIDTH
## Card padding in mockup px (vertical, horizontal): the dark and the gold frame alike (#bf9c698d).
const CARD_PADDING := Vector2(4, 6)
## Gap between the rows of a card (px).
const CARD_GAP := 4
## Forge icons (SPRITES_V13 §B7, art/ui/forge/): loaded when delivered, else these placeholders.
const FORGE_ICON_DIR := "res://art/ui/forge/"
const FORGE_ICONS := {
	MetaProgression.SECOND_SLOT: ["forge_second_slot.png", "res://art/ui/meta_arsenal.png"],
	MetaProgression.SHIELD_PLATE: ["forge_shield_plate.png", "res://art/ui/meta_shield.png"],
	MetaProgression.LANTERN: ["forge_lantern.png", "res://art/environment/objectives/relic_lantern.png"],
}
## Weapon icons of the forge rows (art/ui/icon_<weapon>.png, delivered).
const WEAPON_ICON_PATH := "res://art/ui/icon_%s.png"
## Forge rows (mockup px → px via the label sizes): widths of name, value step, "Leistbar" line,
## buy button and the start/Arsenal cell, so the rows line up like a table and fit 720 px (KE4).
const FORGE_ROW_PADDING := Vector2(1, 5)
const FORGE_NAME_WIDTH := 170.0
const FORGE_STEP_WIDTH := 300.0
const FORGE_AFFORD_WIDTH := 120.0
const FORGE_BUY_WIDTH := 110.0
const FORGE_START_WIDTH := 170.0
const FORGE_ICON_SIZE := 28.0
const FORGE_NOTICE_WIDTH := 880.0
## Trading post icons (SPRITES_V13 §B7, art/ui/trading/, delivered): boost_<id>.png per Proviant,
## trade_slot/trade_luck/trade_merchant_friend.png per trade level.
const TRADING_ICON_DIR := "res://art/ui/trading/"
const TRADE_ICON_FILES := {
	MetaProgression.TRADE_PROVISION_SLOT: "trade_slot.png",
	MetaProgression.TRADE_LUCK: "trade_luck.png",
	MetaProgression.TRADE_MERCHANT_FRIEND: "trade_merchant_friend.png",
}
## Proviant cards per row (7 cards: 4 + 3, so the page with the trade levels fits 720 px).
## #d1a7f411 (TESTWERT, mockup px): room kept free above and below the dialog, scroll bar room, and
## the body is never lower than BODY_MIN_HEIGHT.
const SCREEN_GAP := 8.0
const BODY_SCROLL_BAR := 6.0
const BODY_MIN_HEIGHT := 48.0
const MobileUiScript := preload("res://ui/menus/mobile_ui.gd")
const TRADER_COLUMNS := 4
## Chronicle rows: stat id -> translation key of its caption (D-111).
const STAT_ROWS := [
	[StatsTracker.RUNS, &"VILLAGE_UI_STAT_RUNS"],
	[StatsTracker.DEATHS, &"VILLAGE_UI_STAT_DEATHS"],
	[StatsTracker.EXITS, &"VILLAGE_UI_STAT_EXITS"],
	[StatsTracker.DEEPEST_ROOM, &"VILLAGE_UI_STAT_DEEPEST_ROOM"],
	[StatsTracker.ROOMS_CLEARED, &"VILLAGE_UI_STAT_ROOMS_CLEARED"],
	[StatsTracker.KILLS, &"VILLAGE_UI_STAT_KILLS"],
	[StatsTracker.CHAMPIONS, &"VILLAGE_UI_STAT_CHAMPIONS"],
	[StatsTracker.BOSSES, &"VILLAGE_UI_STAT_BOSSES"],
	[StatsTracker.GOLD_EARNED, &"VILLAGE_UI_STAT_GOLD_EARNED"],
	[StatsTracker.GOLD_BANKED, &"VILLAGE_UI_STAT_GOLD_BANKED"],
	[StatsTracker.BEST_RUN_GOLD, &"VILLAGE_UI_STAT_BEST_RUN_GOLD"],
	[StatsTracker.CRYSTALS_EARNED, &"VILLAGE_UI_STAT_CRYSTALS_EARNED"],
]

var _open_modal: Modal = null
## True from the door until the building dialog is closed (covers Flint's explanation in between).
var _busy := false
## The building Flint explains right now (&"" otherwise) and the one whose info button asked him.
var _explaining: StringName = &""
var _replay_intro: StringName = &""
var _build: Callable
var _body: VBoxContainer = null
## #d1a7f411: the scroll area around _body (null while no building dialog is open).
var _body_scroll: ScrollContainer = null
var _fit_queued := false
var _currencies: HBoxContainer = null
var _notice_root: Control = null
var _notice: Control = null
## The online menu of the open guild dialog (null otherwise).
var _online_menu: OnlineMenu = null
## P1-2: goal line (null while not shown).
var _goal: Control = null
## KE1: the dungeon entrance the card belongs to (Village sets it or it is found under the parent at
## ENTRANCE_NODE), the group level from the host (-1 = solo, the own level) and the card.
var entrance_anchor: Node2D = null
var _group_danger := -1
var _entrance_card: Control = null
## KE4: what the v5 migration did, shown once at the top of the forge (empty otherwise).
var _forge_notice: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_notice_root = Control.new()
	_notice_root.name = "NoticeRoot"
	_notice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_notice_root)
	UiKit.MobileUi.fit_to_safe_area(_notice_root)
	_resume_lobby.call_deferred()
	_hook_entrance()


func is_dialog_open() -> bool:
	return _busy or _open_modal != null


## True while Flint explains a building (before its dialog opens or from the info button).
func is_intro_open() -> bool:
	return _explaining != &""


## The building Flint explains right now (&"" otherwise), for tests and tools.
func get_explaining() -> StringName:
	return _explaining


## Always null since WK9: Flint explains the buildings, there is no explanation card any more. Kept
## for tools that still close the card (screenshots, scene_gallery; integrator: let them skip
## Flint, FlintGuide.of(player).skip()).
func get_intro_modal() -> Modal:
	return null


## The open building dialog (null if none), e.g. for tests and tools.
func get_building_modal() -> Modal:
	return _open_modal


# --- Schmiede ---

func open_forge() -> void:
	# The migration notice of v5 (KE4) is shown once, on the first forge visit after loading.
	_forge_notice = MetaProgression.take_migration_notice()
	if not _forge_notice.is_empty():
		SaveManager.save_game()
	await _open(VillageBuildings.FORGE, _build_forge)
	_forge_notice = []


func _build_forge(body: VBoxContainer, refresh: Callable) -> void:
	if not _forge_notice.is_empty():
		body.add_child(_forge_notice_box(_forge_notice))
	var rows := UiKit.vbox(CARD_GAP)
	rows.name = "ForgeRows"
	body.add_child(rows)
	for weapon in MetaProgression.WEAPON_ORDER:
		rows.add_child(_weapon_row(weapon, refresh))
	# Locked upgrades stay hidden until they open (D-087); one line says when more come.
	for id in MetaProgression.EQUIPMENT_UPGRADES:
		if MetaUnlocks.is_upgrade_open(id):
			rows.add_child(_equipment_row(id, refresh))
	for event in MetaUnlocks.get_locked_upgrade_events():
		var hint := _lock_row(MetaUnlocks.get_forge_lock_text(event))
		hint.name = "LockedUpgradesHint"
		body.add_child(hint)


## "Die Schmiede ist neu" with the lines of MetaProgression.describe_migration (KE4).
func _forge_notice_box(lines: Array[String]) -> Control:
	var card := UiKit.panel(&"gold")
	card.name = "ForgeMigrationNotice"
	card.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", CARD_PADDING.x, CARD_PADDING.y))
	var box := UiKit.vbox(2)
	card.add_child(box)
	box.add_child(_centered(UiKit.label(Loc.t(&"FORGE_MIGRATION_TITLE"), 18, UiKit.ACCENT_COLOR)))
	var text := UiKit.wrapped_label(" ".join(lines), FORGE_NOTICE_WIDTH, 14)
	text.name = "ForgeMigrationText"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	return card


## One weapon: icon, name with its level, the damage step with real values, "Leistbar"/"Noch N Gold",
## the "Waffe schmieden" button and the start cell (Arsenal entry or start choice).
func _weapon_row(weapon: StringName, refresh: Callable) -> Control:
	var id := MetaProgression.smith_id(weapon)
	var row := _forge_row(id, load(WEAPON_ICON_PATH % weapon) as Texture2D, MetaProgression.get_weapon_name(weapon), refresh)
	row.add_child(_start_cell(weapon, refresh))
	return row.get_parent()


func _equipment_row(id: StringName, refresh: Callable) -> Control:
	var row := _forge_row(id, _forge_icon(id), MetaProgression.get_upgrade_name(id), refresh)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = FORGE_START_WIDTH
	row.add_child(spacer)
	return row.get_parent()


## A dark (or, when affordable, gold) row with icon, name and level, value step, afford line and buy
## button; returns the row's HBox (card = get_parent()). Buy_<id> sits next to its afford line, so
## the line is found under button.get_parent() like on the cards.
func _forge_row(id: StringName, icon: Texture2D, title: String, refresh: Callable) -> HBoxContainer:
	var card := UiKit.panel(&"dark")
	card.name = "Row_%s" % id
	card.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", FORGE_ROW_PADDING.x, FORGE_ROW_PADDING.y))
	var row := UiKit.hbox(10)
	card.add_child(row)
	var level := MetaProgression.get_level(id)
	var max_level := MetaProgression.get_max_level(id)
	if icon != null:
		var image := UiKit.icon(icon, FORGE_ICON_SIZE)
		image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(image)
	var name_box := UiKit.vbox(0)
	name_box.custom_minimum_size.x = FORGE_NAME_WIDTH
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_child(UiKit.label(title, 16, UiKit.ACCENT_COLOR))
	var level_label := UiKit.label(Loc.t(&"VILLAGE_UI_LEVEL", [level, max_level]), 13, UiKit.MUTED_COLOR)
	level_label.name = "LevelLabel"
	name_box.add_child(level_label)
	row.add_child(name_box)
	# Real values instead of "+8 % je Stufe" (D-087): "Schaden 15 → 16,2".
	var step := UiKit.label(MetaProgression.describe_level_step(id, level), 15, UiKit.ACCENT_COLOR)
	step.name = "StepLabel"
	step.custom_minimum_size.x = FORGE_STEP_WIDTH
	step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	step.tooltip_text = MetaProgression.get_upgrade_effect(id)
	step.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(step)
	var cost := MetaProgression.get_next_cost(id)
	var buy := _card_button("Max." if cost < 0 else Loc.t(&"VILLAGE_UI_GOLD", [cost]), func() -> void:
		if MetaProgression.try_buy(id):
			Sfx.play_ui(self, &"coin")
		refresh.call())
	buy.name = "Buy_%s" % id
	buy.custom_minimum_size.x = FORGE_BUY_WIDTH
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not MetaProgression.can_buy(id)
	var affordable := cost >= 0 and not buy.disabled
	var line := _afford_label(card, buy, affordable, AffordableScript.gold_missing(id), &"VILLAGE_UI_MISSING_GOLD")
	line.custom_minimum_size.x = FORGE_AFFORD_WIDTH
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(line)
	row.add_child(buy)
	return row


## The start cell of a weapon row: an unlocked weapon picks the start loadout (Start_<weapon>), a
## locked one shows its Arsenal entry (Buy_arsenal_<weapon>) or, before the first boss, a lock.
func _start_cell(weapon: StringName, refresh: Callable) -> Control:
	if MetaProgression.is_weapon_unlocked(weapon):
		var pick := _card_button(_start_cell_text(weapon), func() -> void:
			if _toggle_start_weapon(weapon):
				Sfx.play_ui(self, &"ui_click")
			refresh.call())
		pick.name = "Start_%s" % weapon
		pick.custom_minimum_size.x = FORGE_START_WIDTH
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pick.disabled = not _can_toggle_start_weapon(weapon)
		pick.tooltip_text = Loc.t(&"FORGE_ARSENAL_UNLOCK_EFFECT", [MetaProgression.get_weapon_name(weapon)])
		return pick
	var id := MetaProgression.arsenal_id(weapon)
	if not MetaUnlocks.is_upgrade_open(id):
		var locked := UiKit.hbox(4)
		locked.name = "ArsenalLocked_%s" % weapon
		locked.custom_minimum_size.x = FORGE_START_WIDTH
		locked.alignment = BoxContainer.ALIGNMENT_CENTER
		locked.add_child(UiKit.icon(LOCK_ICON, 18.0))
		locked.add_child(UiKit.label(Loc.t(&"FORGE_ARSENAL_NAME"), 13, UiKit.MUTED_COLOR))
		locked.tooltip_text = MetaUnlocks.get_lock_text(MetaUnlocks.get_upgrade_event(id))
		return locked
	var cost := MetaProgression.get_next_cost(id)
	var unlock := _card_button("%s · %s" % [Loc.t(&"FORGE_ARSENAL_NAME"), Loc.t(&"VILLAGE_UI_GOLD", [cost])], func() -> void:
		if MetaProgression.try_buy(id):
			Sfx.play_ui(self, &"coin")
		refresh.call())
	unlock.name = "Buy_%s" % id
	unlock.custom_minimum_size.x = FORGE_START_WIDTH
	unlock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unlock.disabled = not MetaProgression.can_buy(id)
	unlock.tooltip_text = MetaProgression.get_upgrade_effect(id)
	if not unlock.disabled:
		unlock.add_theme_color_override("font_color", AFFORDABLE_COLOR)
	return unlock


## "Startwaffe" / "1. Waffe" / "2. Waffe" for a weapon in the loadout, else "Mitnehmen".
static func _start_cell_text(weapon: StringName) -> String:
	if weapon == MetaProgression.get_start_weapon():
		return Loc.t(&"VILLAGE_UI_LOADOUT_FIRST" if MetaProgression.has_second_slot() else &"VILLAGE_UI_LOADOUT_ONLY")
	if weapon == MetaProgression.get_second_weapon():
		return Loc.t(&"VILLAGE_UI_LOADOUT_SECOND")
	return Loc.t(&"VILLAGE_UI_LOADOUT_PICK")


## Whether pressing a weapon's start cell changes the loadout (the only start weapon cannot be put
## away; the first one swaps with a second one).
static func _can_toggle_start_weapon(weapon: StringName) -> bool:
	if weapon == MetaProgression.get_start_weapon():
		return MetaProgression.get_second_weapon() != &""
	return true


## Start cell pressed: a new weapon becomes the start weapon (one slot) or the second one (two
## slots, replacing the old second); the second one is put away; the first swaps with the second.
static func _toggle_start_weapon(weapon: StringName) -> bool:
	if weapon == MetaProgression.get_start_weapon():
		var second := MetaProgression.get_second_weapon()
		return second != &"" and MetaProgression.set_start_weapon(second)
	if weapon == MetaProgression.get_second_weapon():
		return MetaProgression.set_second_weapon(&"")
	if MetaProgression.has_second_slot():
		return MetaProgression.set_second_weapon(weapon)
	return MetaProgression.set_start_weapon(weapon)


## Forge icon of an equipment entry: the delivered art/ui/forge/ file, else the placeholder.
static func _forge_icon(id: StringName) -> Texture2D:
	if not FORGE_ICONS.has(id):
		return null
	var entry: Array = FORGE_ICONS[id]
	var delivered := FORGE_ICON_DIR + String(entry[0])
	return load(delivered) as Texture2D if ResourceLoader.exists(delivered) else load(String(entry[1])) as Texture2D


## P1-3: under an affordable entry a gold "Leistbar" and a gold card frame; under one that is not
## yet "Noch N Gold" (key with the missing amount). Maxed or packed entries keep an invisible line of
## the same height, and the gold frame has the dark frame's padding: buying never changes the size
## of a card (#bf9c698d). lead (the forge's level) shares the line, left; the line wraps below it
## only when both do not fit (HFlowContainer), so the forge stays low enough for a 720 px screen.
func _add_afford_line(box: VBoxContainer, button: Button, affordable: bool, missing: int, missing_key: StringName, lead: Label = null) -> void:
	var line := _afford_label(box.get_parent() as PanelContainer, button, affordable, missing, missing_key)
	if lead == null:
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
		return
	var row := HFlowContainer.new()
	row.name = "LevelRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", CARD_GAP)
	for part: Label in [lead, line]:
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(part)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(row)


## The afford line itself: "Leistbar" (and a gold frame on card, gold button text), "Noch N Gold",
## or an invisible line of the same height (maxed, packed). card may be null.
func _afford_label(card: PanelContainer, button: Button, affordable: bool, missing: int, missing_key: StringName) -> Label:
	var line: Label = null
	if affordable:
		if card != null:
			var padding := FORGE_ROW_PADDING if card.name.begins_with("Row_") else CARD_PADDING
			card.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", padding.x, padding.y))
		line = UiKit.label(Loc.t(&"VILLAGE_UI_AFFORDABLE"), 15, AFFORDABLE_COLOR)
		line.name = "AffordableTag"
		button.add_theme_color_override("font_color", AFFORDABLE_COLOR)
	elif missing > 0:
		line = UiKit.label(_amount_text(missing_key, missing), 15, MISSING_COLOR)
		line.name = "MissingLabel"
	else:
		line = UiKit.label(Loc.t(&"VILLAGE_UI_AFFORDABLE"), 15)
		line.name = "AffordSpacer"
		line.modulate.a = 0.0
	return line


## Text with one number ("Noch %d Gold"); a key without its text yet (a new key before it is in
## translations.csv) shows "KEY 28" instead of a formatting error.
static func _amount_text(key: StringName, amount: int) -> String:
	var text := Loc.t(key)
	return text % amount if text.contains("%d") else "%s %d" % [text, amount]


# --- Handelsposten ---

func open_trader() -> void:
	await _open(VillageBuildings.TRADER, _build_trader)


## KE5 (KONZEPT §5.2): Proviant for the next run (seven cards, "Eingepackt: 1 von 2 Plätzen") and the
## permanent trade levels (Proviant-Platz, Glück, Händlerfreund) as rows like the forge's, with real
## values ("Plätze 1 → 2"). Only crystals are spent here; the crystal exchange is gone (D-087).
func _build_trader(body: VBoxContainer, refresh: Callable) -> void:
	body.add_child(_section_title(Loc.t(&"VILLAGE_UI_PROVISIONS")))
	body.add_child(_provision_slots_line())
	var grid := _grid(TRADER_COLUMNS)
	grid.name = "ProvisionGrid"
	body.add_child(grid)
	for id in MetaProgression.BOOST_ORDER:
		grid.add_child(_provision_card(id, refresh))
	body.add_child(_section_title(Loc.t(&"VILLAGE_UI_TRADE_LEVELS")))
	var rows := UiKit.vbox(CARD_GAP)
	rows.name = "TradeRows"
	body.add_child(rows)
	for id in MetaProgression.TRADE_ORDER:
		rows.add_child(_trade_row(id, refresh))
	body.add_child(_centered(UiKit.label(Loc.t(&"VILLAGE_TRADER_HINT_2"), 14, UiKit.MUTED_COLOR)))


## "Eingepackt: 1 von 2 Plätzen" with the slot icon.
func _provision_slots_line() -> Control:
	var row := UiKit.hbox(6)
	row.name = "ProvisionSlots"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.icon(_trading_icon(TRADE_ICON_FILES[MetaProgression.TRADE_PROVISION_SLOT]), 20.0))
	var text := UiKit.label(Loc.t(&"VILLAGE_UI_PROVISION_SLOTS",
		[MetaProgression.get_packed_boosts().size(), MetaProgression.get_provision_slots()]), 15, UiKit.MUTED_COLOR)
	text.name = "ProvisionSlotsLabel"
	row.add_child(text)
	return row


## One Proviant: icon, name, effect, the afford line ("Leistbar", "Noch 2 Kristalle", "Kein Platz
## frei") and the buy button (price or "Eingepackt").
func _provision_card(id: StringName, refresh: Callable) -> Control:
	var box := _card(_trading_icon("boost_%s.png" % id), MetaProgression.get_boost_name(id), MetaProgression.get_boost_effect(id))
	box.get_parent().name = "Provision_%s" % id
	var pending := SaveManager.has_pending_boost(id)
	var button := _card_button(Loc.t(&"VILLAGE_UI_PACKED") if pending else _crystal_price_text(MetaProgression.get_boost_price(id)), func() -> void:
		if MetaProgression.try_buy_boost(id):
			Sfx.play_ui(self, &"coin")
		refresh.call())
	button.name = "Boost_%s" % id
	button.disabled = not MetaProgression.can_buy_boost(id)
	if not pending and not MetaProgression.has_free_provision_slot():
		var full := UiKit.label(Loc.t(&"VILLAGE_UI_SLOTS_FULL"), 15, MISSING_COLOR)
		full.name = "SlotsFullLabel"
		full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(full)
	else:
		var missing := AffordableScript.crystals_missing(id)
		_add_afford_line(box, button, not button.disabled, missing,
			&"VILLAGE_UI_MISSING_CRYSTAL" if missing == 1 else &"VILLAGE_UI_MISSING_CRYSTALS")
	box.add_child(button)
	return box.get_parent()


## One trade level as a row like the forge's: icon, name and level, the step with real values, the
## afford line and the buy button (BuyTrade_<id>).
func _trade_row(id: StringName, refresh: Callable) -> Control:
	var card := UiKit.panel(&"dark")
	card.name = "Row_trade_%s" % id
	card.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", FORGE_ROW_PADDING.x, FORGE_ROW_PADDING.y))
	var row := UiKit.hbox(10)
	card.add_child(row)
	var image := UiKit.icon(_trading_icon(TRADE_ICON_FILES[id]), FORGE_ICON_SIZE)
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(image)
	var name_box := UiKit.vbox(0)
	name_box.custom_minimum_size.x = FORGE_NAME_WIDTH
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.add_child(UiKit.label(MetaProgression.get_trade_name(id), 16, UiKit.ACCENT_COLOR))
	var level_label := UiKit.label(Loc.t(&"VILLAGE_UI_LEVEL",
		[MetaProgression.get_trade_level(id), MetaProgression.get_trade_max_level(id)]), 13, UiKit.MUTED_COLOR)
	level_label.name = "LevelLabel"
	name_box.add_child(level_label)
	row.add_child(name_box)
	var step := UiKit.label(MetaProgression.describe_next_trade_level(id), 15, UiKit.ACCENT_COLOR)
	step.name = "StepLabel"
	step.custom_minimum_size.x = FORGE_STEP_WIDTH
	step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	step.tooltip_text = MetaProgression.get_trade_effect(id)
	step.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(step)
	var cost := MetaProgression.get_trade_next_cost(id)
	var buy := _card_button("Max." if cost < 0 else _crystal_price_text(cost), func() -> void:
		if MetaProgression.try_buy_trade(id):
			Sfx.play_ui(self, &"coin")
		refresh.call())
	buy.name = "BuyTrade_%s" % id
	buy.custom_minimum_size.x = FORGE_BUY_WIDTH
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not MetaProgression.can_buy_trade(id)
	var missing := MetaProgression.trade_crystals_missing(id)
	var line := _afford_label(card, buy, cost >= 0 and not buy.disabled, missing,
		&"VILLAGE_UI_MISSING_CRYSTAL" if missing == 1 else &"VILLAGE_UI_MISSING_CRYSTALS")
	line.custom_minimum_size.x = FORGE_AFFORD_WIDTH
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(line)
	row.add_child(buy)
	return card


static func _crystal_price_text(price: int) -> String:
	return Loc.t(&"VILLAGE_UI_PRICE_CRYSTAL" if price == 1 else &"VILLAGE_UI_PRICE_CRYSTALS", [price])


## A delivered icon of art/ui/trading/; the crystal icon as placeholder while a file is missing.
static func _trading_icon(file: String) -> Texture2D:
	var path := TRADING_ICON_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else CRYSTAL_ICON


# --- Chronik ---

func open_chronicle() -> void:
	await _open(VillageBuildings.CHRONICLE, _build_chronicle)


func _build_chronicle(body: VBoxContainer, _refresh: Callable) -> void:
	var grid := _grid(2)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for row in STAT_ROWS:
		grid.add_child(UiKit.label(Loc.t(row[1]), 17))
		var value := UiKit.label(str(int(SaveManager.get_stat(row[0]))), 17, UiKit.ACCENT_COLOR)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	grid.add_child(UiKit.label(Loc.t(&"VILLAGE_UI_STAT_PLAY_TIME"), 17))
	var time := UiKit.label(StatsTracker.format_play_time(float(SaveManager.get_stat(StatsTracker.PLAY_TIME))), 17, UiKit.ACCENT_COLOR)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(time)
	var frame := UiKit.panel(&"dark")
	frame.add_child(grid)
	# D-188 (KF1): "Dein Fortschritt" of this world next to the statistics.
	var columns := UiKit.hbox(16)
	columns.name = "ChronicleColumns"
	columns.add_child(ProgressView.for_loaded_save(CHRONICLE_PROGRESS_WIDTH, true))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(frame)
	body.add_child(columns)


# --- Gilde ---

## skip_intro: opened by a room wish of the main menu (the explanation waits for the next visit).
func open_guild(skip_intro := false) -> void:
	await _open(VillageBuildings.GUILD, _build_guild, skip_intro)
	_online_menu = null


## The online menu (D-147). It rebuilds itself on lobby and guild changes, so the dialog body is
## built only once; Esc goes back inside the menu first (Modal.input_handler).
func _build_guild(body: VBoxContainer, _refresh: Callable) -> void:
	var lobby := LobbyClient.of(self)
	if lobby == null:
		return
	_online_menu = OnlineMenu.create(lobby, null, OnlineMenu.DEFAULT_WIDTH, OnlineMenu.VILLAGE_CONTENT_HEIGHT)
	body.add_child(_online_menu)
	if _open_modal != null:
		_open_modal.input_handler = _online_menu.handle_input


## The online menu of the open guild dialog (null if none), for tests and tools.
func get_online_menu() -> OnlineMenu:
	return _online_menu if _online_menu != null and is_instance_valid(_online_menu) else null


## After a room was entered or ended the village is reloaded: reopen the room dialog for the
## player who opened it, or explain why the room closed.
func _resume_lobby() -> void:
	# "Online spielen" in the main menu: create or join the room now and show it.
	if LobbyClient.has_pending_launch():
		var launch := LobbyClient.take_launch()
		var client := LobbyClient.of(self)
		if client != null:
			client.run_launch(launch)
			open_guild(true)
		return
	var lobby := LobbyClient.find(self)
	if lobby == null:
		return
	# Guild runs: "+21 Gold für [DOCHT]" once the report was answered (now or later, D-147).
	if lobby.net_run != null:
		if not lobby.net_run.guild_payout_noticed.is_connected(_on_guild_payout):
			lobby.net_run.guild_payout_noticed.connect(_on_guild_payout)
		var payout := lobby.net_run.take_payout_notice()
		if not payout.is_empty():
			_on_guild_payout(payout)
	var notice := lobby.take_notice()
	if not notice.is_empty():
		var lines: Array[String] = [Loc.t(StringName(notice))]
		show_notice(Loc.t(&"LOBBY_SESSION_ENDED"), lines)
	elif lobby.is_in_room() and lobby.resume_dialog:
		lobby.resume_dialog = false
		# Reopened by itself: the explanation waits for a visit of the player's own.
		open_guild(true)


## A guild run paid into the guild treasury: a short notice at the top (the host's run report).
func _on_guild_payout(payout: Dictionary) -> void:
	var lobby := LobbyClient.find(self)
	if lobby != null and lobby.net_run != null:
		# Shown now: not again on the next village load.
		lobby.net_run.take_payout_notice()
	var lines: Array[String] = [NetRun.payout_text(payout)]
	if int(payout.get("treasury", -1)) >= 0:
		lines.append(Loc.t(&"GUILD_RUN_TREASURY_NOW", [int(payout.treasury)]))
	show_notice(Loc.t(&"GUILD_TREASURY"), lines, UiKit.GOLD_ICON)


# --- The mirror: the profile editor (D-152) ---

## The mirror next to Zuhause (VillageMirror) and in the home (KE8): name, figure and colours of the
## player (ProfileEditor). Saving closes the dialog; the player in the village follows via
## SaveManager.profile_changed (in a room the others see it too, NetPlayers). The home's door leads
## inside since KE8 (VillageBuildings.enter_home).
func open_mirror() -> void:
	if is_dialog_open():
		return
	_busy = true
	var modal := Modal.create(PAUSE_VILLAGE_DIALOG)
	modal.name = "MirrorModal"
	_open_modal = modal
	modal.content.add_child(_title(Loc.t(&"MIRROR_TITLE")))
	var subtitle := _centered(UiKit.label(Loc.t(&"MIRROR_SUBTITLE"), 16, UiKit.MUTED_COLOR))
	subtitle.name = "Subtitle"
	modal.content.add_child(subtitle)
	var editor := _profile_editor()
	modal.content.add_child(editor)
	modal.input_handler = editor.handle_input
	# Esc goes through the editor (cancel), so a running save is never cut off.
	modal.cancel_allowed = false
	editor.saved.connect(modal.finish)
	editor.cancelled.connect(modal.finish)
	await modal.open(self)
	_open_modal = null
	_busy = false


func _profile_editor() -> ProfileEditor:
	var profile := PlayerProfile.current()
	var editor := ProfileEditor.create(profile.player_name, profile.look, false, PROFILE_EDITOR_WIDTH)
	# D-188 (KF2): the account level at the mirror and in Zuhause.
	editor.show_level = true
	return editor


## Puts on outfit colour index (PlayerLook palette) and saves the profile; false if it was already
## worn or the index is invalid. Kept for tools (screenshots) from the MM1 wardrobe.
func put_on_color(index: int) -> bool:
	var profile := PlayerProfile.current()
	if index < 0 or index >= PlayerLook.COLOR_COUNT or PlayerLook.get_index(profile.look, PlayerLook.OUTFIT) == index:
		return false
	profile.set_color(PlayerLook.OUTFIT, index)
	profile.save()
	return true


## The editor of the open mirror or Zuhause dialog (null if none), for tests and tools.
func get_profile_editor() -> ProfileEditor:
	if _open_modal == null or not is_instance_valid(_open_modal):
		return null
	return _open_modal.find_child("ProfileEditor", true, false) as ProfileEditor


# --- Explanation (D-087, WK9: by Flint) ---

## Flint explains building_id to the local player nearest to its door (role and a tip) and returns
## when he is done or skipped; the first time also marks it as explained in this world (D-087).
## force: again (info button). False when nobody could hear it (no local player, a script run
## without VillageTour.force_in_scripts, unknown building): then nothing is marked.
func explain_building(building_id: StringName, force := false) -> bool:
	var player := _nearest_local_player(VillageTour.station_node(get_parent(), building_id))
	if not VillageTour.explain_building(player, building_id, force):
		return false
	_explaining = building_id
	await VillageTour.wait_until_done(player, VillageTour.explanation_id(building_id))
	_explaining = &""
	VillageBuildings.mark_intro_seen(building_id)
	return true


## True if Flint could explain building_id here (the info button shows only then).
func can_explain(building_id: StringName) -> bool:
	return VillageTour.has_building_explanation(building_id) and VillageTour.may_explain(_nearest_local_player(null))


## The local player closest to near (any local one without near; null if none on this machine).
func _nearest_local_player(near: Node2D) -> Player:
	var best: Player = null
	var best_distance := INF
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null or not is_instance_valid(player) or not player.is_local or player.is_queued_for_deletion():
			continue
		var distance := player.global_position.distance_to(near.global_position) if near != null and is_instance_valid(near) else 0.0
		if best == null or distance < best_distance:
			best = player
			best_distance = distance
	return best


# --- First visit (P1-2): the goal line ---

## The goal line at the top left: a symbol (the ladder to the dungeon by default), "Ziel" and the
## text (a translation key stays live: the labels translate themselves). Replaces an older one.
func show_goal(text: String, icon: Texture2D = LADDER_ICON) -> void:
	hide_goal()
	var card := UiKit.panel(&"dark")
	card.name = "Goal"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(8)
	var symbol := UiKit.icon(icon, 24.0)
	symbol.name = "GoalIcon"
	row.add_child(symbol)
	var caption := UiKit.label("VILLAGE_GOAL_EYEBROW", 15, UiKit.MUTED_COLOR)
	caption.uppercase = true
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var label := UiKit.label(text, 18, UiKit.ACCENT_COLOR)
	label.name = "GoalText"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	card.add_child(row)
	_notice_root.add_child(card)
	_goal = card
	card.position = GOAL_MARGIN
	UiKit.pop_in(card)


func hide_goal() -> void:
	if _goal != null and is_instance_valid(_goal):
		_goal.queue_free()
	_goal = null


## The goal line while shown (null otherwise), for tests and tools.
func get_goal() -> Control:
	return _goal if _goal != null and is_instance_valid(_goal) and not _goal.is_queued_for_deletion() else null


# --- Notices (D-087: unlocks, locked doors) ---

## "Neu freigeschaltet" with one line per opened thing (MetaUnlocks.take_announcements()).
func show_unlocks(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	Sfx.play_ui(self, &"upgrade")
	show_notice(MetaUnlocks.get_announce_title(), lines)


## A locked building's door: name with a lock and "Öffnet nach …".
func show_locked(building_id: StringName) -> void:
	var text := MetaUnlocks.get_building_lock_text(building_id)
	if text.is_empty():
		return
	Sfx.play_ui(self, &"ui_click")
	show_notice(VillageBuildings.get_display_name(building_id), [text + "."], LOCK_ICON)


## Short card at the top that fades out by itself; never blocks or pauses. A new one replaces it.
func show_notice(title: String, lines: Array[String], icon: Texture2D = null) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.queue_free()
	var card := UiKit.panel(&"gold")
	card.name = "Notice"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiKit.vbox(4)
	var header := UiKit.hbox(8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != null:
		header.add_child(UiKit.icon(icon, 28.0))
	var title_label := UiKit.label(title, 22, UiKit.ACCENT_COLOR)
	title_label.name = "NoticeTitle"
	header.add_child(title_label)
	box.add_child(header)
	for line in lines:
		var label := UiKit.wrapped_label(line, NOTICE_TEXT_WIDTH, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_to_group(&"village_notice_line")
		box.add_child(label)
	card.add_child(box)
	_notice_root.add_child(card)
	_notice = card
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.position.y = NOTICE_TOP
	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, NOTICE_FADE)
	tween.tween_interval(NOTICE_TIME)
	tween.tween_property(card, "modulate:a", 0.0, NOTICE_FADE)
	tween.tween_callback(card.queue_free)


## The visible notice (null if none), for tests and tools.
func get_notice() -> Control:
	return _notice if _notice != null and is_instance_valid(_notice) and not _notice.is_queued_for_deletion() else null


## Lock icon and a muted line, centred.
func _lock_row(text: String) -> Control:
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.icon(LOCK_ICON, 24.0))
	row.add_child(UiKit.label(text, 15, UiKit.MUTED_COLOR))
	return row


# --- Shared widgets ---

## Opens one building: on the first visit Flint explains it, then the dialog with title (+ info
## button), the role sentence as subtitle, currency bar, a body built by build(body, refresh) and
## rebuilt whenever refresh is called (after purchases), and a close button. One at a time. The info
## button closes the dialog, Flint explains again, then the dialog opens anew.
func _open(building_id: StringName, build: Callable, skip_intro := false) -> void:
	if is_dialog_open():
		return
	_busy = true
	if VillageBuildings.needs_intro(building_id) and not skip_intro:
		await explain_building(building_id)
	while true:
		await _show_building(building_id, build)
		var again := _replay_intro == building_id
		_replay_intro = &""
		if not again or not is_inside_tree() or not await explain_building(building_id, true):
			break
	_busy = false


## The building dialog itself (see _open); returns when it is closed.
func _show_building(building_id: StringName, build: Callable) -> void:
	var modal := Modal.create(PAUSE_VILLAGE_DIALOG)
	modal.name = "BuildingModal"
	_open_modal = modal
	_build = build
	modal.content.add_child(_title_row(building_id))
	var subtitle := _centered(UiKit.label(VillageBuildings.get_role(building_id), 16, UiKit.MUTED_COLOR))
	subtitle.name = "Subtitle"
	modal.content.add_child(subtitle)
	_currencies = UiKit.hbox(8)
	_currencies.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.content.add_child(_currencies)
	_body = UiKit.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll = _make_body_scroll()
	_body_scroll.add_child(_body)
	modal.content.add_child(_body_scroll)
	_body.minimum_size_changed.connect(_queue_fit_body)
	var close := _button(Loc.t(&"MENU_CLOSE"), modal.finish)
	close.name = "CloseButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	make_focusable(close)
	modal.content.add_child(close)
	_rebuild()
	# Guild and home set their own key handler (online menu, profile editor) while building.
	if not modal.input_handler.is_valid():
		modal.input_handler = _on_dialog_key
	modal.show_on(self)
	fit_body()
	if not get_viewport().size_changed.is_connected(_queue_fit_body):
		get_viewport().size_changed.connect(_queue_fit_body)
	if modal.input_handler == _on_dialog_key and InputDevice.is_gamepad():
		focus_default()
	await modal.finished
	if get_viewport() != null and get_viewport().size_changed.is_connected(_queue_fit_body):
		get_viewport().size_changed.disconnect(_queue_fit_body)
	_open_modal = null
	_body = null
	_body_scroll = null
	_currencies = null


# --- Scrolling body, "Schließen" always visible (#d1a7f411) ---

func _make_body_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	Modal._style_scroll_bar(scroll.get_v_scroll_bar())
	return scroll


func _queue_fit_body() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	fit_body.call_deferred()


## Gives the body as much height as the screen leaves next to title, currencies, "Schließen" and
## the panel frame; a taller body scrolls inside, so the dialog itself never has to.
func fit_body() -> void:
	_fit_queued = false
	if _body_scroll == null or not is_instance_valid(_body_scroll) or _open_modal == null \
			or not is_instance_valid(_open_modal) or not _open_modal.is_inside_tree():
		return
	var need := _body.get_combined_minimum_size()
	var room := maxf(UiKit.px(BODY_MIN_HEIGHT), body_room())
	var scrolls := need.y > room + 0.5
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if scrolls else ScrollContainer.SCROLL_MODE_DISABLED
	var bar := UiKit.px(BODY_SCROLL_BAR) if scrolls else 0.0
	_body_scroll.custom_minimum_size = Vector2(need.x + bar, minf(need.y, room))


## Height (layout px) the body may take in the open dialog: the screen (safe area at the menu zoom)
## minus everything else in the panel.
func body_room() -> float:
	var viewport := _open_modal.get_viewport()
	var screen := MobileUiScript.safe_rect(viewport).size.y - 2.0 * MobileUiScript.touch_margin(viewport)
	screen /= maxf(MobileUiScript.menu_zoom(viewport), 0.01)
	var style := _open_modal.frame.get_theme_stylebox(&"panel")
	var padding := style.get_minimum_size().y if style != null else 0.0
	var others := _open_modal.content.get_combined_minimum_size().y - _body_scroll.get_combined_minimum_size().y
	return floorf(screen - padding - others - 2.0 * UiKit.px(SCREEN_GAP))


## True while the body of the open dialog scrolls (for tests and tools).
func is_body_scrolling() -> bool:
	return _body_scroll != null and is_instance_valid(_body_scroll) \
			and _body_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func get_body_scroll() -> ScrollContainer:
	return _body_scroll if _body_scroll != null and is_instance_valid(_body_scroll) else null


## Building name with an info button: Flint explains the building again (only where he can).
func _title_row(building_id: StringName) -> Control:
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_title(VillageBuildings.get_display_name(building_id)))
	var info := Button.new()
	info.name = "InfoButton"
	info.icon = UiKit.upscale(INFO_ICON, 2)
	info.flat = true
	# Flat: the frames are never drawn, but their padding made the title row taller than the title.
	for state in ["normal", "hover", "pressed", "disabled"]:
		info.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	make_focusable(info)
	info.tooltip_text = Loc.t(&"VILLAGE_UI_SHOW_INTRO")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(func() -> void:
		Sfx.play_ui(info, &"ui_click")
		ask_flint_again(building_id))
	info.visible = can_explain(building_id)
	row.add_child(info)
	return row


## The info button: closes the building's dialog, Flint explains it again, then it opens anew (_open).
func ask_flint_again(building_id: StringName) -> void:
	if _open_modal == null or not is_instance_valid(_open_modal) or not can_explain(building_id):
		return
	_replay_intro = building_id
	_open_modal.finish()


## Rebuilds the open dialog at the end of the frame (safe to call from a button inside it).
func _request_refresh() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_currencies):
		return
	# Gamepad: the focus stays on the same entry after a purchase (buttons are rebuilt by name).
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_name := StringName(focused.name) if focused != null and _body.is_ancestor_of(focused) else &""
	var before := _body.get_combined_minimum_size()
	for row: Control in [_currencies, _body]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_fill_currencies(_currencies)
	# Gold and crystals do not count online (D-081): the guild dialog shows none.
	_currencies.visible = _build != _build_guild
	_build.call(_body, _request_refresh)
	# While the dialog is open it never shrinks after a purchase (#bf9c698d): the body keeps the
	# largest size of this visit (a new body per visit, so the next one starts fresh).
	_body.custom_minimum_size = _body.custom_minimum_size.max(before)
	if _build != _build_guild:
		for node in _body.find_children("*", "Button", true, false):
			make_focusable(node as Button)
	if focused_name != &"":
		var again := _body.find_child(String(focused_name), true, false) as Control
		if again != null and again.is_inside_tree():
			again.grab_focus()
		else:
			focus_default()


# --- Gamepad and arrow keys (P1-3) ---

## Lets the D-pad, the stick and the arrow keys move to a button and A/Enter press it: the button
## takes focus and shows a light frame and text while focused (the theme's focus style is empty).
static func make_focusable(button: Button) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_ALL
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(FOCUS_BORDER)
	frame.border_color = FOCUS_COLOR
	frame.set_expand_margin_all(2.0)
	button.add_theme_stylebox_override("focus", frame)
	button.add_theme_color_override("font_focus_color", FOCUS_COLOR)


## Focuses the first affordable entry of the open building dialog, else its first enabled button,
## else "Schließen". Returns the focused button (null if there is no dialog).
func focus_default() -> Button:
	if _open_modal == null or not is_instance_valid(_open_modal) or not _open_modal.is_inside_tree():
		return null
	var first_enabled: Button = null
	if _body != null and is_instance_valid(_body):
		for node in _body.find_children("*", "Button", true, false):
			var button := node as Button
			if button.focus_mode != Control.FOCUS_ALL or button.disabled:
				continue
			var box := button.get_parent()
			if box != null and box.find_child("AffordableTag", true, false) != null:
				button.grab_focus()
				return button
			if first_enabled == null:
				first_enabled = button
	var target := first_enabled if first_enabled != null else _open_modal.find_child("CloseButton", true, false) as Button
	if target != null:
		target.grab_focus()
	return target


## The focused button of the open building dialog (null if none), for tests and tools.
func get_focused_button() -> Button:
	if _open_modal == null or not is_instance_valid(_open_modal) or not _open_modal.is_inside_tree():
		return null
	var focus := get_viewport().gui_get_focus_owner()
	return focus as Button if focus != null and _open_modal.is_ancestor_of(focus) else null


## Key handler of the forge, trader and chronicle: while nothing has the focus the first arrow,
## stick or A press puts it on the default entry (afterwards Godot moves and presses it).
func _on_dialog_key(event: InputEvent) -> bool:
	if get_focused_button() != null:
		return false
	var direction := MenuInput.is_up(event) or MenuInput.is_down(event) or MenuInput.is_left(event) or MenuInput.is_right(event)
	if direction or (event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept")):
		if focus_default() != null:
			UiSound.hover(self)
			return true
	return false


func _fill_currencies(row: HBoxContainer) -> void:
	row.add_child(UiKit.icon(GOLD_ICON, 24.0))
	row.add_child(UiKit.label("%d Gold" % SaveManager.get_permanent_gold(), 20, UiKit.ACCENT_COLOR))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	row.add_child(spacer)
	row.add_child(UiKit.icon(CRYSTAL_ICON, 24.0))
	row.add_child(UiKit.label(Loc.t(&"VILLAGE_UI_CRYSTALS", [SaveManager.get_permanent_crystals()]), 20, Color(0.7, 0.85, 1.0)))


## A dialog button like the online menu's (UiKit.dialog_button: bold, the dialog size), BUTTON_WIDTH
## wide; is_default draws it as the Enter action.
static func _button(text: String, on_pressed: Callable, is_default := false) -> Button:
	var button := UiKit.dialog_button(text, "", on_pressed, is_default)
	button.custom_minimum_size.x = UiKit.px(BUTTON_WIDTH)
	return button


## The buy button of a card: a dialog button as wide as the card.
static func _card_button(text: String, on_pressed: Callable) -> Button:
	var button := UiKit.dialog_button(text, "", on_pressed)
	button.custom_minimum_size.x = 0.0
	return button


## A dark card with icon, name and effect text; returns the inner VBox (card = get_parent()).
func _card(icon: Texture2D, title: String, effect: String) -> VBoxContainer:
	var card := UiKit.panel(&"dark")
	card.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", CARD_PADDING.x, CARD_PADDING.y))
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var box := UiKit.vbox(CARD_GAP)
	card.add_child(box)
	var header := UiKit.hbox(10)
	if icon != null:
		header.add_child(UiKit.icon(icon, 32.0))
	header.add_child(UiKit.label(title, 18, UiKit.ACCENT_COLOR))
	box.add_child(header)
	var text := UiKit.wrapped_label(effect, CARD_WIDTH - 40.0, 14)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	return box


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _title(text: String) -> Label:
	var title := UiKit.label(text, 28, UiKit.ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _section_title(text: String) -> Label:
	var title := UiKit.label(text, 20, UiKit.ACCENT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


# --- Dungeon entrance: rank, danger level, loot bonus (KE1, D-196: shown only, never picked) ---

## The entrance node under the village (scene world/village/village.tscn).
const ENTRANCE_NODE := ^"Buildings/DungeonEntrance"
## TESTWERT: the card shows while a local player is this close to the entrance (px, like the
## building captions of Village).
const ENTRANCE_NEAR := 400.0
const ENTRANCE_BADGE_SIZE := 24.0


## Connects to the village's dungeon_requested (sets the run's danger level first) and finds the
## entrance. Without a village parent (tests, tools) nothing happens.
func _hook_entrance() -> void:
	var village := get_parent()
	if village == null:
		return
	if village.has_signal(&"dungeon_requested") and not village.is_connected(&"dungeon_requested", apply_entrance_danger):
		village.connect(&"dungeon_requested", apply_entrance_danger)
	if entrance_anchor == null:
		entrance_anchor = village.get_node_or_null(ENTRANCE_NODE) as Node2D


## Co-op hook (integrator, KE2 online/coop_rules.gd): the group level the host computed for this
## room; -1 goes back to the own level.
func set_group_danger(level: int) -> void:
	_group_danger = maxi(-1, level)
	if get_entrance_info() != null:
		_fill_entrance_info(_entrance_card)


func get_group_danger() -> int:
	return _group_danger


## The danger level of the next run: the group's when set, else this player's own.
func get_entrance_danger() -> int:
	return _group_danger if _group_danger >= 0 else AccountProgress.current().get_danger_level()


## Hands the shown level to the run (RunManager.set_danger_level before start_run).
func apply_entrance_danger() -> void:
	RunManager.set_danger_level(get_entrance_danger())


func _process(_delta: float) -> void:
	if entrance_anchor != null and is_instance_valid(entrance_anchor):
		update_entrance(_local_player_positions())


## Language switch (pause menu options): the entrance card is composed text, fill it again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and get_entrance_info() != null:
		_fill_entrance_info(_entrance_card)


## Shows the card while one of positions is near the entrance and nothing else is on screen
## (dialog, notice), hides it otherwise.
func update_entrance(positions: Array[Vector2]) -> void:
	var near := false
	if entrance_anchor != null and is_instance_valid(entrance_anchor):
		for point in positions:
			if point.distance_to(entrance_anchor.global_position) <= ENTRANCE_NEAR:
				near = true
				break
	if near and not is_dialog_open() and get_notice() == null:
		show_entrance_info()
	else:
		hide_entrance_info()


## The card at the top: rank badge, "Dein Rang" (or "Eure Gruppe"), "Kerze II" and
## "Gefahrenstufe 4 · Beute +20 %". Stays until hide_entrance_info().
func show_entrance_info() -> void:
	if get_entrance_info() != null:
		return
	var card := UiKit.panel(&"dark")
	card.name = "EntranceInfo"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_entrance_info(card)
	_notice_root.add_child(card)
	_entrance_card = card
	# WK8: the first time the card shows, Flint introduces "Deine Gefahr" (once per local player).
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local:
			FlintExplanations.entrance_danger(player, entrance_anchor if is_instance_valid(entrance_anchor) else null)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.position.y = NOTICE_TOP
	card.modulate.a = 0.0
	card.create_tween().tween_property(card, "modulate:a", 1.0, NOTICE_FADE)


func hide_entrance_info() -> void:
	var card := get_entrance_info()
	_entrance_card = null
	if card == null:
		return
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 0.0, NOTICE_FADE * 0.5)
	tween.tween_callback(card.queue_free)


## The entrance card while shown (null otherwise), for tests and tools.
func get_entrance_info() -> Control:
	return _entrance_card if _entrance_card != null and is_instance_valid(_entrance_card) and not _entrance_card.is_queued_for_deletion() else null


## Texts of the card: [eyebrow, rank, danger and loot line] (current language).
func entrance_texts() -> Array[String]:
	var danger := get_entrance_danger()
	var eyebrow := Loc.t(&"ENTRANCE_INFO_GROUP" if _group_danger >= 0 else &"ENTRANCE_INFO_RANK")
	var line := "%s · %s" % [Loc.t(&"ENTRANCE_INFO_DANGER", [danger]), Loc.t(&"ENTRANCE_INFO_LOOT", [DangerRank.loot_percent(danger)])]
	return [eyebrow, DangerRank.rank_text(danger), line]


func _fill_entrance_info(card: Control) -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var texts := entrance_texts()
	var row := UiKit.hbox(10)
	row.add_child(RankBadge.create(get_entrance_danger(), ENTRANCE_BADGE_SIZE))
	var box := UiKit.vbox(0)
	var eyebrow := UiKit.label(texts[0], 13, UiKit.MUTED_COLOR)
	eyebrow.uppercase = true
	box.add_child(eyebrow)
	var rank := UiKit.label(texts[1], 20, UiKit.ACCENT_COLOR)
	rank.name = "EntranceRank"
	box.add_child(rank)
	var line := UiKit.label(texts[2], 15, UiKit.TEXT_COLOR)
	line.name = "EntranceDanger"
	box.add_child(line)
	row.add_child(box)
	card.add_child(row)


## Positions of the players on this machine (co-op: never the others').
func _local_player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.is_local:
			positions.append(player.global_position)
	return positions
