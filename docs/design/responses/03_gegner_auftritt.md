# Gegner-Auftritt (Quellen)

Quellen sind feste Teile des Grundrisses, meist am Rand und hinter dem Spieler. Immer 1 s Warnung mit Licht und Ton, dann Erscheinen, dann Angriff. Sprites in `art/environment/spawn/` (spawn.json: fps, Pivot).

## Grab (Krypta) · `spawn_grave_6f`

Grabstein wackelt + grünes Glimmen (1 s) → Erde bricht, Hand greift heraus (0,3 s) → Skelett richtet sich auf (0,4 s) → steht, greift an. Ton: Erde knirscht, Knochen klappern.

## Sarkophag (Elite/Boss) · `spawn_sarcophagus_4f`

Deckel knirscht, grüner Spalt (1 s) → Deckel gleitet (0,5 s) → Gestalt richtet sich auf → Champion tritt vor.

## Pfütze (Grotte) · `spawn_puddle_6f`

Pfütze blubbert heller (1 s) → Blase wölbt sich → Schleim springt 1 Kachel weit heraus (Landung = Hüpfton) → Pfütze beruhigt sich.

## Bodenriss (Schattenreich) · `spawn_rift_6f`

Riss leuchtet violett auf (1 s) → Riss weitet sich, Silhouette zieht sich hoch (0,5 s) → Augen leuchten, Körper wird fest → Riss glimmt leise weiter.

## Lavaspalte (Glutkammer) · `spawn_vent_6f`

Glut glüht auf, Funken (1 s) → Gegner steigt als dunkle Form aus der Glut (0,5 s) → kühlt ab (Rauch) → Spalte glimmt.

## Wandtor (Arena, alle Biome) · `enemy_gate_4f`

Gitter rasselt, Licht hinter dem Gitter (1 s) → Gitter hebt sich (0,5 s) → Gegner tritt heraus → Gitter fällt.
