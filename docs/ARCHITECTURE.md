# ARCHITECTURE – Landkarte des Spiels

> **Stand:** 17.10.2026 · Wo was liegt und wem welcher Zustand gehört. Einzelheiten stehen im Code (Kopfkommentar jeder Klasse), Gründe in [DECISIONS.md](DECISIONS.md), Regeln für Koop in [MULTIPLAYER.md](MULTIPLAYER.md) (D-178).

## 1. Anwendung und Laufzeit

Eine Godot-4.7.2-Anwendung für Windows, Linux, macOS, Android, iOS und Browser (D-108, D-148). Sie ist **ohne Server spielbar**; Konto, Gilden, Ranglisten und Koop-Relay liegen im Repo `soulwick-platform`, jeder Aufruf darf scheitern, Spiellogik läuft nie auf dem Server (D-083, D-119).

```text
scenes/main.tscn            Hauptmenü (ui/main_menu/)
  → scenes/game.tscn        WorldController: aktive Welt, Spieler, GameMode (Solo/Koop)
       ├─ world/village/village.tscn     Dorf
       └─ dungeon/dungeon.tscn           DungeonManager + RoomContainer
             ├─ Räume aus Plänen (höchstens 3 lebend, während einer Abzweigungswahl 4)
             └─ Gang-Segmente in Seitenansicht (dungeon/side/)
```

Dorf und Dungeon sind verschiedene Welten: Beim Wechsel entsteht der Spieler neu, von Raum zu Raum bleibt er derselbe (D-041).

## 2. Wem welcher Zustand gehört

Ein Zustand hat genau einen Eigentümer; andere lesen über typisierte Methoden und reagieren auf Signale (D-046). **Genau vier Autoloads** (D-044), alles andere hängt an Szenen oder ist `static`/`class_name`.

| Eigentümer | besitzt |
| --- | --- |
| `GameManager` (Autoload) | Spielphase, Pausengründe, Szenenwechsel |
| `RunManager` (Autoload) | laufender Run: Raumnummer, Run-Gold, Kristalle im Run, Run-Ende und Auszahlung |
| `SaveManager` (Autoload) | dauerhafter Spielstand je Welt, Einstellungen, Profil-Ablage |
| `EventBus` (Autoload) | nur systemübergreifende Signale, **kein** Zustand |
| `GameMode` (am WorldController) | Sitzung: Solo, Schnelles Spiel, Gilde; Spielerzahl; ob Menüs pausieren |
| `DungeonManager` | Raumfolge, Vorlagenwahl, Raumkette, Dungeon-RNG (`DungeonContext`) |
| `RoomController` | ein Raum: Kampf, Türen, Gegner, Abschluss |
| `Player` + Komponenten | HP, Schild, Waffen (`WeaponController`), Zustand je Spieler (Flüche, getragene Dinge, letzte sichere Stelle) |
| `UpgradeManager`, `StatCalculator`, `DamageProcessor` | Upgrade-Stufen, effektive Werte, Trefferverrechnung |
| `EconomySystem` | Preise und Kaufprüfung (das Gold selbst führt `RunManager`) |
| `online/*` | Koop: Lobby, Run, Dungeon- und Gegner-Spiegelung (nur aktiv, wenn `GameMode` vernetzt ist) |

## 3. Ordner

| Ordner | Inhalt |
| --- | --- |
| `autoload/`, `scenes/` | die vier Autoloads; Hauptmenü, `game.tscn`, `WorldController`, `GameMode` |
| `world/village/` | Dorf, Gebäude, Bewohner, Deko |
| `dungeon/` | `DungeonManager`, `rooms/` (Pläne, erzeugte Vorlagen, Spezial-, Boss-, Lagerfeuer-, Prüfungsräume), `modes/` (Minispiele), `variants/` (Wagnis, Elite-Nest, Modus-Tabelle), `spawning/` (Gegner-Quellen), `environment/` (Tilesets, Türen, Gänge, Deko, Fallen), `side/` (Seitenansicht), `biomes/` |
| `player/` | Spieler, Eingabe (`input/`, Tastatur/Maus, Gamepad, Touch, Netz), Waffen-Controller, Flüche |
| `enemies/` | Gegner-Basis, KI (`ai/`), Bosse, Türme, Daten (`data/`), Skalierung |
| `weapons/`, `upgrades/`, `economy/` | Daten (`data/*.tres`) und Logik |
| `components/` | wiederverwendbare Bausteine: Health, Shield, Hitbox/Hurtbox, Kampf, Licht und Kamera (`visual/`), Audio |
| `characters/`, `meta/` | Figuren, Aussehen, Spielerprofil; Dorf-Fortschritt, Freischaltungen, Statistik, Spielstände |
| `ui/` | Hauptmenü, HUD, Dialoge, Optionen, Touch, Dev-Feedback (F9) |
| `online/`, `localization/` | API-Client, Relay, Lobby, Koop-Spiegelung; `translations.csv` (en, de), `Loc` |
| `art/`, `audio/` | Grafik und Klang (Rechte vorbehalten, D-177) |
| `tests/`, `tools/` | GUT-Tests; Prüf-, Simulations- und Generator-Werkzeuge ([AGENTS.md](../AGENTS.md) §7) |
| `deploy/`, `.github/` | Browser-Version, CI und Releases ([WEB_BUILD.md](WEB_BUILD.md), [RELEASE.md](RELEASE.md)) |
| `docs/` | Doku; Godot liest den Ordner nicht (`docs/.gdignore`) |

## 4. Szenen und Bausteine

- `player/player.tscn`, `enemies/enemy_base.tscn`: `CharacterBody2D` mit Komponenten aus `components/`.
- **Räume werden erzeugt, nie von Hand bearbeitet:** Pläne als Text in `dungeon/rooms/plans/` → `python tools/generate_room_templates.py` → Szenen und `RoomTemplate`-Daten in `dungeon/rooms/templates/`. Das Dorf entsteht genauso aus `tools/generate_village.py`.
- Grafik wird nach Namenskonvention aus `art/` geladen; fehlt eine Datei, zeichnet der Code einen Platzhalter ([HANDOUT.md](HANDOUT.md)).

## 5. Daten und Speichern

- **Definitionen** sind typisierte `Resource`-Klassen mit `.tres` (Waffen, Upgrades, Gegner, Biome, Raumvorlagen), kein JSON als Gameplay-Definition (D-045). Ausnahmen: Raumpläne als Text, Animationsdaten der Grafiken als JSON.
- **Laufzeitzustand** liegt nie in Resources und wird nicht gespeichert; gespeichert werden nur dauerhafte Werte (D-040).
- **Spielstand:** `ConfigFile` je Welt mit Version und Migration, sicher geschrieben (D-059, D-152, D-165); Einstellungen global in `settings.cfg`, Name und Aussehen in `profile.cfg`. Code: `autoload/save_manager.gd`.
- **Texte:** Schlüssel in `localization/translations.csv`, auch in Daten (D-111, D-164).

## 6. Schnittstellen im Spiel

1. Zustand lesen über typisierte Methoden.
2. Aktionen über Methoden mit eindeutigem Erfolg oder Fehler (z. B. `try_spend_run_gold`).
3. Signale **nach** erfolgreicher Änderung.
4. Lokal direkt verbundene Signale; `EventBus` nur systemübergreifend.
5. Geänderte Schnittstellen im Pull Request nennen; Namen, die `online/` nutzt, nicht ohne Absprache umbenennen ([MULTIPLAYER.md](MULTIPLAYER.md) §6).

## 7. Datenfluss und Grenzen

### 7.1 Dorf → Run → Rückkehr

1. Dorf: Eingang benutzen → `GameManager.change_scene` lädt den Dungeon, `RunManager.start_run()` beginnt den Run, die Dorf-Boni kommen aus `MetaProgression` (nur Solo).
2. Dungeon: `DungeonManager` baut Raum für Raum aus dem Dungeon-RNG (gleicher Seed = gleiche Räume). Beim Betreten von Raum N wird zuerst N−2 entfernt, dann N+1 gebaut, damit nie ein vierter Raum lebt. Ein Kampf startet beim ersten Betreten genau einmal; der Abschluss wird genau einmal gemeldet; eine kaputte Vorlage gilt nie als geschafft.
3. Käufe: `EconomySystem` prüft Angebot und Preis, `RunManager` bucht; Abbuchung und Lieferung zusammen oder gar nicht (D-038).
4. Ende: Portal, Tod oder Abbruch → `RunManager.end_run()` rechnet die Quote (100 % bzw. 50 %), `SaveManager` bucht genau einmal → zurück ins Dorf mit neuem Spieler.

### 7.2 Treffer

Hitbox/Hurtbox → Hit-ID und Unverwundbarkeit prüfen → `StatCalculator` (effektive Werte) → `DamageProcessor` (einmal auf 0,5 runden, Schild vor HP) → Rückmeldung, Tod, erlaubte Sekundäreffekte ohne Kette. Formeln: DECISIONS §6.

## 8. Sicherheit

Beide Repos sind öffentlich: keine Geheimnisse im Repo, der Dev-Schlüssel kommt nie in einen Build (D-148, D-177). Spielstände beim Laden prüfen, defekte kontrolliert behandeln, dauerhaftes Gold nie doppelt gutschreiben.
