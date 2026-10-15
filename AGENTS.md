# AGENTS.md – So arbeiten wir mit KI-Agenten

> Gilt für **jeden** Agenten und jeden neuen Chat in diesem Repository (Claude Code, Subagenten, andere Werkzeuge). Erst diese Datei lesen, dann die genannten Dokumente. Claude-Code-Besonderheiten: [CLAUDE.md](CLAUDE.md).
> **Stand:** 15.10.2026

## 1. Projekt in Kürze

**Soulwick** (D-094): 2D-Top-down-Dungeon-Roguelite in Godot 4.7.2. Endloser, dunkler Dungeon mit Biomen, Bossen und Minispiel-Räumen, Dorf mit Meta-Progression; geplant: Koop, Gilden, Ranglisten, Steam und Mobil. Teamprojekt (Idee eines Kollegen), nach außen „Made with ♥ by WebBude“ ([PRODUKT.md](docs/PRODUKT.md)). Das Projektmitglied schreibt **Deutsch**, ist neu in Godot und arbeitet am liebsten so: Ziel nennen, Agenten bauen lassen, am Ende spielbar testen.

## 2. Repositories (D-093)

Beide Repositories liegen privat auf GitHub in der Organisation **`WebBude-de`**.

| Repository / Ordner | Was | Wichtigste Doku |
| --- | --- | --- |
| **`soulwick`** (dieses Repo) | Godot-Spiel im Repo-Root (`project.godot`, `dungeon/`, `player/` …), GUT-Tests, Tools | [docs/README.md](docs/README.md) (Inhaltsverzeichnis) |
| **`../soulwick-mp`** (Worktree dieses Repos, Branch `feature/multiplayer`) | Multiplayer-Arbeit (Phase 3) parallel zu den Räumen | dort `docs/ROADMAP_MULTIPLAYER.md` |
| **`../soulwick-platform`** (eigenes Repo) | Bun-Workspaces mit Turborepo, Prisma, Biome (Ultracite): `apps/api` (Spieler- und Admin-API, Hono auf Bun), `apps/relay` (Koop-Relay), `apps/web` (Website), `apps/admin` (Admin-Panel), `packages/contracts` (API- und Relay-Verträge, Quelle der Wahrheit), `packages/db` (Prisma-Schema, Migrationen), `infra/` (lokales Postgres, Dokploy-Anleitung) | dortige `AGENTS.md` und `README.md` |

**Warum getrennt:** kein gemeinsamer Code, verschiedene Werkzeuge und Release-Zyklen, das Spiel-Repo bleibt schlank (D-093). Produkt-Entscheidungen (D-Nummern) und die Spiel-Roadmaps stehen hier in `docs/`; die Plattform hat eigene Anforderungen, Roadmap und technische Entscheidungen (P-Nummern). Ändert sich die API, zuerst die Verträge in `soulwick-platform/packages/contracts`, dann den GDScript-Client im Spiel.

## 3. Wo steht, was zu tun ist

Inhaltsverzeichnis mit Lesereihenfolge: [docs/README.md](docs/README.md). Kurz:

1. [docs/PRODUKT.md](docs/PRODUKT.md): Produktüberblick für beide Repositories; zuerst lesen, wenn der Kontext fehlt.
2. [docs/ROADMAP_AUSBAU.md](docs/ROADMAP_AUSBAU.md): **was jetzt dran ist** (D-106): Phase 1 spielbar machen (fertig), Phase 2 Räume, 2b Raum-Rework, 2c Makeover. Für Räume gilt [docs/KONZEPT_RAEUME_V2.md](docs/KONZEPT_RAEUME_V2.md), jedes Paket mit Koop-Check.
3. [docs/ROADMAP_MULTIPLAYER.md](docs/ROADMAP_MULTIPLAYER.md): Phase 3 (Koop, Steam, Gilden, Ranglisten), läuft im Worktree `../soulwick-mp`; das Plattform-Repo darf jederzeit parallel laufen. Danach [ROADMAP_CROSSPLAY.md](docs/ROADMAP_CROSSPLAY.md) (Entscheidungen CP0 vor MP2) und Phase 4 [ROADMAP_KI_BOSS.md](docs/ROADMAP_KI_BOSS.md).
4. Fehlende Grafiken: [docs/design/sprites/README.md](docs/design/sprites/README.md) (Stand je Briefing; offen sind vor allem SPRITES_V8 und Teile von SPRITES_V9).
5. Mockups für UI und Stimmung: [docs/design/](docs/design/README.md) – als Inspiration lesen, bevor UI gebaut wird, nicht pixelgenau nachbauen.
6. Rückmeldungen aus dem Spiel: Dev-Feedback-Modus **F9** (nur Debug-Builds), Anleitung und Auswertung in [docs/feedback/README.md](docs/feedback/README.md).

Jedes Roadmap-Paket ist für **einen Agenten** geschnitten und nennt seine Dateien.

## 4. Rollen

| Rolle | Aufgabe |
| --- | --- |
| **Orchestrator** (der Haupt-Chat) | Plant mit dem Projektmitglied, schneidet Pakete, startet Agenten, integriert, prüft, berichtet auf Deutsch. Schreibt selbst nur Kleinkram und Integration. |
| **Fach-Agent** (ein Paket) | Setzt genau ein Roadmap-Paket um, nur in seinen Dateien. Berichtet Ergebnis, Prüfstand und offene Punkte. |
| **Integrator** | Verdrahtet die Haken der Fach-Agenten in die gemeinsamen Dateien (§5), löst Konflikte, lässt alle Prüfungen laufen. Meist der Orchestrator selbst. |
| **Balance-Agent** | Misst mit `tools/balance_sim.gd` (Bot spielt echte Runs), ändert nur Zahlen (`*.tres`, Konstanten mit `TESTWERT`) und dokumentiert in DECISIONS. |
| **Explore-Agent** | Nur lesen und suchen, wenn viele Dateien durchsucht werden müssen. |

Die Fach-Agenten sind in [.claude/agents/](.claude/agents/) definiert: `rooms-dev` (Räume, Vorlagen, Tilesets), `enemies-dev` (Gegner, Bosse, Waffen, Trefferlogik), `player-dev` (Spieler, Upgrades, HUD), `village-dev` (Dorf, Meta-Progression, Spielstand), `fx-audio-dev` (Shader, Effekte, Musik, Audio), `balance` (Zahlen und Bot-Messung). Jede Definition nennt Besitz, Bauweise, Prüfung und Berichtsform. Der Orchestrator startet sie mit `subagent_type` = Name und ergänzt im Auftrag Paket und ggf. freigegebene Hotspot-Dateien. Für die Plattform gibt es dort `api-dev`, `web-dev` und `admin-dev`.

## 5. Regeln für parallele Agenten

- **Ein Paket = ein Agent = eigene Dateien.** Parallel nur, wenn sich die Dateilisten nicht überschneiden. Im Auftrag steht immer eine **Besitzliste** („Du darfst nur … ändern“).
- **Gemeinsame Hotspots** ändert nur der Integrator oder ein Agent nach dem anderen: `project.godot`, `dungeon/dungeon_manager.gd`, `dungeon/rooms/room_controller.gd`, `enemies/enemy_base.gd`, `player/player.gd`, `scenes/game.tscn`, `autoload/*`, `docs/DECISIONS.md`; in `soulwick-platform`: Root-`package.json`, `packages/contracts`, `packages/db` (Schema und Migrationen).
- Braucht ein Agent eine Änderung in einem Hotspot, baut er in seinen Dateien einen **Haken** (Funktion/Signal) und schreibt in den Bericht, wo der Integrator ihn anschließen soll.
- **Andere Sitzungen:** Oft laufen mehrere Chats im selben Ordner und im Worktree `../soulwick-mp`. Vor größeren Umbauten prüfen, wer gerade arbeitet (zuletzt geänderte Dateien, `git status`, offene Sitzungen), und keine fremde Arbeit überschreiben oder zurücksetzen. Dateien, die der Multiplayer-Zweig neuer hat (`docs/MULTIPLAYER.md`, `docs/ROADMAP_MULTIPLAYER.md`, `docs/ROADMAP_CROSSPLAY.md`), hier nur im Notfall ändern, sonst gibt es Merge-Konflikte.
- Ein abgebrochener Agent hinterlässt halbfertige Dateien: Der Integrator prüft sie mit `validate_project.gd`, bevor weitergebaut wird. Unterbrochene Agenten nicht ungefragt neu starten.

## 6. Harte Regeln

1. **Kein Commit und kein Push**, außer das Projektmitglied sagt es ausdrücklich. Branch-Modell und Commit-Format: [docs/TECHSTACK.md](docs/TECHSTACK.md) §3 (`feature/*` von `dev`, Pull Request mit Review).
2. **Entscheidungen:** Nichts als `OFFEN` Markiertes still festlegen. Balance- und Testwerte sind an Claude delegiert: als `TESTWERT` markieren und in DECISIONS festhalten. Echte Design- und Produktfragen gehen an das Projektmitglied.
3. **D-Nummern:** Vor einem neuen Eintrag die **höchste vorhandene Nummer** in `docs/DECISIONS.md` suchen (`grep -n "^### D-" docs/DECISIONS.md | sort -t- -k2 -n | tail`). Parallele Chats haben schon doppelte Nummern erzeugt; D-121 bis D-129 sind für den Multiplayer-Zweig reserviert.
4. **Tests fassen den echten Spielstand nie an:** In jedem Test und Tool `SaveManager.save_path` vorher auf eine Testdatei umbiegen (`before_all`). Echter Stand: `%APPDATA%/Godot/app_userdata/Soulwick/` (ein alter Stand aus `…/Dungeon Roguelite/` wird beim ersten Start einmal kopiert).
5. **Genau vier Autoloads** (GameManager, RunManager, SaveManager, EventBus, D-044). Hilfen als `static func`/`class_name`, nicht als neuer Autoload.
6. **Multiplayer-Leitplanken** für neuen Spielcode (D-088, Koop-Check in ROADMAP_AUSBAU): kein neues `get_first_node_in_group(&"player")`, Logik von Effekten trennen, Zufall nur über den Dungeon-RNG, keine neuen globalen Pausen, Zustand je Spieler am Spieler.
7. **Code Englisch, Doku Deutsch, Texte im Spiel über Übersetzungsschlüssel (en + de, D-111)**, `snake_case` für Dateien und Variablen, `PascalCase` für Klassen. Kommentare wie der umgebende Code.
8. **Erledigt heißt geprüft:** Roadmap-Punkte nur mit Nachweis abhaken (Tests grün, Datum).
9. **Prozesse nie per Namen beenden** (`taskkill /IM …`, `pkill`, `killall`, `Stop-Process -Name …`): Das trifft Godot-Fenster, Browser und Server anderer Sitzungen. Nur selbst gestartete Prozesse über ihre PID beenden.

## 7. Prüfen

**Spiel** (im Repo-Root von `soulwick`; `godot` = `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`, in Bash `"C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe"`):

| Was | Befehl |
| --- | --- |
| Alle Dateien laden | `godot --headless --path . -s tools/validate_project.gd` |
| Unit-Tests (GUT) | `godot --headless --path . -s addons/gut/gut_cmdln.gd` |
| Durchlauf über N Räume | `godot --headless --fixed-fps 60 --path . -s tools/smoke_test.gd -- 47` |
| Kämpfe, Waffen, Upgrades | `godot --headless --path . -s tools/combat_sim.gd` |
| Bosse, Gegner, Elites | `godot --headless --fixed-fps 60 --path . -s tools/boss_sim.gd` |
| Balance-Bot | `godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- runs=3 policy=sword quiet=1` |
| Screenshots (Fenster) | `godot --path . -s tools/screenshots.gd -- <ordner>` |
| Texte (fehlende Übersetzungen) | `python tools/i18n_check.py <ordner>` |
| Nach neuen Dateien/Grafiken/Texten | `godot --headless --path . --import` |

**Plattform** (im Root von `../soulwick-platform`, Bun 1.3, Node 24, Docker): `bun install`, `bun run services:up` (lokales Postgres), `bun run check` (Biome), `bun run typecheck`, `bun run test`, `bun run build`; lokal starten mit `bun dev`. Details in der dortigen README.

Mindestens vor jedem Bericht: validate + GUT (Spiel) bzw. check + typecheck + test (Plattform). Bei Kampf- und Gegneränderungen zusätzlich combat_sim und boss_sim, bei Raumänderungen smoke_test.

## 8. Grafiken und Audio

- Fehlende Grafiken schreibt der Agent als **Briefing** in `docs/design/sprites/SPRITES_V*.md` (Datei, Größe, Frames, Beschreibung, Ablageort) und trägt es in [docs/design/sprites/README.md](docs/design/sprites/README.md) ein. Das Projektmitglied erstellt sie mit Claude Design und legt sie unter `art/` ab (Website-Grafiken in `soulwick-platform/apps/web/public/`).
- Bis dahin erzeugt der Code **Platzhalter**; echte Dateien mit dem vereinbarten Namen werden automatisch übernommen (z. B. `EnemyArt` lädt nach Namenskonvention).
- Nach dem Ablegen: `godot --headless --path . --import`. Überschreibt das Projektmitglied `art/` komplett, Mauszeiger neu erzeugen (`python tools/generate_cursors.py`) und veraltete `.import`-/UID-Reste prüfen.
- Audio wird synthetisch erzeugt: `python tools/generate_audio.py` (Effekte), `python tools/generate_music.py` (Musik, Details in [docs/AUDIO.md](docs/AUDIO.md)). Eigene Dateien gleichen Namens ersetzen die erzeugten.
- Dateinamen in `docs/design/claude_design_antwort/` nicht ändern: Code und Werkzeuge verweisen darauf.

## 9. Bekannte Stolperfallen

- Mit `-s` gestartete Skripte: Autoloads existieren erst ab dem ersten Frame, also einen Frame warten.
- Python-Patch-Skripte als **Datei** schreiben (nicht als Bash-Heredoc mit Umlauten oder Anführungszeichen).
- Typisierte Arrays in GDScript: keine Lambdas mit `filter` auf `Array[Enemy]`, die ungültige Instanzen enthalten können (Absturz).
- Tippt man WASD im Editor statt im Spiel, landen Buchstaben im Code („Parser Error“). Erst ins Spielfenster klicken.
- HitStop ändert `Engine.time_scale`; Freigabe läuft über Tokens, nicht über Timer.
- Headless-Tools ohne Ton bzw. mit Bildraten-Grenze laufen lassen: Godots Audio-Mischthread kann bei sehr hohen FPS freigegebenen Speicher lesen und abstürzen (D-134; `balance_sim.gd` schaltet Ton standardmäßig ab).

## 10. Auftragsvorlage für einen Fach-Agenten

> Setze in `C:\Users\bmg18\Documents\Workspace\WebBude\WebBude Labs\Soulwick\soulwick` das Paket **[ID]** aus `docs/[ROADMAP-Datei]` um. Lies vorher `AGENTS.md`, die Paketbeschreibung und die genannten D-Einträge in `docs/DECISIONS.md`.
> **Du darfst nur diese Dateien/Ordner ändern:** [Liste]. Brauchst du etwas in anderen Dateien, baue einen Haken und beschreibe ihn im Bericht.
> Prüfe am Ende mit [Befehle aus AGENTS.md §7] und hake die erledigten Punkte mit Datum ab. Kein Commit. Prozesse nur über die eigene PID beenden. Ändere keine Entscheidungen; Unklares als Frage in den Bericht.
> **Bericht:** geänderte/neue Dateien, Prüfergebnisse (Zahlen), Haken für den Integrator, benötigte Grafiken, offene Fragen.

## 11. Neuer Chat – Startprompt

> Lies `AGENTS.md`. Stand: siehe `docs/ROADMAP_AUSBAU.md`. Arbeite als Orchestrator: Nimm die nächsten offenen Pakete der aktuellen Phase, starte sie mit getrennten Besitzlisten parallel, integriere danach, prüfe alles und berichte mir auf Deutsch. Für Räume gilt `docs/KONZEPT_RAEUME_V2.md`, für jedes Paket der Koop-Check.
