# Antwort 20 – Wick statt Flint, Erklären ohne Rahmen, zwei Jump'n'Run-Stile

Stand 16.10.2026. Ersetzt Antwort 19 in den Punkten Begleiter und Erklär-Ecke.

## 1. Wick ist der Begleiter (kein Flint)

Die Figur der Website (`WickFigure`, 32×32-Frame, Kerze 10 px breit, 14 Reihen Wachs, Flamme oben, Füße bei (16,30)) ist das Referenzbild. Die Spiel-Sprites übernehmen genau diese Konstruktion, damit Website und Spiel dieselbe Figur zeigen:

- `art/companions/wick/wick_<anim>_<n>f.png` – idle 6 (8 fps, passt zum Website-Streifen), blink 2, move 6, point 4, talk 4, joy 4, scared 4, sad 4, sleep 4, cast 4. `wick.json` mit Ankern `flame` (16,7), `head`, `eyes`.
- Größe im Spiel: gleicher Maßstab wie alles (×2). Wick ist damit ≈ 23 px hoch inklusive Flamme, die Spielfigur 26 px: minimal kleiner, wie gewünscht. Kein Rahmen, kein Porträt.
- Kein eingemalter Lichtschein: Flamme als Light2D (warm, Radius 2,5 Kacheln) am Anker `flame`. Auf der Website bleibt der Glow als CSS.
- Website: `wick_idle_6f.png` → `public/brand/wick/wick_idle_6f.webp` (lossless) ersetzt den Platzhalter ohne Layout-Änderung (gleicher 32er-Frame, gleiche 6 Frames bei 8 fps).
- Die Flint-Dateien (`art/companions/flint/`) bleiben liegen, werden nicht gebraucht.

## 2. Erklären direkt im Spiel (ohne Rahmen)

Siehe `20_wick_erklaert_ingame.png`. Wick läuft zur Stelle (`move`), stellt sich neben das Objekt, zeigt (`point`), darüber steht eine Sprechblase (`wick_bubble` 9-Slice, Text 8 px Pixelify), über dem Objekt wippt ein gelber Pfeil (`wick_marker_4f`). Keine Ecke, kein Porträtrahmen, keine Abdunkelung: Die Welt bleibt spielbar, der Hinweis verschwindet mit E oder nach 6 s.

Regeln:
- Wick zeigt immer auf etwas Sichtbares im Bild; ist das Ziel außerhalb, läuft er bis zum Bildrand und zeigt in die Richtung.
- Maximal zwei Blasen hintereinander, dann Pause von mindestens einem Raum.
- Beim ersten Kontakt mit einem Objekt (Brunnen, Podest, Altar, Tür-Symbol, Quelle) genau einmal; danach nur noch auf Nachfrage (Wick anklicken/antippen).
- Im Kampf schweigt Wick (`scared` bei < 1 Herz, `joy` nach dem Raum).
- Für die Übersicht (Hauptmenü, Was kommt) darf Wick größer gezeigt werden (×3/×4 des 32er-Frames, nearest), weiterhin ohne Rahmen.

## 3. Zuhause und Plattformen

- Zuhause (Nacht, cozy): Raum von 15×11 auf **11×9** Kacheln verkleinern, Kamera-Zoom 3,5 wie vorgeschlagen; Bett, Truhe, Kamin und Spiegel rücken zusammen. Mockup 18b wird entsprechend neu gerendert (siehe Teil B6).
- Plattformen (halbe Höhe, Treppen, Ebenen) bleiben wie in Antwort 18.

## 4. Jump'n'Run-Stücke: zwei Stile (Hinweis an die Code-Session)

Die Seitenansicht zwischen den Räumen bekommt **zwei klar getrennte Stile**. Beide nutzen dieselben Sprites (Plattformen, Parallax, Becken, Stacheln, Türme, player_jump/land/climb), unterscheiden sich aber in Bau und Tempo:

### 4a. „Kletterstück“ (Präzision)
- 40–60 Kacheln lang, Höhe bis 2 Bildschirme (Kamera folgt vertikal).
- Schwierige Sprünge: Lücken 3–4 Kacheln, bewegliche Plattformen (`platform_moving_4f`, offen), Stachelwellen (`spikes_side_3f` im Takt), hängende Kristalle/Wurzeln als Hindernis, Leitern, kleine Pendelklingen.
- Kein Zeitdruck, Fallen kostet ½ Herz und setzt an den letzten Kontrollpunkt (`checkpoint_torch_4f`, offen).
- Belohnung: goldene Münze an der schwersten Stelle, Truhe am Ende.

### 4b. „Sturmlauf“ (Tempo, Sonic-artig)
- 80–120 Kacheln lang, flach bis leicht abfallend, Kamera scrollt **automatisch** mit Grundtempo; Stehenbleiben ist nicht möglich (Bildrand schiebt).
- Der Spieler rennt, springt über Lücken und **mäht Gegner im Lauf nieder** (Angriff ohne Stopp, Schwung bleibt). Rampen (`ramp_<biom>.png`, offen) geben Sprungweite, Beschleunigungsplatten (`boost_pad_4f`, offen) Tempo.
- Gegner stehen in Reihen (Schleime, Skelette) und auf Vorsprüngen (Türme), Treffer ohne Verlangsamung, verfehlte Gegner kosten nichts außer Punkten.
- Ziel: die Tür vor dem Bildrand erreichen; Zeit und Kill-Serie ergeben Bonusgold (Kombo-Zähler im HUD, `combo_digits.png`, offen).
- Dash wird zum Sprint-Boost (Richtung vorwärts), Doppelsprung (SPRITES_V9 §6, offen) wird hier wichtig.

Zuordnung im Ablauf: Kletterstück nach dem Lagerfeuer (Biomwechsel = „Abstieg“), Sturmlauf als Abzweigung mit Leiter-Symbol **und** zufällig (10 %) nach einem Ruhe-Raum. Beide nie vor einem Boss, nie zweimal hintereinander.

Sprites für die beiden Stile liegen in Teil D (Seitenansicht R2) und ergänzen SPRITES_V9 §6: `platform_moving_4f` (64×16), `checkpoint_torch_4f` (16×40), `ramp_<biom>` (64×32), `boost_pad_4f` (32×16), `combo_digits` (10×48×64), `speed_lines_4f` (64×32, Overlay beim Sprint), `enemy_pop_4f` (32×32, Gegner zerplatzt im Lauf).

## 5. Was sich im Plan ändert

| Teil | vorher | jetzt |
| --- | --- | --- |
| B1 Begleiter | Flint (eigene Figur, 16×16) | Wick wie Website, 32×32, Füße (16,30) – geliefert |
| B2 Erklärer | Ecke mit Porträtrahmen | im Spiel, ohne Rahmen: `wick_bubble`, `wick_marker_4f`, Animationen point/talk – geliefert |
| B6 Zuhause | 15×11 | 11×9, Zoom 3,5 |
| D Seitenansicht R2 | ein Stil | zwei Stile (Kletterstück, Sturmlauf) mit den Zusatz-Sprites oben |

Dateien dieser Antwort: `art/companions/wick/*`, `20_wick_erklaert_ingame.png` (+2x), `20_wick_massstab.png`.
