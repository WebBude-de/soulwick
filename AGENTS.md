# AGENTS.md – So arbeiten wir mit KI-Agenten

> Gilt für **jeden** Agenten und jeden neuen Chat in diesem Repository (Claude Code, Subagenten, andere Werkzeuge). Erst diese Datei lesen, dann die genannten Dokumente.
> **Stand:** 13.10.2026

## 1. Projekt in Kürze

**Soulwick** (D-094): 2D-Top-down-Dungeon-Roguelite in Godot 4.7.2 (Teamprojekt, Idee eines Kollegen; nach außen „Made with ♥ by WebBude“, siehe PRODUKT.md). Endloser, dunkler Dungeon mit Biomen, Bossen, Dorf mit Meta-Progression; geplant: neue Raumarten, Koop-Multiplayer, Gilden, Ranglisten, Steam. Das Projektmitglied schreibt **Deutsch**, ist neu in Godot und arbeitet am liebsten so: Ziel nennen, Agenten bauen, am Ende spielbar testen.

## 2. Repositories (D-093)

| Repository / Ordner | Was | Wichtigste Doku |
| --- | --- | --- |
| **`soulwick`** (dieses Repo, GitLab-Teamrepo) | Godot-Spiel im Repo-Root (`project.godot`, `dungeon/`, `player/` …), GUT-Tests, Tools | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/TECHSTACK.md](docs/TECHSTACK.md) |
| `soulwick/docs/` | PRD, Entscheidungen, **alle** Roadmaps (auch Multiplayer/Server), Grafik-Briefings | [docs/DECISIONS.md](docs/DECISIONS.md) |
| **`../soulwick-platform`** (eigenes Repo, pnpm-Monorepo) | `apps/api` (Anmeldung, Gilden, Runs, Ranglisten, Admin-Funktionen), `apps/web` (Website), `apps/admin` (Admin-Panel: sperren, Gilden, Runs, Protokoll), `packages/contracts` (API-Verträge, Quelle der Wahrheit), `infra/` (Docker, Dokploy) | dortige `AGENTS.md` und `README.md` |

**Warum getrennt:** kein gemeinsamer Code, verschiedene Werkzeuge und Release-Zyklen, das Spiel-Repo bleibt schlank (D-093). Produkt-Entscheidungen (D-Nummern) und die Spiel-Roadmaps stehen hier in `docs/`; die Plattform hat in `soulwick-platform/docs/` eigene Anforderungen, Roadmap und technische Entscheidungen (P-Nummern), die darauf verweisen. Ändert sich die API, zuerst die Verträge in `soulwick-platform/packages/contracts`, dann den GDScript-Client im Spiel.

## 3. Wo steht was zu tun ist

0. [docs/PRODUKT.md](docs/PRODUKT.md): Produktüberblick für **beide** Repositories (Pitch, Säulen, Loop, Online-Teil, Plattformen, Begriffe); zuerst lesen, wenn der Produktkontext fehlt.
1. [docs/ROADMAP.md](docs/ROADMAP.md): Haupt-Roadmap (MVP + Endlos-Ausbau, fast fertig) und Prüfstand.
2. [docs/ROADMAP_AUSBAU.md](docs/ROADMAP_AUSBAU.md): **als Nächstes**, in Phasen (D-106): Phase 1 spielbar machen (Hauptmenü, Spielstände, UX, Dorf), Phase 2 **alle Räume** nach [docs/KONZEPT_RAEUME.md](docs/KONZEPT_RAEUME.md) als Einzelspieler-Content, jedes Paket mit Koop-Check.
3. [docs/ROADMAP_MULTIPLAYER.md](docs/ROADMAP_MULTIPLAYER.md): Phase 3, erst nach den Räumen: Koop, Steam, Server, Gilden, Ranglisten; das Plattform-Repo (MP7, MP7b) darf jederzeit parallel laufen. Danach Phase 4 KI-Bosse ([docs/ROADMAP_KI_BOSS.md](docs/ROADMAP_KI_BOSS.md)).
4. [docs/ROADMAP_CROSSPLAY.md](docs/ROADMAP_CROSSPLAY.md): Phase nach dem Multiplayer (Steam, Google Play, App Store, D-108 VORGESCHLAGEN); nur die Entscheidungen **CP0** fallen **vor MP2**.
5. Grafiken, die noch fehlen: [docs/SPRITES_V8.md](docs/SPRITES_V8.md) (Räume v2, offene Teile) und [docs/SPRITES_V9.md](docs/SPRITES_V9.md) (Makeover-Welle A: Fels-Innenecken, Tunnel-Tore, Wasser, Seitenansicht); ältere Briefings sind geliefert oder darin aufgegangen.
6. [docs/HANDOUT.md](docs/HANDOUT.md) (Übersicht des Projektmitglieds, falls vorhanden) und [docs/design/](docs/design/) (Mockups für UI und Stimmung: als Inspiration lesen, bevor UI gebaut wird).

Jedes Roadmap-Paket ist für **einen Agenten** geschnitten und nennt seine Dateien.

## 4. Rollen

| Rolle | Aufgabe |
| --- | --- |
| **Orchestrator** (der Haupt-Chat) | Plant mit dem Projektmitglied, schneidet Pakete, startet Agenten, integriert, prüft, berichtet auf Deutsch. Schreibt selbst nur Kleinkram und Integration. |
| **Fach-Agent** (ein Paket) | Setzt genau ein Roadmap-Paket um, nur in seinen Dateien. Berichtet Ergebnis, Prüfstand und offene Punkte. |
| **Integrator** | Verdrahtet die Haken der Fach-Agenten in die gemeinsamen Dateien (siehe §5), löst Konflikte, lässt alle Prüfungen laufen. Meist der Orchestrator selbst. |
| **Balance-Agent** | Misst mit `tools/balance_sim.gd` (Bot spielt echte Runs), ändert nur Zahlen (`*.tres`, Konstanten mit `TESTWERT`) und dokumentiert in DECISIONS. |
| **Explore-Agent** | Nur lesen/suchen, wenn viele Dateien durchsucht werden müssen. |

Die Fach-Agenten sind als Definitionen in [.claude/agents/](.claude/agents/) hinterlegt (gleiches Muster wie im Repo DapItUp): `rooms-dev` (Raumarten, Vorlagen, Tilesets), `enemies-dev` (Gegner, Bosse, Waffen, Trefferlogik), `player-dev` (Spieler, Upgrades, HUD), `village-dev` (Dorf, Meta-Progression, Spielstand), `fx-audio-dev` (Shader, Effekte, Musik, Audio), `balance` (Zahlen und Bot-Messung). Jede Definition nennt Besitz, Bauweise, Prüfung und Berichtsform. Der Orchestrator startet sie mit dem Agent-Werkzeug (`subagent_type` = Name) und ergänzt im Auftrag das Paket und ggf. freigegebene Hotspot-Dateien.

## 5. Regeln für parallele Agenten

- **Ein Paket = ein Agent = eigene Dateien.** Parallel nur, wenn sich die Dateilisten nicht überschneiden. Im Auftrag steht immer eine **Besitzliste** („Du darfst nur … ändern“).
- **Gemeinsame Hotspots** ändert nur der Integrator oder ein Agent nach dem anderen: `project.godot`, `dungeon/dungeon_manager.gd`, `dungeon/rooms/room_controller.gd`, `enemies/enemy_base.gd`, `player/player.gd`, `scenes/game.tscn`, `autoload/*`, `docs/DECISIONS.md`, in `soulwick-platform`: Root-`package.json`, `packages/contracts`, Datenbank-Migrationen.
- Braucht ein Agent eine Änderung in einem Hotspot, baut er in seinen Dateien einen **Haken** (Funktion/Signal) und schreibt in den Bericht, wo der Integrator ihn anschließen soll.
- **Andere Sitzungen:** Es laufen oft mehrere Claude-Chats im selben Ordner. Vor größeren Umbauten prüfen, ob gerade jemand arbeitet (zuletzt geänderte Dateien, offene Sitzungen), und keine fremde Arbeit überschreiben.
- Ein abgebrochener Agent hinterlässt halbfertige Dateien: Der Integrator prüft sie mit `validate_project.gd`, bevor weitergebaut wird.

## 6. Harte Regeln

1. **Kein Commit und kein Push**, außer das Projektmitglied sagt es ausdrücklich. Branch-Modell und Commit-Format: [docs/TECHSTACK.md](docs/TECHSTACK.md) §3 (`feature/*` von `dev`, MR mit Review).
2. **Entscheidungen:** Nichts als `OFFEN` Markiertes still festlegen. Balance- und Testwerte sind an Claude delegiert: als `TESTWERT` markieren und in DECISIONS festhalten. Echte Design-/Produktfragen gehen an das Projektmitglied.
3. **D-Nummern:** Vor einem neuen Eintrag die **höchste vorhandene Nummer** in `docs/DECISIONS.md` suchen (`grep -n "^### D-" docs/DECISIONS.md | tail`). Parallele Chats haben schon doppelte Nummern erzeugt.
4. **Tests fassen den echten Spielstand nie an:** In jedem Test/Tool `SaveManager.save_path` vorher auf eine Testdatei umbiegen (`before_all`). Echter Stand: `%APPDATA%/Godot/app_userdata/Soulwick/savegame.cfg` (ein alter Stand aus `…/Dungeon Roguelite/` wird beim ersten Start einmal kopiert).
5. **Genau vier Autoloads** (GameManager, RunManager, SaveManager, EventBus, D-044). Hilfen als `static func`/`class_name`, nicht als neuer Autoload.
6. **Multiplayer-Leitplanken** für neuen Spielcode ([ROADMAP_AUSBAU.md](docs/ROADMAP_AUSBAU.md)): kein neues `get_first_node_in_group(&"player")`, Logik von Effekten trennen, Zufall nur über den Dungeon-RNG, keine neuen globalen Pausen, Zustand je Spieler am Spieler.
7. **Code Englisch, Doku Deutsch, Texte im Spiel über Übersetzungsschlüssel (en + de, D-111)**, `snake_case` für Dateien/Variablen, `PascalCase` für Klassen. Kommentare wie der umgebende Code.
8. **Erledigt heißt geprüft:** Roadmap-Punkte nur mit Nachweis abhaken (Tests grün, Datum).

## 7. Prüfen

**Spiel** (im Repo-Root von `soulwick`; `godot` = `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`):

| Was | Befehl |
| --- | --- |
| Alle Dateien laden | `godot --headless --path . -s tools/validate_project.gd` |
| Unit-Tests (GUT) | `godot --headless --path . -s addons/gut/gut_cmdln.gd` |
| Durchlauf über N Räume | `godot --headless --fixed-fps 60 --path . -s tools/smoke_test.gd -- 47` |
| Kämpfe, Waffen, Upgrades | `godot --headless --path . -s tools/combat_sim.gd` |
| Bosse, Gegner, Elites | `godot --headless --fixed-fps 60 --path . -s tools/boss_sim.gd` |
| Balance-Bot | `godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- runs=3 policy=sword quiet=1` |
| Screenshots (Fenster) | `godot --path . -s tools/screenshots.gd -- <ordner>` |
| Nach neuen Dateien/Grafiken | `godot --headless --path . --import` |

**Plattform** (im Root von `../soulwick-platform`): `pnpm install`, `pnpm typecheck`, `pnpm test`, `pnpm build`, lokal starten mit `docker compose -f infra/docker-compose.yml up` bzw. `pnpm dev`.

Mindestens vor jedem Bericht: validate + GUT (Spiel) bzw. typecheck + test (TypeScript). Bei Kampf-/Gegneränderungen zusätzlich combat_sim und boss_sim, bei Raumänderungen smoke_test.

## 8. Grafiken und Audio

- Fehlende Grafiken schreibt der Agent als **Briefing** in `docs/SPRITES_V*.md` (Datei, Größe, Frames, Beschreibung, Ablageort). Das Projektmitglied erstellt sie mit Claude Design und legt sie unter `art/` ab (Website-Grafiken in `soulwick-platform/apps/web/public/`).
- Bis dahin erzeugt der Code **Platzhalter**; echte Dateien mit dem vereinbarten Namen werden automatisch übernommen (z. B. `EnemyArt` lädt nach Namenskonvention).
- Nach dem Ablegen: `godot --headless --path . --import`. Überschreibt das Projektmitglied `art/` komplett, Cursor neu erzeugen (`python tools/generate_cursors.py`) und veraltete `.import`/UID-Reste prüfen.
- Audio wird synthetisch erzeugt: `python tools/generate_audio.py` (Effekte), `python tools/generate_music.py` (Musik). Eigene Dateien gleichen Namens ersetzen die erzeugten.

## 9. Bekannte Stolperfallen

- Mit `-s` gestartete Skripte: Autoloads existieren erst ab dem ersten Frame, also einen Frame warten.
- Python-Patch-Skripte als **Datei** schreiben (nicht als Bash-Heredoc mit Umlauten oder Anführungszeichen).
- Typisierte Arrays in GDScript: keine Lambdas mit `filter` auf `Array[Enemy]`, die ungültige Instanzen enthalten können (Absturz).
- Tippt man WASD im Editor statt im Spiel, landen Buchstaben im Code („Parser Error“). Erst ins Spielfenster klicken.
- HitStop ändert `Engine.time_scale`; Freigabe läuft über Tokens, nicht über Timer.
- Headless-Tools ohne Ton bzw. mit Bildraten-Grenze laufen lassen: Godots Audio-Mischthread kann bei sehr hohen FPS freigegebenen Speicher lesen und abstürzen (D-134; `balance_sim.gd` schaltet Ton standardmäßig ab).

## 10. Auftragsvorlage für einen Fach-Agenten

> Setze in `C:\Users\bmg18\Documents\Workspace\soulwick` das Paket **[ID]** aus `docs/[ROADMAP-Datei]` um. Lies vorher `AGENTS.md`, die Paketbeschreibung und die genannten D-Einträge in `docs/DECISIONS.md`.
> **Du darfst nur diese Dateien/Ordner ändern:** [Liste]. Brauchst du etwas in anderen Dateien, baue einen Haken und beschreibe ihn im Bericht.
> Prüfe am Ende mit [Befehle aus AGENTS.md §7] und hake die erledigten Punkte mit Datum ab. Kein Commit. Ändere keine Entscheidungen; Unklares als Frage in den Bericht.
> **Bericht:** geänderte/neue Dateien, Prüfergebnisse (Zahlen), Haken für den Integrator, benötigte Grafiken, offene Fragen.

## 11. Neuer Chat – Startprompt

> Lies `AGENTS.md`. Stand: siehe `docs/ROADMAP_AUSBAU.md` (Phasen nach D-106). Arbeite als Orchestrator: Nimm die nächsten offenen Pakete der aktuellen Phase, starte sie mit getrennten Besitzlisten parallel, integriere danach, prüfe alles und berichte mir auf Deutsch. Für Räume gilt `docs/KONZEPT_RAEUME.md`, für jedes Paket der Koop-Check.
