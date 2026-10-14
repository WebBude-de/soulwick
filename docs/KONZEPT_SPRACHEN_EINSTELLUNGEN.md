# Konzept: Sprachen und Einstellungen (UX3, D-111)

> Stand: 14.10.2026 · Paket UX3 aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · Beschluss [D-111](DECISIONS.md) (VERBINDLICH, Projektmitglied 14.10.2026): **Englisch Standard, Deutsch zweite Sprache**, Systemsprache automatisch, umschaltbar in den Optionen. Doku bleibt Deutsch.

## 1. Entscheidung in Kürze

- Zwei Sprachen im Spiel (und auf der Website): `en` (Standard) und `de`. Option `language` ∈ {`auto`, `en`, `de`}, Standard `auto`: Systemsprache Deutsch → `de`, alles andere → `en`.
- Alle Spieltexte laufen über **Übersetzungsschlüssel** in `localization/translations.csv`; Godot erzeugt daraus je Sprache eine `.translation`-Datei, die `Loc.install()` zur Laufzeit registriert. `project.godot` bleibt unverändert (kein neuer Autoload, D-044).
- In UX3 umgestellt: Hauptmenü (`ui/main_menu/**`) und Optionen (`ui/options/**`). Der Rest folgt in Runde zwei (Backlog in §9, Dungeon-Dialoge in UX2).
- Die Optionen sind ausgebaut (Sprache, Gesamtlautstärke, Fenstermodus, VSync, Spielgefühl-Schalter, Zurücksetzen) und in drei Reiter gegliedert, damit sie auch im Pausenmenü auf den 480×270-Bildschirm passen.

## 2. Bausteine

| Datei | Aufgabe |
| --- | --- |
| `localization/translations.csv` | Quelle der Wahrheit, Spalten `keys,en,de`, UTF-8 ohne BOM, Werte in Anführungszeichen, `\n` für Zeilenumbrüche. **101 Schlüssel** (14.10.2026). |
| `localization/translations.en.translation`, `translations.de.translation` | Von `godot --headless --path . --import` aus der CSV erzeugt, liegen neben der CSV, werden mit exportiert. Nach jeder CSV-Änderung neu importieren (Test `test_i18n` prüft, dass beide übereinstimmen). |
| `localization/loc.gd` (`class_name Loc`) | `install()` registriert beide Übersetzungen einmalig (Rückfall: liest die CSV direkt, falls die `.translation` fehlen). `apply(option)` setzt das Locale. `resolve(option, systemsprache)` ist die Regel aus §1 (Systemsprache als Parameter → testbar). `t(key, args)` übersetzt überall, auch außerhalb des Szenenbaums. `current_language()` liefert `en`/`de`. |
| `ui/options/game_options.gd` | Liest/schreibt alle Optionen über `SaveManager.get_option/set_option` (`settings.cfg [options]`, global, nicht je Spielstand) und wendet sie sofort an. `apply_all()` läuft beim Start (`scenes/main.gd`, `scenes/world_controller.gd`) und ruft `Loc.apply()` zuerst. |
| `ui/options/options_view.gd` | Die gemeinsame Optionsansicht (Hauptmenü-Panel und Pausenmenü), drei Reiter, Tastenmodell wie bisher. |
| `ui/options/controls_info.gd` | Tastenübersicht: Beschriftungen und Tastennamen als Schlüssel (`CONTROLS_*`, `KEY_*`), werden beim Aufruf übersetzt. |
| `tools/i18n_check.py` | Findet verbliebene deutsche Texte in `*.gd`/`*.tscn` (optional `*.tres`), schlägt Schlüssel vor, prüft die CSV. Exit 1 bei Funden. |
| `tests/unit/test_i18n.gd`, `tests/unit/test_ux_options.gd` | Vollständigkeit der CSV, Schlüssel im Code, Sprachregel, Live-Umschalten, alle Optionen. |

**Ablauf beim Start:** `main.gd._ready()` → `GameOptions.apply_all()` → `Loc.apply(option)` registriert die Übersetzungen und setzt das Locale, bevor das erste Menü gebaut wird. `MainMenu._ready()` ruft `GameOptions.apply_language()` zusätzlich auf (Sicherheit, falls ein Host `apply_all()` nicht aufruft); `OptionsView._init()` ruft `Loc.install()`.

## 3. Schlüsselschema

`BEREICH_NAME` in Großbuchstaben, Unterstriche, Englisch, keine Umlaute. Der Bereich ist der Ort oder die Rolle des Textes, nicht die Datei:

| Präfix | Bereich | Beispiele |
| --- | --- | --- |
| `COMMON_` | wiederverwendbare Wörter | `COMMON_BACK`, `COMMON_CANCEL`, `COMMON_ON`, `COMMON_OFF`, `COMMON_SOON` |
| `MENU_` | Hauptmenü-Liste, Tagline, Ecken | `MENU_CONTINUE`, `MENU_SLOTS_HINT` (`%d / %d`), `MENU_RECORD` (`%d`), `MENU_KEYS` (`%s`) |
| `SLOTS_` | Panel „Spielstände“ | `SLOTS_TITLE`, `SLOTS_EMPTY`, `SLOTS_SLOT_NUMBER` (`%d`), `SLOTS_DELETE_WARNING` (`%s`, `\n`) |
| `CREATE_` | Panel „Neuer Spielstand“ | `CREATE_TITLE`, `CREATE_FOOTER` (`%d`), `CREATE_START` |
| `OPTIONS_` | Optionen: Reiter `OPTIONS_TAB_*`, Abschnitte `OPTIONS_SECTION_*`, Zeilen und Werte | `OPTIONS_WINDOW_MODE`, `OPTIONS_BORDERLESS`, `OPTIONS_RESET_QUESTION` |
| `CONTROLS_` | Tastenübersicht (Beschriftung, `_NOTE` = Hinweis rechts) | `CONTROLS_DASH`, `CONTROLS_DASH_NOTE` |
| `KEY_` | Tastennamen | `KEY_SPACE`, `KEY_DELETE`, `KEY_MOUSE_LEFT`, `KEY_MOUSE_BUTTON` (`%d`) |

Vorschlag für Runde zwei (Präfixe, die `tools/i18n_check.py` vorschlägt): `HUD_`, `GAME_UI_` (Pausenmenü, Run-Ende), `DUNGEON_UI_` (Upgrade-Wahl, Händler, Lagerfeuer …, in UX2 ggf. `DIALOG_`), `VILLAGE_UI_`/`VILLAGE_`, `DUNGEON_` (Raum-Banner), `BOSS_INTRO_`, `HINT_`, `ENEMY_`/`UPGRADE_`/`WEAPON_` für Datennamen aus `.tres`.

Regeln: Platzhalter `%s`/`%d` in beiden Sprachen gleich oft und in gleicher Reihenfolge (Test und Werkzeug prüfen das). Eigennamen (`English`, `Deutsch`, `Esc`, `Enter`, `F11`, `VSync`) bleiben Klartext. Eyebrows werden nicht in der CSV großgeschrieben, sondern über `Label.uppercase = true` (so bleibt ein Schlüssel wie `MENU_SLOTS` für Titel und Eyebrow nutzbar).

## 4. Einen Text hinzufügen

1. Zeile in `localization/translations.csv`: `BEREICH_NAME,"English text","Deutscher Text"`.
2. `godot --headless --path . --import` (schreibt `translations.en/de.translation`).
3. Im Code:
   - **Einfacher Text:** `label.text = &"BEREICH_NAME"` bzw. `UiKit.text_label(&"BEREICH_NAME", …)`, `UiKit.button(&"…", …)`, `MenuPanel.action_button(&"…", "Esc", …)`. Godot übersetzt beim Setzen und bei jedem Sprachwechsel von selbst (`auto_translate_mode` erbt vom Fenster). Das gilt auch für `tooltip_text`.
   - **Zusammengesetzter Text:** in Knoten `tr(&"BEREICH_NAME") % [wert]`, sonst `Loc.t(&"BEREICH_NAME", [wert])`. Solche Texte in `_notification(NOTIFICATION_TRANSLATION_CHANGED)` neu setzen (§5).
   - **Eyebrow:** `UiKit.eyebrow(&"KEY")` und danach `label.uppercase = true`.
4. `python tools/i18n_check.py <ordner>` und `godot --headless --path . -s addons/gut/gut_cmdln.gd` (mindestens `test_i18n`).

Achtung: `Label.text`/`Button.text` liefern danach den **Schlüssel**, nicht den angezeigten Text. Getter für Tests geben deshalb `tr(text)` zurück (`MenuList.get_entry_text()`, `MenuPanel.get_footer_text()`, `OptionsView.get_caption_text()`, `OptionsView.get_footer_text()`).

## 5. Regel für das Live-Umschalten

`TranslationServer.set_locale()` schickt `NOTIFICATION_TRANSLATION_CHANGED` an jeden Knoten im Baum. Daraus folgt:

- Knoten, deren `text` ein Schlüssel ist, aktualisieren sich selbst: nichts tun.
- Jede Klasse mit zusammengesetzten Texten (Format-Argumente, Cursor „> “ vor einer Beschriftung, Tastennamen aus der InputMap, großgeschriebene Eyebrows mit Zahl) implementiert `_notification(what)` und setzt diese Texte bei `NOTIFICATION_TRANSLATION_CHANGED` neu. Dabei **nicht** auf `is_node_ready()` prüfen (ist in `_ready()` schon wahr), sondern auf die eigenen Knoten (`_list != null`), weil `GameOptions.apply_language()` auch aus `_ready()` heraus das Locale wechseln kann.
- Umgesetzt in: `MainMenu` (`refresh()`: Hinweise mit Zahlen, Rekord, Tastenzeile), `MenuPanel.set_header()`/`set_footer()`, `SlotPanel` (`refresh()`: Karten neu), `CreateSlotPanel` (Kopf mit Platznummer, Zeilen mit Cursor, Fußzeile), `OptionsView` (`_retranslate()`: Beschriftungen, Fußzeile, Tastenseite), `ControlsInfo` liefert immer die aktuelle Sprache.
- Knoten außerhalb des Baums bekommen keine Benachrichtigung; `ControlsHint` (Dungeon) baut seine Texte beim Öffnen, das reicht, weil die Sprache nur in den Optionen wechselt.
- Geprüft durch `test_i18n.test_open_main_menu_switches_language_at_once` (Liste, offenes Optionen-Panel, Spielstände-Panel) und `test_ux_options.test_language_row_switches_the_locale_and_the_open_view`.

## 6. Optionen

Alle Werte global in `settings.cfg [options]` (`SaveManager.get_option/set_option`), sofort gespeichert und angewendet; headless-sicher (keine `DisplayServer`-Aufrufe ohne Fenster).

| Option (Schlüssel) | Werte | Standard | Angewendet in | Bemerkung |
| --- | --- | --- | --- | --- |
| `language` | `auto` · `en` · `de` | `auto` | `Loc.apply()` → `TranslationServer.set_locale` | `auto`: `OS.get_locale_language() == "de"` → `de`, sonst `en` |
| `master_volume` | 0.0 … 1.0 (Schritt 0.05) | 1.0 | `AudioServer.set_bus_volume_db(Master)` | Als **Option**, nicht über `SaveManager.set_volume`: dessen `DEFAULT_VOLUMES` kennt nur `Music`/`SFX` und liest beim Laden nur diese zurück; ohne Hotspot-Änderung wäre Master nach dem Neustart weg. Musik/Effekte bleiben in `[audio]` wie bisher. |
| `window_mode` | `windowed` · `fullscreen` · `borderless` | `windowed` | `DisplayServer.window_set_mode/_flag/_size/_position` | Ersetzt das UX1-Bool `fullscreen`; `fullscreen=true` ohne `window_mode` wird als `fullscreen` gelesen. `is_fullscreen()` = Vollbild **oder** Randlos; `set_fullscreen()`/F11 schalten Vollbild ↔ Fenster. Randlos = rahmenloses Fenster in Bildschirmgröße; zurück zu „Fenster“ stellt 1280×720 zentriert her. |
| `vsync` | `true` · `false` | `true` | `DisplayServer.window_set_vsync_mode` | |
| `screen_shake` | `0.0` (Aus) · `0.5` (Schwach) · `1.0` (Normal) | `1.0` | `CameraShake.enabled = strength > 0`; Stärke über Haken (§8) | UX1-Bool wird gelesen: `false` → 0.0, `true` → 1.0. `is_screen_shake_enabled()` bleibt. |
| `hit_stop` | `true` · `false` | `true` | Haken `HitStop.trigger` (§8) | `GameOptions.is_hit_stop_enabled()` |
| `damage_numbers` | `true` · `false` | `true` | Haken `DamageNumber._spawn` (§8) | Statustexte („Betäubt!“) bleiben sichtbar |
| `reduce_flashes` | `true` · `false` | `false` | Haken `SpriteFx.flash`, `PostProcess.hit_pulse`, `LightSource.flash` (§8) | `GameOptions.get_flash_strength()`: 1.0 bzw. `REDUCED_FLASH_STRENGTH` = 0.35 (TESTWERT) |
| Zurücksetzen | – | – | `GameOptions.reset_to_defaults()` | Setzt alle Optionen und Musik/Effekte auf Standard, nie Spielstände; fragt vorher nach. |

**Bedienung (OptionsView):** Eyebrow „Optionen“, darunter die Reiter **Allgemein** (Ton: Musik, Effekte, Gesamt · Sprache), **Bild** (Anzeige: Fenstermodus, VSync · Spielgefühl: Bildschirmwackeln, Trefferstopp, Schadenszahlen, Blitze reduzieren) und **Tasten** (Übersicht aus `ControlsInfo` + „Tasten ändern: später“). ↑/↓ wandern durch Reiterzeile, Zeilen und den Knopf „Zurücksetzen“ (umlaufend), ←/→ ändern (auf der Reiterzeile: Reiter wechseln), Enter schaltet weiter bzw. löst „Zurücksetzen“ aus, Q/E wechseln den Reiter von überall, Esc bleibt dem Host (Panel bzw. Modal) außer in der Rückfrage. Alle Reiter haben dieselbe Höhe (höchste Seite), das Panel springt nicht. Die Startzeile ist „Musik“ wie in UX1 (`test_main_menu` erwartet, dass ← sofort die Musik regelt). Mausbedienung: Reiter klicken, Beschriftung hovern wählt die Zeile, Werte klicken.

## 7. Prüfungen (14.10.2026)

- `godot --headless --path . --import`: CSV → 2 `.translation`, `project.godot` unverändert.
- `validate_project`: 392 Dateien, 0 fehlgeschlagen (vor den Tests).
- GUT: siehe Bericht/Roadmap (Zahlen vor/nach).
- `python tools/i18n_check.py ui/options ui/main_menu` → 0 Funde, CSV ok.
- Fensterlauf: Screenshots Hauptmenü/Optionen/Spielstände/Pausenmenü je Sprache (Bericht).

## 8. Haken für den Integrator

Die Schalter sind gespeichert und in den Optionen bedienbar; damit sie wirken, je **eine Zeile** in Dateien außerhalb von UX3 (Besitz anderer Agenten):

| Datei · Stelle | Änderung |
| --- | --- |
| `components/visual/camera_shake.gd` Z. 16, `shake()` | `camera.add_trauma(strength * STRENGTH_TO_TRAUMA * GameOptions.get_screen_shake_strength())` (`enabled` bleibt als schneller Aus-Schalter, wird von `GameOptions` gesetzt). |
| `components/visual/hit_stop.gd` Z. 12 ff., `trigger()` | nach der `context`-Prüfung: `if not GameOptions.is_hit_stop_enabled(): return` |
| `ui/damage_numbers/damage_number.gd` Z. 32, `_spawn()` | erste Zeile: `if not GameOptions.are_damage_numbers_enabled(): return` (`spawn_text` für Statustexte bleibt). |
| `components/visual/sprite_fx.gd` Z. 16 ff., `flash()` | `var peak := GameOptions.get_flash_strength()`; `set_shader_parameter(&"flash", peak)` und den Tween von `peak` statt `1.0` starten. |
| `ui/effects/post_process.gd` Z. 73, `hit_pulse()` | `_chroma = maxf(_chroma, clampf(strength * GameOptions.get_flash_strength(), 0.0, 1.0))` |
| `components/visual/light_source.gd` Z. 17 ff., `flash()` (optional) | `light.intensity *= GameOptions.get_flash_strength()` vor dem Tween (Lichtblitze bei Explosionen/Türen). |
| `ui/boss_intro/boss_intro_view.gd` Z. 326 (optional) | `_flash.color.a = 0.35 * GameOptions.get_flash_strength()` |
| `tests/unit/test_main_menu.gd` `before_each()` | nach `SaveManager.load_game()`: `GameOptions.set_language(&"de")` (die Tests vergleichen deutsche Texte; auf einem englischen System schlagen sie sonst fehl). In `after_all()` `TranslationServer.set_locale(<in before_all gemerktes Locale>)`. Mittelfristig die Literale durch `Loc.t(&"MENU_CONTINUE")` usw. ersetzen. |
| `autoload/save_manager.gd` (optional, später) | Soll Master doch in `[audio]` liegen: `DEFAULT_VOLUMES` um `&"Master": 1.0` ergänzen und `GameOptions.MASTER_VOLUME` auf `SaveManager.set_volume` umstellen (einmalige Übernahme des Optionswerts). |
| `project.godot` | **keine Änderung nötig.** |

Kein Haken nötig für: `scenes/main.gd`/`world_controller.gd` (rufen `apply_all()` schon), `ui/menus/game_ui.gd` (Pausenmenü bettet `OptionsView` unverändert ein, geprüft in `test_ux_options`), `UiKit` (unverändert; `Label.uppercase` statt `to_upper()` für Eyebrows mit Schlüsseln).

## 9. Backlog Runde zwei: verbliebene deutsche Texte

`python tools/i18n_check.py --summary --no-csv .` (14.10.2026; `*.gd` + `*.tscn`, ohne `addons/`):

| Ordner | Funde | Hinweis |
| --- | --- | --- |
| `ui/menus` | 76 | `dungeon_ui.gd` 33 (Upgrade-Wahl, Händler, Lagerfeuer, Tab-Übersicht → **UX2**), `game_ui.gd` 23 (Pausenmenü, Run-Ende), `village_ui.gd` 20 |
| `dungeon` | 56 | Raum-Banner in `dungeon_manager.gd`, Altar/Brunnen/Waffenraum/Lagerfeuer-Inhalte, Zutaten-Namen |
| `meta` | 34 | Schmiede/Handelsposten/Chronik-Texte, `SaveSlots.default_name` („Spielstand %d“, auch im Hauptmenü sichtbar) |
| `world` | 13 | Dorf-Gebäude, NPC-Texte |
| `tools` | 19 | Generatoren und Sims (Ausgaben, kein Spieltext) |
| `ui/hud` | 8 | HUD-Beschriftungen |
| `ui/hints` | 5 | Steuerungs-Hinweis erster Raum (`ControlsHint.CAPTIONS` kann auf `ControlsInfo.caption()` umgestellt werden) |
| `ui/boss_intro` | 4 | Überspringen-Hinweise |
| `ui` | 3 | `ui_kit.gd`: `CATEGORY_NAMES`, Waffenwerte-Texte |
| `enemies` | 6 | Statustexte („Betäubt!“ u. ä.) |
| `player` | 6 | Interaktions-Prompts |
| `economy` | 2 | |
| `tests` | 91 | Erwartungswerte in Tests, werden mit den jeweiligen Modulen umgestellt |
| **gesamt** | **323** | |

Mit `--tres` (Datenressourcen) zusätzlich: `enemies` +47 (Gegnernamen, Boss-Story), `upgrades` 19, `weapons` 6, `characters` 4 → **399**. Für `.tres` bietet sich je Feld ein Schlüssel nach Namenskonvention an (z. B. `ENEMY_<ID>_NAME`, `UPGRADE_<ID>_DESC`), die der Code über `Loc.t()` auflöst; die Dateien selbst behalten dann nur noch den Schlüssel.

Empfohlene Reihenfolge: (1) `ui/menus/game_ui.gd` + `ui/hud` (sichtbar in jedem Run, klein), (2) `ui/menus/dungeon_ui.gd` zusammen mit dem Menü-Baukasten aus UX2, (3) `dungeon/` Banner und Rauminhalte, (4) Dorf (`world`, `meta`, `village_ui.gd`), (5) Daten (`.tres`). Jede Runde: `python tools/i18n_check.py <ordner>` muss 0 melden.

## 10. Offene Fragen

- Wortwahl Englisch: „Save slots“/„Slot“ und „Best: room %d“ sind Vorschläge; das Projektmitglied kann in der CSV frei ändern (danach `--import`).
- Soll „Gesamt“ (Master) langfristig in `[audio]` bei Musik/Effekte liegen (Hotspot `SaveManager`, siehe §8)?
- Randlos auf Mehrbildschirm-Systemen: nimmt den Bildschirm, auf dem das Fenster liegt. Reicht das, oder soll der Bildschirm wählbar werden?
- Tasten ändern (Rebinding) ist als „später“ angezeigt; eigenes Paket nach UX2?
- Website (playsoulwick.com) nutzt dieselben Sprachen; eine gemeinsame Wortliste (Glossar) für Spiel und Website wäre sinnvoll, Ort: `soulwick-platform/docs/`.
