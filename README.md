# Soulwick

**Das letzte Licht im endlosen Dunkel.** Soulwick ist ein 2D-Top-down-Dungeon-Roguelite in Pixel-Art: Vom Dorf aus steigst du in einen endlosen, dunklen Dungeon, kämpfst dich mit Maus und Tastatur Raum für Raum durch vier Biome mit Bossen, sammelst Waffen und Upgrades und baust mit dem geretteten Gold das Dorf aus. Koop, Gilden und Ranglisten sind geplant.

Dieses Repository enthält das **Spiel** (Godot 4.7.2). Website, Server und Admin-Panel liegen im Schwester-Repo [WebBude-de/soulwick-platform](https://github.com/WebBude-de/soulwick-platform) (lokal als Nachbarordner `../soulwick-platform`).

## Loslegen

1. **Godot 4.7.2 stable, Standard-Version** (nicht .NET) von <https://godotengine.org/download/archive/> laden und entpacken. Genau diese Version verwenden ([D-051](docs/DECISIONS.md)).
2. Repository klonen: `git clone https://github.com/WebBude-de/soulwick.git`
3. Godot starten → *Importieren* → `project.godot` im geklonten Ordner wählen. Der erste Start importiert alle Grafiken und dauert etwas.
4. **F5** startet das Spiel: Hauptmenü → Spielstand anlegen → Dorf → mit **E** am Dungeon-Eingang einen Run beginnen.

Optional für die Generatoren in `tools/` (Räume, Dorf, Audio, Mauszeiger): Python 3.

## Steuerung

| Taste | Aktion |
| --- | --- |
| WASD | Bewegen |
| Maus | Zielen |
| Linke Maustaste (halten) | Angreifen |
| Rechte Maustaste | Spezialangriff der Waffe |
| Leertaste | Dash (in der Seitenansicht: Sprung) |
| Q | Waffe wechseln |
| E | Benutzen (Eingang, Türen, Händler, Altar, Portal …) |
| Tab | Upgrade-Übersicht |
| Esc | Pause / Dialog schließen |
| F11 | Vollbild |

## So läuft ein Run

Der Dungeon ist in Fünferzyklen gebaut: drei Kampfräume (nach dem dritten eine Upgrade-Wahl), ein Ruheraum (Händler, Waffenauswahl, Brunnen, Upgrade-Altar oder Prüfung) und ein Champion. Ab dem zweiten Zyklus kommen Minispiel-Räume und Abzweigungen dazu. Alle 15 Räume wartet ein Boss, danach ein Lagerfeuer mit Ausgangsportal und ein neues Biom (Krypta, Schleimgrotte, Schattenreich, Glutkammer, dann stärker von vorn). Über das Portal kommt das ganze Run-Gold ins Dorf, bei Tod oder Abbruch die Hälfte. Im Dorf: Schmiede, Handelsposten, Chronik, Zuhause und Gildenhaus.

Der Spielstand liegt unter `%APPDATA%\Godot\app_userdata\Soulwick\`.

## Prüfen

Im Projektordner, `godot` steht für den Pfad zur Godot-EXE:

| Was | Befehl |
| --- | --- |
| Alle Dateien laden | `godot --headless --path . -s tools/validate_project.gd` |
| Unit-Tests (GUT 9.7.1) | `godot --headless --path . -s addons/gut/gut_cmdln.gd` |
| Durchlauf über 47 Räume | `godot --headless --fixed-fps 60 --path . -s tools/smoke_test.gd -- 47` |
| Kämpfe, Waffen, Upgrades | `godot --headless --path . -s tools/combat_sim.gd` |
| Bosse, Gegner, Elites | `godot --headless --fixed-fps 60 --path . -s tools/boss_sim.gd` |
| Balance-Bot (ganze Runs) | `godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- runs=3 policy=sword quiet=1` |
| Screenshots (öffnet ein Fenster) | `godot --path . -s tools/screenshots.gd -- <ordner>` |
| Nach neuen Grafiken/Texten | `godot --headless --path . --import` |

Im Editor laufen die Unit-Tests auch über das Panel *GUT* → *Run All*.

## Mit Freunden testen

Testversion (MP4): `powershell -ExecutionPolicy Bypass -File tools/export_build.ps1` baut Windows und Linux gegen die Umgebung `development` als ZIP nach `builds/` (vorher einmal die Export-Vorlagen von Godot 4.7.2 installieren). Freunde entpacken das ZIP und starten `Soulwick.exe`; online meldet sich jede Installation automatisch mit einem Gastkonto an (Plattform P-028), ein Dev-Schlüssel ist nicht nötig. Im Dorf erstellt der Host im Gildengebäude einen Raum und teilt den **Raumcode**, die anderen geben ihn ein. Keine Portfreigabe, kein VPN, keine Zusatzsoftware. Details und Testliste: [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md) §3d.

## Ordner

| Ordner | Inhalt |
| --- | --- |
| `scenes/` | Einstieg (`main.tscn`) und Weltrahmen (`game.tscn`) |
| `autoload/` | die vier globalen Dienste: GameManager, RunManager, SaveManager, EventBus |
| `world/village/` | Dorf |
| `dungeon/` | Raumfolge, Raumvorlagen, Minispiel-Modi, Varianten, Seitenansicht, Türen, Fallen |
| `player/`, `characters/` | Spielfigur, Steuerung, Charakterdaten |
| `enemies/`, `weapons/`, `upgrades/`, `components/` | Gegner und Bosse, Waffen, Upgrades, Bausteine (Leben, Schild, Treffer, Licht, Audio) |
| `economy/`, `meta/` | Gold, Händler; Dorf-Fortschritt, Spielstände, Statistik |
| `ui/` | Hauptmenü, HUD, Menüs, Optionen, Boss-Intro |
| `localization/` | Texte auf Englisch und Deutsch ([Anleitung](localization/README.md)) |
| `art/`, `audio/` | Grafiken und Klänge |
| `tests/`, `tools/` | GUT-Tests; Prüf-, Simulations- und Generator-Skripte |
| `docs/` | Doku auf Deutsch: [Inhaltsverzeichnis](docs/README.md) |

Spielwerte stehen in `.tres`-Dateien (z. B. `weapons/data/`, `enemies/data/`, `upgrades/data/`, `economy/data/economy_config.tres`) und lassen sich ohne Code ändern; Zahlen mit dem Kommentar `TESTWERT` sind vorläufig. Musik und Geräusche: [docs/AUDIO.md](docs/AUDIO.md).

## Mitarbeiten

- Doku-Einstieg: [docs/README.md](docs/README.md) (Produkt, Anforderungen, Architektur, Roadmaps).
- Arbeiten mit KI-Agenten: [AGENTS.md](AGENTS.md).
- Code und Kommentare Englisch, Doku Deutsch, Texte im Spiel über Übersetzungsschlüssel; Branches und Commit-Format: [docs/TECHSTACK.md](docs/TECHSTACK.md).

## Rechte

Privates Repository der **WebBude** („Made with ♥ by WebBude“). Alle Rechte vorbehalten; Code, Grafiken und Texte nicht ohne Zustimmung weitergeben. Die Rechte am Spiel im Team werden vor einer Veröffentlichung geklärt (ROADMAP_MULTIPLAYER MP10). Fremde Bestandteile behalten ihre Lizenz: Schrift Pixelify Sans (SIL OFL, `art/fonts/`), Test-Framework GUT (MIT, `addons/gut/`).
