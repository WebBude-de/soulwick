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

Kleine Deko wird vom Spiel an Wegrändern und Hauswänden verstreut (fester Zufall, immer gleich), größere Objekte stehen an festen Plätzen.

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `flowers_1.png`, `flowers_2.png`, `flowers_3.png` | je 20×14 | Kleine Blumenbüschel mit Stielen und Blättern, drei Farbvarianten (rosa, gelb, weiß-lila gemischt) |
| `flower_bed.png` | 32×14 | Längliches Blumenbeet mit dunkler Erde und schmalem Holzrand, bunte Blüten |
| `garden_fence.png` | 32×22 | Gartenzaun-Stück waagerecht (zwei Latten, Pfosten links und rechts je halb angeschnitten), **nahtlos aneinanderreihbar**, Holz wie der Dorfzaun |
| `hay_bale.png` | 24×18 | Runder/eckiger Heuballen mit Schnur, warmes Gelb |
| `bench.png` | 28×16 | Holzbank ohne Lehne von vorn, zwei Beine |
| `pond.png` | 56×30 | Kleiner ovaler Teich mit Steinrand, zwei Seerosenblätter, eine Blüte, leichte Lichtreflexe |
| `cart.png` | 48×32 | Holzkarren mit zwei Rädern, Säcke/Kisten beladen, Deichsel nach links (steht neben der Gilde; **heute ohne Platzhalter**) |
| `signpost.png` | 24×30 | Wegweiser: Pfosten mit zwei Brettern (links Haus-Symbol, rechts Totenkopf/Höhle für den Dungeon), **keine Schrift** |
| `grass_tuft.png` | 14×9 | Grasbüschel, etwas dunkler als der Boden |
| `stones.png` | 16×10 | Zwei bis drei kleine Kiesel |
| `bush_small.png` | 32×32 | Kleiner runder Busch (heute aus dem Tileset ausgeschnitten) |

## 2. Dorfbewohner und Tiere (`art/characters/npcs/`, B3)

Laufen langsam auf den Wegen, bleiben kurz stehen; keine Kollision. Heute laufen eingefärbte Kopien der Gebäude-NPCs als Platzhalter. Frames quadratisch, Größe aus der Streifenhöhe.

| Dateien | Frame | Beschreibung |
| --- | --- | --- |
| `villager_1_idle_4f.png`, `villager_1_walk_6f.png` | 32×32 | Bäuerin mit Kopftuch und Weidenkorb (Brot/Äpfel), Schürze |
| `villager_2_idle_4f.png`, `villager_2_walk_6f.png` | 32×32 | Holzfäller/Handwerker mit Axt oder Holzbündel über der Schulter |
| `villager_3_idle_4f.png`, `villager_3_walk_6f.png` | 32×32 | Alter Mann mit Gehstock und Mütze (langsam, schlendert um den Brunnen) |
| `chicken_idle_4f.png`, `chicken_walk_4f.png` | 16×16 | Weißes Huhn mit rotem Kamm; idle = pickt am Boden (heute einfacher Platzhalter) |
| `cat_idle_4f.png`, `cat_walk_6f.png` | 16×16 | Getigerte Katze; idle = sitzt und schlägt mit dem Schwanz (**heute ohne Platzhalter**, erscheint erst mit der Datei) |

## 3. Dorf-UI (`art/ui/`, aus SPRITES_V3 §4 noch offen)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `sign_home.png` | 24×16 | Holzschild über der Tür des Zuhauses, passend zu `sign_forge.png` & Co.: kleines Haus oder Kleiderbügel als Symbol, keine Schrift |

## 4. Dungeon-Türen je Biom und Raumtyp (`art/environment/doors/`)

Heute gibt es nur eine schlichte Holztür (`art/environment/props/door_closed.png`, 32×32, Öffnen als `door_open_4f.png`). Türen sitzen mittig in der oberen bzw. unteren Raumwand, ein Tile breit; der Spieler sieht sie von vorn. Jede Tür besteht aus einem **Rahmen** (bleibt stehen, darf breiter sein als die Tür) und dem **Türblatt**, das sich öffnet. Die Öffnen-Animation endet mit einem freien, dunklen Durchgang.

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `door_frame_crypt.png` | 48×48 | Steinerner Rundbogen mit Schlussstein, Risse, ein Totenschädel-Relief oben, Spinnweben in einer Ecke |
| `door_crypt_open_4f.png` | 32×32, 4 F. | Eisenbeschlagene Holztür, die nach oben/innen aufschwingt (Frame 1 = geschlossen, Frame 4 = offen) |
| `door_frame_slime_grotto.png` | 48×48 | Höhlenöffnung aus grünlichem Fels, Moos und tropfender Schleim am Rand, kleine Kristalle |
| `door_slime_grotto_open_4f.png` | 32×32, 4 F. | Vorhang aus Ranken/Schleimfäden, der sich zur Seite zieht |
| `door_frame_shadow_realm.png` | 48×48 | Dunkler Obsidianbogen mit violett glimmenden Runen |
| `door_shadow_realm_open_4f.png` | 32×32, 4 F. | Runensiegel/Schattenschleier, der sich auflöst (Runen erlöschen von außen nach innen) |
| `door_frame_ember_forge.png` | 48×48 | Schwerer Eisenrahmen mit Nieten, Glut in Fugen, Schlacke am Boden |
| `door_ember_forge_open_4f.png` | 32×32, 4 F. | Metallgitter (Fallgatter), das nach oben fährt, Funken |
| `door_frame_boss.png` | 64×56 | Großes Tor zum Bossraum: zwei Säulen mit Fackelhaltern, Schädelkrone über dem Bogen, Ketten (biomneutral, wird je Biom eingefärbt) |
| `door_boss_open_4f.png` | 32×32, 4 F. | Doppelflügeltür mit Ketten, die zerspringen und aufschwingen |
| `door_special_symbols.png` | 16×16 je Symbol, **7×1 (112×16)** | Kleine Schilder über Spezialraum-Türen: Münze (Shop), Schwert (Waffe), Tropfen (Brunnen), Stern (Upgrade), Sanduhr (Prüfung), Flamme (Lagerfeuer), **neu als 7. Spalte: Schädel (Miniboss)**. Die gelieferte 6er-Fassung funktioniert weiter; mit 7 Spalten übernimmt der Code den Schädel automatisch. |

## 5. Lagerfeuer-Raum (`art/environment/campfire/`, ROADMAP_AUSBAU A6, D-103)

Ruhiger Zwischenraum nach jedem Boss, an dem das alte Biom ins neue übergeht. Warmes Licht im Dunkel, kein Kampf.

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `campfire_6f.png` | 32×32, 6 F. | Lagerfeuer aus Holzscheiten in einem Steinkreis, flackernde Flammen, kleine Funken |
| `log_seat.png` | 32×16 | Baumstamm zum Sitzen |
| `bedroll.png` | 32×16 | Zusammengerollte Schlafmatte mit Riemen |
| `pack.png` | 16×16 | Rucksack/Proviantbündel |
| `transition_overlay_slime_grotto.png` | 32×32 je Tile, 4×1 (128×32) | Halbtransparente Boden-Überlagerungen, die Krypta-Boden „grottiger“ machen: Moosflecken, Schleimpfützen, Pilze (für den Übergang Krypta → Schleimgrotte) |
| `transition_overlay_shadow_realm.png` | 32×32 je Tile, 4×1 | Schattenrisse, violette Glimmspuren, verdorrtes Moos (Schleimgrotte → Schattenreich) |
| `transition_overlay_ember_forge.png` | 32×32 je Tile, 4×1 | Glutrisse, Ascheflecken, verkohlte Stellen (Schattenreich → Glutkammer) |
| `transition_overlay_crypt.png` | 32×32 je Tile, 4×1 | Knochenreste, Staub, alte Steinplatten (Glutkammer → Krypta, ab Zyklus 5) |

## Wo der Code die Dateien abholt

- Deko: `VillageArt.get_texture("<name>")` in `world/village/village_art.gd` lädt `art/environment/village/<name>.png`.
- Figuren: `VillageArt.get_character_frames("<name>")` lädt `<name>_idle_<n>f.png` und `<name>_walk_<n>f.png` aus `art/characters/npcs/` (4 bzw. 8 Bilder/s).
- Schild: `VillageBuildings.get_sign_texture(&"home")` lädt `art/ui/sign_home.png`.
- Türen und Lagerfeuer: werden von den Paketen D1 (Türen) und A6 (Lagerfeuer) nach diesen Dateinamen geladen; bis dahin Platzhalter aus vorhandenen Grafiken.
