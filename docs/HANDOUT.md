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
- Regler: `slider_grabber` 8×8 auf 4 px Schiene; deaktivierte Knöpfe `button_disabled` (9-Slice, Rand 6 px) mit Text `#7a7396`.
- Herzen 16 px, 18 px Abstand; 1 Herz = 2 HP in Viertelschritten.
- Gegner-HP-Leiste 20 × 4 px, 4 px über dem Sprite; Elite-Badge 12 px, 4 px darüber.
- Menü-Overlay `rgba(21,19,31,0.78)`; jedes Menü pausiert, die Fußzeile nennt Tasten und „Spiel pausiert“.
- Gold-Konsequenz steht an jeder Entscheidung (100 % Portal, 50 % Tod/Abbruch, „bleibt im Run“ bei Endlos).
- Hauptmenü: Menüliste links auf abgedunkeltem Rand, Szene bleibt sichtbar; aktiver Eintrag `button_hover` + Gold-Cursor, gesperrte Einträge `#7a7396` mit Hinweis.
- Positionen und Größen aller Screens: `docs/design/ui_spec.json`; Referenzbilder: `docs/design/screens/` (1× pixelgenau und 2×).

## Animierte Props

`fountain`, `weapon_pedestal`, `upgrade_altar` (Spezialräume), `well`, `pond` (Dorf) liegen statisch **und** als `_4f`-Schleife (4–6 fps) mit gleichen Maßen und Pivot. Code darf die `_4f`-Datei bevorzugen und auf die statische zurückfallen.

## Türen (D1)

Jede Tür = Rahmen (48×48, Boss 64×56, Pivot unten Mitte, über die Wand gelegt) + Türblatt 32×32 im Durchgang (Rahmen-x+8, y+16; Boss x+16, y+24). `*_open_4f`: Frame 1 geschlossen, Frame 4 offen. **Der Durchgang im Rahmen ist transparent** (seit V5): dahinter Boden bzw. Dunkelheit des Spiels. `door_special_symbols.png` (7×16×16, weiß/grau, einfärben): Münze, Schwert, Tropfen, Stern, Sanduhr, Flamme, Schädel (Miniboss).

## Phase-2-Räume (V5)

- Öffnungen, Löcher und Durchgänge sind transparent (Türrahmen, `wall_breach_6f`, `wall_break_6f`, `crumbling_floor_6f` Frame 6, `escape_hole_4f`, `enemy_gate_4f`-Öffnung halbtransparent).
- Biomneutral (grau/türkis-weiß, per Modulate einfärben): `light_crystal`, `rubble_*`, `torch_stand`, `summoning_rift*`, `wall_breach`, `wall_break`, `wager_icons`, `curse_icons`, `door_branch_symbols`.
- Je Biom (Suffix `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`): `abyss_tiles_<biom>` (Layout wie `abyss_tiles.png`), `wall_cracked_<biom>` (ersetzt eine `wall_front`-Kachel).
- Ankündigungen vor Schaden: `spike_trap` Frame 2, `flame_jet` Frame 2 (Funken), `pendulum_blade` Außenpositionen Frame 1/5, `explosive_barrel_fuse` 4 Frames, `crumbling_floor` Frame 2–3 (Risse).
- Steinwächter: `stone_guardian_idle/walk` = aktiv im Dunkeln (Augen glühen), `stone_guardian_frozen` im Lichtkreis.
- Seelenflamme: `soul_flame_6f` Loop, `soul_flame_dying_6f` einmalig, letzter Frame stehen lassen. Seelenlaterne (16×24) am Anker `weapon_hand` tragen, `lantern_socket_lit_4f` am Ausgang.
- Pivots und fps pro Gruppe: `rooms.json`, `arena.json`, `variants.json`, `trials.json`, `secrets.json` in den jeweiligen Ordnern.

## Koop-Einfärbung

`player_tint_mask.png` (zu `player_walk_6f`) plus `_idle`, `_dash`, `_death`: weiß = Kleidung, schwarz = Rest. Vorschlag für Spielerfarben: P1 `#3690da`, P2 `#e0463a`, P3 `#5fcd62`, P4 `#f2cf4a`. `teammate_arrow` und `guild_emblems` sind weiß/grau und werden per Modulate eingefärbt.

## Ordner

```
art/
  characters/player|enemies/<typ>|bosses/<name>|npcs
  weapons  projectiles  effects
  environment/tiles  environment/props  environment/buildings
  environment/village (Dorf-Deko B3)  environment/doors (Türen je Biom + Bosstor, D1)  environment/campfire (Lagerfeuer-Raum + Übergangs-Overlays, A6)
  environment/rooms (Kampfraum-Zutaten A3, Arena A5, Geheimnisse A10)  environment/variants (Kampf-Varianten A7/A9)  environment/trials (Prüfungen + Pakt A8)
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

## Räume V2 (Design-Antwort, 14.10.2026)

- Wand-Autotile je Biom (`wall_autotile_<biom>`, Maske N=1 O=2 S=4 W=8, Zeile 5 Vorderseiten) ersetzt inner_wall_tiles; Regel: Mauer mit Boden im Süden ≥ 2 Kacheln hoch.
- Seitentüren `door_side_<biom>_open_4f` (Westwand, Ost spiegeln), Abbruchkanten `abyss_cliff_<biom>`, Tint-Maske Fall.
- Gegner-Quellen `art/environment/spawn/`, Tür-Erkennung `door_mode_symbols` + `door_glow` (Farben in docs/design/claude_design_antwort/05_tueren.md), Geleit-Figur `lost_villager`, Minispiel-Objekte `art/environment/objectives/`, Deko-Gruppen `art/environment/deco/`.
- Beleuchtungsvorschlag: Umgebung 45–55 % sichtbar, Lichtkreis 5 Kacheln, jede Quelle mit Light2D.

## Makeover 3 (14.10.2026)

- Fels-Terrain `rock_blob_<biom>` (47 Kacheln, Godot „Match Corners and Sides“, Maske N=1 NO=2 O=4 SO=8 S=16 SW=32 W=64 NW=128) für Höhlenräume; `wall_autotile_<biom>` bleibt für gemauerte Räume.
- Eingänge: `cave_mouth_<biom>` 64×48 über zwei Vorderseiten; Emporen über `ladder`/`ladder_top`.
- Seitenansicht-Segmente: `player_jump_3f`, `player_land_2f`, Fall = `player_fall_4f` Frame 1; Plattformen aus `front_mid` + `rock_blob`.
- Details: docs/design/claude_design_antwort/11_makeover3_komplett.md

## Weiche Palette & Zugänge (14.10.2026)

- Referenz-Set `crypt_soft`: Erdboden ohne Fugen, Fels `#5a5677`, Kante `#b9b5d2`/`#8f8bac`, Kontur `#2a2740`; Klippen (`front_*` in rock_blob_crypt_soft) statt Ziegel in Höhlen; Treppen `stairs_cut`.
- Zugänge: max. 1 Kachel Gang, geschlossen bündig gefüllt (`gate_slab_open_4f` / `gate_bars_open_4f`, 32×48, 10 fps).

## V9 (15.10.2026)

- Fels-Innenecken `rock_blob_<biom>_soft_inner` (Bogenband Radius 4), Füllkacheln fill_left/right/both, front_step_*.
- Tore: `cave_mouth_<biom>_soft` nur Bogen, `door_frame_<biom>_soft` rund, `tunnel_shade_*`, `side_mouth_<biom>_soft` (Ostwand, Code spiegelt), `door_side_<biom>_bars_4f`.
- Deko-Gruppen je Biom, Nebel, Wasser-Glitzer, Felsnische/-riss, Abgrund soft für alle Biome, Höhlen-Durchbruch.
- Seitenansicht: Plattformkanten, Parallax-Hintergründe, Stacheln, goldene Münze, Leiter-Symbol (11. Spalte), player_climb + Masken.
- lost_villager ohne eingemalten Laternenschein (Licht-System), Anker lantern (20,20).
