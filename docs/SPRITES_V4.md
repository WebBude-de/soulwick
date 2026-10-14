# Grafik-Briefing V4 – Soulwick: Dorf beleben (und Nachträge aus Phase 2)

> **Für Claude Design.** Diese Datei ist eigenständig lesbar. Sie ergänzt [SPRITES.md](SPRITES.md), [SPRITES_V2.md](SPRITES_V2.md) und [SPRITES_V3.md](SPRITES_V3.md). Abschnitt 1–3 gehören zu ROADMAP_AUSBAU **B3 – Dorf beleben** (Stand 14.10.2026); weitere Pakete hängen ihre Grafiken unten als eigene Abschnitte an.
> **Ablage:** im Spiel-Repo unter `art/` im angegebenen Unterordner. **Dateinamen exakt übernehmen**, dann baut der Code sie automatisch ein. Bis dahin zeigt das Dorf einfache Platzhalter (bzw. lässt Karren und Katze weg). Danach einmal `godot --headless --path . --import` ausführen.

## Spiel in einem Satz

2D-Top-down-Dungeon-Roguelite in Pixel-Art: Vom Dorf aus steigt der Spieler in einen endlosen, dunklen Dungeon hinab. Das Dorf ist der helle, warme Gegenpol: Fachwerkhäuser, Wege aus Erde, Marktplatz mit Brunnen, Wald am Rand.

## Stil und Format (wie bisher, unbedingt einhalten)

- **Pixel-Art**, Top-down mit leichter Schrägsicht (3/4), gleiche Palette und gleicher Pixel-Maßstab wie die vorhandenen Dorf-Grafiken (`art/environment/buildings/`, `village_tileset.png`). Das Spiel zeichnet alles **doppelt so groß** (1 Grafik-Pixel = 2 Bildschirm-Pixel).
- **PNG mit transparentem Hintergrund** (kein Gras unter den Objekten), exakte Pixelgrößen, kein Anti-Aliasing, kein Hochskalieren.
- **Kontur 1 px `#1c1a2b`** wie bei Häusern und Figuren.
- **Pivot = unten Mitte:** Die unterste nicht-transparente Pixelreihe ist die Linie, auf der das Objekt am Boden steht. Objekte mittig in die Datei setzen.
- **Animationen als horizontaler Streifen** ohne Abstand, quadratische Frames, Frame-Anzahl im Namen (`villager_1_walk_6f.png`). **Figuren schauen nach rechts**, Füße in allen Frames auf gleicher Höhe (32er-Frame: y = 29/30 wie die Dorf-NPCs, 16er-Frame: y = 14/15).
- **Palette Dorf** (docs/HANDOUT.md): Gras `#5a8f46` / `#6ea455` / `#4a7a3a`, Weg `#a8875a`, Holz `#a8703f` / `#8a5a34` / `#5c3a24`, Stein `#9a94b5` / `#7d7799` / `#59547a`, Wasser `#6cb2ec` / `#3690da` / `#2a6cb0`, Blüten z. B. `#f0648c`, `#f2cf4a`, `#e9e4d2`, `#a66ef0`.

## 1. Dorf-Deko (`art/environment/village/`, B3)

Kleine Deko wird vom Spiel an Wegrändern und Hauswänden verstreut (fester Zufall, immer gleich), größere Objekte stehen an festen Plätzen. Prioritäten: **P1** sofort sichtbar und heute nur grober Platzhalter, **P2** schön zu haben.

| Prio | Datei | Größe | Beschreibung |
| --- | --- | --- | --- |
| P1 | `flowers_1.png`, `flowers_2.png`, `flowers_3.png` | je 20×14 | Kleine Blumenbüschel mit Stielen und Blättern, drei Farbvarianten (rosa, gelb, weiß-lila gemischt) |
| P1 | `flower_bed.png` | 32×14 | Längliches Blumenbeet mit dunkler Erde und schmalem Holzrand, bunte Blüten |
| P1 | `garden_fence.png` | 32×22 | Gartenzaun-Stück waagerecht (zwei Latten, Pfosten links und rechts je halb angeschnitten), **nahtlos aneinanderreihbar**, Holz wie der Dorfzaun |
| P1 | `hay_bale.png` | 24×18 | Runder/eckiger Heuballen mit Schnur, warmes Gelb |
| P1 | `bench.png` | 28×16 | Holzbank ohne Lehne von vorn, zwei Beine |
| P1 | `pond.png` | 56×30 | Kleiner ovaler Teich mit Steinrand, zwei Seerosenblätter, eine Blüte, leichte Lichtreflexe |
| P2 | `cart.png` | 48×32 | Holzkarren mit zwei Rädern, Säcke/Kisten beladen, Deichsel nach links (steht neben der Gilde; **heute ohne Platzhalter**) |
| P2 | `signpost.png` | 24×30 | Wegweiser: Pfosten mit zwei Brettern (links Haus-Symbol, rechts Totenkopf/Höhle für den Dungeon), **keine Schrift** |
| P2 | `grass_tuft.png` | 14×9 | Grasbüschel, etwas dunkler als der Boden |
| P2 | `stones.png` | 16×10 | Zwei bis drei kleine Kiesel |
| P2 | `bush_small.png` | 32×32 | Kleiner runder Busch (heute aus dem Tileset ausgeschnitten) |

## 2. Dorfbewohner und Tiere (`art/characters/npcs/`, B3)

Laufen langsam auf den Wegen, bleiben kurz stehen; keine Kollision. Heute laufen eingefärbte Kopien der Gebäude-NPCs als Platzhalter. Frames quadratisch, Größe aus der Streifenhöhe.

| Prio | Dateien | Frame | Beschreibung |
| --- | --- | --- | --- |
| P1 | `villager_1_idle_4f.png`, `villager_1_walk_6f.png` | 32×32 | Bäuerin mit Kopftuch und Weidenkorb (Brot/Äpfel), Schürze |
| P1 | `villager_2_idle_4f.png`, `villager_2_walk_6f.png` | 32×32 | Holzfäller/Handwerker mit Axt oder Holzbündel über der Schulter |
| P1 | `villager_3_idle_4f.png`, `villager_3_walk_6f.png` | 32×32 | Alter Mann mit Gehstock und Mütze (langsam, schlendert um den Brunnen) |
| P2 | `chicken_idle_4f.png`, `chicken_walk_4f.png` | 16×16 | Weißes Huhn mit rotem Kamm; idle = pickt am Boden (heute einfacher Platzhalter) |
| P2 | `cat_idle_4f.png`, `cat_walk_6f.png` | 16×16 | Getigerte Katze; idle = sitzt und schlägt mit dem Schwanz (**heute ohne Platzhalter**, erscheint erst mit der Datei) |

## 3. Dorf-UI (`art/ui/`, aus SPRITES_V3 §4 noch offen)

| Prio | Datei | Größe | Beschreibung |
| --- | --- | --- | --- |
| P1 | `sign_home.png` | 24×16 | Holzschild über der Tür des Zuhauses, passend zu `sign_forge.png` & Co.: kleines Haus oder Kleiderbügel als Symbol, keine Schrift |

## Wo der Code die Dateien abholt

- Deko: `VillageArt.get_texture("<name>")` in `world/village/village_art.gd` lädt `art/environment/village/<name>.png`.
- Figuren: `VillageArt.get_character_frames("<name>")` lädt `<name>_idle_<n>f.png` und `<name>_walk_<n>f.png` aus `art/characters/npcs/` (4 bzw. 8 Bilder/s).
- Schild: `VillageBuildings.get_sign_texture(&"home")` lädt `art/ui/sign_home.png`.
