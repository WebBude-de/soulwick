# Grafik-Briefing V8 – Soulwick: Räume v2, offene Teile

> **Für Claude Design.** Ergänzt [design/claude_design_antwort/SPRITES_V8_vorschlag.md](../claude_design_antwort/SPRITES_V8_vorschlag.md): Die dort als GELIEFERT markierten Teile sind im Spiel eingebaut. Hier stehen nur die **offenen** Teile. Dateinamen exakt übernehmen, dann baut der Code sie automatisch ein; bis dahin laufen Platzhalter.
> **Stand:** 14.10.2026 · Stil wie bisher (Pixel-Art, 32-px-Kacheln, Kontur `#1c1a2b`, Palette `docs/HANDOUT.md`, Animationen als Streifen mit Frame-Anzahl im Namen, je Datei ein JSON mit fps und Pivot wie bei den gelieferten Teilen).

## 1. Türen und Gänge

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/doors/door_frame_boss_<biom>.png` | 64×56 | Bosstor je Biom (heute ein graues Tor, nur eingefärbt) |
| `art/environment/doors/door_boss_chains_4f.png` | 4 × 64×56 | Ketten des Bosstors, die beim Öffnen rasseln und fallen |
| `art/environment/corridors/corridor_<biom>_{straight,stairs,niche}.png` | je 96×64 | Gänge mit Charakter zwischen den Räumen: gerade, mit Treppe/Höhenversatz, mit Nische und Tropfstelle |

## 2. Dorf und Dungeon-Eingang

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/village/dungeon_entrance_v2.png` | 96×80, Pivot unten Mitte (48,80) | Ruine mit Treppe nach unten, Ketten, Seelen-Rune (siehe `06_dorf.md`); Fackelflammen bei (35,51) und (61,51), Raben sitzen auf dem Sturz bei ca. (48,18) |
| `art/environment/village/entrance_flame_bowl_6f.png` | 6 × 32×32, Pivot unten Mitte | Seelenflammen-Becken vor dem Eingang |
| `art/environment/village/ravens_4f.png` | 4 × 32×16 | Raben: sitzen, picken, Flügel oben, Flügel unten; Füße auf der untersten Zeile |
| `art/environment/village/village_tiles_v2.png` | 256×32 (8 Kacheln) | Pflaster A/B, Felskante A/B (nur Zeile 6–28 fest), Treppe links/rechts, Steinplatten A/B |
| `art/environment/village/chronicle_board.png` | 24×30 | leere Kreidetafel auf einer Staffelei vor der Chronik; Schieferfläche x3–20 / y3–16 für Kreidestriche |

## 3. UI

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/ui/taskbar_frame.png` | 48×24 (9-Slice) | Rahmen der Aufgabenleiste |
| `art/ui/banner_stripe.png` | 8×32 | Farbstreifen links am Banner (wird in Modusfarbe getönt) |
| `art/ui/countdown_digits.png` | 3 × 24×32 | große Ziffern 3, 2, 1 |
| `art/ui/objective_icons.png` | 10 × 16×16 | Aufgabenleisten-Icons (wie `door_mode_symbols`, farbig) |

## 4. Minispiele und Ziele

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/characters/npcs/lost_chicken_lantern_idle_4f.png`, `_walk_4f.png` | 16×16 je Frame | Huhn mit Laterne am Hals (seltene Geleit-Figur) |
| `art/environment/objectives/relic_pedestal_<biom>.png` | 32×32 | Podest der Reliquie je Biom |
| `art/environment/trials/collapse_marker_4f.png` | 4 × 32×32 | Einbruch-Warnmarke: Risse und rotes Glühen |

## 5. Quellen und Deko

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/spawn/spawn_<biom>_idle_4f.png` | 4 × 32×32 | Ruhezustand der Quellen, leichtes Glimmen |
| `art/environment/deco/deco_group_<biom>_{1..3}.png` | 64×48 | fertige Deko-Gruppen je Biom als ein Bild |
| `art/environment/deco/puddle_4f.png` | 4 × 32×32 | Pfütze unter der Tropfstelle |
| `art/environment/deco/dust_fall_4f.png` | 4 × 16×16 | Staub an der eingestürzten Säule |
| `art/environment/deco/gravestone.png` | 32×32 | einzelner Grabstein für Opferstellen (kein Quellen-Grab) |
| `art/environment/deco/shallow_water_edge.png` | 4 × 32×32 | weicher Rand für Wasserbecken (heute eckig) |
