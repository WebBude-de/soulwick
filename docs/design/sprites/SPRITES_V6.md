# Grafik-Briefing V6 – Soulwick: einheitliche Innenmauern

> **Status 15.10.2026: abgelöst.** Nicht mehr einzeln liefern: Das Wand-System kam mit der Design-Antwort ([04_wandsystem.md](../responses/04_wandsystem.md), `wall_autotile_<biom>`, D-131) und für Höhlenräume das Fels-Terrain (`rock_blob_<biom>`, D-142). Übersicht aller Briefings: [README.md](README.md).
>
> **Für Claude Design.** Eigenständig lesbar. Ergänzt [SPRITES_V5.md](SPRITES_V5.md). Anlass: Im Playtest wirken Innenmauern mal flach (nur Oberseite), mal halb-3D (mit Vorderseite), mal mit, mal ohne Kante. Das gelieferte Set `inner_wall_tiles*.png` (8 Teile) reicht für Ecken, dicke Blöcke und Seitenkanten nicht.
> **Ablage:** `art/environment/tiles/`, Dateinamen exakt übernehmen. Bis dahin erzeugt der Code die Kanten aus der vorhandenen Krone.
> **Stand:** 14.10.2026

## Regel (gilt für alle Mauern, außen wie innen)

Jede Mauer sieht aus wie die Außenwand des Raums, in 3/4-Ansicht:

1. **Krone** (Oberseite, dunkler Bruchstein wie die Außenwand-Krone) auf jedem Mauer-Tile.
2. **Helle Kante 1 px** an jeder Seite der Krone, an die Boden grenzt (Norden, Osten, Westen und Süden), dunkle Kontur `#1c1a2b` außen. Grenzt Mauer an Mauer, keine Kante.
3. **Vorderseite** (Ziegel, wie die Außenwand-Front) genau **eine Tile-Reihe hoch** unter jeder Krone, deren Süden Boden ist. Die Vorderseite gehört zur Mauer (nicht begehbar).
4. Säulen sind kleine Mauern: 1 Tile Krone + 1 Tile Vorderseite.

## Dateien (je Biom: `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`)

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `wall_autotile_<biom>.png` | 32×32 je Tile, Raster 4×5 (128×160) | **Zeilen 1–4:** 16 Kronen-Varianten nach Nachbarn (N, O, S, W = Mauer ja/nein), Reihenfolge als 4-Bit-Maske N=1, O=2, S=4, W=8, also Tile 0 = freistehend (Kante ringsum) bis Tile 15 = ganz umschlossen (keine Kante). **Zeile 5:** Vorderseite links, Mitte, rechts, einzeln (1 Tile breit). |
| `wall_inner_corner_<biom>.png` | 32×32 je Tile, 4×1 (128×32) | Innenecken der Krone (Kante nur als Eckpixel), für dicke Blöcke: oben-links, oben-rechts, unten-links, unten-rechts |

Formatregeln wie bisher: Pixel-Art, keine Kantenglättung, Palette der Biom-Tilesets (`docs/HANDOUT.md`), Krone und Vorderseite farblich exakt wie die Außenwand des Bioms, damit Innen- und Außenmauern nahtlos zusammenpassen.
