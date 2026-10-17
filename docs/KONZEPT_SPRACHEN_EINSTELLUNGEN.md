# Sprachen und Einstellungen – Regeln (D-111)

> **Stand:** 17.10.2026 · **Gebaut** (UX3 und zweite Übersetzungsrunde, 14.10.2026). Hier stehen nur die Regeln; Bausteine und Ablauf im Code: `localization/` (mit Kurzanleitung in `localization/README.md`), `ui/options/game_options.gd`, `ui/options/options_view.gd`, Werkzeug `tools/i18n_check.py`.

## 1. Sprachen

- Zwei Sprachen im Spiel und auf der Website: **Englisch Standard, Deutsch zweite Sprache** (D-111). Option `language` = `auto` · `en` · `de`; `auto` nimmt Deutsch, wenn das System Deutsch ist, sonst Englisch.
- **Jeder Text im Spiel** läuft über einen Übersetzungsschlüssel in `localization/translations.csv` (Spalten `keys,en,de`, UTF-8 ohne BOM). Das gilt auch für Daten: Gegner, Bosse, Biome, Räume, Upgrades und Waffen speichern Schlüssel bzw. folgen einer Namenskonvention (D-164, `DataTexts`).
- Wörter für Spiel und Website: [GLOSSAR.md](GLOSSAR.md). Doku bleibt Deutsch, Code Englisch.
- Kein neuer Autoload: `Loc` registriert die Übersetzungen zur Laufzeit; `project.godot` bleibt dafür unverändert.

## 2. Schlüsselschema

`BEREICH_NAME` in Großbuchstaben, Englisch, keine Umlaute. Der Bereich ist der Ort oder die Rolle des Textes, nicht die Datei: z. B. `COMMON_`, `MENU_`, `OPTIONS_`, `CONTROLS_`, `KEY_`, `HUD_`, `GAME_UI_`, `VILLAGE_`, `FORGE_`, `ROOM_`, `RUNEND_`, Daten per Konvention `UPGRADE_<ID>_NAME`, `WEAPON_<ID>_SPECIAL`.

- Platzhalter `%s`/`%d` in beiden Sprachen gleich oft und in gleicher Reihenfolge; ein wörtliches `%` in einem Text mit Platzhaltern als `%%`.
- Eigennamen (`English`, `Deutsch`, `Esc`, `F11`, `VSync`) bleiben Klartext.
- Eyebrows nicht in der CSV großschreiben, sondern `Label.uppercase = true`; so dient ein Schlüssel für Titel und Eyebrow.
- `DungeonTexts` hält das Deutsch der Dungeon-Menüs im Code, die CSV trägt Englisch und eine Kopie des Deutschen; fehlt eine Zeile, zeigt das Spiel Deutsch. Fehlendes Englisch findet `python tools/i18n_check.py --dungeon-texts --export`.

## 3. Einen Text hinzufügen

1. Zeile in `translations.csv`: `BEREICH_NAME,"English","Deutsch"`, danach `godot --headless --audio-driver Dummy --path . --import`.
2. Einfacher Text: `label.text = &"BEREICH_NAME"` (Godot übersetzt selbst und bei jedem Sprachwechsel neu). Zusammengesetzter Text: `tr(&"KEY") % [wert]` bzw. `Loc.t(&"KEY", [wert])` und in `_notification(NOTIFICATION_TRANSLATION_CHANGED)` neu setzen.
3. Prüfen: `python tools/i18n_check.py <ordner>` (0 Funde) und GUT (`test_i18n*`).

## 4. Live-Umschalten

- Knoten, deren Text ein Schlüssel ist, aktualisieren sich selbst.
- Jede Klasse mit zusammengesetzten Texten setzt sie bei `NOTIFICATION_TRANSLATION_CHANGED` neu. Dabei auf die eigenen Knoten prüfen (`_list != null`), nicht auf `is_node_ready()`, weil das Locale auch aus `_ready()` heraus wechseln kann.
- `Label.text` liefert danach den **Schlüssel**; Getter für Tests geben `tr(text)` zurück.

## 5. Einstellungen und ihre Haken

- Alle Optionen sind global (`settings.cfg [options]` über `SaveManager.get_option/set_option`), nie je Spielstand, und wirken sofort; `GameOptions.apply_all()` läuft beim Start.
- Optionen müssen headless sicher sein (keine `DisplayServer`-Aufrufe ohne Fenster).
- **Schalter wirken am Effekt (Haken):** Bildschirmwackeln, Trefferstopp, Schadenszahlen und reduzierte Blitze werden dort gelesen, wo der Effekt passiert (je eine Zeile in `CameraShake`, `HitStop`, `DamageNumber`, `SpriteFx`, `PostProcess`, `LightSource`), nicht im Optionen-Code. Neue Spielgefühl-Schalter folgen demselben Muster.
- „Zurücksetzen“ setzt nur Optionen und Lautstärken zurück, nie Spielstände, und fragt vorher nach.

## 6. Tests und Werkzeuge

- Tests, die deutsche Texte vergleichen, setzen in `before_all` `Loc.apply(&"de")` und stellen in `after_all` das alte Locale her (`Loc.apply` schreibt keine `settings.cfg`).
- Werkzeuge (`smoke_test`, `balance_sim`, `screenshots`) biegen Spielstand **und** Einstellungen auf eigene Dateien um und setzen dort die Sprache, sonst überschreibt die echte `settings.cfg` sie.

## 7. Offen

- Englische Wortwahl ist Vorschlag; das Projektmitglied darf in der CSV frei ändern (danach `--import`).
- Tasten ändern (Rebinding) für Tastatur fehlt noch.
- Randlos-Fenster auf mehreren Bildschirmen nimmt den Bildschirm des Fensters; ob er wählbar werden soll, ist offen.
