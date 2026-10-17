# Soulwick – Design-Handout

> **Stand:** 17.10.2026 · Was Code und Grafik gemeinsam wissen müssen: Ton, Maßstab, Palette, Namensregeln, Ordner. Spielgrafik liegt in `art/`, Briefings in [design/sprites/](design/sprites/README.md), Referenzen in [design/](design/README.md), Website-Grafik im Repo `soulwick-platform` unter `apps/web/public/brand/` (WebP).

## Ton und Aufmachung (D-174)

- **Dungeon:** spannend und atmosphärisch, darf düster sein, nie ernst oder lächerlich. Das Licht des Spielers ist warm und positiv.
- **Dorf:** süß, gemütlich, lebendig, heller als der Dungeon. Die Palette unten gilt weiter; das Dorf **darf heller und wärmer werden** (OFFEN in D-174, nicht still festlegen: erst mit Briefing und Freigabe).
- **Moderne Pixel-Art statt Retro-Look:** Pixel bleiben, dazu dynamisches Licht, Bloom, weiche Schatten, Partikel, Wind, Squash and Stretch, weiche Kamera, klares animiertes UI. Keine gewollten Grafikfehler. Nach außen „moderne Pixel-Art“, nicht „8-Bit“.
- **Maskottchen:** Wick (Docht-Wesen) und das Huhn (D-175); Figuren und Name sind geschützt (D-177).

## Maßstab und Format

- Pixel-Art, 3/4-Top-down, kein Anti-Aliasing, PNG mit Transparenz; Godot-Texturfilter **Nearest**.
- Figuren 32×32 je Frame (Golem 48×48, Bosse 64×64, Mini-Schleim 16×16), Kacheln 32×32, UI-Icons 16×16, Badges 12×12, Boss-Porträts 48×48. Die Welt wird ganzzahlig ×2 gezeichnet (32-px-Kachel = 64 px).
- UI-Maße in Mockup-Pixeln 480 × 270; das Spiel läuft in 1280 × 720 und rechnet über `UiKit` um.
- Animationen als waagerechter Streifen ohne Abstand: `<objekt>_<animation>_<n>f.png`. Standard: idle 4, walk 6, attack 4 (Frame 1–2 = Ausholen), death 6; Bosse zusätzlich attack2 4.
- Blick nach rechts, links per `flip_h`. Füße in jedem Frame auf y = 29 (32er-Frame), Pivot unten Mitte (16, 30).
- Konturen 1 px `#1c1a2b`; Effekte ohne Kontur.
- Zu jeder Figur `<name>.json` (fps, Pivot, Anker) und `<name>_frames.tres` (Godot SpriteFrames).

## Farbpalette

**Grundton und Kontur**

- `#1c1a2b` Kontur, Schatten-Text · `#15131f` tiefster Hintergrund · `#1e1b2c` Seitenhintergrund · `#2a2638` Panel-Fläche · `#3b3650` Panel-Innenrahmen · `#5d577a` / `#8f88ad` Panel-Kanten

**Text**

- `#e9e4d2` Text · `#d9d2e8` Text weich · `#b9b3c9` gedämpft · `#7a7396` deaktiviert

**Akzente**

- `#f2cf4a` Gold / Titel / Schadenszahlen · `#e0b84a` / `#c99a2e` Gold dunkel (Münzen, Panel-Gold)
- `#e0463a` Schaden, Gefahr, Herzen (`#a8322a` Schatten, `#ff8a80` Glanz)
- `#6cb2ec` Schild, Schildschaden, Kategorie *Attribut* (`#3690da` Tunika des Spielers, `#2a6cb0` Schatten)
- `#5fcd62` Kategorie *Mechanik*, Erfolg, Nekromanten-Grün (`#b4f09c` hell, `#2f944c` dunkel)
- `#ff8a3c` Kategorie *Effekt*, Feuer (`#e04e2a` Glut, `#ffd166` Flamme hell, `#fff3c4` Kern)
- `#a66ef0` Magie, Kategorie *Waffe* (`#dcbcff` hell, `#6a3cb4` dunkel, `#a98cf5` Link/Hinweis)
- `#2fb391` / `#7ff0c8` Kristall (Schleimgrotte) · `#5ee1ff` Elite „Flink“ · `#f0648c` Schleimkönigin / Slime rosa

**Material**

- Haut `#f3c9a3` / `#d99c6c` · Holz `#a8703f` / `#8a5a34` / `#5c3a24` · Stein `#9a94b5` / `#7d7799` / `#59547a` · Metall `#c6ccd6` / `#8c8f9a` / `#5a5f6a` · Knochen `#e9e4d2` / `#b8b09a`

**Biome (Grundtöne)**

- Krypta `#4a4560` Boden, `#2c2840` Wandkrone, `#6b6584` Ziegel
- Schleimgrotte `#3f5a4a` Boden, `#1f2d2a` Krone, `#4f6b64` Ziegel, Moos `#6fbf5a`
- Schattenreich `#2e2640` Boden, `#16111f` Krone, `#3b3150` Ziegel, Riss-Leuchten `#6a3cb4`
- Glutkammer `#2f2a2a` Boden, `#1a1616` Krone, `#3f3737` Ziegel, Glutadern `#ff8a3c`
- Weiche Palette für Fels-Räume (D-142): Referenz `crypt_soft` (Erdboden ohne Fugen, Fels `#5a5677`, Kante `#b9b5d2`/`#8f8bac`, Kontur `#2a2740`); andere Biome per Palettentausch in `tools/build_tilesets.gd`
- Dorf: Gras `#5a8f46` / `#6ea455` / `#4a7a3a`, Weg `#a8875a`

Koop-Farben P1 `#3690da`, P2 `#e0463a`, P3 `#5fcd62`, P4 `#f2cf4a` (Namensschilder; VORGESCHLAGEN). Spielerfiguren werden über ihre Schlüsselfarben umgefärbt (`PlayerLook`, D-152); was nicht umgefärbt werden soll, braucht eigene Farben ([SPRITES_V10.md](design/sprites/SPRITES_V10.md)).

## UI-Regeln

- Panels als 9-Slice mit 6 px Rand (`panel`, `panel_gold` = ausgewählt, `panel_dark` = HUD, `button`, `button_hover`, `button_disabled`); Godot-Theme `art/ui/theme.tres`.
- Schrift Pixelify Sans (`art/fonts/`, OFL), Text immer mit 1 px Schatten `#1c1a2b`; Eyebrows in Versalien mit etwas Sperrung.
- Menüs dunkeln die Szene ab, sie bleibt sichtbar; Dialoge höchstens etwa 60 % der Bildhöhe (D-139).
- Die Gold-Folge steht an jeder Entscheidung (100 % Portal, 50 % Tod oder Abbruch).
- Nicht leistbar heißt: Karte normal, Preis rot, Schloss; nichts halbdurchsichtig verstecken (D-110).
- Maße der ersten Screens: [design/ui_spec.json](design/ui_spec.json), Bilder in `docs/design/mockups/screens/`.

## Regeln für Grafik-Lieferungen

- **Öffnungen sind transparent** (Türrahmen, Durchbrüche, Löcher, Tore): Dahinter zeichnet das Spiel Boden oder Dunkelheit.
- **Biomneutral** (grau/weiß, das Spiel färbt per Modulate) für alles, was in mehreren Biomen vorkommt; sonst je Biom mit Suffix `_crypt`, `_slime_grotto`, `_shadow_realm`, `_ember_forge`.
- **Ankündigung vor Schaden:** Fallen und Angriffe haben einen eigenen Warn-Frame (z. B. `spike_trap` Frame 2).
- **Animierte Props** gibt es statisch **und** als `_4f`-Schleife mit gleichen Maßen und Pivot; der Code nimmt die Schleife, sonst die statische.
- **Türen:** Rahmen über der Wand plus Türblatt im Durchgang; `*_open_4f`: Frame 1 zu, Frame 4 offen.
- **Autotiles:** Wand-Autotile `wall_autotile_<biom>` (Maske N=1 O=2 S=4 W=8) für gemauerte Räume, Fels-Terrain `rock_blob_<biom>` (47 Kacheln, Maske N=1 NO=2 O=4 SO=8 S=16 SW=32 W=64 NW=128) für Höhlen.
- **Licht setzt das Spiel:** Wo das Spiel eine Lichtquelle setzt (Laterne, Fackel, Flamme), keinen Lichtschein einmalen (V9).
- Pivots und fps je Gruppe in einer JSON neben den Bildern; Übersicht aller Gruppen in `art/index.json`.

## Ordner

```text
art/
  characters/player|enemies/<typ>|bosses/<name>|npcs
  companions/wick            (Begleiter, später Pets; geplant, SPRITES_V12)
  cosmetics/hats|wick_hats   (Kosmetik-Teile für Spielfigur und Wick; geplant, SPRITES_V12)
  weapons  projectiles  effects
  environment/tiles|props|buildings|village|doors|campfire|rooms|variants|trials|spawn|objectives|deco|side
  ui  ui/menu  fonts
  ui/mascot  ui/cosmetics    (Wick groß für Menü und Stores, Kosmetik-Symbole; geplant, SPRITES_V12)
  index.json                 (alle Gruppen und Dateien, maschinenlesbar)
docs/design/
  sprites/                   (Briefings SPRITES_V*.md mit Stand)
  responses/                 (Antworten von Claude Design)
  mockups/screens|backgrounds, ui_spec.json
  gallery/                   (Fotos aus dem Spiel, erzeugt)
soulwick-platform/apps/web/public/brand/   (Logo, Keyart, OG-Bild, Biom-Szenen als WebP)
```

## Offen

- Preise und Gold in Mockups sind Platzhalter; im Spiel gelten TESTWERTE (D-064, D-091, D-118).
- Keyart und Biom-Szenen sind aus Spiel-Sprites komponiert; eine gemalte Illustration wäre der nächste Schritt für die Stores.
- Hellere, wärmere Dorf-Palette (D-174 OFFEN).
