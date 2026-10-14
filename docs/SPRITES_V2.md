# Grafik-Briefing V2 – Biome, neue Gegner, Bosse, Dorf

> **Für Claude Design.** Diese Datei ist eigenständig lesbar. Sie ergänzt die bereits gelieferten Grafiken (siehe [SPRITES.md](SPRITES.md)) um alles, was für den Endlos-Dungeon, die Biome, die neuen Gegner und das ausgebaute Dorf gebraucht wird.
> **Ablage:** im Projekt unter `art/` im jeweils angegebenen Ordner. Dateinamen exakt übernehmen, dann werden sie automatisch eingebaut.

## Spiel in einem Satz

2D-Top-down-Dungeon-Roguelite in Pixel-Art: Der Spieler kämpft sich mit Schwert, Bogen oder Magierstab durch einen endlosen, dunklen Dungeon mit wechselnden Biomen und Bossen. Zwischen den Runs verbessert er sich im Dorf.

## Stil und Format (wie bisher, unbedingt einhalten)

- **Pixel-Art**, Top-down mit leichter Schrägsicht (3/4), gleiche Palette und gleicher Pixel-Maßstab wie die vorhandenen Grafiken.
- **PNG mit transparentem Hintergrund**, exakte Pixelgrößen, kein Anti-Aliasing, kein Hochskalieren.
- **Animationen als horizontaler Streifen** ohne Abstand. Dateiname enthält die Frame-Anzahl: `golem_walk_6f.png`.
- **Figuren schauen nach rechts.** Füße in allen Frames auf gleicher Höhe, Figur mittig.
- Standard-Animationen pro Figur: `idle` (4), `walk` (6), `attack` (4, die ersten Frames = sichtbares Ausholen), `death` (6). Bosse zusätzlich `attack2` (4) für ihren Spezialangriff.
- Zu jeder Figur gern eine kleine JSON-Datei wie bisher (Pivot, Anker, FPS).

## 1. Biome – Tilesets (`art/environment/tiles/`)

Jedes Tileset **exakt im Layout von `dungeon_tileset.png`**: 256×96 px, 8×3 Tiles à 32×32 px, gleiche Reihenfolge der 24 Tiles (floor_1–4, wall_top, wall_front, wall_front_2, wall_front_top, wall_n/e/s/w, wall_outer_ne/nw/se/sw, wall_inner_ne/nw/se/sw, wall_ns, wall_ew, wall_pillar, void).

| Datei | Biom | Beschreibung |
| --- | --- | --- |
| `slime_grotto_tileset.png` | Schleimgrotte | Feuchte, grünliche Höhle; Moos, Schleimpfützen auf Bodenvarianten, tropfende Wände |
| `shadow_realm_tileset.png` | Schattenreich | Violett-schwarzer Stein, Risse mit schwachem violetten Leuchten, Nebelfetzen |
| `ember_forge_tileset.png` | Glutkammer | Dunkler Basalt, glühende Glutadern in Boden und Wänden, Asche |

## 2. Biom-Deko und Gefahren (`art/environment/props/`)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `torch_green_4f.png` | 32×32, 4 F. | Grüne Kristall-Fackel (Schleimgrotte), an `wall_front` |
| `torch_purple_4f.png` | 32×32, 4 F. | Violette Seelenflamme (Schattenreich) |
| `brazier_4f.png` | 32×32, 4 F. | Feuerschale am Boden (Glutkammer), Pivot unten Mitte |
| `toxic_puddle_4f.png` | 32×32, 4 F. | Blubbernde Giftpfütze (Bodengefahr) |
| `lava_crack_4f.png` | 32×32, 4 F. | Glühender Lavariss im Boden (Bodengefahr) |
| `spike_trap_3f.png` | 32×32, 3 F. | Stachelfalle: eingefahren / Warnung (Spitzen schauen raus) / ausgefahren |
| `crystal_cluster.png`, `mushrooms.png`, `chains.png`, `anvil_broken.png` | 32×32 | Biom-Deko (je eine pro Biom genügt) |

## 3. Neue Gegner (`art/characters/enemies/<name>/`)

| Ordner / Präfix | Größe | Aussehen und Verhalten |
| --- | --- | --- |
| `shadow/shadow_*` | 32×32 | Schattenwesen: halbtransparente, geisterhafte Gestalt mit leuchtenden Augen. Attack = Krallen-Hieb |
| `bomber/bomber_*` | 32×32 | Bomber: kleiner Kobold mit brennender Lunte auf dem Rücken. Attack = Lunte sprüht, Körper bläht sich auf |
| `splitter_slime/splitter_slime_*` | 32×32 | Splitterschleim: grüner Schleim mit sichtbarem Kern in zwei Hälften |
| `mini_slime/mini_slime_*` | 16×16 | Mini-Schleim: kleiner, flinker grüner Schleim |
| `golem/golem_*` | 48×48 | Golem: wuchtiger Steinkoloss. Attack = Faust hebt sich und kracht runter |
| `necromancer/necromancer_*` | 32×32 | Nekromant: Kapuzenmagier mit Knochenstab und grünem Leuchten. Attack = Zauber, `summon` (4 F.) = Arme hoch |

## 4. Bosse (`art/characters/bosses/<name>/`, 64×64)

| Ordner | Boss | Spezialangriff (`attack2`) |
| --- | --- | --- |
| `bone_king/` | Knochenkönig – Skelett mit Krone, Turmschild und Krummschwert | Schildstoß (Ansturm) |
| `slime_queen/` | Schleimkönigin – riesiger rosa Schleim mit Krone, kleine Schleime im Inneren | Sprung (Anlauf, in der Luft, Landung) |
| `shadow_lord/` | Schattenlord – große dunkle Magiergestalt, schwebend, Umhang aus Rauch | Teleport (verblassen / erscheinen) |
| `ember_golem/` | Glutgolem – Golem aus Basalt mit glühenden Rissen und Feueraugen | Stampfer (Faust in den Boden, Funken) |

Zusätzlich je Boss ein **Porträt** 48×48 (`<name>_portrait.png`) für die Boss-Leiste.

## 5. Gegner-Kennzeichen (`art/ui/`, 12×12 px)

Kleine Symbole über besonderen Gegnern, damit man sofort sieht, was sie können:

| Datei | Bedeutung |
| --- | --- |
| `badge_swift.png` | Elite „Flink“ – Blitz, cyan |
| `badge_armored.png` | Elite „Gepanzert“ – Schild, stahlblau |
| `badge_volatile.png` | Elite „Explosiv“ – Bombe, orange |
| `badge_stun.png` | Betäubt (Sterne) – Skelett-Schildstoß |
| `badge_blind.png` | Blendet (geschlossenes Auge) – Schattenwesen |
| `badge_summoner.png` | Beschwört (Schädel) – Nekromant |
| `badge_explode.png` | Explodiert (Funke) – Bomber |
| `badge_champion.png` | Champion/Miniboss (Krone) |

## 6. Dorf (`art/environment/buildings/`, `art/characters/npcs/`)

Wichtig: **Proportionen passend zur 32-px-Spielfigur**, die Tür muss etwa so hoch sein wie die Figur (≈ 28–32 px) und unten mittig liegen.

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `forge.png` | 96×96 | Schmiede mit Esse, Rauch, Amboss davor, Schild „Schmiede“ |
| `trading_post.png` | 96×80 | Handelshaus mit Markise und Kisten |
| `chronicle_hall.png` | 80×96 | Archiv/Chronik mit Turm und Bannern |
| `guild_hall.png` | 112×96 | Gildenhaus (später Multiplayer-Lobby) mit Wappen |
| `home.png` | 80×80 | Haus des Spielers (Lagerkiste davor) |
| `well.png`, `market_stall.png`, `lamp_post_4f.png` | 32–64 px | Dorf-Deko, Laterne animiert |
| `npcs/smith_idle_4f.png` | 32×32 | Schmied mit Hammer |
| `npcs/trader_idle_4f.png` | 32×32 | Händlerin mit Rucksack |
| `npcs/chronicler_idle_4f.png` | 32×32 | Alter Gelehrter mit Buch |
| `npcs/guild_master_idle_4f.png` | 32×32 | Gildenmeisterin in Rüstung |

## 7. Benutzeroberfläche (`art/ui/`, 16×16 px)

| Datei | Bedeutung |
| --- | --- |
| `meta_vitality.png` | Herz mit Plus (mehr Max-HP) |
| `meta_shield.png` | Schild mit Plus (Startschild) |
| `meta_sharpness.png` | Klinge mit Funkeln (mehr Schaden) |
| `meta_greed.png` | Goldsack (mehr Gold) |
| `meta_dash.png` | Flügelstiefel (Dash-Abklingzeit) |
| `meta_arsenal.png` | Waffenständer (zweite Startwaffe) |
| `crystal_icon.png` | Seelenkristall (zweite Währung, von Bossen) |
| `trophy_icon.png`, `skull_icon.png`, `clock_icon.png` | Chronik-Statistiken (Rekord, Kills, Spielzeit) |

## 8. Neue Waffen und Effekte (`art/weapons/`, `art/ui/`, `art/projectiles/`, `art/effects/`)

Waffen zeigen nach rechts, Griff links (wie `sword.png`).

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `weapons/dagger.png` | 32×32 | Zwei kurze Dolche, Griff bei ca. (6,16) |
| `weapons/hammer.png` | 48×32 | Schwerer Kriegshammer, Griff am linken Ende |
| `ui/icon_dagger.png`, `ui/icon_hammer.png` | 16×16 | Icons für HUD und Shop |
| `projectiles/throwing_knife.png` | 16×5 | Wurfmesser (Spezialangriff der Dolche), Pivot (8,2) |
| `effects/hammer_slam_6f.png` | 96×96, 6 F. | Aufschlag des Hammers: Staub, Risse, Steinsplitter |
| `effects/spin_slash_4f.png` | 96×96, 4 F. | 360°-Wirbelschlag des Schwerts (optional) |
| `effects/nova_ring_6f.png` | 128×128, 6 F. | Arkane Nova des Stabs, Ring nach außen (optional) |
| `effects/muzzle_puff_3f.png` | 16×16, 3 F. | Abschuss-Wölkchen für Bogen/Stab (optional) |

## Priorität

1. **Gegner-Kennzeichen (5)** und **Stachelfalle**: klein, schnell gemacht, großer Nutzen
2. **Neue Gegner (3)** und **Bosse (4)**
3. **Biom-Tilesets (1)** und Deko (2)
4. **Dorf (6)** und **UI-Icons (7)**
