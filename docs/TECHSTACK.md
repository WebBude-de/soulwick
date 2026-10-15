# TECHSTACK – Werkzeuge und technische Leitplanken

> **Stand:** 15.10.2026 · **Basis:** Überarbeitetes GDD Master 1.0 und die Branch-Regeln aus D-047 (ursprünglich für GitLab beschlossen, gelten sinngemäß auf GitHub).  
> **Wichtig:** Diese Datei beschreibt **Technologieentscheidungen** des Spiels. Der Stack der Plattform (Bun, Turborepo, Prisma, Biome) steht in `soulwick-platform/docs/TECHSTACK.md`. **Nicht beschlossene Tools werden nicht als bereits ausgewählt ausgegeben.**

## 1. Kernstack – VERBINDLICH

| Baustein | Technologie | Warum / GDD-Bezug |
| --- | --- | --- |
| Spiel-Engine | **Godot 4.7.2** | Native 2D-Szenen, Nodes, Physik, Signale, Laufzeitverwaltung und Editor für unabhängig gestaltbare Räume. |
| Sprache | **GDScript** | Direkte Godot-Integration, typisierte Methoden/Variablen, Signal- und Resource-API. |
| Szenen/Level | **`.tscn`**, `Node2D`, `TileMapLayer` | Wiederverwendbare und im Editor bearbeitbare Dungeonräume, Dorf und UI. |
| Spielfiguren/Bewegung | **`CharacterBody2D`** | Steuerbare Spieler- und Gegnerkörper mit Kollisionen. |
| Trigger/Interaktion | **`Area2D`**, `Marker2D` | Dungeon-Eingang, Interaktionen, feste Spawnpunkte und Zonen. |
| Definitionsdaten | **Eigene typisierte `Resource`-Klassen + `.tres`** | Waffendaten, Upgrades und Gegner-/Balancewerte unabhängig vom instanziierten Zustand; **kein JSON für MVP-Definitionsdaten**. |
| Entkopplung | **Godot-Signale**, vier Kern-Autoloads | Zustandsverantwortlichkeiten klar halten, lokale Events lokal lassen. |
| Versionskontrolle | **Git + GitHub** (privat, Organisation `WebBude-de`, Repo `soulwick`) | Parallele Teamarbeit, Reviews und stabile Versionsstände. |
| Dokumentation | **Markdown** in `docs/`, konsolidiertes GDD als Referenz | Änderungen und Entscheidungen neben dem Code versionieren. |

**Engine-Version:** **Godot 4.7.2 stable, Standard-Build** (kein .NET), festgelegt am 13.10.2026 ([D-051](DECISIONS.md)). Alle Teammitglieder nutzen genau diese Version.

## 2. Programmierrichtlinien – VERBINDLICH

| Element | Konvention | Beispiel |
| --- | --- | --- |
| Variablen, Methoden, Signale | `snake_case` | `current_health`, `room_completed` |
| Interne Methoden | `_snake_case` | `_calculate_damage()` |
| Klassen, Nodes | `PascalCase` | `HealthComponent`, `DungeonManager` |
| Konstanten | `UPPER_SNAKE_CASE` | `MAX_WEAPON_SLOTS` |
| Dateien | `snake_case` | `weapon_controller.gd` |
| Codekommentare/Bezeichner | **Englisch** | `# Prevent duplicate hit registration` |
| Game-Design-Dokumentation | Deutsch erlaubt | `docs/PRD.md` |

- Variablen und Methoden nach Möglichkeit **statisch typisieren**.
- `const` für technische Konstanten, `@export` für Inspector-konfigurierbare Parameter, `.tres` für Balancing- und Inhaltsdaten.
- Kommentare begründen nicht offensichtliche Regeln oder Schnittstellen statt triviale Codezeilen zu wiederholen.
- **Vier und nur vier Kern-Autoloads:** `GameManager`, `RunManager`, `SaveManager`, `EventBus`.
- Feature-Manager bleiben **szenenbezogen** (Dungeon, Upgrades, Economy, UI).
- Bei gemeinsamer Arbeit `.tscn`/`.tres`-Konflikte vermeiden, Node-Umbenennungen abstimmen und gelöste Merge-Konflikte im Godot-Editor prüfen.

## 3. Git und GitHub – VERBINDLICH

### Branch-Modell

| Branch | Rolle | Regel |
| --- | --- | --- |
| Haupt-Branch (`master` laut D-047, Name auf GitHub beim ersten Push festlegen) | Stabile Release-Versionen | Geschützt, nur getestete Stände per Pull Request |
| `dev` | Integration | Geschützt, gemeinsames Ziel der Pull Requests |
| `feature/*` | Neue Features | Von `dev` erstellen, per MR zurückführen |
| `fix/*` | Normale Fehlerkorrekturen | Von `dev` erstellen |
| `hotfix/*` | Dringende Release-Fehler | Gegen den Haupt-Branch und anschließend in `dev` zurückführen |

**Jeder Pull Request braucht mindestens ein Review durch eine andere Person.** Kein direkter Push auf den Haupt-Branch und `dev`. Kurzlebige Feature-Branches nach dem Merge entfernen, freigegebene Stände taggen. Längere Parallelarbeit läuft in eigenen Worktrees (z. B. `../soulwick-mp` für `feature/multiplayer`).

### Commit-Konvention

```text
feat(player): add dash movement
fix(dungeon): prevent duplicate enemy spawns
refactor(combat): simplify damage processing
docs(gdd): update master specification
test(economy): cover gold payout scenarios
chore: update gitignore
```

Gültige Präfixe: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. Bereich in Klammern optional (`feat(rooms,side): …`).

### Gitignore / Projektdateien

- **Versionieren:** `project.godot`, `.gd`, `.tscn`, `.tres`, Source-Assets, Dokumentation, von Godot erzeugte `.uid`-Dateien.
- **Nicht versionieren:** generierte Godot-Editor-/Import-Caches, insbesondere `.godot/`; neu erzeugbare Bilder der Szenen-Galerie (`docs/design/szenen/*.png`); lokale Dev-Feedback-Auswertungen (`docs/feedback/` außer README).
- Optional weitere **generierte** Dateien ausschließen, sobald tatsächlich verwendet. Keine pauschal unbestätigten Ausschlussregeln für echte Quellen/Assets festlegen.

## 4. Konkrete Godot-APIs (aus dem GDD)

| Anforderung | GDD-konformer Ansatz |
| --- | --- |
| Maussteuerung/WASD/Dash | Godot-Input-Map, CharacterBody2D, normalisierte Bewegung |
| Ein-/Ausgang und Interaktion | `Area2D` plus Aktion `E` |
| Kampfkontakt | Hitbox-/Hurtbox-Komponenten, eindeutige Hit-IDs |
| Spieler-Unverwundbarkeit | Separate Ursachen für Dash und Treffer-I-Frames |
| Shader-/Sprite-Darstellung | Godot-2D-Visuals; **konkrete Asset-Packs/Renderer nicht verbindlich gewählt** |
| Status und UI | Signale statt selbstständig nachgerechneter HUD-Zustände |
| Weltwechsel | Aktivwelt unter `game.tscn` austauschen; Spieler bei Weltwechsel neu instanziieren |
| Dungeon-Raumwechsel | Raumcontainer mit maximal drei gleichzeitig existierenden Rauminstanzen |
| Game-Pause | Godot-SceneTree-Pause plus fortlaufend verarbeitete Menü-UI |
| Save | SaveManager, Datenversion/Validierung; `ConfigFile` je Spielstand (D-059, VORGESCHLAGEN) |

## 5. Testing / Qualitätssicherung

**VERBINDLICH:** Gezielte **automatisierte Tests** für Schadensberechnung, Upgrade-Regeln, Economy und Speichern; zusätzlich manuelle Szenen-Tests für Input, Streaming, Kampf und UI. Test-Framework: **GUT 9.7.1** in `addons/gut/` ([D-052](DECISIONS.md)).

```text
# Alle Unit-Tests headless ausführen (liest .gutconfig.json)
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

Unit-Tests liegen in `tests/unit/test_*.gd`; manuelle Testszenen in `tests/manual/` (z. B. `combat_sandbox.tscn`). Alle Prüfbefehle (Smoke-Test, Kampf- und Boss-Simulation, Balance-Bot): [AGENTS.md](../AGENTS.md) §7.

Mindesttestfelder:

- Damage: Basis + flache/prozentuale Boni, einmalige Rundung auf 0,5, Blockierung, Schild zuerst, Mindestschaden.
- I-Frames: Auch schildexklusiver Schaden aktiviert 0,5 s; Dash und Treffer-Ursachen unabhängig.
- Projektile: Hit-IDs, getrennte Doppelschuss-Historien, Durchschlag und Abprall.
- Upgrades: OR-Anwendbarkeit + `required_tags`, Stacklimits, keine Auswahl-Duplikate, keine Sekundärrekursion, normale Kills durch Sekundäreffekte.
- Economy: Kauf vollständig oder gar nicht, Auszahlungen 50/100 %, **keine doppelte Gutschrift**.
- Save: Permanenter Fortschritt bleibt nach Neustart, Run nicht; defekte Dateien sicher behandeln.
- Dungeon: Fünf-Raum-Zyklus, Bossersetzung, 3-Raum-Obergrenze **inkl. Freigabe-Frame**, eindeutige Spawnpunkte, echte Raumabschlusslogik.
- UI: Vollständige Pause (Timer/Projektile), weiter bedienbare Menüs, Waffenvergleich mit effektiven Werten.

## 6. Bewusst nicht als Stack-Bestandteil beschlossen

> **Nach dem MVP geändert (D-083, D-093, D-119):** Für Konten, Gilden, Ranglisten, Koop-Relay, Website und Admin-Panel gibt es das eigene Repository `soulwick-platform` (TypeScript auf Bun, Hono, Prisma mit PostgreSQL, Next.js). Das **Spiel selbst** bleibt ohne Server spielbar; die Punkte unten gelten weiter für den Spielkern.

- **Backend / Accounts / Datenbank im Spiel:** keine; der Spielstand liegt lokal. Online-Funktionen sprechen nur die Plattform-API an.
- **Interne Schnittstellen:** Godot-Methoden und Signale, keine HTTP-Aufrufe zwischen Spielsystemen.
- **JSON-Gameplay-Konfiguration:** Stattdessen typisierte Godot-Resources.
- **C#, C++ oder Visual-Scripting als primäre Sprache:** Nicht die beschlossene Implementierungssprache.
- **Grafik und Audio:** eigene Pixel-Art aus Claude Design (Briefings in `docs/design/sprites/`), synthetisch erzeugte Musik und Effekte (`tools/generate_*.py`); fremde Quellen nur mit geprüfter Lizenz (heute: Pixelify Sans, OFL).
- **Build-/Release-CI und Exportziele:** geplant in ROADMAP_CROSSPLAY CP7 (Windows, Linux, Android, später iOS); CI-Anbieter noch festzulegen.

**Weiterlesen:** [ARCHITECTURE.md](ARCHITECTURE.md) · [PRD.md](PRD.md) · [ROADMAP.md](ROADMAP.md) · [DECISIONS.md](DECISIONS.md)
