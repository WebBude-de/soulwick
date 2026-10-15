# Grafik-Briefing V9 – Soulwick: Makeover-Welle A, offene Teile

> **Für Claude Design.** Diese Teile sind im Spiel heute **Platzhalter aus Code**. Sie laufen schon, sehen aber noch nicht sauber aus. Liefert ihr eine Datei mit genau diesem Namen, baut der Code sie automatisch ein.
> **Stand:** 15.10.2026 · Stil wie bisher: Pixel-Art, 32-px-Kacheln, Kontur `#1c1a2b`, weiche Palette aus `crypt_soft` (andere Biome per Palettentausch). Animationen als Streifen mit Frame-Anzahl im Namen. Zu jeder Datei ein JSON mit fps und Pivot, wie bei den gelieferten Teilen.
> **Leitlinie des Projektmitglieds:** „Das Game muss clean sein.“ Keine sichtbaren Rechteckkanten, keine Stummel, keine harten Schatten. Jedes Teil schließt nahtlos an die Nachbarkacheln an.
> `<biom>` = `crypt`, `slime_grotto`, `shadow_realm`, `ember_forge`. `_soft` = weiche Palette.

## 1. Fels-Terrain: Innenecken und Füllungen (M1)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/tiles/rock_blob_<biom>_soft.png`, **Ergänzung** | 32×32 je Kachel, 8×7-Raster wie bisher | Die Masken mit fehlender oberer Diagonale (NE oder NW frei, N und E bzw. W fest), z. B. r87, r93, r213, r215, r221, r223, r241, r245, r247, r253. In der jeweiligen oberen Ecke läuft das Randband (2 px hell, 2 px mittel, wie an geraden Kanten) als Bogen um den Eckpunkt, Innenradius ca. 4 px. Heute zeichnet der Code diesen Viertelbogen nach. |
| Dieselben Sheets, **Slots 51–53** (Zeile 6, Spalten 3–5) | je 32×32 | Füllkacheln: transparent bis auf ein Felsstück in der unteren Ecke, Varianten links, rechts, beide. Rundung mit Radius 5 px, Bandfarben wie die Kante. Sie liegen auf der Bodenkachel unter einer Innenecke. |
| `art/environment/tiles/front_step_{left,right}_<biom>_soft.png` *(optional)* | 32×32 | Wie `front_left`/`front_right`, aber die Lippe oben biegt an einer Stufe nach unten um. |

## 2. Tore und Tunnel (M2)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/doors/cave_mouth_<biom>_soft.png`, **nur Bogen** | 64×48 | Nur der Bogenrand (≈ 5 px). Öffnung und Umfeld sind durchsichtig. Die Krone mit Lichtkante läuft oben **durch**, es gibt keinen Aufsatz über der Krone. Dann muss der Code die Grafik nicht mehr zuschneiden. |
| `art/environment/doors/door_frame_<biom>_soft.png`, **runde Öffnung** | 64×56 | Gemauerter Torbogen. Die Öffnung ist oben rund statt gerade, ohne Spinnennetz in der Öffnung, und die Krone läuft durch. |
| `art/environment/doors/tunnel_shade_{cave,arch}.png` *(optional)* | so groß wie der Rahmen | Innenschatten des Bogens als weicher Verlauf (≈ 18 px), in Form der Öffnung. Heute entsteht er aus der Öffnungsmaske. |
| `art/environment/doors/side_mouth_<biom>[_soft].png` | 20×32, 1 Frame, Pivot (0,0), für die Ostwand gezeichnet (der Code spiegelt für West) | Seitlicher Durchgang in einer durchlaufenden Wand, von außen nach innen: 7 px Schatten auf dem Boden, 5 px dunkler Schlitz über der Lichtkante, 8 px Übergang in den Fels. Oben und unten läuft er weich aus und schließt nahtlos an die Seiten-Lichtkante der Fels-Teile an. |
| `art/environment/doors/door_side_<biom>_bars_4f.png` | 4 × 32×32 | Fallgitter quer, von oben gesehen, schmal (≈ 10 px) auf der Lichtkante. Frame 1 zu, Frame 4 ganz weg. Ersetzt das alte Holztür-Blatt an Seitentüren. |

## 3. Wasser und Deko (M1)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/deco/water_glint_4f.png` *(optional)* | 4 × 32×32 | Glitzer-Overlay für Becken und Pfützen. Die Formen bleiben prozedural ohne Raster, Wasserfarbe je Biom: Krypta kühl-blau, Grotte grünlich, Glutkammer dunkel mit warmem Glanz, Schattenreich violett. |
| `art/environment/deco/deco_group_<biom>_{1..3}.png` | 64×48 | Fertige Deko-Gruppe je Biom als ein Bild (Schrein, Beinhaus, Geröll, Pilzbeet, Kristalle, Schmiede, Lager). Heute baut der Code sie aus Einzelteilen zusammen. Steht schon in SPRITES_V8 und ist weiter offen. |
| `art/environment/deco/deco_group_large_<biom>_{1,2}.png` | 96×64 | Größere Gruppe für Ecken und Buchten. |
| `art/environment/deco/fog_floor_4f.png` | 4 × 64×32 | Bodennebel-Fetzen. Heute dient `abyss_mist` schwach als Ersatz. |
| `art/environment/tiles/wall_cracked_<biom>_soft.png` | 32×48 | Rissige Felsfront für Geheimnischen in Höhlenräumen. Heute steht dort eine Ziegelfront. |
| `art/environment/tiles/wall_niche_soft.png` | 32×48 | Felsnische statt Ziegelnische. |
| `art/environment/tiles/abyss_tiles_<biom>_soft.png` | wie `abyss_tiles_crypt_soft` | Abgrund-Set für Grotte, Schattenreich, Glutkammer in der weichen Palette. |
| `art/environment/rooms/wall_breach_cave_<biom>_6f.png` | wie `wall_breach_6f` | Wanddurchbruch einer Gegnerquelle in Höhlenräumen. Heute steht dort ein gemauerter Rahmen, der im Fels fremd wirkt. |

## 4. Seitenansicht (M5)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/deco/platform_edge_<biom>.png` | 96×16 | Oberkante der Plattformen, links/Mitte/rechts je 32×16: Gras, Moos, Glut bzw. Violett. |
| `art/environment/side/bg_<biom>_parallax.png` | 480×270 | Hintergrund, läuft mit halber Geschwindigkeit. |
| `art/environment/side/spikes_side_3f.png` | 3 × 32×16 | Stachelfalle: eingefahren, Warnung, ausgefahren. |
| `art/environment/props/golden_coin_4f.png` | 4 × 16×16 | Goldene Münze an der schwersten Stelle. |
| Leiter-Symbol | 16×16 | 11. Symbol in `door_mode_symbols` bzw. `door_branch_symbols` („ladder“) für den Leiter-Weg einer Abzweigung. |
| `art/characters/player/player_climb_4f.png` und `player_tint_mask_climb_4f.png` | je 4 × 32×32 | Klettern an der Leiter. Heute klettert die Figur mit den Laufbildern. |
| `art/characters/player/player_tint_mask_land_2f.png` | 2 × 32×32 | Kleidungsmaske für die Landung. |

## 5. Figuren

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/characters/npcs/lost_villager_{idle_4f,walk_6f,scared_4f}.png`, **Nachlieferung** | Frames 32×32 | Den Laternenschein **nicht** einmalen: Er war am Framerand abgeschnitten und wurde am 15.10.2026 aus den Dateien entfernt. Den Schein erzeugt das Licht-System. Gern die Laterne etwas weiter vom Rand weg (Laternen-Anker heute bei 22,20). |
