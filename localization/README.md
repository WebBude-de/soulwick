# localization/ – Sprachen im Spiel (D-111)

Englisch ist Standard, Deutsch die zweite Sprache. Die Sprache kommt aus dem System (`auto`) oder aus den Optionen (`GameOptions.LANGUAGE`). Konzept, Schlüsselschema und Backlog: [docs/KONZEPT_SPRACHEN_EINSTELLUNGEN.md](../docs/KONZEPT_SPRACHEN_EINSTELLUNGEN.md).

| Datei | Zweck |
| --- | --- |
| `translations.csv` | Quelle der Wahrheit: Spalten `keys,en,de`, UTF-8 ohne BOM, Werte in Anführungszeichen. |
| `translations.en.translation`, `translations.de.translation` | Von Godot aus der CSV erzeugt (`godot --headless --path . --import`), werden mit exportiert. |
| `loc.gd` | `Loc.install()` (registriert beide Übersetzungen zur Laufzeit), `Loc.apply(option)`, `Loc.t(key, args)`, `Loc.current_language()`. |
| `data_texts.gd` | `DataTexts`: Namen und Beschreibungen von Upgrades/Waffen nach Konvention (`UPGRADE_<ID>_NAME`, `WEAPON_<ID>_SPECIAL` …), Rückfall auf das deutsche `.tres`-Feld. |

`DungeonTexts` (`ui/menus/dungeon_texts.gd`) hält das Deutsch der Dungeon-Menüs; ihr Englisch steht hier in der CSV. Fehlt es für neue Schlüssel: `python tools/i18n_check.py --dungeon-texts --export` gibt die fehlenden Zeilen aus (Konzept §2).

## Text hinzufügen

1. Zeile in `translations.csv`: `BEREICH_NAME,"English","Deutsch"` (Platzhalter `%s`/`%d` in beiden Spalten gleich).
2. `godot --headless --path . --import` ausführen.
3. Im Code: `label.text = &"BEREICH_NAME"` (Godot übersetzt selbst und bei Sprachwechsel neu) oder `tr(&"BEREICH_NAME") % [wert]` bzw. `Loc.t(&"BEREICH_NAME", [wert])` und dann in `_notification(NOTIFICATION_TRANSLATION_CHANGED)` neu setzen. Ein wörtliches `%` in einem Text mit Platzhaltern als `%%` schreiben.
4. Prüfen: `python tools/i18n_check.py <ordner>` (findet verbliebene deutsche Texte) und GUT `tests/unit/test_i18n.gd`.
