# Sprite-Liste – 2D-Dungeon-Roguelite

> **Zweck:** Vollständige Liste aller Grafiken für den MVP, inklusive Stil- und Formatvorgaben. Die Datei ist eigenständig lesbar, auch ohne den Rest des Projekts.
> **Ablage der fertigen Dateien:** im Projekt unter `art/` im jeweils angegebenen Unterordner.

## Spiel in einem Satz

Ein 2D-Top-down-Dungeon-Roguelite: Der Spieler läuft mit WASD durch vorgefertigte Dungeonräume, zielt mit der Maus in alle Richtungen (360°) und kämpft mit Schwert, Bogen oder Magierstab gegen Slimes, Skelette und Bogenschützen.

## Stil (Vorschlag, im Team zu bestätigen)

- **Pixel-Art**, klare Silhouetten, gut lesbar auf dunklem Dungeonboden.
- **Perspektive:** Top-down mit leichter Schrägsicht von oben (3/4-Ansicht), alle Grafiken in derselben Perspektive.
- **Stimmung:** dunkler Dungeon mit warmen Lichtakzenten (Fackeln); Spieler und Gegner farblich klar voneinander unterscheidbar.
- **Begrenzte Farbpalette**, für alle Sprites dieselbe.

## Technisches Format (verbindlich für den Import)

- **PNG mit transparentem Hintergrund**, keine Hintergrundfarbe, keine Schatten-Flächen außerhalb der Figur.
- **Exakte Pixelgrößen**, kein Hochskalieren, keine weichgezeichneten Kanten (Anti-Aliasing). Jeder Pixel muss auf dem Raster sitzen.
- **Größen:** Figuren 32×32 px pro Frame, Bosse 64×64 px, Tiles 32×32 px, UI-Icons 16×16 px.
- **Animationen als horizontaler Streifen:** alle Frames gleich groß, direkt nebeneinander, ohne Abstand und ohne Rand. Beispiel: 6 Frames à 32×32 ergeben ein Bild von 192×32 px.
- **Blickrichtung:** Figuren und Waffen zeigen **nach rechts**. Links wird im Spiel gespiegelt, Waffen werden zur Maus gedreht.
- **Figur mittig im Frame**, Füße in allen Frames auf derselben Höhe, damit nichts „wackelt“.
- **Dateinamen** klein mit Unterstrich: `<objekt>_<animation>_<frames>f.png`, z. B. `slime_walk_6f.png`.
- Frame-Zahlen unten sind Richtwerte. Treffer-Aufblinken und Rückstoß macht der Code, dafür braucht es kein eigenes Sprite.

## Priorität 1 – Kampf (M1, sofort einbaubar)

### Spieler – `characters/player/`

- [ ] `player_idle_4f.png`
- [ ] `player_walk_6f.png`
- [ ] `player_dash_3f.png` (optional, sonst Walk + Effekt)
- [ ] `player_death_6f.png`

### Gegner – `characters/enemies/<typ>/`

| Datei | Slime | Skeleton | Archer |
| --- | --- | --- | --- |
| `<typ>_idle_4f.png` | [ ] | [ ] | [ ] |
| `<typ>_walk_6f.png` | [ ] (hüpfen) | [ ] | [ ] |
| `<typ>_attack_4f.png` (Ausholen = Ankündigung) | [ ] | [ ] | [ ] (Bogen spannen) |
| `<typ>_death_6f.png` | [ ] | [ ] | [ ] |

### Waffen in der Hand – `weapons/` (zeigen nach rechts, drehen sich mit der Maus)

- [ ] `sword.png`
- [ ] `bow.png`
- [ ] `staff.png`

### Projektile – `projectiles/`

- [ ] `arrow.png` (Spieler, ca. 16×4)
- [ ] `magic_orb_4f.png` (Magierstab, ca. 16×16)
- [ ] `enemy_arrow.png` (Archer, andere Farbe)

### Effekte – `effects/`

- [ ] `sword_swing_4f.png` (Bogen-/Sichel-Schwung nach rechts, ca. 100°)
- [ ] `explosion_6f.png` (Stab-Einschlag, ca. 96×96)
- [ ] `hit_spark_3f.png`
- [ ] `dash_dust_4f.png`

## Priorität 2 – Dungeon (M2)

### Tiles – `environment/tiles/` (als ein Tileset-Bild, 32×32 pro Tile)

- [ ] Boden: 3–4 Varianten
- [ ] Wand: gerade oben/unten/links/rechts
- [ ] Wand: 4 Außenecken + 4 Innenecken
- [ ] Wandfront (die sichtbare „Höhe“ unterhalb der Oberkante)

### Props – `environment/props/`

- [ ] `door_closed.png`, `door_open.png` (bzw. `door_open_4f.png`)
- [ ] 3–5 Deko-Objekte (Fackel `torch_4f.png`, Kisten, Knochen, Fässer)

## Priorität 3 – Spezialräume, Gold, Dorf (M3–M5)

### Spezialraum-Objekte – `environment/props/`

- [ ] `exit_portal_6f.png`
- [ ] `fountain.png` (Brunnen)
- [ ] `shop_counter.png` + optional `merchant_idle_4f.png`
- [ ] `weapon_pedestal.png` (Waffenauswahl)
- [ ] `upgrade_altar.png` (Extra-Upgrade)
- [ ] `gold_coin_4f.png` (Drop am Boden)
- [ ] `dungeon_entrance.png` (im Dorf)

### Dorf – `environment/`

- [ ] Dorf-Tileset (Gras, Weg, Zaun)
- [ ] 2–3 Gebäude

## Priorität 4 – UI (M6) – `ui/`

- [ ] Herzen: `heart_full.png`, `heart_3q.png`, `heart_half.png`, `heart_1q.png`, `heart_empty.png` (1 Herz = 2 HP, Schritte 0,5 HP = Viertelherz)
- [ ] `shield_icon.png`, `gold_icon.png`
- [ ] Waffen-Icons: `icon_sword.png`, `icon_bow.png`, `icon_staff.png`
- [ ] Panel-Hintergrund für Menüs/Shop (`panel.png`, 9-Slice-fähig)
- [ ] 15 Upgrade-Icons (`upgrade_<id>.png`):
  - [ ] Verstärkter Angriff · [ ] Krafttraining · [ ] Schneller Angriff · [ ] Präzise Pfeile · [ ] Magische Verstärkung
  - [ ] Schnelle Geschosse · [ ] Schildverstärkung · [ ] Durchschlag · [ ] Wandabprall · [ ] Doppelschuss
  - [ ] Größerer Schwung · [ ] Größere Explosion · [ ] Explosiver Treffer · [ ] Heilung bei Tötung · [ ] Schild bei Tötung

## Erweiterung (optional) – eigene Grafiken für neue Gegner und Bosse

Diese Gegner nutzen vorerst **eingefärbte, vergrößerte** vorhandene Sprites. Eigene Grafiken können mit denselben Animationsnamen (`idle`, `walk`, `attack`, `death`) in `characters/enemies/<typ>/` abgelegt werden:

- [ ] Schattenwesen (`shadow_*`) – halbtransparente, geisterhafte Gestalt
- [ ] Bomber (`bomber_*`) – kleiner Kerl mit Lunte; Attack = Lunte brennt
- [ ] Knochenkönig (`bone_king_*`, 64×64) – Skelett mit Krone und Schild; Attack 2 = Schildstoß
- [ ] Schleimkönigin (`slime_queen_*`, 64×64) – großer Schleim mit Krone; Sprung-Animation
- [ ] Schattenlord (`shadow_lord_*`, 64×64) – dunkler Magier; Teleport-Animation
- [ ] Stachelfalle (`spike_trap_3f.png`, 32×32: eingefahren / Warnung / ausgefahren) – aktuell per Code gezeichnet

## Später

- [ ] Miniboss: reicht anfangs ein vergrößerter Standardgegner (D-011)
- [ ] Bosse für Raum 15/30/45 (Design noch OFFEN)
