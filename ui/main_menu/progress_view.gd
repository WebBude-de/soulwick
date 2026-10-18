class_name ProgressView
extends VBoxContainer
## "Dein Fortschritt" (D-188, KF1): one view for the main menu (ProgressPanel) and the chronicle in
## the village (VillageUI). From top to bottom: "Nächstes Ziel" in gold, this world (forge levels
## x/20 with a bar, record, bosses), the four biomes (reached, boss defeated), unlocks (open or what
## opens them) and the next goals. Built from ProgressSummary (read only); compact drops the unlocks
## and keeps two goals (the chronicle shows its statistics next to it).
## Sizes in mockup pixels (UiKit.px), texts are translation keys resolved when built (D-111).

const LOCK_ICON: Texture2D = preload("res://art/ui/icon_lock.png")
const TROPHY_ICON: Texture2D = preload("res://art/ui/trophy_icon.png")
const SKULL_ICON: Texture2D = preload("res://art/ui/skull_icon.png")
const DEFAULT_WIDTH := 244.0
const GAP := 4.0
## Goals shown in the compact view.
const COMPACT_GOALS := 2

var summary: Dictionary = {}
var world: Dictionary = {}
var width := DEFAULT_WIDTH
var compact := false


## world: a ProgressSummary snapshot (exists, name); summary: ProgressSummary.build() of it.
static func create(world_snapshot: Dictionary, progress: Dictionary, spec_width := DEFAULT_WIDTH, is_compact := false) -> ProgressView:
	var view := ProgressView.new()
	view.name = "ProgressView"
	view.world = world_snapshot
	view.summary = progress
	view.width = spec_width
	view.compact = is_compact
	return view


## The view of the loaded save (village chronicle).
static func for_loaded_save(spec_width := DEFAULT_WIDTH, is_compact := false) -> ProgressView:
	var snapshot := ProgressSummary.world_from_save()
	return create(snapshot, ProgressSummary.build(snapshot), spec_width, is_compact)


## The view of the world "Weiterspielen" continues (main menu), read from its file; no world =
## an empty one.
static func for_continue_world(spec_width := DEFAULT_WIDTH, is_compact := false) -> ProgressView:
	var snapshot := continue_world()
	return create(snapshot, ProgressSummary.build(snapshot), spec_width, is_compact)


## Snapshot of the world of "Weiterspielen" (empty_world() without one); its name is the display name.
static func continue_world() -> Dictionary:
	var slot := SaveManager.get_continue_slot()
	if slot <= 0:
		return ProgressSummary.empty_world()
	var snapshot := ProgressSummary.world_from_file(SaveManager.slot_path(slot))
	if String(snapshot.get("name", "")).strip_edges().is_empty():
		snapshot["name"] = SaveSlots.default_name(slot)
	return snapshot


func _ready() -> void:
	add_theme_constant_override("separation", int(UiKit.px(GAP)))
	custom_minimum_size.x = UiKit.px(width)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		for child in get_children():
			remove_child(child)
			child.queue_free()
		_build()


func _build() -> void:
	var goal := ProgressSummary.next_goal_text(summary)
	if not goal.is_empty():
		var goal_box := UiKit.panel(&"gold")
		goal_box.name = "NextGoal"
		goal_box.add_theme_stylebox_override("panel", UiKit.padded_style(&"gold", 3, 5))
		goal_box.add_child(UiKit.wrapped_text(goal, width - 12.0, UiKit.SIZE_BODY, UiKit.COLOR_GOLD))
		add_child(goal_box)
	_build_account()
	add_child(_world_section())
	add_child(_biome_section())
	if not compact:
		add_child(_unlock_section())
	add_child(_goal_section())


## Hook for the account part (KF2).
func _build_account() -> void:
	pass


func _world_section() -> Control:
	var box := UiKit.vbox(int(UiKit.px(2)))
	box.name = "World"
	var exists: bool = world.get("exists", false)
	var title := Loc.t(&"PROGRESS_WORLD", [String(world.get("name", ""))]) if exists else Loc.t(&"PROGRESS_WORLD_NONE")
	box.add_child(UiKit.eyebrow(title))
	var forge_row := UiKit.hbox(int(UiKit.px(6)))
	forge_row.name = "Forge"
	var caption := UiKit.text_label(Loc.t(&"PROGRESS_FORGE"), UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
	forge_row.add_child(caption)
	var level := int(summary.get("forge_level", 0))
	var top := maxi(1, int(summary.get("forge_max", 1)))
	var bar := PixelBar.create(float(level) / float(top), UiKit.COLOR_GOLD)
	bar.name = "ForgeBar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_row.add_child(bar)
	var value := UiKit.text_label(Loc.t(&"PROGRESS_FORGE_VALUE", [level, top]), UiKit.SIZE_BODY, UiKit.COLOR_GOLD, true)
	value.name = "ForgeValue"
	forge_row.add_child(value)
	box.add_child(forge_row)
	var deepest := int(summary.get("deepest_room", 0))
	var record := Loc.t(&"PROGRESS_ROOM", [deepest]) if deepest > 0 else Loc.t(&"MENU_NO_RECORD")
	var rows := UiKit.hbox(int(UiKit.px(10)))
	var record_row := UiKit.value_row(Loc.t(&"PROGRESS_RECORD"), record, UiKit.COLOR_TEXT, UiKit.SIZE_BODY)
	record_row.name = "Record"
	record_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(record_row)
	var bosses_row := UiKit.value_row(Loc.t(&"PROGRESS_BOSSES"), str(int(summary.get("bosses", 0))), UiKit.COLOR_TEXT, UiKit.SIZE_BODY)
	bosses_row.name = "Bosses"
	bosses_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(bosses_row)
	box.add_child(rows)
	return box


## Four tiles: biome name, then "Boss besiegt" (gold), "Erreicht" or "Ab Raum 31" (greyed).
func _biome_section() -> Control:
	var box := UiKit.vbox(int(UiKit.px(2)))
	box.name = "Biomes"
	box.add_child(UiKit.eyebrow(Loc.t(&"PROGRESS_BIOMES")))
	var grid := GridContainer.new()
	grid.columns = 4 if width >= 200.0 else 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", int(UiKit.px(3)))
	grid.add_theme_constant_override("v_separation", int(UiKit.px(3)))
	for entry: Dictionary in summary.get("biomes", []):
		var biome := int(entry["biome"])
		var tile := UiKit.panel(&"dark")
		tile.name = "Biome%d" % biome
		tile.add_theme_stylebox_override("panel", UiKit.padded_style(&"dark", 2, 3))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inner := UiKit.vbox(0)
		var reached: bool = entry["reached"]
		var beaten: bool = entry["beaten"]
		var name_label := UiKit.text_label(RoomSequence.get_biome_name(biome), UiKit.SIZE_BODY, UiKit.COLOR_TEXT if reached else UiKit.COLOR_DISABLED, true)
		name_label.clip_text = true
		inner.add_child(name_label)
		var state := UiKit.hbox(int(UiKit.px(2)))
		var text := Loc.t(&"PROGRESS_BIOME_BEATEN")
		var color := UiKit.COLOR_GOLD
		var icon := TROPHY_ICON
		if not beaten and reached:
			text = Loc.t(&"PROGRESS_BIOME_REACHED")
			color = UiKit.COLOR_TEXT_SOFT
			icon = SKULL_ICON
		elif not reached:
			text = Loc.t(&"PROGRESS_BIOME_FROM_ROOM", [biome * RoomSequence.BOSS_INTERVAL + 1])
			color = UiKit.COLOR_DISABLED
			icon = LOCK_ICON
		state.add_child(UiKit.pixel_icon(icon, 8.0))
		var state_label := UiKit.text_label(text, UiKit.SIZE_EYEBROW, color)
		state_label.name = "State"
		state.add_child(state_label)
		inner.add_child(state)
		tile.add_child(inner)
		grid.add_child(tile)
	box.add_child(grid)
	return box


## One row per village event: what it opened (open) or the lock and when it opens.
func _unlock_section() -> Control:
	var box := UiKit.vbox(int(UiKit.px(1)))
	box.name = "Unlocks"
	box.add_child(UiKit.eyebrow(Loc.t(&"PROGRESS_UNLOCKS")))
	for entry: Dictionary in summary.get("unlocks", []):
		var event := StringName(entry["event"])
		var done: bool = entry["done"]
		var row := UiKit.hbox(int(UiKit.px(3)))
		row.name = "Unlock_%s" % event
		var what := UiKit.text_label(MetaUnlocks.describe_event(event), UiKit.SIZE_BODY, UiKit.COLOR_TEXT if done else UiKit.COLOR_DISABLED)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.clip_text = true
		row.add_child(what)
		if done:
			row.add_child(UiKit.text_label(Loc.t(&"PROGRESS_UNLOCK_OPEN"), UiKit.SIZE_BODY, UiKit.COLOR_SUCCESS, true))
		else:
			row.add_child(UiKit.pixel_icon(LOCK_ICON, 8.0))
			row.add_child(UiKit.text_label(Loc.t(&"UNLOCK_OPENS", [Loc.t(MetaUnlocks.LOCK_CONDITIONS[event])]), UiKit.SIZE_EYEBROW, UiKit.COLOR_MUTED))
		box.add_child(row)
	return box


func _goal_section() -> Control:
	var box := UiKit.vbox(int(UiKit.px(1)))
	box.name = "Goals"
	box.add_child(UiKit.eyebrow(Loc.t(&"PROGRESS_GOALS")))
	var list: Array = summary.get("goals", [])
	if compact:
		list = list.slice(0, COMPACT_GOALS)
	for goal: Dictionary in list:
		var line := UiKit.wrapped_text("› " + ProgressSummary.goal_text(goal), width, UiKit.SIZE_BODY, UiKit.COLOR_TEXT_SOFT)
		line.name = "Goal_%s" % goal["kind"]
		box.add_child(line)
	return box
