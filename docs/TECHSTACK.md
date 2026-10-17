# TECHSTACK – Werkzeuge und technische Leitplanken

> **Stand:** 17.10.2026 · Technologieentscheidungen und Konventionen des **Spiels**. Der Stack der Plattform (Bun, Turborepo, Prisma, Biome) steht in `soulwick-platform/docs/TECHSTACK.md`. Nicht beschlossene Werkzeuge werden nicht als gewählt ausgegeben.

## 1. Kernstack – VERBINDLICH

| Baustein | Technologie | Warum |
| --- | --- | --- |
| Spiel-Engine | **Godot 4.7.2 stable, Standard-Build** (kein .NET, D-051) | 2D-Szenen, Nodes, Physik, Signale, Editor für Räume; alle im Team nutzen genau diese Version |
| Sprache | **GDScript**, statisch typisiert | direkte Godot-Integration, Signal- und Resource-API |
| Szenen | **`.tscn`**, `Node2D`, `TileMapLayer`, `CharacterBody2D`, `Area2D` | wiederverwendbare, im Editor bearbeitbare Räume, Dorf und UI |
| Definitionsdaten | **typisierte `Resource`-Klassen + `.tres`** | Werte getrennt vom Laufzeitzustand, Balancing ohne Code; **kein JSON als Gameplay-Definition** (D-045) |
| Entkopplung | **Signale**, genau **vier Autoloads** (D-044) | klare Zuständigkeiten, lokale Ereignisse bleiben lokal |
| Tests | **GUT 9.7.1** in `addons/gut/` (D-052) | Headless-Läufe lokal und in der CI |
| Versionskontrolle | **Git + GitHub**, Organisation `WebBude-de`, Repo öffentlich (D-146, D-148) | Reviews, Releases über GitHub Actions |
| Dokumentation | **Markdown** in `docs/`, Deutsch | Absicht und Gründe neben dem Code; das Gebaute beschreibt der Code (D-178) |

## 2. Programmierrichtlinien – VERBINDLICH

| Element | Konvention | Beispiel |
| --- | --- | --- |
| Variablen, Methoden, Signale | `snake_case` | `current_health`, `room_completed` |
| Interne Methoden | `_snake_case` | `_calculate_damage()` |
| Klassen, Nodes | `PascalCase` | `HealthComponent`, `DungeonManager` |
| Konstanten | `UPPER_SNAKE_CASE` | `MAX_WEAPON_SLOTS` |
| Dateien | `snake_case` | `weapon_controller.gd` |
| Code und Kommentare | **Englisch** | `# Prevent duplicate hit registration` |
| Doku | Deutsch | `docs/PRD.md` |
| Texte im Spiel | Übersetzungsschlüssel, en + de (D-111) | `&"MENU_CONTINUE"` |

- Variablen und Methoden statisch typisieren; `const` für technische Konstanten, `@export` für Inspector-Werte, `.tres` für Balancing und Inhalt. Vorläufige Zahlen mit Kommentar `TESTWERT`.
- Kommentare begründen nicht offensichtliche Regeln oder Schnittstellen, statt Code zu wiederholen. Jede Klasse hat einen Kopfkommentar, der sagt, wofür sie da ist.
- Hilfen als `static func` bzw. `class_name`, nie als weiterer Autoload; Feature-Manager hängen an ihrer Szene.
- Erzeugte Dateien (Raumvorlagen, Dorf, Tilesets, Ton) nie von Hand bearbeiten, sondern den Generator in `tools/`.
- `.tscn`/`.tres`-Konflikte vermeiden, Node-Umbenennungen abstimmen, gelöste Merge-Konflikte im Editor prüfen.

## 3. Git und GitHub – VERBINDLICH

| Branch | Rolle | Regel |
| --- | --- | --- |
| `main` (Name laut D-146 offen; Repo und CI nutzen `main`) | stabile Releases | geschützt, nur getestete Stände per Pull Request |
| `dev` | Integration; jeder Push wird eine Testversion (D-157) | geschützt, Ziel der Pull Requests |
| `feature/*`, `fix/*` | neue Features, Fehlerkorrekturen | von `dev` erstellen |
| `hotfix/*` | dringende Release-Fehler | gegen `main`, danach nach `dev` |

**Jeder Pull Request braucht mindestens ein Review durch eine andere Person** (D-047). Kein direkter Push auf `main` und `dev`; kurzlebige Branches nach dem Merge löschen; Releases per Tag `v*` ([RELEASE.md](RELEASE.md)).

```text
feat(player): add dash movement
fix(dungeon): prevent duplicate enemy spawns
refactor(combat): simplify damage processing
docs: shorten the PRD
test(economy): cover gold payout scenarios
chore: update gitignore
```

Gültige Präfixe: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`; Bereich in Klammern optional (`feat(rooms,side): …`).

- **Versionieren:** `project.godot`, `.gd`, `.tscn`, `.tres`, `.uid`, Quell-Grafik und -Ton (Ton über Git LFS), Doku.
- **Nicht versionieren:** `.godot/`, `builds/`, Bilder der Szenen-Galerie (`docs/design/gallery/*.png`), lokale Dev-Feedback-Auswertungen (`docs/feedback/` außer README), `_inbox/`.
- **Nie ins Repo:** Schlüssel, Keystores, Tokens, Dev-Keys (die Repos sind öffentlich, D-148).

## 4. Godot-Bauweise

- Eingaben über die Input-Map und die `PlayerInput`-Schicht (Tastatur/Maus, Gamepad, Touch, Netz), nie `Input` direkt im Spieler.
- Interaktion über `Area2D` und die Aktion „Benutzen“ (E); Kampf über Hitbox-/Hurtbox-Komponenten mit Hit-IDs.
- UI zeigt, was Signale melden, und rechnet nichts selbst nach (D-034).
- Pixel-Art mit Texturfilter **Nearest**; Grafik nach Namenskonvention aus `art/`, Platzhalter im Code, solange eine Datei fehlt ([HANDOUT.md](HANDOUT.md)).
- Renderer: Forward+ auf dem PC, Compatibility (GLES 3 / WebGL 2) auf Handy und im Browser.

## 5. Testen

**VERBINDLICH:** automatisierte Tests für Schaden, Upgrades, Gold und Speichern (D-048), dazu Simulationen und Smoke-Tests für ganze Runs. Unit-Tests liegen in `tests/unit/test_*.gd`, manuelle Testszenen in `tests/manual/`. Alle Prüfbefehle: [AGENTS.md](../AGENTS.md) §7; die CI (`ci.yml`) lässt validate und GUT bei jedem Pull Request laufen.

Was Tests mindestens absichern:

- Schaden: Formel, einmalige Rundung auf 0,5, Blockieren, Schild zuerst, Mindestschaden (DECISIONS §6).
- I-Frames: auch reiner Schildschaden schützt; Dash und Treffer sind getrennte Ursachen.
- Geschosse: Hit-IDs, getrennte Historien bei Doppelschuss, Durchschlag, Abprall.
- Upgrades: Tag-Regeln, Limits, keine Dubletten im Angebot, keine Sekundär-Ketten.
- Gold: Kauf ganz oder gar nicht, Auszahlung 50/100 %, **nie doppelt**.
- Speichern: dauerhafter Fortschritt bleibt, Run nicht; defekte Dateien sicher behandeln; Tests fassen den echten Spielstand nie an (AGENTS.md §6).
- Dungeon: Fünferzyklus, Bossräume, höchstens drei lebende Räume, Kampf genau einmal, gleicher Seed = gleiche Räume.

## 6. Bewusst nicht Teil des Spiel-Stacks

- **Server, Konten, Datenbank im Spiel:** keine; der Spielstand liegt lokal. Online-Funktionen sprechen nur die Plattform-API an (`soulwick-platform`: Bun, Hono, Prisma, PostgreSQL, Next.js; D-083, D-093, D-119).
- **HTTP zwischen Spielsystemen:** nein, nur Methoden und Signale.
- **JSON als Gameplay-Konfiguration:** nein, typisierte Resources.
- **C#, C++ oder Visual Scripting** als Hauptsprache: nein.
- **Fremde Grafik- oder Ton-Pakete:** nicht gewählt. Grafik kommt aus Claude Design (Briefings in `docs/design/sprites/`), Musik und Effekte synthetisch aus `tools/generate_*.py` als Platzhalter; fremde Dateien nur mit geprüfter Lizenz (heute Pixelify Sans, OFL). Grafik, Ton, Name und Figuren sind von der GPL ausgenommen (D-177).
- **Build und Release:** GitHub Actions für Windows, Linux, macOS, Android (D-148); die Browser-Version baut Dokploy aus dem `Dockerfile` ([WEB_BUILD.md](WEB_BUILD.md)).
