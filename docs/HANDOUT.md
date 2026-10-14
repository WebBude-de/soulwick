# Soulwick – Design-Handout

Alles, was Code und Grafik gemeinsam wissen müssen: Palette, Maßstab, Namensregeln, Ordner. Die Spielgrafiken liegen in `art/`, die Referenz-Screens in `docs/design/`, die Website-Grafiken in `website/public/` (→ `soulwick-platform/apps/web/public/`).

## Maßstab und Format

- Pixel-Art, 3/4-Top-down, kein Anti-Aliasing, PNG mit Transparenz.
- Figuren 32×32 pro Frame (Golem 48×48, Bosse 64×64, Mini-Schleim 16×16), Tiles 32×32, UI-Icons 16×16, Badges 12×12, Boss-Porträts 48×48.
- Animationen als horizontaler Streifen ohne Abstand: `<objekt>_<animation>_<n>f.png`. Standard: idle 4, walk 6, attack 4 (Frame 1–2 = Ausholen), death 6; Bosse zusätzlich attack2 4.
- Blick nach rechts, links per `flip_h`. Füße in jedem Frame auf y = 29 (32er-Frame), Pivot unten Mitte (16, 30).
- Konturen 1 px, einheitlich `#1c1a2b`. Effekte ohne Kontur.
- Virtuelle Auflösung 480 × 270, Integer-Scaling. Godot: Texturfilter **Nearest**.
- Zu jeder Figur liegt `<name>.json` (fps, Pivot, Anker) und `<name>_frames.tres` (Godot SpriteFrames, direkt in AnimatedSprite2D ziehen).

## Farbpalette

Grundton und Kontur
- `#1c1a2b` Kontur, Schatten-Text · `#15131f` tiefster Hintergrund · `#1e1b2c` Seitenhintergrund · `#2a2638` Panel-Fläche · `#3b3650` Panel-Innenrahmen · `#5d577a` / `#8f88ad` Panel-Kanten

Text
- `#e9e4d2` Text · `#d9d2e8` Text weich · `#b9b3c9` gedämpft · `#7a7396` deaktiviert

Akzente
- `#f2cf4a` Gold / Titel / Schadenszahlen · `#e0b84a` / `#c99a2e` Gold dunkel (Münzen, Panel-Gold)
- `#e0463a` Schaden, Gefahr, Herzen (`#a8322a` Schatten, `#ff8a80` Glanz)
- `#6cb2ec` Schild, Schildschaden, Kategorie *Attribut* (`#3690da` Tunika des Spielers, `#2a6cb0` Schatten)
- `#5fcd62` Kategorie *Mechanik*, Erfolg, Nekromanten-Grün (`#b4f09c` hell, `#2f944c` dunkel)
- `#ff8a3c` Kategorie *Effekt*, Feuer (`#e04e2a` Glut, `#ffd166` Flamme hell, `#fff3c4` Kern)
- `#a66ef0` Magie, Kategorie *Waffe* (`#dcbcff` hell, `#6a3cb4` dunkel, `#a98cf5` Link/Hinweis)
- `#2fb391` / `#7ff0c8` Kristall (Schleimgrotte) · `#5ee1ff` Elite „Flink“ · `#f0648c` Schleimkönigin / Slime rosa

Material
- Haut `#f3c9a3` / `#d99c6c` · Holz `#a8703f` / `#8a5a34` / `#5c3a24` · Stein `#9a94b5` / `#7d7799` / `#59547a` · Metall `#c6ccd6` / `#8c8f9a` / `#5a5f6a` · Knochen `#e9e4d2` / `#b8b09a`

Biome (Tileset-Grundtöne)
- Krypta `#4a4560` Boden, `#2c2840` Wandkrone, `#6b6584` Ziegel
- Schleimgrotte `#3f5a4a` Boden, `#1f2d2a` Krone, `#4f6b64` Ziegel, Moos `#6fbf5a`
- Schattenreich `#2e2640` Boden, `#16111f` Krone, `#3b3150` Ziegel, Riss-Leuchten `#6a3cb4`
- Glutkammer `#2f2a2a` Boden, `#1a1616` Krone, `#3f3737` Ziegel, Glutadern `#ff8a3c`
- Dorf: Gras `#5a8f46` / `#6ea455` / `#4a7a3a`, Weg `#a8875a`

## UI-Regeln

- Panels als 9-Slice mit 6 px Rand: `panel` (Standard), `panel_gold` (ausgewählt), `panel_dark` (HUD), `button`, `button_hover`. Fertiges Godot-Theme: `art/ui/theme.tres`. `nameplate` 9-Slice mit 3 px Rand.
- Schrift: Pixelify Sans (`art/fonts/`, OFL), Größen 6–14 px, Text immer mit 1 px Schatten `#1c1a2b`. Eyebrows in Versalien mit 0,08 em Letterspacing.
- Herzen 16 px, 18 px Abstand; 1 Herz = 2 HP in Viertelschritten.
- Gegner-HP-Leiste 20 × 4 px, 4 px über dem Sprite; Elite-Badge 12 px, 4 px darüber.
- Menü-Overlay `rgba(21,19,31,0.78)`; jedes Menü pausiert, die Fußzeile nennt Tasten und „Spiel pausiert“.
- Gold-Konsequenz steht an jeder Entscheidung (100 % Portal, 50 % Tod/Abbruch, „bleibt im Run“ bei Endlos).
- Hauptmenü: Menüliste links auf abgedunkeltem Rand, Szene bleibt sichtbar; aktiver Eintrag `button_hover` + Gold-Cursor, gesperrte Einträge `#7a7396` mit Hinweis.
- Positionen und Größen aller Screens: `docs/design/ui_spec.json`; Referenzbilder: `docs/design/screens/` (1× pixelgenau und 2×).

## Animierte Props

`fountain`, `weapon_pedestal`, `upgrade_altar` (Spezialräume), `well`, `pond` (Dorf) liegen statisch **und** als `_4f`-Schleife (4–6 fps) mit gleichen Maßen und Pivot. Code darf die `_4f`-Datei bevorzugen und auf die statische zurückfallen.

## Türen (D1)

Jede Tür = Rahmen (48×48, Boss 64×56, Pivot unten Mitte, über die Wand gelegt) + Türblatt 32×32 im Durchgang (Rahmen-x+8, y+16; Boss x+16, y+24). `*_open_4f`: Frame 1 geschlossen, Frame 4 offen. Der Durchgang im Rahmen soll **transparent** sein (das Spiel zeigt dahinter den Gang; dunkel gemalte Durchgänge macht der Code beim Laden transparent). `door_special_symbols.png` (6×16×16, weiß/grau, einfärben): Münze, Schwert, Tropfen, Stern, Sanduhr, Flamme.

## Koop-Einfärbung

`player_tint_mask.png` (zu `player_walk_6f`) plus `_idle`, `_dash`, `_death`: weiß = Kleidung, schwarz = Rest. Vorschlag für Spielerfarben: P1 `#3690da`, P2 `#e0463a`, P3 `#5fcd62`, P4 `#f2cf4a`. `teammate_arrow` und `guild_emblems` sind weiß/grau und werden per Modulate eingefärbt.

## Ordner

```
art/
  characters/player|enemies/<typ>|bosses/<name>|npcs
  weapons  projectiles  effects
  environment/tiles  environment/props  environment/buildings
  environment/village (Dorf-Deko B3)  environment/doors (Türen je Biom + Bosstor, D1)  environment/campfire (Lagerfeuer-Raum + Übergangs-Overlays, A6)
  ui  fonts
  ui/menu             (Hauptmenü-Hintergrund in Ebenen + menu.json mit Sprite- und Lichtpositionen)
  index.json          (alle Gruppen und Dateien, maschinenlesbar)
docs/
  HANDOUT.md          (diese Datei)
  design/README.md    (Screen-Beschreibungen)
  design/ui_spec.json
  design/screens/     (12 Screens, 1x/ und 2x)
  design/scenes/      (gerenderte Räume und Dorf als Hintergrund)
website/public/       (logo.svg + .png, logo_square.svg + .png, logo_mono.svg, favicon-32.png, keyart, og_image, biome_*)
art/ui/logo.png, logo_square.png   (1×-Pixelversionen 128×32 / 64×64 für In-Game, Nearest skalieren)
```

## Offen

- Preise, Gold-Drops, Skalierung ab Raum 46 sind im PRD OFFEN; Mockups zeigen Platzhalter.
- Keyart und Biom-Szenen sind aus den Spiel-Sprites komponiert; eine gemalte Illustration wäre der nächste Schritt für den Store-Auftritt.
