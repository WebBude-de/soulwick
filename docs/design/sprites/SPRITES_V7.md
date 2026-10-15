# Grafik-Briefing V7 – Soulwick: Seitentüren und Abgrund-Nachträge

> **Für Claude Design.** Eigenständig lesbar. Ergänzt [SPRITES_V4.md](SPRITES_V4.md) §4 (Türen), [SPRITES_V5.md](SPRITES_V5.md) §5–§6 (Abgrund, Wegführung) und [SPRITES_V6.md](SPRITES_V6.md) (Mauer-Autotile, noch offen). **Dateinamen exakt übernehmen**, dann baut der Code sie automatisch ein; bis dahin zeigt das Spiel Platzhalter.
> **Stand:** 14.10.2026 (Pakete A4 und A10 aus [ROADMAP_AUSBAU.md](../../ROADMAP_AUSBAU.md))

## Spiel in einem Satz

2D-Top-down-Dungeon-Roguelite in Pixel-Art mit leichter Schrägsicht (3/4): ein endloser, dunkler Dungeon mit vier Biomen (Krypta, Schleimgrotte, Schattenreich, Glutkammer). Ausgänge liegen oben, links und rechts; manche Räume haben Abgründe mit Brücken.

## Stil und Format (wie bisher)

- Pixel-Art 32 px je Tile, im Spiel doppelt so groß gezeichnet, Palette aus `docs/HANDOUT.md`, Kontur 1 px `#1c1a2b`.
- PNG mit Transparenz, kein Anti-Aliasing, Animationen als horizontaler Streifen ohne Abstand, Frame-Anzahl im Namen.
- Je Biom vier Varianten mit Suffix `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`.

## 1. Türblatt in der Seitenwand (A10) (`art/environment/doors/`)

Eine Tür in der **West- oder Ostwand** sitzt in einem waagerechten Gang, 1 Kachel hoch. Man sieht sie von oben: kein Torbogen wie an der Nordwand, sondern ein schmales Türblatt quer im Gang. Über dem Gang liegt eine Reihe Mauer-Vorderseite (dort hängt schon die vorhandene Fackel), darunter die Mauerkrone.

| Datei | Größe | Frames | Beschreibung |
| --- | --- | --- | --- |
| `door_side_crypt_open_4f.png` | 32×32 je Frame (128×32) | 4 | Holztür mit Eisenbändern, **von oben gesehen**: ein senkrechter Balken (ca. 10–14 px breit, volle 32 px hoch) mittig in der Kachel, Bretterkanten und Beschläge oben sichtbar. Frame 1 geschlossen, Frames 2–4 schwingt die Tür zur Wand hin auf (Balken wird schmaler/kürzer), Frame 4 offen (nur ein schmaler Rest am Rand oder leer). Gezeichnet für eine **Westwand-Tür** (Gang führt nach links), die Ostwand spiegelt das Spiel |
| `door_side_slime_grotto_open_4f.png` | 32×32 je Frame | 4 | Ranken- und Schleimvorhang quer im Gang, öffnet sich zu beiden Seiten (wie das Nordwand-Blatt der Grotte) |
| `door_side_shadow_realm_open_4f.png` | 32×32 je Frame | 4 | Violetter Runenschleier quer im Gang, löst sich auf |
| `door_side_ember_forge_open_4f.png` | 32×32 je Frame | 4 | Fallgitter quer im Gang, von oben gesehen (Gitterstäbe als Punktreihe), fährt in die Wand |

Hinweise:

- Der Gang ist **transparent** zu lassen (dahinter zeichnet das Spiel den Boden).
- Die Tür steht auf der Wandkachel direkt am Raum; ihre Kollision ist die ganze Kachel, die Grafik darf also die volle Kachel nutzen.
- Kein Rahmen, keine Fackeln: Die Fackel über dem Gang und das Abzweigungs-Symbol (`door_branch_symbols.png`, geliefert) setzt der Code selbst.
- Optional `doors.json` um die vier Einträge ergänzen (Name, Datei, `frame_size` 32×32, 4 Frames, fps 8, Pivot 0/0).

## 2. Spieler fällt – Kleidungsfarbe (A4) (`art/characters/player/`)

| Datei | Größe | Beschreibung | Bis dahin |
| --- | --- | --- | --- |
| `player_tint_mask_fall_4f.png` | 32×32, 4 F. (128×32) | Tint-Maske zu `player_fall_4f.png` wie die anderen `player_tint_mask_*`: weiß, wo die Kleidung ist, sonst transparent; Frame für Frame deckungsgleich mit dem Fall | Der Fall wird in der Grundfarbe gezeigt (ohne gewählte Kleidungsfarbe, 0,5 s) |

Der Fall wird heute als eigenes Sprite gezeichnet (`PlayerFall`); mit der Maske kann er in die `SpriteFrames` des Charakters wandern und die Kleidungsfarbe übernehmen.

## 3. Abgrund – Abbruchkante nach Süden (A4, optional, `art/environment/tiles/`)

| Datei | Größe | Beschreibung | Bis dahin |
| --- | --- | --- | --- |
| `abyss_cliff_<biom>.png` | 32×32 je Tile, 4×1 (128×32) | Sichtbare Felswand unter der Nordkante eines Abgrunds (Boden liegt nördlich): links, Mitte, rechts, einzeln (1 Tile breit). Die Kante der Bodenplatte oben, darunter 10–14 px Fels, der nach unten ins Schwarz ausläuft; passend zu den Biom-Kanten (Krypta Stein, Grotte Moos, Schattenreich Kristall, Glutkammer glühend) | Die Nordkante zeigt nur die Randlinie aus `abyss_tiles_<biom>.png` |

Ablage nach Namen; der Code (`AbyssAutotile`) kann sie danach als zusätzliche Lage über den Abgrund-Teilen zeichnen (eigener kleiner Folgeauftrag).

## 4. Bereits geliefert und eingebunden (keine Arbeit)

| Datei | Wo |
| --- | --- |
| `art/environment/rooms/wall_cracked_<biom>.png` | rissige Mauer-Vorderseite vor einer Geheimnische |
| `art/environment/rooms/wall_break_6f.png` | Aufbrechen der Mauer (wird je Biom eingefärbt) |
| `art/environment/rooms/door_branch_symbols.png` | Symbole über den Abzweigungs-Türen (Elite-Nest, sicherer Weg, unbekannt) |
| `art/characters/npcs/wandering_merchant_idle_4f.png` | wandernder Händler in der Geheimnische |
| `art/environment/props/crystal_cluster.png` | Seelenkristalle in der Geheimnische |
