class_name DungeonTexts
extends RefCounted
## All texts of the dungeon menus, room genre banners and first-time cards (UX2) in one table:
## translation key -> German text. The translation round (D-111, UX3: localization/translations.csv,
## columns keys,en,de) can copy DE as the "de" column. t() takes the TranslationServer text once the
## key is registered there (Loc.install()), otherwise the German text from this table, so the game
## shows the same German texts until the keys exist.
## Keys follow the localization scheme BEREICH_NAME (localization/README.md). The arena and ambush
## keys are WaveRules' own (A5: ROOM_ARENA_*, ROOM_AMBUSH_*); trial and pact explanations are copies
## of TrialContent / altar constants for the export, test_ux2_menus checks they still match.

const DE: Dictionary[StringName, String] = {
	# --- Menu kit: keys and footers ---
	&"MENU_PAUSED": "Spiel pausiert",
	&"MENU_KEY_ENTER": "Enter",
	&"MENU_KEY_ESC": "Esc",
	&"MENU_KEY_TAB": "Tab",
	&"MENU_KEY_ARROWS": "←→",
	&"MENU_HINT_PICK": "wählen",
	&"MENU_HINT_BUY": "kaufen",
	&"MENU_HINT_CONFIRM": "bestätigen",
	&"MENU_HINT_LATER": "später",
	&"MENU_HINT_CLOSE": "schließen",
	&"MENU_HINT_CANCEL": "abbrechen",
	&"MENU_HINT_REPLACE": "ersetzen",
	&"MENU_HINT_MOVE": "auswählen",
	&"MENU_CHOOSE": "Wählen",
	&"MENU_CLOSE": "Schließen",
	&"MENU_CANCEL": "Abbrechen",
	&"MENU_YES": "Ja",
	&"MENU_NO": "Nein",
	# --- Card states (UX2: badges instead of half transparency) ---
	&"STATE_TOO_LITTLE_GOLD": "zu wenig Gold",
	&"STATE_SOLD": "Verkauft",
	&"STATE_AT_LIMIT": "Am Limit",
	&"STATE_HP_FULL": "HP voll",
	&"STATE_SHIELD_FULL": "Schild voll",
	&"STATE_OWNED": "Im Besitz",
	&"STATE_NOT_POSSIBLE": "Nicht möglich",
	&"STATE_REPLACE_SLOT": "Slot ersetzen",
	&"STATE_NEW": "Neu",
	&"STATE_MAX": "Max",
	# --- Upgrade choice ---
	&"UPGRADE_EYEBROW": "Upgrade-Wahl",
	&"UPGRADE_SUBTITLE": "Wähle ein Upgrade – es gilt für den ganzen Run.",
	&"UPGRADE_SUBTITLE_STACKS": "Wähle ein Upgrade – es steigt um %d Stufen.",
	&"UPGRADE_STACKS_LIMITED": "%d / %d → %d / %d",
	&"UPGRADE_STACKS_UNLIMITED": "Stufe %d → %d · unbegrenzt",
	&"CATEGORY_ATTRIBUTE": "Attribut",
	&"CATEGORY_MECHANIC": "Mechanik",
	&"CATEGORY_EFFECT": "Effekt",
	# --- Shop ---
	&"SHOP_EYEBROW": "Spezialraum",
	&"SHOP_TITLE": "Händler",
	&"SHOP_SUBTITLE": "Run-Gold gegen Upgrades, Waffen, Heilung und Schild.",
	&"SHOP_EMPTY_SLOT": "kein %d. Angebot",
	&"SHOP_KIND_UPGRADE": "Upgrade · %s",
	&"SHOP_KIND_WEAPON": "Waffe",
	&"SHOP_KIND_HEAL": "Heilung",
	&"SHOP_KIND_SHIELD": "Schild",
	# --- Weapon slot ---
	&"WEAPON_EYEBROW": "Waffe aufnehmen",
	&"WEAPON_TITLE": "Waffe ersetzen?",
	&"WEAPON_SUBTITLE": "Beide Slots sind belegt. Welche Waffe soll weg?",
	&"WEAPON_OFFER": "Angebot",
	&"WEAPON_SLOT": "Slot %d",
	&"WEAPON_SLOT_ACTIVE": "Slot %d · aktiv",
	&"WEAPON_EMPTY": "leer",
	&"WEAPON_VALUES_NOTE": "Werte inkl. aktiver Upgrades.",
	# --- Choices and confirmations (portal, pact altar) ---
	&"CHOICE_EYEBROW": "Entscheidung",
	# --- Campfire ---
	&"CAMPFIRE_EYEBROW": "Rast",
	&"CAMPFIRE_TITLE": "Rast am Lagerfeuer",
	&"CAMPFIRE_SUBTITLE": "Eine Wahl: Wunden versorgen oder ein Upgrade um eine Stufe stärken.",
	&"CAMPFIRE_LIFE": "Leben",
	&"CAMPFIRE_HEAL": "Heilen",
	&"CAMPFIRE_HEAL_AMOUNT": "+%s HP",
	&"CAMPFIRE_HEAL_FULL": "Leben ist voll",
	&"CAMPFIRE_OR_UPGRADE": "Oder ein Upgrade stärken",
	&"CAMPFIRE_NO_UPGRADE": "Kein Upgrade zum Stärken (keines oder alle am Limit).",
	&"CAMPFIRE_STACK_LIMITED": "%d / %d → %d / %d",
	&"CAMPFIRE_STACK_UNLIMITED": "Stufe %d → %d",
	# --- Tab overview ---
	&"OVERVIEW_EYEBROW": "Raum %d",
	&"OVERVIEW_TITLE": "Übersicht",
	&"OVERVIEW_UPGRADES": "Upgrades dieses Runs · %d Stacks",
	&"OVERVIEW_NO_UPGRADES": "Noch keine Upgrades.",
	&"OVERVIEW_VALUES": "Effektive Werte",
	&"OVERVIEW_STATS": "HP %s / %s · Schild %s (Softcap %s) · Dash %s s",
	&"OVERVIEW_CURSES": "Flüche bis zum Ende des Runs",
	&"OVERVIEW_SLOT": "Slot %d",
	&"OVERVIEW_SLOT_ACTIVE": "Slot %d · aktiv",
	# --- Run end (GameUI) ---
	&"RUNEND_EYEBROW": "Run-Ende",
	&"RUNEND_DEATH": "Du bist gefallen",
	&"RUNEND_EXIT": "Dungeon verlassen",
	&"RUNEND_ABORT": "Run abgebrochen",
	&"RUNEND_SUBTITLE": "Erreichter Raum %d · Zyklus %d",
	&"RUNEND_RECORD": "Neuer Rekord! (bisher Raum %d)",
	&"RUNEND_CAUSE": "Todesursache: %s",
	&"RUNEND_ROOMS": "Räume",
	&"RUNEND_KILLS": "Gegner",
	&"RUNEND_UPGRADES": "Upgrades",
	&"RUNEND_TIME": "Zeit",
	&"RUNEND_GOLD_EARNED": "Run-Gold gesammelt",
	&"RUNEND_GOLD_LEFT": "Run-Gold übrig",
	&"RUNEND_PAYOUT": "Gutschrift (%s)",
	&"RUNEND_CRYSTALS": "Seelenkristalle (%s)",
	&"RUNEND_VILLAGE_GOLD": "Gold im Dorf",
	&"RUNEND_TO_VILLAGE": "Zurück ins Dorf",
	&"RUNEND_NEW_RUN": "Neuer Run",
	&"RUNEND_HINT_VILLAGE": "Dorf",
	&"RUNEND_HINT_NEW_RUN": "neuer Run",
	&"RUNEND_FOOTNOTE": "Alle Rekorde stehen in der Chronik im Dorf.",
	# --- Room genres (D-110): banners and first-time cards. Arena/ambush keys come from WaveRules (A5). ---
	&"ROOM_EYEBROW_COMBAT": "Raum %d · Kampfraum",
	&"ROOM_EYEBROW_SPECIAL": "Raum %d · Spezialraum",
	&"ROOM_EYEBROW_TRIAL": "Raum %d · Prüfung",
	&"ROOM_EYEBROW_REST": "Rast zwischen den Gebieten",
	&"ROOM_EYEBROW_WAGER": "Raum %d · Wagnis",
	&"ROOM_INTRO_EYEBROW": "Neu: %s",
	# Arena and ambush (A5)
	&"ROOM_ARENA_TITLE": "Arena",
	&"ROOM_ARENA_SUB": "Überlebe alle Wellen",
	&"ROOM_ARENA_INTRO": "Gegner kommen in Wellen aus den Toren in den Wänden – überlebe alle Wellen.",
	&"ROOM_AMBUSH_TITLE": "Hinterhalt!",
	&"ROOM_AMBUSH_SUB": "Sie brechen aus den Wänden",
	&"ROOM_AMBUSH_INTRO": "Der Raum war nicht leer: Gegner brechen aus den Wänden – überlebe alle Wellen.",
	# Catacomb and chasm (A3, A4)
	&"ROOM_CATACOMB_TITLE": "Katakombe",
	&"ROOM_CATACOMB_SUB": "Sackgassen im Dunkeln",
	&"ROOM_CATACOMB_INTRO": "Enge Gänge im Dunkeln: In den Sackgassen lauern Gegner – in der tiefsten wartet eine Truhe.",
	&"ROOM_CHASM_TITLE": "Abgrund",
	&"ROOM_CHASM_SUB": "Mit Dash über die Lücken",
	&"ROOM_CHASM_INTRO": "Mit %s (Dash) über Abgründe springen – Herunterfallen kostet ein Herz. Starker Rückstoß stößt Gegner hinein.",
	# First abyss outside a chasm room (small holes, A4; ChasmRules.get_hint_entry)
	&"HINT_CHASM_TITLE": "Abgrund",
	&"HINT_CHASM_TEXT": "Mit %s (Dash) über Löcher springen – Herunterfallen kostet ein Herz. Starker Rückstoß stößt Gegner hinein.",
	# Trials (A8)
	&"ROOM_TRIAL_SUB": "Truhe am Ende · makellos +1 Kristall",
	&"ROOM_TRIAL_GAUNTLET_TITLE": "Spießrutenlauf",
	&"ROOM_TRIAL_GAUNTLET_INTRO": "Der Weg zum Ausgang ist sicher. Lauf durch den Parcours zur Truhe – ohne Fehler gibt es zusätzlich einen Seelenkristall. Fehler kosten ½ Herz, nie den Run. Stacheln, Flammen und Pendelklingen haben ihren eigenen Takt: warte die Lücke ab.",
	&"ROOM_TRIAL_LIGHT_RUN_TITLE": "Lichtlauf",
	&"ROOM_TRIAL_LIGHT_RUN_INTRO": "Der Weg zum Ausgang ist sicher. Lauf durch den Parcours zur Truhe – ohne Fehler gibt es zusätzlich einen Seelenkristall. Fehler kosten ½ Herz, nie den Run. Die Fackeln erlöschen nacheinander. Bleib im Licht – im Dunkeln kostet es alle 2 s ½ Herz.",
	&"ROOM_TRIAL_CRUMBLE_TITLE": "Bröckelboden",
	&"ROOM_TRIAL_CRUMBLE_INTRO": "Der Weg zum Ausgang ist sicher. Der Boden des Parcours bricht kurz nach dem Betreten hinter dir weg – bleib in Bewegung und spring mit Dash über die Lücken. Ein Sturz kostet ein Herz, nie den Run; ohne Fehler gibt es zusätzlich einen Seelenkristall.",
	# Altars (A8, A7)
	&"ROOM_PACT_TITLE": "Pakt-Altar",
	&"ROOM_PACT_SUB": "Stärkeres Upgrade gegen einen Fluch",
	&"ROOM_PACT_INTRO": "Ein Pakt gibt ein stärkeres Upgrade – und einen Fluch bis zum Ende des Runs. Das gewöhnliche Upgrade kostet nichts.",
	&"ROOM_UPGRADE_ALTAR_TITLE": "Upgrade-Altar",
	&"ROOM_UPGRADE_ALTAR_SUB": "Ein Upgrade geschenkt",
	&"ROOM_UPGRADE_ALTAR_INTRO": "Ein Upgrade geschenkt: Geh mit E an den Altar und wähle eine von drei Karten.",
	&"ROOM_WAGER_TITLE": "Wagnis-Altar",
	&"ROOM_WAGER_SUB": "Prüfung oder Fluch – mit E annehmen",
	&"ROOM_WAGER_INTRO": "Der Altar bietet eine Bedingung an. Nimm sie mit E an, solange die Tür offen ist – wer besteht, bekommt eine Belohnung.",
	# Campfire (A6)
	&"ROOM_CAMPFIRE_TITLE": "Lagerfeuer",
	&"ROOM_CAMPFIRE_SUB": "Rast vor: %s",
	&"ROOM_CAMPFIRE_SUB_PLAIN": "Rast, bevor es weitergeht",
	&"ROOM_CAMPFIRE_INTRO": "Eine Wahl am Feuer: heilen oder ein Upgrade um eine Stufe stärken. Das Portal bringt dich mit 100 % Gold ins Dorf.",
	&"ROOM_CAMPFIRE_INTRO_NO_PORTAL": "Eine Wahl am Feuer: heilen oder ein Upgrade um eine Stufe stärken. Danach geht es ins nächste Gebiet.",
	# Special rooms
	&"ROOM_SHOP_TITLE": "Händler",
	&"ROOM_SHOP_SUB": "Upgrades, Waffen und Heilung gegen Gold",
	&"ROOM_SHOP_INTRO": "Gib dein Run-Gold beim Händler aus (E). Was du nicht ausgibst, nimmst du am Ende teilweise mit ins Dorf.",
	&"ROOM_WEAPON_TITLE": "Waffenauswahl",
	&"ROOM_WEAPON_SUB": "Nimm eine der Waffen",
	&"ROOM_WEAPON_INTRO": "Nimm eine der Waffen mit E. Du trägst zwei – sind beide Slots belegt, ersetzt du eine. Mit Q wechselst du.",
	&"ROOM_FOUNTAIN_TITLE": "Brunnen",
	&"ROOM_FOUNTAIN_SUB": "Einmal kostenlos heilen",
	&"ROOM_FOUNTAIN_INTRO": "Trink mit E aus dem Brunnen: Er heilt dich einmal kostenlos.",
	# Combat variants (A7, proposal until A7 names them)
	&"ROOM_SOUL_FLAME_TITLE": "Seelenflamme",
	&"ROOM_SOUL_FLAME_SUB": "Beschütze die Flamme",
	&"ROOM_SOUL_FLAME_INTRO": "Die Gegner wollen die Seelenflamme löschen. Beschütze sie – überlebt sie, wartet eine Bonus-Truhe.",
	&"ROOM_RIFTS_TITLE": "Beschwörungsrisse",
	&"ROOM_RIFTS_SUB": "Zerstöre die Risse",
	&"ROOM_RIFTS_INTRO": "Die Risse rufen immer neue Gegner. Zerstöre die Risse – erst dann ist der Raum geschafft.",
	&"ROOM_STONE_GUARDIAN_TITLE": "Steinwächter",
	&"ROOM_STONE_GUARDIAN_SUB": "Halte sie im Licht",
	&"ROOM_STONE_GUARDIAN_INTRO": "Steinwächter rücken nur im Dunkeln vor. Im Licht erstarren sie und sind verwundbar.",
	&"ROOM_LANTERN_TITLE": "Laternenträger",
	&"ROOM_LANTERN_SUB": "Bring das Licht zum Ausgang",
	&"ROOM_LANTERN_INTRO": "Trag die Seelenlaterne (E) zum Sockel am Ausgang. Mit ihr siehst du weiter, kämpfen kannst du nur ohne sie.",
	&"ROOM_GRAVEDIGGER_TITLE": "Totengräber",
	&"ROOM_GRAVEDIGGER_SUB": "Zerstöre die Knochen",
	&"ROOM_GRAVEDIGGER_INTRO": "Besiegte Skelette stehen wieder auf. Zerstöre ihre Knochenhaufen schnell – drüberlaufen, Dash oder ein Treffer.",
	&"ROOM_BOUNTY_TITLE": "Kopfgeld",
	&"ROOM_BOUNTY_SUB": "Fang den Gekrönten",
	&"ROOM_BOUNTY_INTRO": "Ein Gegner mit Goldkrone flieht zu einem Loch. Erwischst du ihn rechtzeitig, gibt es eine Bonus-Truhe.",
	&"ROOM_TORCH_ROOM_TITLE": "Fackelraum",
	&"ROOM_TORCH_ROOM_SUB": "Entzünde die Fackeln",
	&"ROOM_TORCH_ROOM_INTRO": "Zünde die Fackeln mit Treffern oder E an – jede macht den Raum heller.",
	&"ROOM_ELITE_NEST_TITLE": "Elite-Nest",
	&"ROOM_ELITE_NEST_SUB": "Doppelte Kristalle",
	&"ROOM_ELITE_NEST_INTRO": "Nur wenige, aber starke Gegner – dafür doppelte Seelenkristalle.",
	# Combat variants in the room (A7): banners and world captions
	&"VARIANT_BONUS_TITLE": "Bonus erfüllt!",
	&"VARIANT_BONUS_SUB": "Eine Bonus-Truhe ist erschienen",
	&"VARIANT_CHEST_TITLE": "Bonus-Truhe",
	&"VARIANT_SOUL_FLAME_WAVE": "Angriff auf die Flamme",
	&"VARIANT_SOUL_FLAME_WAVE_SUB": "Fang sie ab!",
	&"VARIANT_SOUL_FLAME_HELD": "Die Flamme brennt",
	&"VARIANT_SOUL_FLAME_HELD_SUB": "Besiege die letzten Gegner",
	&"VARIANT_SOUL_FLAME_LOST": "Die Flamme ist erloschen",
	&"VARIANT_SOUL_FLAME_LOST_SUB": "Keine Bonus-Truhe – kämpf weiter",
	&"VARIANT_RIFT_CLOSED": "Riss geschlossen",
	&"VARIANT_RIFT_CLOSED_SUB": "Noch %d",
	&"VARIANT_RIFTS_ALL_CLOSED_SUB": "Alle Risse sind zu",
	&"VARIANT_GRAVEDIGGER_RISE": "Ein Skelett steht wieder auf!",
	&"VARIANT_BOUNTY_SPOTTED": "Der Gekrönte flieht!",
	&"VARIANT_BOUNTY_SPOTTED_SUB": "Fang ihn in %d s",
	&"VARIANT_BOUNTY_CAUGHT": "Kopfgeld!",
	&"VARIANT_BOUNTY_ESCAPED": "Entkommen",
	&"VARIANT_BOUNTY_ESCAPED_SUB": "Keine Bonus-Truhe",
	# Wager altar (A7, D-104): conditions, rules, prompt and outcome
	&"WAGER_PROMPT": "Wagnis annehmen",
	&"WAGER_REWARD": "Belohnung: +%d Kristall",
	&"WAGER_DOOR_HINT": "Nur solange die Tür offen ist",
	&"WAGER_ACCEPTED": "Wagnis angenommen",
	&"WAGER_WON": "Wagnis bestanden!",
	&"WAGER_WON_SUB": "+%d Seelenkristall",
	&"WAGER_LOST": "Wagnis verloren",
	&"WAGER_LOST_SUB": "Keine weitere Strafe",
	&"WAGER_NO_HIT": "Kein Treffer",
	&"WAGER_NO_HIT_RULE": "Niemand darf getroffen werden",
	&"WAGER_UNDER_TIME": "Unter %d s",
	&"WAGER_UNDER_TIME_RULE": "Schaffe den Raum in %d s",
	&"WAGER_SECONDARY_ONLY": "Nur Zweitwaffe",
	&"WAGER_SECONDARY_ONLY_RULE": "Kämpfe nur mit der zweiten Waffe",
	&"WAGER_CURSE_GLOOM": "Fluch: Düsternis",
	&"WAGER_CURSE_GLOOM_RULE": "Lichtkreis −%d %% in diesem Raum",
	&"WAGER_CURSE_HASTE": "Fluch: Gehetzt",
	&"WAGER_CURSE_HASTE_RULE": "Gegner +%d %% Tempo in diesem Raum",
	&"WAGER_CURSE_NO_HEAL": "Fluch: Keine Heilung",
	&"WAGER_CURSE_NO_HEAL_RULE": "Keine Heilung in diesem Raum",
}


## Text of a key: the registered translation (TranslationServer) or the German text of DE,
## formatted with args. Unknown keys come back unchanged.
static func t(key: StringName, args: Array = []) -> String:
	var text := String(TranslationServer.translate(key))
	if text == String(key):
		text = DE.get(key, String(key))
	return text % args if not args.is_empty() else text


static func has_text(key: StringName) -> bool:
	return DE.has(key)


## Keys of the table in a stable order (export for the translation CSV).
static func get_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.assign(DE.keys())
	return keys


## The table as CSV lines "KEY,,"German"" (en column left empty for the translation round).
static func to_csv_lines() -> PackedStringArray:
	var lines := PackedStringArray(["keys,en,de"])
	for key in get_keys():
		lines.append('%s,"","%s"' % [key, DE[key].replace('"', '""')])
	return lines
