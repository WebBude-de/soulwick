# Grafik-Briefing V9 – Soulwick: Makeover-Welle A, offene Teile

> **Seit 22.10.2026 (D-193):** Die noch offenen Teile dieses Briefings stehen gesammelt in [SPRITES_V13.md](../SPRITES_V13.md) Teil D; hier gelten nur noch die Namensregeln und Maße des Gelieferten.
> **Für Claude Design.** Diese Teile sind im Spiel heute **Platzhalter aus Code**. Sie laufen schon, sehen aber noch nicht sauber aus. Liefert ihr eine Datei mit genau diesem Namen, baut der Code sie automatisch ein.
> **Stand:** 15.10.2026 (Abschnitte 1–5 geliefert, siehe `design/responses/SPRITES_V9_lieferung.md`; **offen: Nachlieferung Abschnitt 1 und Abschnitt 6**) · Stil wie bisher: Pixel-Art, 32-px-Kacheln, Kontur `#1c1a2b`, weiche Palette aus `crypt_soft` (andere Biome per Palettentausch). Animationen als Streifen mit Frame-Anzahl im Namen. Zu jeder Datei ein JSON mit fps und Pivot, wie bei den gelieferten Teilen.
> **Leitlinie des Projektmitglieds:** „Das Game muss clean sein.“ Keine sichtbaren Rechteckkanten, keine Stummel, keine harten Schatten. Jedes Teil schließt nahtlos an die Nachbarkacheln an.
> `<biom>` = `crypt`, `slime_grotto`, `shadow_realm`, `ember_forge`. `_soft` = weiche Palette.

## 1. Fels-Terrain: Innenecken und Füllungen (M1)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/tiles/rock_blob_<biom>_soft.png`, **Ergänzung** | 32×32 je Kachel, 8×7-Raster wie bisher | Die Masken mit fehlender oberer Diagonale (NE oder NW frei, N und E bzw. W fest), z. B. r87, r93, r213, r215, r221, r223, r241, r245, r247, r253. In der jeweiligen oberen Ecke läuft das Randband (2 px hell, 2 px mittel, wie an geraden Kanten) als Bogen um den Eckpunkt, Innenradius ca. 4 px. Heute zeichnet der Code diesen Viertelbogen nach. |
| Dieselben Sheets, **Slots 51–53** (Zeile 6, Spalten 3–5) | je 32×32 | Füllkacheln: transparent bis auf ein Felsstück in der unteren Ecke, Varianten links, rechts, beide. Rundung mit Radius 5 px, Bandfarben wie die Kante. Sie liegen auf der Bodenkachel unter einer Innenecke. |
| `art/environment/tiles/front_step_{left,right}_<biom>_soft.png` *(optional)* | 32×32 | Wie `front_left`/`front_right`, aber die Lippe oben biegt an einer Stufe nach unten um. |

**Nachlieferung §1 (offen, Stand 15.10.2026):** Das gelieferte Set `rock_blob_<biom>_soft_inner.png` ist eingebaut, aber abgeschaltet (`RockTerrain.USE_DELIVERED_INNER = false`), weil es im Raum nicht sauber anschließt: Die Bögen liegen 4–8 px neben dem Eckpunkt statt die geraden Randbänder fortzusetzen (heller Fleck in der Ecke), und `fill_left/right/both` sind eine nach außen gewölbte Felsbeule statt einer nach innen gerundeten Füllung. Gewünscht: Bogen genau dort, wo das obere und das seitliche Band der Nachbarkacheln enden (Band 2 px hell + 2 px mittel, Innenradius 4 px), Füllkacheln als Hohlkehle (konkav, Radius 5 px) in den Farben von `rock_blob_<biom>_soft.png`. Bis dahin zeichnet der Code Bögen und Füllungen selbst; nach der Lieferung den Schalter auf `true` setzen.

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

## 6. Seitenansicht Runde 2: Doppelsprung, Wandrutschen, Staub (offen)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/characters/player/player_double_jump_4f.png` und `player_tint_mask_double_jump_4f.png` | 4 × 32×32, Pivot (16,30), 14 fps, keine Schleife | Figur zusammengerollt (Knie an der Brust, Arme um die Beine), Haare und Kleidung flattern leicht. **Keine Drehung einmalen**, den Salto dreht der Code. Maske: weiß = Kleidung, deckungsgleich. |
| `art/characters/player/player_wall_slide_2f.png` und `player_tint_mask_wall_slide_2f.png` | 2 × 32×32, Pivot (16,30), 6 fps, Schleife | Figur seitlich mit Blick nach rechts, Rücken, eine Hand und ein Fuß an einer Wand am linken Bildrand (Wand bei x ≈ 4); Bild 2 einen Pixel tiefer. |
| `art/effects/side_jump_puff_4f.png` | 4 × 32×16, Pivot (16,16) | Zwei kleine Wölkchen weichen seitlich vom Fuß weg. Helles Grauviolett, transparent, biomneutral (gilt für alle Staub-Teile). |
| `art/effects/side_land_dust_5f.png` | 5 × 48×16, Pivot (24,16) | Breite Wolke nach links und rechts, löst sich auf (der Code skaliert 0,8–1,4× nach Landehärte). |
| `art/effects/side_double_jump_ring_5f.png` | 5 × 32×16, Pivot (16,8) | Flacher Ring (Ellipse), dehnt sich aus und verblasst. |
| `art/effects/side_wall_dust_3f.png` | 3 × 16×16, Pivot (8,8) | Zwei, drei Krümel fallen von der Wand nach unten. |

Hinweis zu `side_props.json` der Lieferung: Die goldene Münze gibt **keinen** Seelenkristall, sondern Gold wie zwei Münzen (Balance, D-144).

## 7. Höhe: Plateaus, Treppen, Leitern (M3, optional)

Plateaus, Klippen, Treppen und Leitern laufen heute schon mit den gelieferten Teilen (`rock_blob_<biom>_soft` für Krone und Klippe, `stairs_cut.png`, `ladder.png`, `ladder_top.png`); die Plateau-Fläche ist der Plattenboden der Bodenzonen mit Felsrand, die Treppe wird per Palette auf das Biom umgefärbt (in der Glutkammer wirken die Stufenkanten dadurch orange). Eigene Dateien mit diesen Namen übernimmt der Code automatisch (`PlateauArt`).

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/deco/stairs_cut_<biom>_soft.png` | 32×32, 1 Frame, Pivot (0,0) | Treppe in die Klippe geschlagen wie `stairs_cut.png`, 4 Stufen von oben nach unten, in der weichen Felspalette des Bioms (Grotte, Schattenreich, Glutkammer; Krypta = `stairs_cut.png`). Seitenränder laufen in die Klippen-Vorderseite (`front_*`) daneben über. |
| `art/environment/deco/plateau_floor_<biom>.png` | 32×32, nahtlos kachelbar | Begehbare Plateau-Fläche: Steinplatten etwas heller als der Boden darunter, sehr feine Fugen, ohne Rand (den Felsrand zeichnet der Code). |
| `art/characters/player/player_climb_top_4f.png` und `player_tint_mask_climb_top_4f.png` *(später)* | 4 × 32×32, Pivot (16,30) | Klettern an einer Leiter in der Draufsicht (Rücken zur Kamera, Arme abwechselnd oben). Heute läuft die Figur langsam mit den Laufbildern über die Leiter; der Anschluss im Spieler fehlt noch. |
