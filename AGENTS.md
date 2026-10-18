# AGENTS.md – So arbeiten wir mit KI-Agenten

> Gilt für **jeden** Agenten und jeden neuen Chat in diesem Repository (Claude Code, Subagenten, andere Werkzeuge). Erst diese Datei lesen, dann die genannten Dokumente. Claude-Code-Besonderheiten: [CLAUDE.md](CLAUDE.md).
> **Stand:** 17.10.2026

## 1. Projekt in Kürze

**Soulwick** (D-094): Pixel-Roguelite in Godot 4.7.2, in das man mit Freunden reinrennt (D-173): endloser Dungeon mit Biomen, Bossen und Minispiel-Räumen, Dorf mit Meta-Progression, Koop, Gilden, Ranglisten; Browser, Steam und Handy. Zielgruppe 12 bis 25, Freundesgruppen; Ton: Dungeon atmosphärisch, Dorf süß, moderne Pixel-Art (D-174); Maskottchen Wick (D-175). Teamprojekt (Idee eines Kollegen), nach außen „Made with ♥ by WebBude“ ([PRODUKT.md](docs/PRODUKT.md)). Das Projektmitglied schreibt **Deutsch**, ist neu in Godot und arbeitet am liebsten so: Ziel nennen, Agenten bauen lassen, am Ende spielbar testen.

## 2. Repositories (D-093)

Beide Repositories liegen **öffentlich** auf GitHub in der Organisation **`WebBude-de`**: Code GPL-3.0, Grafik, Audio, Name und Figuren alle Rechte vorbehalten ([LICENSE-ASSETS.md](LICENSE-ASSETS.md), D-177). Also nie Geheimnisse ins Repo.

| Repository / Ordner | Was | Wichtigste Doku |
| --- | --- | --- |
| **`soulwick`** (dieses Repo) | Godot-Spiel im Repo-Root (`project.godot`, `dungeon/`, `player/` …), GUT-Tests, Tools | [docs/README.md](docs/README.md) (Inhaltsverzeichnis) |
| **`../soulwick-platform`** (eigenes Repo) | Bun-Workspaces mit Turborepo, Prisma, Biome (Ultracite): `apps/api` (Spieler- und Admin-API, Hono auf Bun), `apps/relay` (Koop-Relay), `apps/web` (Website), `apps/admin` (Admin-Panel), `packages/contracts` (API- und Relay-Verträge, Quelle der Wahrheit), `packages/db` (Prisma-Schema, Migrationen), `infra/` (lokales Postgres, Dokploy-Anleitung) | dortige `AGENTS.md` und `README.md` |

**Warum getrennt:** kein gemeinsamer Code, verschiedene Werkzeuge und Release-Zyklen, das Spiel-Repo bleibt schlank (D-093). Produkt-Entscheidungen (D-Nummern) und die Spiel-Roadmaps stehen hier in `docs/`; die Plattform hat eigene Anforderungen, Roadmap und technische Entscheidungen (P-Nummern). Ändert sich die API, zuerst die Verträge in `soulwick-platform/packages/contracts`, dann den GDScript-Client im Spiel.

## 3. Wo steht, was zu tun ist

Inhaltsverzeichnis mit Lesereihenfolge: [docs/README.md](docs/README.md). Kurz:

1. [docs/PRODUKT.md](docs/PRODUKT.md): wofür Soulwick da ist, für wen, Ton, Geschäftsmodell; zuerst lesen, wenn der Kontext fehlt. Begriffe: [docs/GLOSSAR.md](docs/GLOSSAR.md).
2. [docs/ROADMAP.md](docs/ROADMAP.md): **was jetzt dran ist**, Übersicht über alle Phasen in Reihenfolge (D-179): Phase 2 Räume ([ROADMAP_AUSBAU.md](docs/ROADMAP_AUSBAU.md), für Räume gilt [KONZEPT_RAEUME_V2.md](docs/KONZEPT_RAEUME_V2.md)), Phase 3 Koop ([ROADMAP_MULTIPLAYER.md](docs/ROADMAP_MULTIPLAYER.md)), Phase 4 KI-Bosse ([ROADMAP_KI_BOSS.md](docs/ROADMAP_KI_BOSS.md)), Phase 5 Party-Modus, dazu Crossplay und Stores ([ROADMAP_CROSSPLAY.md](docs/ROADMAP_CROSSPLAY.md)) und die parallelen Stränge Look (LK) und Wick (WK). Jedes Paket mit Koop-Check; das Plattform-Repo darf jederzeit parallel laufen.
3. **Doku-Regel (D-178):** Doku beschreibt Absicht, Gründe, Regeln, Begriffe und was kommt; was gebaut ist, steht im Code. Gebautes nicht in Doku nacherzählen, erledigte Pakete auf eine Zeile kürzen, Konzepte nach dem Bau auf Entscheidung und Glossar eindampfen. Jede Klasse sagt im Kopfkommentar, wofür sie da ist.
4. Fehlende Grafiken: [docs/design/sprites/README.md](docs/design/sprites/README.md) (Stand je Briefing; offen sind vor allem SPRITES_V8, Teile von SPRITES_V9, SPRITES_V12 mit Wick, Huhn und erster Kosmetik sowie die offenen Teile von SPRITES_V10: Eingabe-Symbole, niedrige Torbögen, Hochkant-Controller).
5. Mockups für UI und Stimmung: [docs/design/](docs/design/README.md) – als Inspiration lesen, bevor UI gebaut wird, nicht pixelgenau nachbauen.
6. Rückmeldungen aus dem Spiel: Dev-Feedback-Modus **F9** (nur Debug-Builds), Anleitung und Auswertung in [docs/feedback/README.md](docs/feedback/README.md).

Jedes Roadmap-Paket ist für **einen Agenten** geschnitten und nennt seine Dateien.

**Wohin mit was (Doku-Pflege, im selben Commit wie der Code):**

| Auslöser | Doc |
| --- | --- |
| Punkt gebaut und geprüft | in der passenden `ROADMAP_*.md` abhaken mit Datum und Nachweis, das Paket in die Erledigt-Liste (eine Zeile) |
| Neue Aufgabe beim Bauen | `- [ ]` in die passende `ROADMAP_*.md` (Reihenfolge = Vorrang) |
| Idee „nicht jetzt“ | [docs/BACKLOG.md](docs/BACKLOG.md), eine Zeile, statt sie umzusetzen |
| Neues Fachwort, UI-Wort, Code-Name | [docs/GLOSSAR.md](docs/GLOSSAR.md), vor dem Code |
| Entscheidung, Testwert | `docs/DECISIONS.md` mit der nächsten freien D-Nummer (§6.3) |
| Neue Abhängigkeit, Werkzeugwechsel | `docs/TECHSTACK.md` (warum) und DECISIONS, nur nach Rückfrage (§6.11) |
| Ziel, Zielgruppe, Nicht-Ziel ändert sich | `docs/PRODUKT.md` bzw. `docs/PRD.md` und DECISIONS, nur nach Rückfrage |
| Neuer Befehl, neues Werkzeug | §7 dieser Datei |
| Fehler passiert zum zweiten Mal | §9 Stolperfallen |

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
- **Andere Sitzungen:** Oft laufen mehrere Chats im selben Ordner (Räume und Multiplayer im selben Branch, kein eigener Worktree mehr). Vor größeren Umbauten prüfen, wer gerade arbeitet (zuletzt geänderte Dateien, `git status`, offene Sitzungen), und keine fremde Arbeit überschreiben oder zurücksetzen.
- Ein abgebrochener Agent hinterlässt halbfertige Dateien: Der Integrator prüft sie mit `validate_project.gd`, bevor weitergebaut wird. Unterbrochene Agenten nicht ungefragt neu starten.

## 6. Harte Regeln

1. **Kein Commit und kein Push**, außer das Projektmitglied sagt es ausdrücklich. Branch-Modell und Commit-Format: [docs/TECHSTACK.md](docs/TECHSTACK.md) §3 (`feature/*` von `dev`, Pull Request mit Review).
2. **Entscheidungen:** Nichts als `OFFEN` Markiertes still festlegen. Balance- und Testwerte sind an Claude delegiert: als `TESTWERT` markieren und in DECISIONS festhalten. Echte Design- und Produktfragen gehen an das Projektmitglied.
3. **D-Nummern:** Vor einem neuen Eintrag die **höchste vorhandene Nummer** in `docs/DECISIONS.md` suchen (`grep -n "^### D-" docs/DECISIONS.md | sort -t- -k2 -n | tail`). Parallele Chats haben schon doppelte Nummern erzeugt (D-121 bis D-129 gehören zum Multiplayer).
4. **Tests fassen den echten Spielstand nie an:** In jedem Test und Tool `SaveManager.save_path` vorher auf eine Testdatei umbiegen (`before_all`). Echter Stand: `%APPDATA%/Godot/app_userdata/Soulwick/` (ein alter Stand aus `…/Dungeon Roguelite/` wird beim ersten Start einmal kopiert).
5. **Genau vier Autoloads** (GameManager, RunManager, SaveManager, EventBus, D-044). Hilfen als `static func`/`class_name`, nicht als neuer Autoload.
6. **Multiplayer-Leitplanken** für neuen Spielcode (D-088, Koop-Check in ROADMAP_AUSBAU): kein neues `get_first_node_in_group(&"player")`, Logik von Effekten trennen, Zufall nur über den Dungeon-RNG, keine neuen globalen Pausen, Zustand je Spieler am Spieler.
7. **Code Englisch, Doku Deutsch, Texte im Spiel über Übersetzungsschlüssel (en + de, D-111)**, `snake_case` für Dateien und Variablen, `PascalCase` für Klassen. Kommentare wie der umgebende Code.
8. **Erledigt heißt geprüft:** Roadmap-Punkte nur mit Nachweis abhaken (Tests grün, Datum).
9. **Prozesse nie per Namen beenden** (`taskkill /IM …`, `pkill`, `killall`, `Stop-Process -Name …`): Das trifft Godot-Fenster, Browser und Server anderer Sitzungen. Nur selbst gestartete Prozesse über ihre PID beenden.
10. **Keine Geheimnisse ins Repo** (es ist öffentlich): Schlüssel nur in gitignorten Dateien (`.env*`, `secrets.json` im Root), Vorlage `secrets.example.json`. `art/environment/rooms/secrets.json` ist Grafik für Geheimräume, kein Secret.
11. **Keine neue Abhängigkeit ohne Rückfrage** (Godot-Addon, Python- oder Bun-Paket, Docker-Image); Grund in TECHSTACK, Entscheidung in DECISIONS.
12. **Größeres erst planen:** als Paket in die passende Roadmap schneiden (Dateien, Prüfung, Koop-Check), dann bauen.
13. **Kein `sudo`** ohne Rückfrage.
14. **Konventionen:** Commits als Conventional Commits auf Englisch (`feat|fix|refactor|docs|test|chore|perf|build|ci|balance|art(scope): was`, höchstens 72 Zeichen, Body = warum; Details [docs/TECHSTACK.md](docs/TECHSTACK.md) §3). `TODO:` nur mit Ziel (`TODO: → ROADMAP_AUSBAU M3`). Stil: kurze Funktionen, sprechende Namen, keine Vorab-Abstraktion; Fehlermeldungen sagen, was zu tun ist.

## 7. Prüfen

**Spiel** (im Repo-Root von `soulwick`; `godot` = `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`, in Bash `"C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe"`; unter Linux `godot` im PATH, `~/.local/bin/godot`. Audio liegt in Git LFS: ohne `git lfs install` und `git lfs pull` sind die WAV-Dateien nur Platzhalter und der Import schlägt fehl):

| Was | Befehl |
| --- | --- |
| Alle Checks auf einmal | `scripts/check` (Import, alle Dateien laden, GUT; headless) · `scripts/check --quick` ohne GUT (läuft im pre-commit-Hook) |
| Einmal nach dem Klonen | `git lfs install` und `git config core.hooksPath .githooks` (Hook: Secrets-Sperre und `scripts/check --quick`, enthält die Git-LFS-Hooks) |
| Alle Dateien laden | `godot --headless --path . -s tools/validate_project.gd` |
| Unit-Tests (GUT) | `godot --headless --path . -s addons/gut/gut_cmdln.gd` |
| Durchlauf über N Räume | `godot --headless --fixed-fps 60 --path . -s tools/smoke_test.gd -- 47` |
| Kämpfe, Waffen, Upgrades | `godot --headless --path . -s tools/combat_sim.gd` |
| Bosse, Gegner, Elites | `godot --headless --fixed-fps 60 --path . -s tools/boss_sim.gd` |
| Balance-Bot | `godot --headless --fixed-fps 60 --path . -s tools/balance_sim.gd -- runs=3 policy=sword quiet=1` |
| Screenshots (Fenster) | `godot --path . -s tools/screenshots.gd -- <ordner>`; unter Linux nur `tools/godot_offscreen.sh --path . -s tools/screenshots.gd -- <ordner>` (unsichtbarer Bildschirm über `cage` oder `weston`, stumm; nie `kwin_wayland --virtual`, das legt die KWin-Kürzel der Sitzung lahm) |
| Texte (fehlende Übersetzungen) | `python tools/i18n_check.py <ordner>` |
| Nach neuen Dateien/Grafiken/Texten | `godot --headless --path . --import` |
| Builds (Windows, Linux, macOS, Android) | `tools/export_build.sh development "" "windows linux macos"`; Releases per Tag `v*` über GitHub Actions ([docs/RELEASE.md](docs/RELEASE.md)); Browser-Version per `Dockerfile` auf Dokploy ([docs/WEB_BUILD.md](docs/WEB_BUILD.md)) |

**Plattform** (im Root von `../soulwick-platform`, Bun 1.3, Node 24, Docker): `bun install`, `bun run services:up` (lokales Postgres), `bun run check` (Biome), `bun run typecheck`, `bun run test`, `bun run build`; lokal starten mit `bun dev`. Details in der dortigen README.

**Leise laufen (Projektmitglied 16.10.2026):** Agenten und Werkzeuge starten Godot nie mit Ton und nie im Vordergrund, weil das Projektmitglied oft parallel spielt. Jeder Lauf mit `--audio-driver Dummy`; Fensterläufe (Screenshots) zusätzlich mit der Umgebungsvariable `SOULWICK_QUIET=1` (alle Busse stumm, Fenster bekommt keinen Fokus und liegt fast ganz außerhalb des Bildschirms, `components/quiet_run.gd`). Bash: `SOULWICK_QUIET=1 godot --audio-driver Dummy --path . -s tools/screenshots.gd -- <ordner>`. Wann immer möglich `--headless`. Browser-Tests des Web-Builds (Playwright/Chromium) immer stumm: `--mute-audio`, möglichst headless. Der normale Spielstart bleibt unverändert.

Mindestens vor jedem Bericht: validate + GUT (Spiel) bzw. check + typecheck + test (Plattform). Bei Kampf- und Gegneränderungen zusätzlich combat_sim und boss_sim, bei Raumänderungen smoke_test.

## 8. Grafiken und Audio

- Fehlende Grafiken schreibt der Agent als **Briefing** in `docs/design/sprites/SPRITES_V*.md` (Datei, Größe, Frames, Beschreibung, Ablageort) und trägt es in [docs/design/sprites/README.md](docs/design/sprites/README.md) ein. Das Projektmitglied erstellt sie mit Claude Design und legt sie unter `art/` ab (Website-Grafiken in `soulwick-platform/apps/web/public/`).
- Bis dahin erzeugt der Code **Platzhalter**; echte Dateien mit dem vereinbarten Namen werden automatisch übernommen (z. B. `EnemyArt` lädt nach Namenskonvention).
- Nach dem Ablegen: `godot --headless --path . --import`. Überschreibt das Projektmitglied `art/` komplett, Mauszeiger neu erzeugen (`python tools/generate_cursors.py`) und veraltete `.import`-/UID-Reste prüfen.
- Audio wird synthetisch erzeugt: `python tools/generate_audio.py` (Effekte), `python tools/generate_music.py` (Musik, Details in [docs/AUDIO.md](docs/AUDIO.md)). Eigene Dateien gleichen Namens ersetzen die erzeugten.
- Dateinamen in `docs/design/responses/` (Antworten von Claude Design) nicht ändern: Code und Werkzeuge verweisen darauf. Ordnernamen unter `docs/design/` sind Englisch (D-178).
- Grafik- und Audio-Beiträge von außen nur nach Absprache (D-177); Kommentare und Doku verweisen auf D-Nummern statt auf gelöschte Konzepte.

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

> Lies `AGENTS.md`. Stand: siehe `docs/ROADMAP.md` (Phasen nach D-179 und parallele Stränge; Details in den verlinkten Roadmaps). Arbeite als Orchestrator: Nimm die nächsten offenen Pakete nach der Vorrang-Regel, starte sie mit getrennten Besitzlisten parallel, integriere danach, prüfe alles und berichte mir auf Deutsch. Für Räume gilt `docs/KONZEPT_RAEUME_V2.md`, für jedes Paket der Koop-Check.
