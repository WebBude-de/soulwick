# Grafik-Briefing V3 – Soulwick: Raumarten, Waffen, Multiplayer, Website

> **Für Claude Design.** Diese Datei ist eigenständig lesbar. Sie ergänzt [SPRITES.md](SPRITES.md) und [SPRITES_V2.md](SPRITES_V2.md) um alles, was für [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md), [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) und die Website gebraucht wird.
> **Ablage:** Spielgrafiken im Spiel-Repo unter `art/` im angegebenen Unterordner, Website-Grafiken im Repo `soulwick-platform` unter `apps/web/public/`. Dateinamen exakt übernehmen, dann werden sie automatisch eingebaut. Bis dahin erzeugt der Code Platzhalter.

## Spiel in einem Satz

2D-Top-down-Dungeon-Roguelite in Pixel-Art: Der Spieler kämpft sich mit Schwert, Bogen, Stab, Dolchen oder Kriegshammer durch einen endlosen, dunklen Dungeon mit wechselnden Biomen (Krypta, Schleimgrotte, Schattenreich, Glutkammer), Bossen und neuen Raumarten (offene Arena, Mauerräume, Abgründe mit Brücken). Später zu zweit bis zu viert im Koop, mit Gilden und Ranglisten.

## Stil und Format (wie bisher, unbedingt einhalten)

- **Pixel-Art**, Top-down mit leichter Schrägsicht (3/4), gleiche Palette und gleicher Pixel-Maßstab wie die vorhandenen Grafiken.
- **PNG mit transparentem Hintergrund**, exakte Pixelgrößen, kein Anti-Aliasing, kein Hochskalieren.
- **Tiles 32×32 px**, Figuren 32×32 px pro Frame, UI-Icons 16×16 px.
- **Animationen als horizontaler Streifen** ohne Abstand. Der Dateiname enthält die Frame-Anzahl, z. B. `player_fall_4f.png`.
- **Figuren und Waffen schauen nach rechts.** Füße in allen Frames auf gleicher Höhe, Figur mittig.
- **Biome:** Tiles neutral bis leicht kühl halten; das Spiel färbt je Biom ein. Wo unten „je Biom“ steht, gern eigene Varianten mit Suffix `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`.

## 1. Waffen (noch offen aus SPRITES_V2 §8, höchste Priorität)

Im Spiel sind Dolche und Kriegshammer heute **Platzhalter** (der Hammer ist ein brauner Stab). Ablage `art/weapons/`, `art/ui/`, `art/projectiles/`, `art/effects/`. Griff links, Spitze rechts (wie `sword.png`).

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `weapons/dagger.png` | 32×32 | Zwei kurze, gekreuzte Dolche, Griff bei ca. (6,16) |
| `weapons/hammer.png` | 48×32 | Schwerer Kriegshammer: kurzer Holzstiel links, großer Eisenkopf rechts |
| `ui/icon_dagger.png`, `ui/icon_hammer.png` | 16×16 | Icons für HUD und Shop |
| `projectiles/throwing_knife.png` | 16×5 | Wurfmesser (Spezialangriff der Dolche), Pivot (8,2) |
| `effects/hammer_slam_6f.png` | 96×96, 6 F. | Aufschlag des Hammers: Staub, Risse, Steinsplitter |
| `effects/spin_slash_4f.png` | 96×96, 4 F. | 360°-Wirbelschlag des Schwerts |
| `effects/nova_ring_6f.png` | 128×128, 6 F. | Arkane Nova des Stabs, Ring nach außen |
| `effects/quake_ring_6f.png` | 128×128, 6 F. | „Erdbeben“ des Hammers: Bodenwelle mit Rissen |

## 2. Raumarten (`art/environment/tiles/`, ROADMAP_AUSBAU A3–A4)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `abyss_tiles.png` | 32×32 je Tile, Raster 4×4 (128×128) | Abgrund: reine Tiefe (fast schwarz mit leichtem Schimmer), Kante oben (sichtbare Bodenplatte mit Abbruchkante), Kanten links/rechts/unten, vier Außenecken, vier Innenecken |
| `bridge_tiles.png` | 32×32 je Tile, 4×1 (128×32) | Holzbrücke waagerecht, senkrecht, Brückenende links/oben (das andere Ende spiegelt der Code) |
| `inner_wall_tiles.png` | 32×32 je Tile, 4×2 (128×64) | Innenmauer passend zu den Biom-Tilesets: Mauerkrone (oben), Vorderseite, Enden links/rechts, freistehendes Mauerstück, Kreuzung |
| `abyss_mist_4f.png` | 32×32, 4 F. | Aufsteigender Nebel aus der Tiefe (Deko, langsam) |

## 3. Spieler (`art/characters/player/`)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `player_fall_4f.png` | 32×32, 4 F. | Spieler fällt in den Abgrund: wird kleiner, dreht sich leicht, verschwindet |
| `player_down_2f.png` | 32×32, 2 F. | Am Boden liegend, wartet auf Wiederbelebung (Koop) |
| `player_revive_4f.png` | 32×32, 4 F. | Aufstehen nach Wiederbelebung |
| `player_tint_mask.png` | 32×32 je Frame, gleiche Streifen wie `player_walk_*` | **Optional:** Maske (weiß = Kleidung) für die Koop-Farben; ohne Maske färbt der Code die ganze Figur leicht ein |

## 4. Dorf (`art/ui/`, ROADMAP_AUSBAU B1–B2)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `icon_lock.png` | 16×16 | Schloss für gesperrte Gebäude oder Verbesserungen („Öffnet nach …“) |
| `icon_info.png` | 16×16 | Kleines „i“ für Gebäude-Erklärungen |
| `sign_forge.png`, `sign_trading.png`, `sign_chronicle.png`, `sign_guild.png` | 24×16 | Holzschilder über den Türen (Amboss, Waage, Buch, Banner) |

## 5. Koop und Gilden (`art/ui/`, ROADMAP_MULTIPLAYER MP2–MP8)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `icon_revive.png` | 16×16 | Hand/Herz-Symbol über einem gefallenen Mitspieler |
| `teammate_arrow.png` | 16×16 | Pfeil am Bildrand zu Mitspielern außerhalb des Bildes (weiß, wird eingefärbt) |
| `nameplate.png` | 48×12, 9-Slice (Rand 3 px) | Rahmen für Spielernamen über den Figuren |
| `icon_host.png` | 16×16 | Krone für den Host in der Spielerliste |
| `icon_ping_good.png`, `icon_ping_mid.png`, `icon_ping_bad.png` | 16×16 | Verbindungsqualität (3 Balken) |
| `guild_emblems.png` | 24×24 je Wappen, 8×1 (192×24) | Acht Gilden-Wappen zur Auswahl (Schwert, Schädel, Flamme, Mond, Krone, Schlange, Turm, Auge), weiß/grau, wird eingefärbt |
| `icon_leaderboard.png` | 16×16 | Pokal für die Ranglisten |
| `icon_treasury.png` | 16×16 | Gildenkasse (Truhe mit Münzen) |

## 6. Website (`soulwick-platform/apps/web/public/`, kein Pixel-Raster-Zwang außer wo angegeben)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `logo.png` | 512×128, Pixel-Art | Spiellogo: Schriftzug **SOULWICK**, das „i“ als brennender Docht/Kerze mit blauviolett-goldener Seelenflamme, transparent |
| `logo_square.png` | 256×256, Pixel-Art | Quadratisches Logo für Favicon und Social Media |
| `keyart.png` | 1920×1080 | Titelbild: Held mit Fackel vor dunklem Dungeon-Eingang, Bosse im Schatten; Pixel-Art, dunkel-lila mit warmem Gold |
| `og_image.png` | 1200×630 | Vorschaubild beim Teilen (Logo + Keyart-Ausschnitt) |
| `biome_crypt.png`, `biome_slime_grotto.png`, `biome_shadow_realm.png`, `biome_ember_forge.png` | 640×360 | Szenen je Biom für die Startseite (Screenshots gehen auch, siehe unten) |

**Screenshots** kann das Spiel selbst erzeugen (`tools/screenshots.gd`); dafür braucht es keine Grafik.

## 7. Nachträge nach dem Einbau (14.10.2026)

Die Abschnitte 1–5 sind geliefert und eingebaut. Beim Einbau fiel Folgendes auf (Slider und deaktivierter Button werden nach der Lieferung im `UiKit` angeschlossen):

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `effects/nova_ring_6f.png` | 128×128, 6 F. (neu exportieren) | In Frame 5 und 6 ist die ganze Scheibe mit halbtransparentem Schwarz gefüllt. Bitte mit transparentem Innenraum exportieren, nur der Ring blendet aus. Der Code filtert das bis dahin heraus. |
| `ui/slider_grabber.png` | 8×8 | Griff für die Lautstärkeregler im Pausemenü (heute Godot-Standardgriff), Stil wie `button.png` |
| `ui/menu/menu_bg_near.png` | 480×270 (im Spiel repariert) | Weg-Kreuzung: 4 px Grasspalt zwischen waagerechtem und senkrechtem Weg (x 288–291) und 4 px Stufe rechts am senkrechten Weg (x 316–319, ab y 206) wurden am 14.10.2026 per Skript korrigiert. Bei einem Neuexport bitte die saubere L-Kreuzung übernehmen. |
| `ui/button_disabled.png` | wie `button.png`, 9-Slice mit 6 px Rand | Deaktivierter Button (ausgegraut, flacher), heute wird der normale Button blass dargestellt |

## Priorität

1. **Waffen (1)**: sofort sichtbar im Spiel, heute Platzhalter
2. **Raumarten (2)** und **Spieler fällt (3, `player_fall_4f`)**: nötig für ROADMAP_AUSBAU A3–A4
3. **Dorf (4)**: nötig für B1–B2
4. **Website (6)**: Logo und Keyart, sobald die Website online geht
5. **Koop (5)** und restliche Spieler-Animationen (3): erst mit ROADMAP_MULTIPLAYER MP2–MP5
