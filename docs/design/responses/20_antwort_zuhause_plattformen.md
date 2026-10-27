# Antwort 20 – Zuhause cozy, halbe Plattformhöhe, Dorf mit Ebenen (22.10.2026)

## 1. Zuhause innen: von Anfang an gemütlich

Das Zuhause ist beim ersten Betreten **fertig eingerichtet** (nicht leer), und der Spieler darf später umstellen und kaufen. Mockup `14b_zuhause_cozy.png` (480×270) zeigt den Startzustand bei Nacht.

**Lichtkonzept (macht die Atmosphäre, nicht die Möbel):**
- Grundhelligkeit 40 %, Farbton leicht blau (`#2d2250` bei 25 %).
- **Kamin** = Hauptlicht: warmer Kegel (`#ff8a3c`, Radius 5 Kacheln, flackert 2–4 %), wirft den Schatten der Stube nach links.
- **Mondlicht** fällt als schräges Rechteck vom Fenster auf den Boden (`#c8beff` bei 12 %), Staubpartikel darin (3–5 langsame Punkte).
- **Kerzen-Altar** mit drei kleinen Lichtern in Pfadfarben (türkis, orange, violett), Radius 1,5 Kacheln.
- **Nachtlicht am Bett** (kleine Lampe, `#ffd166`, Radius 2 Kacheln).
- Flint schläft vor dem Kamin (`flint_sleep`), seine Flamme ist die fünfte Lichtquelle.
- Fenster zeigt Mond + 2–3 Sterne, bei Tag (zurück aus dem Dungeon am Morgen) Hellblau mit Vögeln – `home_window_night.png` / `home_window_day.png`.

**Startmöblierung** (alles aus B6, plus Nachlieferung): Bett mit Decke und Kissen, Nachttisch mit Lampe, Kamin, Sessel davor, runder Teppich, Regal mit Büchern und Krug, Truhe, Pflanze, Spiegel (vorhanden), Kerzen-Altar, Fensterbank mit Blume, Wandbild (kleines gerahmtes Dorfbild), Besen in der Ecke, Körbchen für Flint. Zusätzliche Dateien gegenüber B6: `nightstand.png` (16×24), `armchair.png` (32×32), `bookshelf_full.png` (32×48), `wall_picture.png` (24×16), `broom.png` (8×24), `window_sill_flower.png` (24×12), `home_window_night.png` / `home_window_day.png` (48×40).

**Umstellen:** Möbel haben einen sauberen Fuß (Pivot unten Mitte) und eine Boden-Fläche in Kacheln (im JSON `footprint`), damit der Stellmodus ein Raster zeigt. Kaufbare Möbel kommen beim Händler (Katalog mit Vorschaubild).

## 2. Plattformen: halbe Höhe

Regel für die Raumgenerierung (Dungeon und Dorf):
- Eine begehbare **Plattform/Empore ist 16 px hoch** (eine halbe Kachel), nie 32. Zwei Stufen à 8 px führen hinauf (Treppe = 1 Kachel breit, 2 Stufen).
- Eine Plattform liegt damit immer **unter** der Krone des Raumrahmens (Krone = 32 px): Es sieht nie so aus, als könne man aus dem Raum laufen. Plattformen dürfen die Außenwand nicht berühren; mindestens 1 Kachel Boden dazwischen.
- Grafiken: `platform_front_<biom>.png` (32×16, Vorderseite halb hoch, links/Mitte/rechts/einzeln = 128×16), `platform_top_<biom>.png` (32×32 Bodenplatte mit 2-px-Lichtkante nach Süden), `stairs_half_<biom>.png` (32×16, zwei Stufen). Gegner nutzen Plattformen nicht (sichere Insel für Fernkampf).
- Abgründe bleiben volle Tiefe; Klippen (`abyss_cliff`) sind davon nicht betroffen.

## 3. Dorf dynamischer (später, Richtung)

- Dorf auf **zwei Ebenen**: Marktplatz mit Brunnen oben (Pflaster), Wohnhäuser eine halbe Stufe tiefer, verbunden durch kurze Treppen (`stairs_half`), Mauerkanten mit Lichtkante. Der Dungeon-Eingang liegt am tiefsten Punkt, der Weg führt sichtbar hinab.
- Wege als Kopfstein-Flecken statt gerader Erdstreifen, Beete und Zäune in Gruppen, Laternen als Lichtinseln, Rauch aus Schmiede und Kaminen, Vögel/Hühner/Katze mit Revieren.
- Tageszeit nur als Licht (Zoom, Tint), keine zweiten Tilesets.

Mockup Dorf-Ebenen folgt mit Teil B7 (Schilder) – das aktuelle Dorf ist laut Rückmeldung erst einmal in Ordnung.
