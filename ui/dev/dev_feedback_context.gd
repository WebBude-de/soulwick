class_name DevFeedbackContext
extends RefCounted
## Context of a dev feedback note (DevFeedback, F9): where the game was (scene, phase, room, biome,
## mode, template, seed, players, camera), which screen or dialog was open (screen: main menu panel,
## options tab, online tab and guild page, pause menu, upgrade choice, shop, campfire, run end,
## village building ...), the boss fight (boss), co-op (coop: players, host/client, ping, never a
## room code), the device (device: platform, input device, screen size, UI zoom) and which UI and
## world nodes lie under each marked rectangle. location is one readable German line for the admin
## list and the overview, e.g. "Dungeon · Raum 23 · Schleimgrotte · Kampf + Upgrade" or
## "Hauptmenü · Online · Gilden · Gildenseite" (German whatever the game language, so reports group
## the same way). Everything is read defensively (get(), has_method(), class names looked up at run
## time): game classes may be half finished by other agents and a missing value is simply left out,
## it never stops a note from being saved. Rectangles are in view coordinates (the canvas of the
## root viewport, the same space the overlay draws in).

const MAX_NODES := 15
## TileMapLayer sampling: at most this many cells per layer and rectangle, at most this many layers.
const MAX_TILE_CELLS := 6000
const MAX_TILE_LAYERS := 4
const MAX_TILES_PER_LAYER := 6
const MAX_TEXT := 120
## Pure layout controls (without script, text or texture) come after everything that draws.
const LAYOUT_CLASSES: Array[String] = ["Control", "Container", "BoxContainer", "HBoxContainer", "VBoxContainer",
	"GridContainer", "MarginContainer", "CenterContainer", "AspectRatioContainer", "FlowContainer",
	"HFlowContainer", "VFlowContainer", "ScrollContainer", "HSplitContainer", "VSplitContainer"]
## Fallback world tile size when RoomTiles cannot be read.
const TILE_WORLD_FALLBACK := 64.0
## No class_name (mobile_ui.gd): preloaded.
const MobileUiScript := preload("res://ui/menus/mobile_ui.gd")
## Readable names of the open dialogs by Modal.pause_reason (GameManager, GameUI, DungeonUI, VillageUI).
const DIALOG_NAMES := {
	"pause_menu": "Pausemenü", "upgrade_choice": "Upgrade-Wahl", "shop": "Shop", "weapon_choice": "Waffenwahl",
	"upgrade_overview": "Upgrade-Übersicht", "confirm": "Abfrage", "run_end": "Run-Ende", "options": "Optionen",
	"village_dialog": "Gebäude", "village_intro": "Dorf-Einführung", "dialog_queue": "Dialog",
}
## Main menu panels (MenuPanel subclasses) -> readable name.
const MENU_PANELS := {
	&"SlotPanel": "Welten", &"CreateSlotPanel": "Neue Welt", &"ProfilePanel": "Profil",
	&"OptionsPanel": "Optionen", &"OnlinePanel": "Online",
}
## OnlineMenu.View -> readable path (CREATE, JOIN, DETAIL ... belong to the guild tab).
const ONLINE_VIEWS := {
	"QUICK": ["Schnell"], "GUILDS": ["Gilden"], "CREATE": ["Gilden", "Gilde gründen"],
	"JOIN": ["Gilden", "Gilde beitreten"], "DETAIL": ["Gilden", "Gildenseite"], "CONFIRM": ["Gilden", "Bestätigen"],
	"PROFILE": ["Gilden", "Aussehen"],
}
## RunManager.EndReason -> readable.
const RUN_END_REASONS := {"DEATH": "Tod", "EXIT": "Ausgang", "ABORT": "Abbruch"}
## InputDevice.Kind -> context value.
const INPUT_NAMES := {"KEYBOARD_MOUSE": "mouse", "GAMEPAD": "gamepad", "TOUCH": "touch"}
## Keys of NetDiagnostics.snapshot() that hold a room code: never sent.
const ROOM_CODE_KEYS: Array[String] = ["room", "room_code", "code_room"]
const MAX_TITLE := 80

## Last input device seen by DevFeedback (note_input), when InputDevice cannot be read.
static var _last_input := ""


## Scene, phase, window, camera, pause reasons, run, dungeon room and players.
static func collect(tree: SceneTree, exclude: Node = null) -> Dictionary:
	var context := {}
	if tree == null:
		return context
	var scene := tree.current_scene
	context["scene"] = scene.scene_file_path if scene != null else ""
	context["scene_name"] = str(scene.name) if scene != null else ""
	context["phase"] = _phase_name(tree)
	context["window"] = _window_info(tree)
	context["camera"] = _camera_info(tree)
	context["pause_reasons"] = _pause_reasons(tree)
	var run_manager := tree.root.get_node_or_null(^"RunManager")
	if run_manager != null and run_manager.has_method(&"is_run_active"):
		context["run"] = {"active": run_manager.call(&"is_run_active"), "room": run_manager.call(&"get_current_room")}
	var dungeon := find_by_class(scene, &"DungeonManager", exclude)
	var room: Node = null
	if dungeon != null:
		var info := _dungeon_info(dungeon)
		room = info.get("_room") as Node
		info.erase("_room")
		context["dungeon"] = info
	context["players"] = _players_info(tree, room)
	context["screen"] = screen_info(tree, str(context["phase"]), room, exclude)
	var boss := boss_info(tree, room)
	if not boss.is_empty():
		context["boss"] = boss
	context["coop"] = coop_info(tree)
	context["device"] = device_info(tree)
	context["location"] = describe_location(context)
	return context


# --- screen and dialogs ------------------------------------------------------------------------

## The open screen: {label: "Hauptmenü · Online · Gilden · Gildenseite", parts: [...], nodes: [...]}.
## parts come after the phase name (main menu panel and its tabs, then every visible dialog);
## nodes name the dialogs found (path, pause reason, title in the game language).
static func screen_info(tree: SceneTree, phase: String, room: Node = null, exclude: Node = null) -> Dictionary:
	var parts: Array = []
	var nodes: Array = []
	var scene := tree.current_scene if tree != null else null
	if phase == "menu":
		parts.append_array(_menu_parts(scene, exclude))
	if scene != null:
		var intro := find_by_class(scene, &"BossIntro", exclude)
		if intro != null and intro.has_method(&"is_running") and intro.call(&"is_running"):
			parts.append("Boss-Intro")
	var modals: Array[Node] = []
	_find_visible(tree.root if tree != null else null, &"Modal", exclude, modals)
	for modal in modals:
		var reason := str(modal.get(&"pause_reason")) if modal.get(&"pause_reason") != null else ""
		var title := _title_of(modal)
		parts.append_array(_dialog_parts(modal, reason, title, room))
		var entry := {"path": str(modal.get_path()), "reason": reason}
		if not title.is_empty():
			entry["title"] = title
		nodes.append(entry)
	var label: PackedStringArray = [phase_label(phase, scene)]
	for part in parts:
		label.append(str(part))
	return {"label": " · ".join(label), "parts": parts, "nodes": nodes}


## "Hauptmenü", "Dorf", "Dungeon" or the scene name.
static func phase_label(phase: String, scene: Node = null) -> String:
	match phase:
		"menu":
			return "Hauptmenü"
		"village":
			return "Dorf"
		"dungeon":
			return "Dungeon"
	return str(scene.name) if scene != null else "?"


## Main menu: the open panel, the options tab, the online tab and guild page.
static func _menu_parts(scene: Node, exclude: Node) -> Array:
	var parts: Array = []
	if scene == null:
		return parts
	var menu: Variant = scene.get(&"menu")
	if not (menu is Node) or not is_instance_valid(menu):
		menu = find_by_class(scene, &"MainMenu", exclude)
	if menu == null or not (menu as Node).has_method(&"get_open_panel"):
		return parts
	var panel: Variant = (menu as Node).call(&"get_open_panel")
	if not (panel is Node) or not is_instance_valid(panel):
		return parts
	var name := str((panel as Node).name)
	for panel_class: StringName in MENU_PANELS:
		if has_class(panel, panel_class):
			name = MENU_PANELS[panel_class]
			break
	if has_class(panel, &"ProfilePanel") and bool((panel as Node).get(&"first_start")):
		name += " (erster Start)"
	parts.append(name)
	parts.append_array(_options_parts(panel as Node))
	parts.append_array(_online_parts(panel as Node))
	return parts


## Tab of the OptionsView at or below node ("Allgemein", "Bild", "Tasten", "Touch").
static func _options_parts(node: Node) -> Array:
	var view := find_by_class(node, &"OptionsView")
	if view == null or not view.has_method(&"get_tab"):
		return []
	var tab := int(view.call(&"get_tab"))
	var keys: Variant = class_constant(&"OptionsView", &"TAB_KEYS", [])
	if keys is Array and tab >= 0 and tab < (keys as Array).size():
		return [de_text(keys[tab])]
	return [enum_key(&"OptionsView", &"Tab", tab).capitalize()]


## Tab and page of the OnlineMenu at or below node ("Gilden", "Gildenseite"), plus the lobby room.
static func _online_parts(node: Node) -> Array:
	var menu := find_by_class(node, &"OnlineMenu")
	if menu == null or menu.get(&"view") == null:
		return []
	var key := enum_key(&"OnlineMenu", &"View", menu.get(&"view"))
	var parts: Array = (ONLINE_VIEWS.get(key, [key.capitalize()]) as Array).duplicate()
	if menu.has_method(&"is_in_room") and menu.call(&"is_in_room"):
		parts.append("Lobby-Raum")
	return parts


## Readable name of one dialog: campfire and upgrade choice share a reason, the run end names its
## cause, options name the tab, village buildings their name (the guild building its online tab).
static func _dialog_parts(modal: Node, reason: String, title: String, room: Node) -> Array:
	var name := str(DIALOG_NAMES.get(reason, ""))
	var parts: Array = []
	match reason:
		"upgrade_choice":
			var campfire: bool = room != null and room.has_method(&"is_campfire") and bool(room.call(&"is_campfire"))
			if campfire or (not title.is_empty() and title == _translated(&"CAMPFIRE_TITLE")):
				name = "Lagerfeuer"
		"run_end":
			var run_manager := modal.get_tree().root.get_node_or_null(^"RunManager") if modal.is_inside_tree() else null
			if run_manager != null and run_manager.has_method(&"get_last_summary"):
				var summary: Variant = run_manager.call(&"get_last_summary")
				if summary is Dictionary and (summary as Dictionary).has("reason"):
					var cause := str(RUN_END_REASONS.get(enum_key(&"RunManager", &"EndReason", summary["reason"]), ""))
					if not str(cause).is_empty():
						name += " (%s)" % cause
	if str(modal.name) == "MirrorModal":
		name = "Spiegel"
	elif str(modal.name) == "BuildingModal" or reason == "village_dialog":
		var building := _village_building(modal)
		if not building.is_empty():
			name = building
	if name.is_empty():
		name = str(modal.name) if not str(modal.name).begins_with("@") else (reason if not reason.is_empty() else "Dialog")
	parts.append(name)
	parts.append_array(_options_parts(modal))
	parts.append_array(_online_parts(modal))
	return parts


## German name of the village building whose name a label of modal shows (VillageBuildings).
static func _village_building(modal: Node) -> String:
	var info: Variant = class_constant(&"VillageBuildings", &"INFO", {})
	if not (info is Dictionary):
		return ""
	var names := {}
	for id: Variant in info:
		var key: Variant = (info[id] as Dictionary).get("name", "")
		names[_translated(StringName(str(key)))] = de_text(key)
	for label in modal.find_children("*", "Label", true, false):
		var text := str((label as Label).text).strip_edges()
		if names.has(text):
			return names[text]
	return ""


## Title label of a dialog built with UiDialog (content/Header/.../TitleRow/Title), "" otherwise.
static func _title_of(modal: Node) -> String:
	var title := modal.find_child("Title", true, false)
	if title is Label:
		return _short(str((title as Label).text))
	return ""


static func _find_visible(node: Node, global_name: StringName, exclude: Node, found: Array[Node], depth := 0) -> void:
	if node == null or node == exclude or _skips_subtree(node, depth):
		return
	if has_class(node, global_name):
		found.append(node)
		return
	for child in node.get_children():
		_find_visible(child, global_name, exclude, found, depth + 1)


# --- boss, co-op, device -----------------------------------------------------------------------

## The boss of the current fight: {id, name (German, with tier), phase, hp, hp_max, count, miniboss,
## intro}; {} without a living boss. Bosses inside the active room win; minibosses count when no
## real boss is there.
static func boss_info(tree: SceneTree, room: Node = null) -> Dictionary:
	if tree == null:
		return {}
	var bosses: Array[Node] = []
	var minis: Array[Node] = []
	for node in tree.get_nodes_in_group(&"enemies"):
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
			continue
		var data: Variant = node.get(&"data")
		if not (data is Object) or data == null:
			continue
		var health: Variant = node.get(&"health")
		if health is Object and health != null and (health as Object).has_method(&"is_dead") and (health as Object).call(&"is_dead"):
			continue
		if bool((data as Object).get(&"is_boss")):
			bosses.append(node)
		elif bool(node.get(&"is_miniboss")):
			minis.append(node)
	var list := bosses if not bosses.is_empty() else minis
	if list.is_empty():
		return {}
	if room != null:
		var inside: Array[Node] = []
		for node in list:
			if room.is_ancestor_of(node):
				inside.append(node)
		if not inside.is_empty():
			list = inside
	var boss := list[0]
	var boss_data: Object = boss.get(&"data")
	var info := {"id": str(boss_data.get(&"id")), "count": list.size(), "miniboss": bosses.is_empty()}
	var name := de_text(boss_data.get(&"display_name"), str(boss_data.get(&"id")))
	if boss.has_method(&"get_boss_tier"):
		var tier := int(boss.call(&"get_boss_tier"))
		var rules := class_script(&"BossRules")
		if tier > 0 and rules != null:
			name = "%s %s" % [name, str(rules.call(&"tier_numeral", tier))]
	info["name"] = name
	if boss.get(&"phase") != null:
		info["phase"] = int(boss.get(&"phase"))
	var health: Variant = boss.get(&"health")
	if health is Object and health != null and (health as Object).has_method(&"get_health"):
		info["hp"] = snappedf(float((health as Object).call(&"get_health")), 0.1)
		info["hp_max"] = snappedf(float((health as Object).call(&"get_max_health")), 0.1)
	if boss.has_method(&"is_in_intro"):
		info["intro"] = bool(boss.call(&"is_in_intro"))
	return info


## Co-op: {mode (solo/quick/guild), players, local_players, role (solo/local/host/client), online}.
## Never a room code (LobbyClient.room, NetDiagnostics) and no other player's name.
static func coop_info(tree: SceneTree) -> Dictionary:
	var info := {}
	if tree == null:
		return info
	var players := 0
	var local := 0
	for node in tree.get_nodes_in_group(&"player"):
		if is_instance_valid(node):
			players += 1
			if node.get(&"is_local") == null or bool(node.get(&"is_local")):
				local += 1
	var mode_script := class_script(&"GameMode")
	if mode_script != null:
		var mode: Variant = mode_script.call(&"of_tree", tree)
		if mode is Object and mode != null:
			info["mode"] = enum_key(&"GameMode", &"Kind", (mode as Object).get(&"kind")).to_lower()
			if (mode as Object).has_method(&"get_player_count"):
				players = maxi(players, int((mode as Object).call(&"get_player_count")))
	info["players"] = players
	info["local_players"] = local
	# Group lookup only: LobbyClient.of() / OnlineSession.of() would create a node.
	var lobby := tree.get_first_node_in_group(&"lobby_client")
	var online := lobby != null and lobby.has_method(&"is_in_room") and bool(lobby.call(&"is_in_room"))
	info["online"] = online
	if online:
		info["role"] = "host" if lobby.has_method(&"is_host") and lobby.call(&"is_host") else "client"
	else:
		info["role"] = "local" if players > 1 else "solo"
	return info


## Copies the ping of context.network (NetDiagnostics, connection.rtt_ms.last) to context.coop.ping_ms.
static func add_ping(context: Dictionary) -> void:
	var network: Variant = context.get("network", {})
	if not (network is Dictionary):
		return
	var connection: Variant = (network as Dictionary).get("connection", {})
	if connection is Dictionary and (connection as Dictionary).get("rtt_ms") is Dictionary:
		var coop: Dictionary = context.get("coop", {})
		coop["ping_ms"] = int((connection["rtt_ms"] as Dictionary).get("last", -1))
		context["coop"] = coop


## Deep copy of value without room codes (NetDiagnostics.snapshot carries connection.room and
## last_disconnect.room).
static func without_room_codes(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if not ROOM_CODE_KEYS.has(str(key)):
				result[key] = without_room_codes(value[key])
		return result
	if value is Array:
		var list: Array = []
		for item: Variant in value:
			list.append(without_room_codes(item))
		return list
	return value


## Platform, phone UI, input device, screen size and UI zoom.
static func device_info(tree: SceneTree) -> Dictionary:
	var info := {"platform": DevFeedbackUpload.platform(), "input": input_device()}
	info["mobile_ui"] = bool(MobileUiScript.is_phone())
	if MobileUiScript.is_forced():
		info["mobile_ui_forced"] = true
	info["touch_screen"] = bool(MobileUiScript.is_touch_screen())
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.window_get_current_screen()
		info["screen_size"] = _vec(DisplayServer.screen_get_size(screen))
		info["screen_scale"] = snappedf(DisplayServer.screen_get_scale(screen), 0.01)
	if tree != null:
		info["ui_zoom"] = snappedf(float(MobileUiScript.menu_zoom(tree.root)), 0.01)
		info["content_scale"] = snappedf(tree.root.content_scale_factor, 0.01)
	info["ui_size"] = str(MobileUiScript.SizeMode.find_key(MobileUiScript.size_mode)).to_lower()
	return info


## "mouse", "gamepad" or "touch" (InputDevice.shared().kind; DevFeedback's own record otherwise).
static func input_device() -> String:
	var script := class_script(&"InputDevice")
	if script != null:
		var device: Variant = script.call(&"shared")
		if device is Object and device != null and (device as Object).get(&"kind") != null:
			var key := enum_key(&"InputDevice", &"Kind", (device as Object).get(&"kind"))
			if INPUT_NAMES.has(key):
				return INPUT_NAMES[key]
	return _last_input if not _last_input.is_empty() else "mouse"


## DevFeedback passes every input event: the fallback for input_device().
static func note_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_input = "touch"
	elif event is InputEventJoypadButton:
		_last_input = "gamepad"
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_last_input = "gamepad"
	elif event is InputEventKey or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		_last_input = "mouse"


# --- texts -------------------------------------------------------------------------------------

## German text of a translation key whatever the game language (location stays comparable); the
## fallback (or the key itself) when there is none.
static func de_text(key: Variant, fallback := "") -> String:
	var text_key := str(key) if key != null else ""
	if text_key.is_empty():
		return fallback
	Loc.install()
	var translation := TranslationServer.get_translation_object("de")
	if translation != null:
		var text := String(translation.get_message(StringName(text_key)))
		if not text.is_empty():
			return text
	return fallback if not fallback.is_empty() else text_key


## Text of a key in the current game language (to recognise a shown title).
static func _translated(key: StringName) -> String:
	Loc.install()
	return String(TranslationServer.translate(key))


static func _short(text: String) -> String:
	text = text.strip_edges()
	return text if text.length() <= MAX_TITLE else text.substr(0, MAX_TITLE - 1) + "…"


## Visible Controls whose rectangle meets rect, smallest first (then deepest), at most MAX_NODES.
static func ui_nodes_in(root: Node, rect: Rect2, exclude: Node = null) -> Array:
	var found: Array[Dictionary] = []
	_walk_ui(root, rect, exclude, 0, found)
	found.sort_custom(_by_area_then_depth)
	return _strip(found.slice(0, MAX_NODES))


## Visible sprites, lights, scripted Node2D and TileMapLayers under rect, at most MAX_NODES; tile
## layers (with the tiles under the rect) first, then the rest smallest first.
static func world_nodes_in(root: Node, rect: Rect2, exclude: Node = null) -> Array:
	var tiles: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	_walk_world(root, rect, exclude, 0, tiles, others)
	others.sort_custom(_by_area_then_depth)
	var result := tiles.slice(0, MAX_TILE_LAYERS)
	result.append_array(others.slice(0, MAX_NODES - result.size()))
	return _strip(result)


## One readable German line for index.md, the admin list and the overview (at most 200 characters):
## "Dungeon · Raum 23 · Schleimgrotte · Kampf + Upgrade · Arena · Bosskampf: Knochenkönig (Phase 2)
## · Pausemenü", "Hauptmenü · Online · Gilden · Gildenseite", "Dorf · Schmiede".
static func describe_location(context: Dictionary) -> String:
	var parts: PackedStringArray = []
	var phase := str(context.get("phase", ""))
	match phase:
		"menu", "village", "dungeon":
			parts.append(phase_label(phase))
		_:
			parts.append(str(context.get("scene_name", "?")))
	var dungeon: Dictionary = context.get("dungeon", {})
	if not dungeon.is_empty():
		if dungeon.has("room_index"):
			parts.append("Raum %d" % int(dungeon["room_index"]))
		for key in ["biome_name", "room_type_name", "genre_name"]:
			var value := str(dungeon.get(key, ""))
			if not value.is_empty() and value != "<null>" and not parts.has(value):
				parts.append(value)
		var side_view := bool(dungeon.get("side_view", false))
		for player: Variant in context.get("players", []):
			if player is Dictionary and bool((player as Dictionary).get("side_view", false)):
				side_view = true
		if side_view:
			parts.append("Seitenansicht")
	var boss: Dictionary = context.get("boss", {})
	if not boss.is_empty():
		var fight := "%s: %s" % ["Miniboss" if bool(boss.get("miniboss", false)) else "Bosskampf", str(boss.get("name", "?"))]
		if boss.has("phase"):
			fight += " (Phase %d)" % int(boss["phase"])
		parts.append(fight)
	var screen: Dictionary = context.get("screen", {})
	for part: Variant in screen.get("parts", []):
		parts.append(str(part))
	if parts.size() == 1 and not ["menu", "village", "dungeon"].has(phase) and str(context.get("scene", "")) != "":
		parts.append(str(context["scene"]).get_file())
	var line := " · ".join(parts)
	return line if line.length() <= 200 else line.substr(0, 199) + "…"


## First node below from whose script (or a base script) has the given class_name.
static func find_by_class(from: Node, global_name: StringName, exclude: Node = null) -> Node:
	if from == null or from == exclude:
		return null
	if has_class(from, global_name):
		return from
	for child in from.get_children():
		var hit := find_by_class(child, global_name, exclude)
		if hit != null:
			return hit
	return null


static func has_class(node: Object, global_name: StringName) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if script.get_global_name() == global_name:
			return true
		script = script.get_base_script()
	return false


## Constant of a global script class (e.g. RoomTiles.TILE_WORLD), or fallback.
static func class_constant(global_name: StringName, constant: StringName, fallback: Variant) -> Variant:
	var script := class_script(global_name)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(constant, fallback)


static func class_script(global_name: StringName) -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if StringName(entry.get("class", "")) == global_name:
			return load(str(entry.get("path", ""))) as Script
	return null


static func enum_key(global_name: StringName, enum_name: StringName, value: Variant) -> String:
	var values: Variant = class_constant(global_name, enum_name, {})
	if values is Dictionary:
		var key: Variant = (values as Dictionary).find_key(int(value)) if typeof(value) == TYPE_INT else null
		if key != null:
			return str(key)
	return str(value)


static func _phase_name(tree: SceneTree) -> String:
	var manager := tree.root.get_node_or_null(^"GameManager")
	if manager == null or not manager.has_method(&"get_phase"):
		return ""
	var phase: int = manager.call(&"get_phase")
	var phases: Variant = manager.get_script().get_script_constant_map().get(&"Phase", {})
	if phases is Dictionary:
		var key: Variant = (phases as Dictionary).find_key(phase)
		if key != null:
			return str(key).to_lower()
	return str(phase)


static func _pause_reasons(tree: SceneTree) -> Array:
	var reasons: Array = []
	var manager := tree.root.get_node_or_null(^"GameManager")
	if manager == null:
		return reasons
	var active: Variant = manager.get(&"_pause_reasons")
	if active is Dictionary:
		for reason: Variant in (active as Dictionary).keys():
			if StringName(reason) != DevFeedback.PAUSE_REASON:
				reasons.append(str(reason))
	return reasons


static func _window_info(tree: SceneTree) -> Dictionary:
	var info := {
		"view_size": _vec(tree.root.get_visible_rect().size),
		"content_scale": tree.root.content_scale_factor,
	}
	if DisplayServer.get_name() != "headless":
		info["window_size"] = _vec(DisplayServer.window_get_size())
		info["mode"] = DisplayServer.window_get_mode()
	return info


static func _camera_info(tree: SceneTree) -> Dictionary:
	var camera := tree.root.get_camera_2d()
	if camera == null:
		return {}
	return {
		"path": str(camera.get_path()),
		"zoom": _vec(camera.zoom),
		"position": _vec(camera.get_screen_center_position()),
	}


static func _dungeon_info(dungeon: Node) -> Dictionary:
	var info := {"path": str(dungeon.get_path())}
	var seed_value: Variant = dungeon.call(&"get_run_seed") if dungeon.has_method(&"get_run_seed") else dungeon.get(&"_run_seed")
	if seed_value != null:
		# As text: 64-bit seeds do not survive JSON readers that use doubles.
		info["seed"] = str(seed_value)
	if dungeon.has_method(&"get_active_slot"):
		info["slot"] = dungeon.call(&"get_active_slot")
	if dungeon.has_method(&"get_active_room_index"):
		info["room_index"] = dungeon.call(&"get_active_room_index")
	var room: Node = null
	if dungeon.has_method(&"get_room_at_slot") and info.has("slot"):
		room = dungeon.call(&"get_room_at_slot", info["slot"]) as Node
	if room == null and dungeon.has_method(&"get_room") and info.has("room_index"):
		room = dungeon.call(&"get_room", info["room_index"]) as Node
	var room_index := int(info.get("room_index", 0))
	if room_index > 0:
		# Same count as the HUD line "Zyklus n" (RoomSequence.CYCLE_LENGTH).
		var cycle_length := int(class_constant(&"RoomSequence", &"CYCLE_LENGTH", 5))
		info["cycle"] = floori(float(room_index - 1) / maxi(1, cycle_length)) + 1
		var sequence := class_script(&"RoomSequence")
		if sequence != null:
			var biome_index: Variant = sequence.call(&"get_biome", room_index)
			info["biome_name"] = de_text(sequence.call(&"get_biome_name_key", biome_index),
					str(sequence.call(&"get_biome_name", biome_index)))
	if room == null:
		return info
	info["_room"] = room
	info["room_path"] = str(room.get_path())
	info["template"] = room.scene_file_path
	for key: StringName in [&"slot_index", &"is_arena", &"is_ambush", &"is_extra_dark", &"has_portal"]:
		var value: Variant = room.get(key)
		if value != null:
			info[str(key)] = value
	var type_value: Variant = room.get(&"room_type")
	if type_value != null:
		info["room_type"] = enum_key(&"RoomSequence", &"RoomType", type_value)
		# Readable like the HUD line (HUD_ROOM_TYPE_*), German.
		var sequence_script := class_script(&"RoomSequence")
		var german_type := str(sequence_script.call(&"get_type_name", type_value)) if sequence_script != null else ""
		info["room_type_name"] = de_text("HUD_ROOM_TYPE_" + str(info["room_type"]), german_type)
	var kind_value: Variant = room.get(&"room_kind")
	if kind_value != null:
		info["room_kind"] = enum_key(&"RoomSequence", &"RoomKind", kind_value)
	var size_value: Variant = room.get(&"room_size_class")
	if size_value != null:
		info["room_size"] = enum_key(&"RoomSequence", &"RoomSize", size_value)
	var special: Variant = room.get(&"special_type")
	if special != null and int(special) >= 0:
		info["special_type"] = enum_key(&"RoomSequence", &"SpecialType", special)
	if room.has_method(&"is_campfire") and room.call(&"is_campfire"):
		info["campfire"] = true
	if room.has_method(&"get_variant_id"):
		info["variant"] = str(room.call(&"get_variant_id"))
	var signs := class_script(&"DoorSigns")
	if signs != null:
		info["mode"] = str(signs.call(&"mode_of", room))
	if dungeon.has_method(&"get_room_kind_label"):
		info["kind_label"] = str(dungeon.call(&"get_room_kind_label", room))
	var genre_script := class_script(&"RoomGenre")
	if genre_script != null and has_class(room, &"RoomController"):
		var genre := str(genre_script.call(&"of_room", room))
		var table: Variant = class_constant(&"RoomGenre", &"TABLE", {})
		if not genre.is_empty():
			info["genre"] = genre
			if table is Dictionary and (table as Dictionary).has(StringName(genre)):
				var genre_key := str(((table as Dictionary)[StringName(genre)] as Dictionary).get("key", ""))
				info["genre_name"] = de_text(genre_key + "_TITLE", genre.capitalize())
	var spawner: Variant = room.get(&"spawner")
	if spawner is Object and is_instance_valid(spawner) and (spawner as Object).has_method(&"get_biome"):
		var biome: Variant = (spawner as Object).call(&"get_biome", room_index)
		if biome is Object and biome != null:
			info["biome"] = str((biome as Object).get(&"id"))
			var display: Variant = (biome as Object).get(&"display_name")
			if display != null and str(display) != "":
				# display_name is a translation key (BIOME_SLIME_GROTTO): German text.
				info["biome_name"] = de_text(display)
	return info


static func _players_info(tree: SceneTree, room: Node) -> Array:
	var players: Array = []
	var tile_world := float(class_constant(&"RoomTiles", &"TILE_WORLD", TILE_WORLD_FALLBACK))
	var origin := Vector2i.ZERO
	var has_origin := false
	if room is Node2D:
		origin = Vector2i(((room as Node2D).position / tile_world).round())
		has_origin = true
	for node in tree.get_nodes_in_group(&"player"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var player := node as Node2D
		var tile := Vector2i((player.global_position / tile_world).floor())
		var entry := {
			"path": str(player.get_path()),
			"position": _vec(player.global_position),
			"tile": _vec(tile),
		}
		if has_origin:
			entry["room_tile"] = _vec(tile - origin)
		if player.has_method(&"is_side_view"):
			entry["side_view"] = player.call(&"is_side_view")
		players.append(entry)
	return players


static func _walk_ui(node: Node, rect: Rect2, exclude: Node, depth: int, found: Array[Dictionary]) -> void:
	if node == exclude or _skips_subtree(node, depth):
		return
	if node is Control:
		var control := node as Control
		var bounds := control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
		bounds = bounds.abs()
		if bounds.get_area() > 0.0 and bounds.intersects(rect):
			var entry := _base_entry(control, bounds, depth)
			var text := _text_of(control)
			if not text.is_empty():
				entry["text"] = text
			var texture := _texture_of(control)
			if not texture.is_empty():
				entry["texture"] = texture
			entry["plain"] = text.is_empty() and texture.is_empty() and control.get_script() == null \
					and LAYOUT_CLASSES.has(control.get_class())
			found.append(entry)
	for child in node.get_children():
		_walk_ui(child, rect, exclude, depth + 1, found)


static func _walk_world(node: Node, rect: Rect2, exclude: Node, depth: int,
		tiles: Array[Dictionary], others: Array[Dictionary]) -> void:
	if node == exclude or _skips_subtree(node, depth):
		return
	if node is TileMapLayer:
		var layer_entry := _tile_layer_entry(node as TileMapLayer, rect, depth)
		if not layer_entry.is_empty():
			tiles.append(layer_entry)
	elif node is Node2D:
		var item := node as Node2D
		var xform := item.get_global_transform_with_canvas()
		var local := _local_rect(item)
		var entry := {}
		if local.size != Vector2.ZERO:
			var bounds := (xform * local).abs()
			if bounds.intersects(rect):
				entry = _base_entry(item, bounds, depth)
		elif item.get_script() != null and not _has_node2d_child(item) and rect.has_point(xform.origin):
			# Scripted leaf without a texture (drawn in _draw, particles): its origin counts.
			entry = _base_entry(item, Rect2(xform.origin, Vector2.ZERO), depth)
			entry["area"] = rect.get_area()
		if not entry.is_empty():
			var texture := _texture_of(item)
			if not texture.is_empty():
				entry["texture"] = texture
			entry["z_index"] = item.z_index
			var holder := _scripted_ancestor(item)
			if holder != null and holder != item:
				entry["holder"] = str(holder.get_path())
				entry["holder_script"] = (holder.get_script() as Script).resource_path
			if item.owner != null and item.owner.scene_file_path != "":
				entry["scene"] = item.owner.scene_file_path
			others.append(entry)
	for child in node.get_children():
		_walk_world(child, rect, exclude, depth + 1, tiles, others)


## Hidden canvas items and layers hide their subtree; nested viewports and windows draw elsewhere.
static func _skips_subtree(node: Node, depth: int) -> bool:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return true
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return true
	return depth > 0 and (node is Viewport)


static func _base_entry(node: Node, bounds: Rect2, depth: int) -> Dictionary:
	var script := node.get_script() as Script
	return {
		"path": str(node.get_path()),
		"class": node.get_class(),
		"script": script.resource_path if script != null else "",
		"rect": _rect_dict(bounds),
		"area": bounds.get_area(),
		"depth": depth,
	}


static func _local_rect(item: Node2D) -> Rect2:
	if item is Sprite2D:
		var sprite := item as Sprite2D
		return sprite.get_rect() if sprite.texture != null else Rect2()
	if item is AnimatedSprite2D:
		var animated := item as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return Rect2()
		if animated.sprite_frames.get_frame_count(animated.animation) <= animated.frame:
			return Rect2()
		var frame_texture := animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if frame_texture == null:
			return Rect2()
		var size := frame_texture.get_size()
		var top_left := animated.offset - (size / 2.0 if animated.centered else Vector2.ZERO)
		return Rect2(top_left, size)
	if item is PointLight2D:
		var light := item as PointLight2D
		if light.texture == null:
			return Rect2()
		var light_size := light.texture.get_size() * light.texture_scale
		return Rect2(light.offset - light_size / 2.0, light_size)
	if item is Polygon2D:
		var polygon := (item as Polygon2D).polygon
		if polygon.size() < 3:
			return Rect2()
		var poly_rect := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			poly_rect = poly_rect.expand(point)
		return poly_rect
	return Rect2()


static func _tile_layer_entry(layer: TileMapLayer, rect: Rect2, depth: int) -> Dictionary:
	if layer.tile_set == null:
		return {}
	var local := (layer.get_global_transform_with_canvas().affine_inverse() * rect).abs()
	var from := layer.local_to_map(local.position)
	var to := layer.local_to_map(local.end)
	var counts := {}
	var cells := 0
	var used := 0
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			cells += 1
			if cells > MAX_TILE_CELLS:
				break
			var cell := Vector2i(x, y)
			var source := layer.get_cell_source_id(cell)
			if source < 0:
				continue
			used += 1
			var key := "%d:%d,%d" % [source, layer.get_cell_atlas_coords(cell).x, layer.get_cell_atlas_coords(cell).y]
			counts[key] = int(counts.get(key, 0)) + 1
	if used == 0:
		return {}
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var top: Array = []
	for key: String in keys.slice(0, MAX_TILES_PER_LAYER):
		top.append({"tile": key, "cells": counts[key]})
	var entry := _base_entry(layer, rect, depth)
	entry["tile_set"] = layer.tile_set.resource_path
	entry["cells_in_rect"] = used
	entry["cell_range"] = {"from": _vec(from), "to": _vec(to)}
	entry["tiles"] = top
	entry["z_index"] = layer.z_index
	if layer.owner != null and layer.owner.scene_file_path != "":
		entry["scene"] = layer.owner.scene_file_path
	return entry


static func _has_node2d_child(node: Node) -> bool:
	for child in node.get_children():
		if child is Node2D:
			return true
	return false


static func _scripted_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if current.get_script() != null:
			return current
		current = current.get_parent()
	return null


static func _text_of(control: Control) -> String:
	var text := ""
	if control is RichTextLabel:
		text = (control as RichTextLabel).get_parsed_text()
	else:
		var value: Variant = control.get(&"text")
		if value is String or value is StringName:
			text = str(value)
	text = text.strip_edges()
	if text.length() > MAX_TEXT:
		text = text.substr(0, MAX_TEXT - 1) + "…"
	return text


static func _texture_of(node: Node) -> String:
	for property: StringName in [&"texture", &"texture_normal", &"sprite_frames"]:
		var value: Variant = node.get(property)
		if value is Resource and value != null:
			var path := (value as Resource).resource_path
			return path if path != "" else (value as Resource).get_class()
	return ""


static func _by_area_then_depth(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("plain", false)) != bool(b.get("plain", false)):
		return not bool(a.get("plain", false))
	if not is_equal_approx(float(a["area"]), float(b["area"])):
		return float(a["area"]) < float(b["area"])
	return int(a["depth"]) > int(b["depth"])


## Drops the sort helpers from the entries.
static func _strip(entries: Array) -> Array:
	for entry: Dictionary in entries:
		entry.erase("area")
		entry.erase("depth")
		entry.erase("plain")
	return entries


static func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": snappedf(rect.position.x, 0.1), "y": snappedf(rect.position.y, 0.1),
			"w": snappedf(rect.size.x, 0.1), "h": snappedf(rect.size.y, 0.1)}


static func _vec(value: Variant) -> Array:
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector2:
		return [snappedf(value.x, 0.1), snappedf(value.y, 0.1)]
	return []
