# Grafik-Briefing V10 – Soulwick: Touch-Steuerung und Eingabe-Symbole

> **Für Claude Design.** Die Bildschirm-Steuerung für Handys und die kleinen Tasten-Symbole in HUD und Hinweisen sind heute **Platzhalter aus Code** (Kreise, Striche, Mini-Pixelbilder). Liefert ihr eine Datei mit genau diesem Namen, baut der Code sie automatisch ein; fehlt eine Datei, bleibt der Platzhalter.
> **Stand:** 15.10.2026 · **offen** · Stil wie das Spiel: Pixel-Art ohne Anti-Aliasing, PNG mit Transparenz, Kontur 1 px `#1c1a2b`, Palette aus [HANDOUT.md](../../HANDOUT.md) (Gold `#f2cf4a`, Text `#e9e4d2`, Panel `#2a2638`/`#3b3650`, Kanten `#5d577a`/`#8f88ad`, warmer Ring der heutigen Knöpfe `#d9b77e`).
> **Wunsch des Projektmitglieds:** „Richtige Controls statt selbst gezeichneter Kreise. Auf dem Handy soll nirgends ‚Leertaste‘ stehen, sondern ein Icon, in dem man den Dash erkennt.“
> **Leitlinien:** Ein Symbol muss **ohne Text** verständlich sein, auch klein und mit dem Daumen halb darüber. Knöpfe liegen über dem laufenden Spiel: Fläche halbtransparent dunkel, Ring und Icon hell und klar. Icons der Touch-Knöpfe und die kleinen HUD-Symbole zeigen **dasselbe Motiv** (gleiches Dash-Bild auf dem Knopf und im HUD).

## Maßstab

- Spielfenster 1280×720, Pixel-Art im Maßstab 480×270. Der Code zeichnet die Touch-Teile mit **3 Bildschirmpixeln je Grafikpixel** (ganzzahlig, scharf).
- Aktions-Icons sind **16×16** und werden je nach Knopf ×4 (Angriff), ×3 (normal) oder ×2 (klein) gezeichnet. Sie sitzen mittig im Knopf, rund 2 px Luft zum Ring einplanen.
- Eingabe-Symbole in HUD und Hinweisen sind **10 px hoch** (wie eine Tastenkappe) und werden ×2 bis ×3 gezeichnet.
- Pivot aller Teile: **Mitte**. Knöpfe und Stick sind rund; die Ecken außerhalb des Kreises bleiben durchsichtig.

## 1. Touch-Steuerung (`art/ui/touch/`)

Genutzt von `ui/touch/touch_overlay.gd` über `ui/touch/touch_art.gd` (`TouchArt`). Fehlt `_pressed` oder `_disabled`, tönt der Code die normale Grafik heller bzw. grauer.

| Datei | Größe | Frames | Beschreibung |
| --- | --- | --- | --- |
| `touch_stick_base.png` | 60×60 | 1 | Sockel des Bewegungs-Sticks: runde Scheibe, Fläche `#15131f` mit ca. 40 % Deckkraft, Ring 2 px in `#d9b77e` (ca. 60 % Deckkraft) mit 1 px dunkler Innenkante, unten ein Hauch Schatten. Ruhig, nicht verspielt, das Spiel bleibt sichtbar. |
| `touch_stick_arrows.png` *(optional)* | 60×60 | 1 | Vier kleine Richtungsdreiecke (je ca. 5×4 px) innen am Ring oben, rechts, unten, links, `#e9e4d2` mit 50 % Deckkraft. Liegt über dem Sockel. |
| `touch_stick_knob.png` | 24×24 | 1 | Stick-Knopf: gewölbte Scheibe, Fläche `#d9b77e` mit ca. 45 % Deckkraft, 1 px hellere Glanzkante oben links, Kontur `#1c1a2b`. |
| `touch_stick_knob_pressed.png` | 24×24 | 1 | Knopf gedrückt: deckender und wärmer (Richtung Gold `#f2cf4a`, ca. 75 %), Glanzkante etwas stärker. |
| `touch_btn_large.png` | 48×48 | 1 | Großer runder Aktionsknopf (nur **Angriff**): Fläche `#15131f` ca. 45 % Deckkraft, Ring 2 px `#d9b77e`, darunter 2 px dunkler Rand `#5d577a` als „Dicke“ (wie eine Taste von schräg oben). |
| `touch_btn_large_pressed.png` | 48×48 | 1 | Gedrückt: Fläche warm getönt (`#f2cf4a` ca. 35 %), Ring heller, die untere „Dicke“ fehlt (Taste ist eingedrückt). |
| `touch_btn_large_disabled.png` | 48×48 | 1 | Gesperrt: Ring grau `#7a7396` ca. 50 %, Fläche wie normal. |
| `touch_btn.png` | 32×32 | 1 | Normaler Knopf (Spezial, Dash, Benutzen, Springen, Seiten-Dash), gleicher Aufbau wie groß. |
| `touch_btn_pressed.png` | 32×32 | 1 | Gedrückt, wie oben. |
| `touch_btn_disabled.png` | 32×32 | 1 | Gesperrt (z. B. Dash oder Spezial lädt noch). |
| `touch_btn_small.png` | 24×24 | 1 | Kleiner Knopf (Waffe wechseln, oben Upgrades und Pause), Ring 1–2 px. |
| `touch_btn_small_pressed.png` | 24×24 | 1 | Gedrückt. |
| `touch_btn_small_disabled.png` | 24×24 | 1 | Gesperrt. |
| `touch_cooldown_8f.png` | 8 × 32×32 | 8 | Abklingzeit über einem normalen Knopf: Frame 1 = gerade benutzt (fast ganz abgedunkelt), Frame 8 = gleich bereit. Dunkle Tortenfläche (`#15131f` ca. 55 %), die im Uhrzeigersinn ab 12 Uhr freigegeben wird, außen ein schmaler heller Fortschrittsring (`#d9b77e`). Kein eigenes Icon darin, das Icon liegt darunter. |

### Aktions-Icons (je 16×16, 1 Frame)

Helles Motiv `#e9e4d2` mit Schattenkante `#b9b3c9`, Kontur `#1c1a2b`, damit es auf dunkler Fläche **und** über hellem Boden lesbar bleibt. Waffen-Icons dürfen farbig sein (Metall, Holz, Magie) wie die vorhandenen Item-Icons `art/ui/icon_<waffe>.png`.

| Datei | Beschreibung |
| --- | --- |
| `icon_attack.png` | Angriff neutral (kein Waffenwissen): gekreuzte Klinge mit kurzem Hiebbogen. |
| `icon_attack_sword.png` | Angriff mit Schwert: Schwert schräg nach oben rechts mit Schwungbogen. Heute nimmt der Code `art/ui/icon_sword.png`. |
| `icon_attack_bow.png` | Bogen mit eingelegtem Pfeil, Pfeilspitze nach rechts oben. |
| `icon_attack_staff.png` | Stab mit leuchtender Kugel (`#a66ef0`), kleiner Funke. |
| `icon_attack_dagger.png` | Zwei Dolche, leicht gefächert. |
| `icon_attack_hammer.png` | Kriegshammer schräg, Aufschlag-Strahlen unter dem Kopf. |
| `icon_dash.png` | **Dash, muss sofort verständlich sein:** kleine Figur (Silhouette, nach rechts geneigt im Sprint) **oder** kräftiger Pfeil nach rechts, dahinter drei waagerechte Bewegungsstreifen unterschiedlicher Länge, die nach links auslaufen. **Kein „>>“** (sieht aus wie Vorspulen). Der Platzhalter zeigt schon Pfeil plus Streifen. |
| `icon_side_dash.png` | Dash in der Seitenansicht: wie `icon_dash`, darunter eine waagerechte Bodenlinie. |
| `icon_jump.png` | Springen (Seitenansicht): Pfeil nach oben über einer Bodenlinie, gern mit zwei kleinen Staubwölkchen links und rechts der Linie. |
| `icon_special.png` | Spezialfähigkeit: Stern mit vier Funken bzw. Strahlenkranz, Gold `#f2cf4a` als Akzent erlaubt. |
| `icon_interact.png` | Benutzen/Interagieren: offene Hand, die nach etwas greift (Handfläche nach vorn, Finger leicht gespreizt), optional kleiner Glanzpunkt an den Fingerspitzen. |
| `icon_switch.png` | Waffe wechseln: zwei Pfeile im Kreis (Wechsel), in der Mitte ein winziges Schwertheft oder leer. |
| `icon_pause.png` | Pause: zwei senkrechte Balken. |
| `icon_menu.png` | Upgrades/Übersicht: aufgeschlagenes Buch oder Schriftrolle mit drei Zeilen (nicht nur drei Striche). |

## 2. Eingabe-Symbole für HUD und Hinweise (`art/ui/input/`)

Genutzt von `ui/icons/input_glyphs.gd` (`InputGlyphs.texture(id)` lädt `art/ui/input/input_<id>.png`) und darüber von `ui/widgets/key_cap.gd`, der HUD-Tastenzeile (`ui/hud/hud.gd`) und der Steuerungskarte (`ui/hints/controls_hint.gd`). Alle **10 px hoch**. Buchstaben und Ziffern zeichnet der Code als Schrift auf eine leere Kappe, dafür reicht `input_key_cap`.

**Farben der Kappen:** Rand `#5d577a`, Fläche `#15131f`, Symbol `#e9e4d2`. Aufbau wie heute: 1 px Rand oben und seitlich, 7 px Fläche, 2 px Rand unten als Tastenkante, Ecken offen.

### 2a. Vorhandene Platzhalter (Namen und Größen stehen fest)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `input_space.png` | 17×10 | Leertaste: breite Kappe mit dem Leertasten-Zeichen (Klammer „␣“ unten offen). |
| `input_shift.png` | 11×10 | Umschalt: hohler Pfeil nach oben. |
| `input_tab.png` | 13×10 | Tab: Pfeil nach rechts an einen senkrechten Strich. |
| `input_enter.png` | 11×10 | Enter: abgeknickter Pfeil (runter, dann nach links). |
| `input_backspace.png` | 13×10 | Rücktaste: Pfeil nach links. |
| `input_arrow_up.png`, `input_arrow_down.png`, `input_arrow_left.png`, `input_arrow_right.png` | je 11×10 | Pfeiltasten. |
| `input_mouse_left.png`, `input_mouse_right.png`, `input_mouse_middle.png` | je 9×10 | Maus von oben, Umriss `#d9d2e8`, Körper `#15131f`; die gemeinte Taste gold `#f2cf4a`. |
| `input_mouse_wheel.png` | 9×10 | Maus mit goldenem Rad, gern mit winzigen Pfeilen hoch/runter am Rad. |
| `input_mouse.png` | 9×10 | Maus ohne gedrückte Taste (Zielen). |
| `input_touch_special.png` | 9×10 | Runder Touch-Knopf im Kleinformat: Ring `#d9b77e`, Fläche `#15131f`, unten 1 px Schatten `#5d577a`; darin das Motiv von `icon_special` (Stern). |
| `input_touch_dash.png` | 9×10 | Wie oben, darin das **Dash-Motiv von `icon_dash`** (Pfeil oder Figur mit Bewegungsstreifen) auf 5×5 px; kein „>>“. |
| `input_touch_switch.png` | 9×10 | Wie oben, darin die Wechselpfeile von `icon_switch`. |

### 2b. Neue Symbole (Code ergänzt die ids in `InputGlyphs.IDS`)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `input_key_cap.png` | 9×10, 9-Slice | Leere Tastenkappe für Buchstaben per Schrift. Ränder: links 2, rechts 2, oben 1, unten 2 (die Fläche dazwischen wird gestreckt). |
| `input_escape.png` | 13×10 | Esc: Kappe mit Pfeil aus einem Rahmen heraus (nach oben links) statt Schrift. |
| `input_touch_attack.png` | 9×10 | Touch-Knopf klein mit Angriffs-Motiv (Klinge). |
| `input_touch_interact.png` | 9×10 | Touch-Knopf klein mit Hand. |
| `input_touch_jump.png` | 9×10 | Touch-Knopf klein mit Sprungpfeil über Bodenlinie. |
| `input_touch_side_dash.png` | 9×10 | Touch-Knopf klein mit Dash-Motiv über Bodenlinie. |
| `input_touch_pause.png`, `input_touch_menu.png` | je 9×10 | Kleine Touch-Knöpfe Pause und Upgrades (Buch). |
| `input_touch_stick.png` | 9×10 | Stick-Sockel mit Knopf (Bewegen auf dem Handy). |
| `input_gesture_tap.png` | 10×10 | Geste Tippen: Zeigefinger mit kleinem Ring an der Fingerkuppe. |
| `input_gesture_hold.png` | 10×10 | Geste Halten: Finger mit doppeltem, dickerem Ring (oder Ring mit Uhr-Strich). |
| `input_gesture_swipe.png` | 10×10 | Geste Wischen: Finger mit Bewegungsstreifen und Pfeil nach rechts. |
| `input_pad_south.png`, `input_pad_east.png`, `input_pad_west.png`, `input_pad_north.png` | je 10×10 | Gamepad-Gesichtstasten neutral: Raute aus vier Punkten, der gemeinte Punkt gold gefüllt (passt für Xbox, PlayStation, Switch). |
| `input_pad_a.png`, `input_pad_b.png`, `input_pad_x.png`, `input_pad_y.png` *(optional)* | je 10×10 | Runde Taste mit Buchstabe, Farben gedeckt (A grün `#5fcd62`, B rot `#e0463a`, X blau `#6cb2ec`, Y gold `#f2cf4a`). |
| `input_pad_lb.png`, `input_pad_rb.png` | je 13×10 | Schultertasten: flache, oben abgerundete Kappe, Pfeil-Ecke links bzw. rechts. |
| `input_pad_lt.png`, `input_pad_rt.png` | je 11×10 | Trigger: höhere Kappe, nach unten zulaufend. |
| `input_pad_stick_left.png`, `input_pad_stick_right.png` | je 10×10 | Analogstick von oben (Kreis mit Knopf), links/rechts durch einen kleinen Punkt links bzw. rechts unten unterschieden. |
| `input_pad_dpad.png` | 10×10 | Steuerkreuz. |
| `input_pad_start.png`, `input_pad_select.png` | je 10×10 | Menü-Taste (drei Striche) und Ansicht-Taste (zwei Rechtecke). |

## 3. JSON zu den Dateien

Bitte zu jedem Ordner eine Beschreibung mitliefern (wie `art/ui/controls.json`):

```json
{
  "group": "touch",
  "pixel_scale": 3,
  "items": [
    { "name": "touch_stick_base", "file": "touch_stick_base.png", "frame_size": [60, 60], "frames": 1, "pivot": [30, 30] },
    { "name": "touch_stick_knob", "file": "touch_stick_knob.png", "frame_size": [24, 24], "frames": 1, "pivot": [12, 12] },
    { "name": "touch_btn_large", "file": "touch_btn_large.png", "frame_size": [48, 48], "frames": 1, "pivot": [24, 24], "states": ["", "_pressed", "_disabled"] },
    { "name": "touch_btn", "file": "touch_btn.png", "frame_size": [32, 32], "frames": 1, "pivot": [16, 16], "states": ["", "_pressed", "_disabled"] },
    { "name": "touch_btn_small", "file": "touch_btn_small.png", "frame_size": [24, 24], "frames": 1, "pivot": [12, 12], "states": ["", "_pressed", "_disabled"] },
    { "name": "touch_cooldown", "file": "touch_cooldown_8f.png", "frame_size": [32, 32], "frames": 8, "fps": 0, "pivot": [16, 16], "note": "Frame nach Restanteil, nicht als Animation" },
    { "name": "icon_dash", "file": "icon_dash.png", "frame_size": [16, 16], "frames": 1, "pivot": [8, 8] }
  ]
}
```

```json
{
  "group": "input",
  "height": 10,
  "items": [
    { "name": "input_key_cap", "file": "input_key_cap.png", "frame_size": [9, 10], "nine_slice": { "left": 2, "right": 2, "top": 1, "bottom": 2 } },
    { "name": "input_space", "file": "input_space.png", "frame_size": [17, 10] },
    { "name": "input_touch_dash", "file": "input_touch_dash.png", "frame_size": [9, 10] }
  ]
}
```

## 4. Was der Code damit macht

| Teil | Code | Verhalten |
| --- | --- | --- |
| §1 Stick, Knöpfe, Abklingzeit, Icons | `ui/touch/touch_art.gd`, `ui/touch/touch_overlay.gd` | Lädt `art/ui/touch/<name>.png`, sonst Platzhalter. Angriff zeigt die aktive Waffe (`icon_attack_<waffe>` → `art/ui/icon_<waffe>.png` → `icon_attack`). Dash und Spezial zeigen beim Abklingen `_disabled` plus `touch_cooldown_8f`. |
| §2a vorhandene Symbole | `ui/icons/input_glyphs.gd` | Datei ersetzt den Platzhalter gleichen Namens sofort. |
| §2b neue Symbole | `ui/icons/input_glyphs.gd`, `ui/widgets/key_cap.gd` | Kommen mit dem Einbau der ids; bis dahin Schrift auf der Kappe. |

Nach dem Ablegen: `godot --headless --path . --import`.

## 5. Türme (Gegner, `art/characters/enemies/<id>/`)

Stationäre Türme, die dauerhaft auf den Spieler schießen und ihn kurz verlangsamen (Turm-Gegner, `enemies/turret/`). Ablage nach `EnemyArt`-Konvention, `<id>` = `bone_turret` (Krypta), `slime_spitter` (Schleimgrotte), `shadow_eye` (Schattenreich), `ember_cauldron` (Glutkammer). 32×32 je Frame, Blick nach rechts (wird gespiegelt), Fußpunkt (16,30), optional `<id>.json` mit `"pivot": [16, 30]`. Auge bzw. Mündung etwa bei (16,10): Dort startet das Geschoss.

| Datei | Frames | Inhalt |
| --- | --- | --- |
| `<id>_idle_4f.png` | 4, 3 fps, Schleife | ruhig, das Auge glimmt schwach |
| `<id>_walk_4f.png` | 4 | Kopie von idle (`EnemyArt` verlangt idle **und** walk) |
| `<id>_attack_6f.png` | 6 | Frames 0–3 Aufladen (Auge wird heller und größer), **Frame 4 = Schuss** (hellster Blitz), Frame 5 Rückstoß |
| `<id>_death_6f.png` | 6 | zerbröckeln bzw. umkippen zu einem Schutthaufen |

Je Biom:

- **Knochenturm:** Knochensäule mit Schädelkopf, Auge eisblau.
- **Schleimspeier:** grüner Schleimhügel mit Spuckmaul.
- **Schattenauge:** violetter Obelisk mit starrem Auge.
- **Glutkessel:** eiserner Kessel mit glühender Schlacke, orange.

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/projectiles/<id>_shot_4f.png` | 4 × 16×16 | Geschoss, rund, in Biomfarbe, leicht pulsierend |
| `art/effects/slow_status_6f.png` | 6 × 32×32, Schleife | Verlangsamung am Spieler, mittig auf dem Körper: bläulicher Frostschimmer, Eiskristalle an den Füßen, aufsteigende Funken |

## 6. Seitenansicht (Jump'n'Run)

> **Stand:** 16.10.2026 · **offen** · Runde 3 der Gang-Segmente (D-144): Türme, Becken, Stachel-Wellen, Biom-Deko und Parallax. Heute zeichnet der Code alles hier als Platzhalter; liefert ihr eine Datei mit genau diesem Namen, ersetzt sie den Platzhalter automatisch.
> **Schon geliefert und weiter genutzt:** `bg_<biom>_parallax.png`, `spikes_side_3f.png`, `platform_edge_<biom>.png`, `golden_coin_4f.png` (SPRITES_V9 §4), die Deko-Gruppen `deco_group_<biom>_{1..3}.png`, Kerzen, Pilze, Kristalle, Amboss, Fass, Glutbecken, Ketten, Tropfen (Räume). **Weiter offen und hier nicht doppelt:** SPRITES_V9 §6 (Doppelsprung, Wandrutschen, Staub).
> **Türme:** Die Seitenansicht nutzt dieselben Turm-Grafiken wie §5 (`bone_turret`, `slime_spitter`, `shadow_eye`, `ember_cauldron`). Der Code dreht sie für Decke (180°) und Wand (90°); bitte den Fuß (16,30) wie in §5 einhalten, dann sitzt der Turm sauber im Fels.

| Datei | Größe | Frames | Beschreibung |
| --- | --- | --- | --- |
| `art/environment/side/mid_<biom>_parallax.png` | 480×270 | 1 | **Mittlere Parallax-Ebene** (läuft mit ¾ Kamera-Tempo vor `bg_<biom>_parallax`). Durchsichtig bis auf Silhouetten, nur wenig heller als die Rückwand, damit Plattformen lesbar bleiben. Krypta: Bögen auf Säulen, hängende Ketten, Nischen mit Kerzenschein. Grotte: Wurzeln von oben, Tropfsteine, großer Pilz mit leuchtenden Punkten. Schattenreich: schwebende Felssplitter mit glimmender Rune. Glutkammer: hängende Käfige an Ketten, Schmelzofen mit Glutmaul unten, Rohre. Links und rechts nahtlos kachelbar. |
| `art/environment/side/pool_<biom>_4f.png` | 4 × 32×32 | 4, 6 fps, Schleife | **Becken im Boden** (Plan-Zeichen `w`), eine Zelle; der Code reiht sie nebeneinander, also links/rechts nahtlos. Oberfläche bei y ≈ 13 als helle Wellenlinie (2 px), darunter die Flüssigkeit, unten dunkler. Krypta: kühles Wasser (blau), Grotte: grüner Schleim mit Blasen, Schattenreich: violettes, fast schwarzes Wasser, Glutkammer: glühende Schlacke (orange, Blasen). Halbtransparent (≈ 75 %), damit die Figur darin noch zu sehen ist. |
| `art/environment/side/hang_roots.png` | 32×48 | 1 | Hängende Wurzeln (Grotte), Oberkante = Fels, 2–3 Stränge, an den Spitzen ein grün leuchtender Tropfen. |
| `art/environment/side/hang_crystals.png` | 32×48 | 1 | Hängende Kristallsplitter (Schattenreich), Oberkante = Fels, 3 Spitzen nach unten, violett mit hellem Rand. |

**Hinweise:**

- Maßstab wie überall: 32-px-Kacheln, im Spiel ×2. Kontur `#1c1a2b`, weiche Palette wie `crypt_soft`, andere Biome per Palettentausch.
- Kein Licht einmalen (Lichtkegel, Glow-Höfe): Licht macht das Licht-System. Glühende Stellen (Kerzen, Glut, Pilze) dürfen als helle Pixel drin sein.
- Die Deko-Gruppen der Räume stehen auch im Jump'n'Run auf dem Boden. Die flache Schleimpfütze `deco_group_slime_grotto_3` sieht von der Seite falsch aus und wird dort nicht benutzt; eine Seitenansicht-Fassung ist nicht nötig.
- Nach dem Ablegen: `godot --headless --path . --import`.
