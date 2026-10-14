# Grafik-Briefing V7 (A4) – Abgrund und Brücken, Nachträge

> **Stand:** 14.10.2026 · Paket A4 (ROADMAP_AUSBAU). Die Grundgrafiken sind geliefert (SPRITES_V3, SPRITES_V5 §5): `abyss_tiles_<biom>.png`, `bridge_tiles.png`, `abyss_mist_4f.png`, `player_fall_4f.png`, `crumbling_floor_6f.png`. Hier stehen nur Nachträge. Bis zur Lieferung läuft das Spiel ohne sie (siehe „Bis dahin“).

## Stil und Format (wie bisher)

Pixel-Art 32 px je Tile, im Spiel mit Faktor 2 gezeichnet, Umriss `#1c1a2b`, Animationen als horizontaler Streifen ohne Abstand, Dateiname mit Frame-Anzahl. PNG mit Transparenz.

## 1. Spieler fällt – Kleidungsfarbe (`art/characters/player/`)

| Datei | Größe | Beschreibung | Bis dahin |
| --- | --- | --- | --- |
| `player_tint_mask_fall_4f.png` | 32×32, 4 F. (128×32) | Tint-Maske zu `player_fall_4f.png` wie die anderen `player_tint_mask_*`: weiß, wo die Kleidung ist, sonst transparent; Frame für Frame deckungsgleich mit dem Fall | Der Fall wird in der Grundfarbe gezeigt (ohne gewählte Kleidungsfarbe, 0,5 s) |

Der Fall wird heute als eigenes Sprite gezeichnet (`PlayerFall`); mit der Maske kann er in die `SpriteFrames` des Charakters wandern und die Kleidungsfarbe übernehmen.

## 2. Abgrund – Abbruchkante nach Süden (optional, `art/environment/tiles/`)

| Datei | Größe | Beschreibung | Bis dahin |
| --- | --- | --- | --- |
| `abyss_cliff_<biom>.png` | 32×32 je Tile, 4×1 (128×32) | Sichtbare Felswand unter der Nordkante eines Abgrunds (Boden liegt nördlich): links, Mitte, rechts, einzeln (1 Tile breit). Die Kante der Bodenplatte oben, darunter 10–14 px Fels, der nach unten ins Schwarz ausläuft; passend zu den Biom-Kanten (Krypta Stein, Grotte Moos, Schattenreich Kristall, Glutkammer glühend) | Die Nordkante zeigt nur die Randlinie aus `abyss_tiles_<biom>.png` |

Ablage nach Namen; der Code (`AbyssAutotile`) kann sie danach als zusätzliche Lage über den Abgrund-Teilen zeichnen (eigener kleiner Folgeauftrag).
