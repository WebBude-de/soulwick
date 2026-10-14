# Grafik-Briefing V5 – Soulwick: neue Räume (Phase 2)

> **Für Claude Design.** Eigenständig lesbar. Ergänzt [SPRITES_V4.md](SPRITES_V4.md) (Dorf, Türen, Lagerfeuer – geliefert). Gehört zu Phase 2 in [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) und zum Raumkonzept [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md).
> **Ablage:** im Spiel-Repo unter `art/` im angegebenen Unterordner. **Dateinamen exakt übernehmen**, dann baut der Code sie automatisch ein; bis dahin zeigt das Spiel Platzhalter. Zu jeder Gruppe gern eine JSON-Datei mit Pivots wie bei den Türen (`doors.json`).
> **Stand:** 14.10.2026

## Spiel in einem Satz

2D-Top-down-Dungeon-Roguelite in Pixel-Art: ein endloser, dunkler Dungeon mit vier Biomen (Krypta, Schleimgrotte, Schattenreich, Glutkammer). Der Spieler sieht nur einen Lichtkreis um sich; Fackeln und Kristalle schneiden zusätzliche Lichtinseln ins Dunkel. Phase 2 bringt viele neue Raumformen, Kampf-Varianten, Prüfungsräume und Geheimnisse.

## Stil und Format (wie bisher)

- Pixel-Art, Top-down mit leichter Schrägsicht (3/4), Palette aus `docs/HANDOUT.md`, Kontur 1 px `#1c1a2b`. Das Spiel zeichnet alles doppelt so groß.
- PNG mit Transparenz, kein Anti-Aliasing. **Durchgänge, Löcher und Öffnungen sind transparent**, nicht schwarz gemalt (das Spiel zeigt dahinter den Boden bzw. die Dunkelheit).
- Pivot = unten Mitte (unterste nicht-transparente Pixelreihe steht auf dem Boden). Figuren schauen nach rechts.
- Animationen als horizontaler Streifen ohne Abstand, Frame-Anzahl im Namen (`soul_flame_6f.png`).
- **Biomneutral** heißt: grau/steinfarben, das Spiel färbt je Biom ein. Wo „je Biom“ steht, bitte vier Varianten mit Suffix `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`.

## 1. Formen und Zutaten normaler Kampfräume (`art/environment/rooms/`, A3)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `chest_closed.png`, `chest_open_4f.png` | 32×32, Öffnen 4 F. | Holztruhe mit Eisenbeschlag; beim Öffnen springt der Deckel auf, goldenes Leuchten. Wird für Katakomben-Sackgassen, Bonus-Truhen und Prüfungen gebraucht |
| `explosive_barrel.png`, `explosive_barrel_fuse_4f.png` | 32×32 | Rotes Fass mit Warnzeichen; Zünd-Animation (Lunte sprüht, Fass bläht sich). Explodiert mit dem vorhandenen Explosions-Effekt |
| `rubble_1.png`, `rubble_2.png` | 32×24 | Schutthaufen als niedrige Deckung, biomneutral |
| `light_crystal_4f.png` | 32×32, 4 F. | Leuchtender Kristall auf Steinsockel (Lichtinsel), sanft pulsierend, biomneutral weiß-türkis (wird eingefärbt) |
| `torch_stand_4f.png` | 16×40, 4 F. | Freistehender Fackelständer (Eisenstab mit Fackel) für Raummitte, Flamme flackert |
| `bone_pile.png`, `coffin.png` | 32×20, 32×40 | Deko für die Katakombe: Knochenhaufen, steinerner Sarg (leicht geöffnet) |
| `cobweb_corner.png` | 32×32 | Spinnwebe für Wand-Ecken (Katakombe, Krypta) |

## 2. Arena mit Wellen (`art/environment/rooms/`, A5)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `wall_breach_6f.png` | 32×48, 6 F. | Gegner bricht aus der Wand: Risse, Steine fliegen, Loch bleibt (transparent) – biomneutral |
| `enemy_gate_4f.png` | 32×32, 4 F. | Kleines Gittertor in der Wand, aus dem Gegner kommen; Gitter fährt hoch |
| `wave_banner_icon.png` | 16×16 | Kleines Symbol „Welle“ (gekreuzte Schwerter mit Totenkopf) für die HUD-Anzeige |

## 3. Kampf-Varianten (`art/environment/variants/`, A7 und A9)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `soul_flame_6f.png` | 32×48, 6 F. | **Seelenflamme**: blauviolett-goldene Flamme auf einem Kerzenständer/Docht (Soulwick-Motiv), lebendig flackernd |
| `soul_flame_dying_6f.png` | 32×48, 6 F. | Die Flamme erlischt: schrumpft, Rauch, Docht glimmt nach |
| `summoning_rift_6f.png` | 32×48, 6 F. | **Beschwörungsriss** in der Wand oder im Boden: pulsierender Spalt mit Partikeln, biomneutral (wird eingefärbt) |
| `summoning_rift_break_6f.png` | 32×48, 6 F. | Riss schließt sich/zerspringt |
| `totem_4f.png` | 24×40, 4 F. | Alternative zum Riss: Knochen-/Steintotem mit glühenden Augen |
| `stone_guardian_idle_4f.png`, `stone_guardian_walk_6f.png`, `stone_guardian_frozen.png` | 32×48 | **Steinwächter**: Statue eines Ritters; im Dunkeln bewegt sie sich (Augen glühen), im Licht erstarrt sie (Augen aus, leichter Steinstaub) |
| `soul_lantern_4f.png` | 16×24, 4 F. | **Seelenlaterne** zum Tragen (Laternenträger), helles Licht |
| `lantern_socket.png`, `lantern_socket_lit_4f.png` | 32×32 | Sockel am Ausgang, leer bzw. mit eingesetzter Laterne (leuchtet auf) |
| `bounty_crown.png` | 16×16 | Goldkrone, schwebt über dem **Kopfgeld**-Gegner |
| `escape_hole_4f.png` | 32×32, 4 F. | Fluchtloch im Boden, in das der Kopfgeld-Gegner springt |
| `bone_heap_rise_6f.png` | 32×32, 6 F. | **Totengräber**: Knochenhaufen eines besiegten Skeletts, der wieder zusammenwächst |
| `torch_stand_unlit.png` | 16×40 | **Fackelraum**: unbeleuchteter Fackelständer (die beleuchtete Fassung ist `torch_stand_4f.png` aus §1) |
| `wager_altar_4f.png` | 32×48, 4 F. | **Wagnis-Altar**: Steinaltar mit Waage oder Sanduhr, schwaches Glimmen |
| `wager_icons.png` | 16×16 je Symbol, 6×1 (96×16) | Bedingungen: kein Treffer (durchgestrichenes Herz), Zeit (Sanduhr), nur Zweitwaffe (Waffe mit „2“), Fluch Licht (verdunkelte Laterne), Fluch Tempo (Gegner mit Pfeilen), Fluch keine Heilung (durchgestrichenes Kreuz) |

## 4. Prüfungsräume und Pakt (`art/environment/trials/`, A8)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `pendulum_blade_8f.png` | 32×64, 8 F. | Pendelklinge an Kette, schwingt von links nach rechts (Frame 1 und 5 Außenpositionen) |
| `flame_jet_6f.png` | 32×48, 6 F. | Flammendüse in Boden/Wand: Funken (Warnung) → Flammenstoß → aus |
| `crumbling_floor_6f.png` | 32×32, 6 F. | **Bröckelboden**: Bodenplatte bekommt Risse, bricht, fällt ins Dunkel (letzter Frame transparent), biomneutral |
| `trial_pressure_plate.png` | 32×32 | Start-/Zielplatte des Parcours mit Rune |
| `pact_altar_4f.png` | 32×48, 4 F. | **Pakt-Altar**: dunkler Obsidianaltar mit schwebender violetter Flamme, bedrohlich |
| `curse_icons.png` | 16×16 je Symbol, 4×1 (64×16) | Flüche für die Tab-Übersicht: −1 Max-Herz, Gegner schneller, Lichtkreis kleiner, Brunnen heilen halb |

## 5. Abgrund (`art/environment/tiles/`, A4)

Abgrund-, Brücken- und Nebel-Grafiken sind geliefert (SPRITES_V3). Optional für mehr Abwechslung:

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `abyss_tiles_<biom>.png` | wie `abyss_tiles.png` (128×128) | je Biom eigene Abbruchkante (Krypta Steinplatten, Grotte Moos/Schleim, Schattenreich Kristallsplitter, Glutkammer glühende Ränder) |
| `bridge_rope_tiles.png` | 128×32 | Hängebrücke aus Seil und Brettern als zweite Brückenart |

## 6. Wegführung und Geheimnisse (`art/environment/rooms/`, A10)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `wall_cracked_<biom>.png` | 32×32 | Rissige Wand (feine Risse, etwas Staub), Hinweis auf einen **Geheimraum**, je Biom |
| `wall_break_6f.png` | 32×48, 6 F. | Rissige Wand bricht nach einer Explosion auf (Loch transparent) |
| `door_branch_symbols.png` | 16×16 je Symbol, 3×1 (48×16) | Symbole über **Abzweigungs**-Türen: gekreuzte Schwerter (Elite-Nest), Herz (sicherer Weg), Fragezeichen (unbekannt) |
| `wandering_merchant_idle_4f.png` | 32×32, 4 F. | Seltener wandernder Händler in Geheimnischen (Kapuze, großer Rucksack) |

## 7. Anpassungen an gelieferten Grafiken

| Datei | Was | Status |
| --- | --- | --- |
| `art/environment/doors/door_frame_*.png` | Der Durchgang ist dunkel gemalt; das Spiel macht ihn inzwischen beim Laden transparent. Bei einem Neuexport bitte **transparent** liefern | im Code gelöst |
| `art/environment/doors/door_special_symbols.png` | 7. Spalte **Schädel (Miniboss)** ergänzen (dann 112×16) | offen |
| `art/characters/npcs/chronicler_idle_4f.png` | Füße stehen auf Zeile 26 statt 29 wie bei allen anderen; der Code misst die Fußlinie inzwischen selbst | im Code gelöst, Angleichen optional |
| `art/effects/nova_ring_6f.png` | Frames 5–6 sind innen schwarz gefüllt (SPRITES_V3 §7) | im Code gefiltert, Neuexport offen |
| `art/ui/slider_grabber.png`, `art/ui/button_disabled.png` | Pixel-Griff für Regler (8×8) und eigener Zustand für deaktivierte Knöpfe (SPRITES_V3 §7) | offen |

## Wo der Code die Dateien abholt

Die Phase-2-Pakete laden diese Dateien nach Namen aus den angegebenen Ordnern, mit Platzhaltern bis zur Lieferung. Nach dem Ablegen einmal `godot --headless --path . --import`.
