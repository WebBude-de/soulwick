# Grafik-Briefing V10 – Soulwick: Touch-Steuerung und Eingabe-Symbole

> **Seit 22.10.2026 (D-193):** Die noch offenen Teile dieses Briefings stehen gesammelt in [SPRITES_V13.md](../SPRITES_V13.md) Teil D; hier gelten nur noch die Namensregeln und Maße des Gelieferten.
> **Für Claude Design.** Die Bildschirm-Steuerung für Handys und die kleinen Tasten-Symbole in HUD und Hinweisen sind heute **Platzhalter aus Code** (Kreise, Striche, Mini-Pixelbilder). Liefert ihr eine Datei mit genau diesem Namen, baut der Code sie automatisch ein; fehlt eine Datei, bleibt der Platzhalter.
> **Stand:** 17.10.2026 · **geliefert und übernommen**, 14 Eingabe-Symbole offen (siehe Lieferstand), neu offen: §9 niedrige Torbögen · Stil wie das Spiel: Pixel-Art ohne Anti-Aliasing, PNG mit Transparenz, Kontur 1 px `#1c1a2b`, Palette aus [HANDOUT.md](../../../HANDOUT.md) (Gold `#f2cf4a`, Text `#e9e4d2`, Panel `#2a2638`/`#3b3650`, Kanten `#5d577a`/`#8f88ad`, warmer Ring der heutigen Knöpfe `#d9b77e`).
> **Wunsch des Projektmitglieds:** „Richtige Controls statt selbst gezeichneter Kreise. Auf dem Handy soll nirgends ‚Leertaste‘ stehen, sondern ein Icon, in dem man den Dash erkennt.“
> **Leitlinien:** Ein Symbol muss **ohne Text** verständlich sein, auch klein und mit dem Daumen halb darüber. Knöpfe liegen über dem laufenden Spiel: Fläche halbtransparent dunkel, Ring und Icon hell und klar. Icons der Touch-Knöpfe und die kleinen HUD-Symbole zeigen **dasselbe Motiv** (gleiches Dash-Bild auf dem Knopf und im HUD).

## Lieferstand 17.10.2026

Lieferung von Claude Design (`responses/SPRITES_V10_lieferung.md` liegt nur im Export in `_inbox/`), geprüft auf Maße, Frames, Transparenz und im Spiel (Screenshots), übernommen nach `art/`:

| Abschnitt | Stand |
| --- | --- |
| §1 Touch-Steuerung | **geliefert**: alle 15 Rahmen/Sticks und 14 Aktions-Icons übernommen. |
| §2 Eingabe-Symbole | **teilweise**: 32 von 46 übernommen. **Nicht übernommen** (der Code-Platzhalter ist lesbarer, Vergleichsbild beim Projektmitglied): `input_pad_a`, `_b`, `_x`, `_y` (Buchstaben zerfallen), `input_pad_lb`, `_rb`, `_lt`, `_rt` (Buchstaben unleserlich, z. B. „Γc“ statt „LB“), `input_gesture_tap`, `_hold`, `_swipe` (Hand nicht erkennbar), `input_escape` (kein Pfeil, nur Ecke und Rahmen), `input_pad_select` (statt zwei Rechtecken ein geteilter Kreis), `input_touch_interact` (Oval statt Hand). Bitte neu liefern: Buchstaben in einer 3×5-Pixelschrift wie der Platzhalter, Hand mit erkennbaren Fingern. |
| §5 Türme | **geliefert** mit Nachbesserung: Bei `bone_turret`, `slime_spitter`, `shadow_eye` war die Augenhöhle in Idle-Frame 2–4 und im Angriff **durchsichtig** (Boden schien durch den Kopf), die Ladeglut ersetzte die Kopfpixel halbtransparent. Beim Übernehmen per Skript den Kopf aus Idle-Frame 1 hinterlegt (Auge in den übrigen Frames gedimmt, Schussframe 4 über dem hellen Auge). Für eine Neulieferung: Glut **über** das Auge legen, Kopf deckend lassen. Geschosse und `slow_status_6f` unverändert übernommen. |
| §6 Seitenansicht | **geliefert**: `mid_<biom>_parallax`, `pool_<biom>_4f`, `hang_roots`, `hang_crystals`. |
| §7a Figuren | **geliefert**: Ember, Moss, Frost je 10 Streifen, Schlüsselfarben exakt (keine Zwischentöne). Hinweis: `<id>_climb_4f` zeigt die Figur seitlich statt mit dem Rücken zur Kamera; `fall`, `down`, `revive` liegen bereit, der Code nutzt dafür noch Wicks Bilder (Haken in `CharacterData.STRIP_ANIMATIONS` bzw. Spielerdateien). Die mitgelieferten `<id>_frames.tres` sind **nicht** übernommen (falsche Animationsnamen `jump`/`land`/`climb` statt `side_*`, sie würden die Streifen-Logik von `CharacterData` aushebeln). |
| §7b Lobby | **geliefert**: `slot_normal/own/host/empty`, `ready`, `../icon_world`; überarbeitete `icon_host` (kleiner) und `icon_ping_*` (vier Balken) übernommen. |
| §7c Spiegel | **geliefert**: `mirror.png`. |
| §8 App-Icons | geliefert 16.10.2026; die Fassung vom 17.10. ist pixelgleich (nur RGBA statt RGB), daher nicht ersetzt. |
| §9 Niedrige Torbögen | **offen** (17.10.2026, Fehlermeldung #67215ac5): `door_frame_boss_low`, `door_frame_<biom>_soft_low`, optional `tunnel_shade_arch_low`; bis dahin kürzt der Code die hohen Bögen. |

## Maßstab

- Spielfenster 1280×720, Pixel-Art im Maßstab 480×270. Der Code zeichnet die Touch-Teile mit **3 Bildschirmpixeln je Grafikpixel** (ganzzahlig, scharf).
- Aktions-Icons sind **16×16** und werden je nach Knopf ×4 (Angriff), ×3 (normal) oder ×2 (klein) gezeichnet. Sie sitzen mittig im Knopf, rund 2 px Luft zum Ring einplanen.
- Eingabe-Symbole in HUD und Hinweisen sind **10 px hoch** (wie eine Tastenkappe) und werden ×2 bis ×3 gezeichnet.
- Pivot aller Teile: **Mitte**. Knöpfe und Stick sind rund; die Ecken außerhalb des Kreises bleiben durchsichtig.

## 1. Touch-Steuerung (`art/ui/touch/`)

Genutzt von `ui/touch/touch_overlay.gd` über `ui/touch/touch_art.gd` (`TouchArt`). Fehlt `_pressed` oder `_disabled`, tönt der Code die normale Grafik heller bzw. grauer.

**Nachtrag 17.10.2026 (Projektmitglied: „so pixelig wie das Spiel“):** Die Platzhalter sind jetzt selbst Pixel-Art in genau diesen Namen, Größen und Farben (`ui/touch/touch_pixel_art.gd`); eine gelieferte Datei ersetzt sie wie bisher. Neu in den Einstellungen (Reiter „Touch“): **Größe** Klein/Mittel/Groß zeichnet alle Teile mit **2, 3 oder 4** Bildschirmpixeln je Grafikpixel (Icons auf großen/kleinen Knöpfen eine Stufe größer/kleiner) – bitte keine Details unter 1 px planen, die bei ×2 verschwinden. **Deckkraft** 50/75/100 % wirkt zusätzlich auf die ganze Steuerung; die Grafiken selbst bitte wie oben beschrieben halbtransparent anlegen. Mit „Seiten tauschen“ wird nur die Position gespiegelt, nicht die Grafik. Die gezeichneten Knöpfe haben unten 2 px „Dicke“; das Icon sitzt 1 px über der Bildmitte (gedrückt 1 px darunter), bei gelieferten Rahmen genau mittig.

| Datei | Größe | Frames | Beschreibung |
| --- | --- | --- | --- |
| `touch_stick_base.png` | 60×60 | 1 | Sockel des Bewegungs-Sticks: runde Scheibe, Fläche `#15131f` mit ca. 40 % Deckkraft, Ring 2 px in `#d9b77e` (ca. 60 % Deckkraft) mit 1 px dunkler Innenkante, unten ein Hauch Schatten. Ruhig, nicht verspielt, das Spiel bleibt sichtbar. |
| `touch_stick_arrows.png` *(optional)* | 60×60 | 1 | Vier kleine Richtungsdreiecke (je ca. 5×4 px) innen am Ring oben, rechts, unten, links, `#e9e4d2` mit 50 % Deckkraft. Liegt über dem Sockel. |
| `touch_stick_knob.png` | 24×24 | 1 | Stick-Knopf: gewölbte Scheibe, Fläche `#d9b77e` mit ca. 45 % Deckkraft, 1 px hellere Glanzkante oben links, Kontur `#1c1a2b`. |
| `touch_stick_knob_pressed.png` | 24×24 | 1 | Knopf gedrückt: deckender und wärmer (Richtung Gold `#f2cf4a`, ca. 75 %), Glanzkante etwas stärker. |
| `touch_stick_aim_base.png` *(optional)* | 60×60 | 1 | Sockel des **Ziel-Sticks** rechts (zielen und automatisch angreifen, ersetzt den Angriffsknopf; `touch_btn_large*` wird dafür nicht mehr gezeigt). Aufbau wie `touch_stick_base`, Ring eher in Glutrot `#c8643c` statt Gold, damit beide Sticks unterscheidbar sind. Fehlt die Datei, nimmt der Code `touch_stick_base`; der Knopf ist `touch_stick_knob` mit dem Waffen-Icon darauf. |
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

> **Stand:** 16.10.2026 · **geliefert 17.10.2026** · Runde 3 der Gang-Segmente (D-144): Türme, Becken, Stachel-Wellen, Biom-Deko und Parallax. Heute zeichnet der Code alles hier als Platzhalter; liefert ihr eine Datei mit genau diesem Namen, ersetzt sie den Platzhalter automatisch.
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

## 7. Figuren und Lobby (D-152)

> **Wunsch des Projektmitglieds:** „Ein Charakter pro Account. Mehr Charaktere und Farben, Auswahl in der Lobby und im Dorf. 4 Figuren + Farben, alles frei.“
> **Stand heute:** Die vier Figuren `wick` (die bisherige Spielerfigur), `ember`, `moss`, `frost` sind im Spiel wählbar; die drei neuen sind **Platzhalter** (Grundfigur mit Kopf-Merkmal aus Code: Flammenschopf, Spitzhut, Bommelmütze). Alle Figuren spielen gleich, es geht nur ums Aussehen. Liefert ihr die Dateien unten, nimmt der Code sie ohne weitere Änderung.

### 7a. Drei neue Figuren (`art/characters/<id>/`)

| id | Name (de / en) | Silhouette und Idee |
| --- | --- | --- |
| `ember` | Glut / Ember | Hitzkopf: wilder Haarschopf, der in drei Flammenzacken nach oben steht; kurze Weste über dem Hemd, Schal mit flatterndem Ende. Etwas schmaler und sprunghafter als Wick. |
| `moss` | Moos / Moss | Waldläufer: spitzer, nach hinten geknickter Hut (der Hut ist **Kleidung**), Umhang bis über die Knie, Kräuterbeutel am Gürtel. Gedrungen, ruhig. |
| `frost` | Frost / Frost | Aus dem Norden: Bommelmütze (Mütze = **Akzent**, Bommel weiß), dicker gesteppter Mantel, Fellkragen. Breiter, etwas tapsig. |

**Maße und Regeln wie die Spielerfigur** (`art/characters/player/player.json`): Frames **32×32**, Fußpunkt **(16,30)**, Blick **nach rechts** (links wird gespiegelt), Waffenhand bei **(19,19)** (die Waffe ist ein eigenes Sprite, nicht einzeichnen), Kontur 1 px `#1c1a2b`, kein Anti-Aliasing. Kopf und Körper sollen bei gleicher Höhe wie Wick bleiben (Namensschild, Lichtkreis, Trefferflächen sind darauf eingestellt).

| Datei | Frames | fps | Schleife | Inhalt |
| --- | --- | --- | --- | --- |
| `<id>_idle_4f.png` | 4 | 4 | ja | ruhiges Atmen |
| `<id>_walk_6f.png` | 6 | 10 | ja | Laufzyklus |
| `<id>_dash_3f.png` | 3 | 12 | nein | Ausweichsprung nach vorn |
| `<id>_death_6f.png` | 6 | 8 | nein | Umfallen, letzter Frame halbtransparent |
| `<id>_jump_3f.png` | 3 | 10 | nein | Seitenansicht: Absprung, Flug, Scheitel |
| `<id>_land_2f.png` | 2 | 14 | nein | Seitenansicht: Landung |
| `<id>_climb_4f.png` | 4 | 8 | ja | Seitenansicht: Klettern (Rücken zur Kamera) |
| `<id>_fall_4f.png` | 4 | 8 | nein | Sturz in die Tiefe: schrumpft zur Mitte (16,24) und verblasst |
| `<id>_down_2f.png` | 2 | 2 | ja | am Boden liegend, atmet (Koop) |
| `<id>_revive_4f.png` | 4 | 8 | nein | Aufstehen, endet im Idle-Frame (Koop) |

Optional wie bei Wick (SPRITES_V9, noch offen): `<id>_double_jump_4f.png`, `<id>_wall_slide_2f.png`. Die ersten sieben Streifen übernimmt der Code heute schon (`CharacterData.STRIP_ANIMATIONS`); `fall`, `down`, `revive` nutzen bis zum Einbau die Frames von Wick.

**Farben statt Tint-Maske:** Das Spiel färbt jetzt **vier Bereiche** frei um (je 8 Farben: Haare, Kleidung, Haut, Akzent). Es erkennt die Bereiche an festen **Schlüsselfarben**. Neue Figuren brauchen deshalb **keine** `*_tint_mask_*`-Dateien mehr, müssen aber genau diese Farben benutzen (± 3 je Kanal):

| Bereich | Grundton | weitere Töne |
| --- | --- | --- |
| Haare (bei Moos und Frost auch, wenn unter Hut/Mütze sichtbar) | `#c7542e` | Schatten `#86351c` |
| Kleidung (Hauptstoff: Hemd, Weste, Mantel, Moos' Hut) | `#3690da` | Schatten `#2a6cb0`, Licht `#6cb2ec` |
| Haut | `#f3c9a3` | Schatten `#d99c6c` |
| Akzent (Hose, zweiter Stoff, Frosts Mütze) | `#3f3b58` | Schatten `#2f2b45` |

Alles, was nicht umgefärbt werden soll (Kontur, Augen, Stiefel `#452a16`/`#6b4226`, Gürtel `#8a5a34`, Schnalle `#e0b84a`, Bommel, Metall), in **anderen** Farben der HANDOUT-Palette. Keine Zwischentöne der Schlüsselfarben erfinden, sonst bleiben diese Pixel beim Umfärben stehen. Die Masken von Wick (`player_tint_mask_*`) bleiben liegen, werden aber nicht mehr gebraucht.

### 7b. Lobby-Plätze (`art/ui/lobby/`)

Der Raum-Dialog zeigt je Spieler einen Platz (heute aus den Theme-Panels gebaut). Rahmen als **9-Slice, Rand 6 px**, Mitte einfarbig (der Inhalt liegt darüber), Mindestgröße 24×24:

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `slot_normal.png` | 24×24 | Platz eines Mitspielers: dunkles Panel `#2a2638`, Rahmen `#5d577a`/`#8f88ad` |
| `slot_own.png` | 24×24 | eigener Platz: gleicher Aufbau, Rahmen gold `#f2cf4a` mit hellerer Innenkante |
| `slot_host.png` | 24×24 | Platz des Hosts: wie normal, oben mittig eine kleine Zierleiste (die Krone sitzt rechts oben) |
| `slot_empty.png` | 24×24 | freier Platz: gestrichelter Rahmen `#5d577a`, Mitte fast durchsichtig |
| `ready.png` | 7×7 | Bereit-Häkchen grün `#5fcd62` mit Kontur |
| `../icon_world.png` | 16×16 | Welt-Symbol für die Weltenliste im Hauptmenü (kleine Landkarte oder Insel); ohne Datei steht dort die Platznummer |

Krone und Ping-Balken gibt es schon (`art/ui/icon_host.png`, `icon_ping_good.png`, `icon_ping_mid.png`, `icon_ping_bad.png`, je 16×16) und werden benutzt; eine Überarbeitung mit gleichen Namen ist willkommen (Krone darf etwas kleiner wirken, sie wird 9 px breit gezeichnet).

### 7c. Spiegel im Dorf (`art/environment/village/mirror.png`)

**16×28** (im Spiel ×2), Fußpunkt unten Mitte, 1 Frame: Standspiegel mit Holzrahmen (`#8a5a34`, Licht `#a8703f`, Schatten `#5c3a24`) auf zwei kurzen Füßen, Glas bläulich-grau mit einem schrägen Glanzstreif. Steht rechts neben dem Zuhause; mit **E** öffnet er Name und Aussehen. Optional als zweite Idee: Schneiderpuppe mit Stoffbahnen (gleiche Größe, Dateiname `tailor.png`; der Code nutzt heute nur `mirror.png`).

| Teil | Code | Verhalten |
| --- | --- | --- |
| §7a Figuren | `characters/character_data.gd`, `characters/player_look.gd` | Streifen mit genau diesen Namen ersetzen den Platzhalter (Kopf-Merkmal fällt weg); Farben über die Schlüsselfarben. |
| §7b Lobby | `ui/menus/online/lobby_slot.gd`, `ui/main_menu/slot_panel.gd` | Datei da → Rahmen/Häkchen/Welt-Symbol aus der Datei, sonst Theme-Panel bzw. gezeichnetes Häkchen. |
| §7c Spiegel | `world/village/village_mirror.gd` | Datei da → Grafik, sonst gezeichneter Platzhalter. |

Nach dem Ablegen: `godot --headless --path . --import`.

## 8. App-Icons der Browser-Version (`deploy/web/icons/`)

Die Browser-Version (game-dev/game.playsoulwick.com) lässt sich als App installieren (PWA, D-148). **Geliefert 16.10.2026** (übernommen nach `deploy/web/icons/`). `deploy/web/make_icons.py` bleibt als Ersatz (nur mit `--force`). Neue Fassungen mit **genau diesen Namen** ablegen; Ausführlich in [WEB_BUILD.md §8](../../../WEB_BUILD.md).

| Datei | Größe | Wofür | Beschreibung |
| --- | --- | --- | --- |
| `icon_512.png` | 512×512 | Android-Startbildschirm, Desktop-App | Kerze mit violettem Seelen-Kristall (wie `logo_square`) in Pixel-Art, auf 128×128 gezeichnet und ×4 skaliert (nearest neighbor). Motiv in der mittleren **80 %** (Android schneidet rund zu), Hintergrund vollflächig `#15131f` mit leichtem violettem Schein hinter der Flamme, **keine Transparenz**, kein Text. |
| `icon_180.png` | 180×180 | iOS Home-Bildschirm | Gleiches Motiv, 60×60 Pixel-Art ×3; ohne eigene Ecken oder Rahmen (iOS rundet selbst), keine Transparenz. |
| `icon_144.png` | 144×144 | Favicon, App-Liste | Gleiches Motiv, 48×48 Pixel-Art ×3; muss auch auf 32 px (Browser-Tab) erkennbar bleiben. |

Nach dem Ablegen baut Dokploy die Browser-Version beim nächsten Push neu; kein Godot-Import nötig.

## 9. Niedrige Torbögen (`art/environment/doors/`, offen seit 17.10.2026)

**Warum:** Fehlermeldung #67215ac5 („Cutted der Eingang“, Bosstor in Raum 14). Zwischen zwei Räumen liegt genau **eine** Gangkachel (M2): Über der Türkachel (32×32) folgt eine Kachel Krone (32 px), dann beginnt schon der Boden des nächsten Raums. Die hohen Bögen (64×56, Türkachel bei y 24) reichten bis 8 px unter diese Kante und wirkten oben abgeschnitten. Ein Rahmen darf deshalb höchstens **16 px über die Türkachel** ragen (`DoorStyle.MAX_FRAME_RISE`), also **48 px hoch** sein, wie die normalen Bögen (48×48) und Höhlenmäuler (64×48).

**Bis zur Lieferung** nimmt der Code aus den hohen Bildern 8 Zeilen heraus (leere Zeilen oben, gleiche Ziegelreihen in den Pfeilern, beim Bosstor Säulenzeilen), nie skaliert. Das sieht ordentlich aus, aber Ziegelreihen werden ungleich hoch und der Schlussstein flacher. Eigene Bilder mit genau diesen Namen ersetzen das automatisch (`DoorArt`, `DoorStyle._fit_rise`).

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `door_frame_boss_low.png` | 64×48, 1 Frame | Das Bosstor aus [SPRITES_V4 §4](SPRITES_V4.md) (`door_frame_boss.png`) in niedrig: zwei Säulen mit Fackelhaltern und gemalten Fackeln, Schädelkrone über dem Bogen, Ketten, biomneutral grau (`#b4aecb`/`#8f88ad`/`#5d577a`, wird je Biom eingefärbt). Säulen kürzer bzw. Bogen flacher, **Schädel und Krone ganz im Bild**, oben 1–2 px Luft. Fackelhalter bei etwa y 14. Öffnung mit `#0b0a12` füllen (der Code macht sie durchsichtig), unten 32 px breit für das Doppeltor `door_boss_open_4f.png` (32×32). |
| `door_frame_<biom>_soft_low.png` für `crypt`, `slime_grotto`, `shadow_realm`, `ember_forge` | 64×48, 1 Frame | Der gemauerte Torbogen mit **runder Öffnung** aus [SPRITES_V9 §2](SPRITES_V9.md) (`door_frame_<biom>_soft.png`) in niedrig, gleiche Farben je Biom. Ziegelreihen gleich hoch lassen, Bogenkopf etwa 6–8 px stark, Scheitel der Öffnung bei etwa y 6–8 (also 8–10 px über der Türkachel, damit der Spieler im Bogen sichtbar bleibt). Die Krone läuft durch, Umfeld durchsichtig, kein Aufsatz über dem Bogen. |
| `tunnel_shade_arch_low.png` *(optional)* | 64×48 | Innenschatten zu den niedrigen Bögen wie `tunnel_shade_arch.png` (V9 §2): weicher Verlauf (≈ 18 px) in Form der Öffnung. Fehlt er, entsteht der Schatten aus der Öffnung. |

**Für alle:** Pixel-Art ohne Anti-Aliasing, Kontur 1 px `#1c1a2b`, PNG mit Transparenz. **Fußlinie und Pivot:** unten Mitte (32, 47); die Türkachel liegt bei **(16, 16)** bis (47, 47), die Unterkante des Bildes ist die Bodenlinie der Wandfront. Die Öffnung beginnt unten in voller Türkachel-Breite (Säulen-Innenkante bei x 16 bzw. 47 oder weiter außen). Gilt auch für das spätere Bosstor je Biom aus [SPRITES_V8](../SPRITES_V13.md) (`door_frame_boss_<biom>.png`): bitte gleich in 64×48 liefern.

Nach dem Ablegen: `godot --headless --path . --import`.

## 10. Hochkant-Controller (`art/ui/touch/`, offen seit 17.10.2026)

**Wunsch des Projektmitglieds:** „Hochkant schauen wäre so cool: oben zocken und unten wie ein Gamepad. Voll retro.“ Hält man das Handy hochkant, zeigt das Spiel oben das Spielbild über die volle Breite und darunter ein **Handheld-Gehäuse** mit Steuerkreuz links, runden Knöpfen rechts (A Gold, B Violett, X und Y kleiner, Anordnung wie beim SNES: A rechts, B unten, X oben, Y links), flachen Select/Start-Knöpfen in der Mitte und einem kleinen Benutzen-Knopf oben im Feld. Heute zeichnet der Code alles als Pixel-Art-Platzhalter (`ui/touch/portrait_pixel_art.gd`); eine Datei mit genau diesem Namen ersetzt den Platzhalter automatisch (`PortraitPad`).

**Maßstab:** Der Code zeichnet je Grafikpixel eine **ganze Zahl** Bildschirmpixel (Handybreite / 176, auf 1080 px breiten Handys ×6; Option „Größe“ Klein/Groß ×5/×7). Die Teile sind **deckend** (das Gehäuse liegt nicht über dem Spiel). Icons auf den Knöpfen kommen weiter aus §1 (`icon_*.png`, auf A die aktive Waffe), Buchstaben A/B/X/Y und der Schriftzug „SOULWICK“ zeichnet der Code in einer 3×5-Pixelschrift neben die Knöpfe – bitte **nicht** in die Knopfgrafik malen. Pivot aller Teile: Mitte.

Palette: Gehäuse dunkel mit Lila-Ton `#2b2540`, Licht `#3b3356`/`#4a4170`, Schatten `#211c33`, Rille `#1c1a2b`, Kontur `#15131f`, Aufdruck `#7a7396`; A Gold `#f2cf4a` (Licht `#fff0a8`, Schatten `#c9a227`), B Violett `#a66ef0` (Licht `#cba6ff`, Schatten `#7a48c0`), kleine Knöpfe `#5d577a`/`#8f88ad`/`#3b3650`.

| Datei | Größe | Frames | Beschreibung |
| --- | --- | --- | --- |
| `portrait_panel.png` | 24×24 | 1 | **9-Slice** des Gehäuses (Rand je Seite **8 px**, die Mitte wird gestreckt): Kunststoff dunkel-lila, oben 2 px dunkle Rille unter dem Bildschirm, darunter eine helle Glanzkante, links etwas heller, rechts und unten dunkler, unten runde Ecken (Radius ≈ 5 px, außerhalb durchsichtig). Ruhige Fläche, keine Muster in der gestreckten Mitte. |
| `dpad.png` | 52×52 | 1 | Steuerkreuz von oben: Kreuz aus Armen **16 px** breit und **18 px** lang (Mittelquadrat 16×16 bei (18, 18)), erhabene Fläche `#2f2a45` mit heller Kante oben links und dunkler unten rechts, kleine Pfeile (≈ 5×3 px) außen auf jedem Arm, Mulde in der Mitte. Außerhalb des Kreuzes durchsichtig. |
| `dpad_pressed.png` | 52×52 | 1 | Gleiches Kreuz **mit allen vier Armen eingedrückt** (dunkler, helle Kante weg, Innenschatten). Der Code zeigt davon nur den gedrückten Arm (Ausschnitt oben (18,0,16,18), unten (18,34,16,18), links (0,18,18,16), rechts (34,18,18,16)); diagonal zwei Arme. Kreuz-Umriss daher **deckungsgleich** mit `dpad.png`. |
| `button_a.png` | 28×28 | 1 | Runder Knopf A, Gold: Fläche ⌀ 26 oben (Mitte bei (14, 13)), darunter 2 px „Dicke“ in dunklem Gold `#7d6114`, Glanz oben links, Kontur. Ohne Buchstaben und ohne Icon. |
| `button_a_pressed.png` | 28×28 | 1 | A gedrückt: Fläche 2 px tiefer auf der Dicke (Mitte (14, 15)), etwas dunkler, ohne Glanz. |
| `button_b.png` | 28×28 | 1 | Runder Knopf B, Violett, Aufbau wie A (Dicke `#45286f`). |
| `button_b_pressed.png` | 28×28 | 1 | B gedrückt, wie A. |
| `button_small.png` | 20×20 | 1 | Kleiner runder Knopf (X, Y, Benutzen, in der Seitenansicht Waffe wechseln), grau-lila `#5d577a`, Fläche ⌀ 18, 2 px Dicke. |
| `button_small_pressed.png` | 20×20 | 1 | Gedrückt, Fläche 2 px tiefer. |
| `button_flat.png` | 20×8 | 1 | Flacher Gummiknopf Select/Start (Pille, runde Enden), `#4a4466`, helle Oberkante, 1 px dunkle Dicke unten. Beschriftung setzt der Code darunter. |
| `button_flat_pressed.png` | 20×8 | 1 | Gedrückt: dunkler, 1 px tiefer. |

Fehlt eine `_pressed`-Datei, zeigt der Code die normale Datei heller getönt. Gelieferte runde Knöpfe: Icon sitzt genau mittig (bei Platzhaltern 1 px über der Mitte).

```json
{
  "group": "touch_portrait",
  "pixel_scale": 6,
  "items": [
    { "name": "portrait_panel", "file": "portrait_panel.png", "frame_size": [24, 24], "frames": 1, "nine_slice": { "left": 8, "right": 8, "top": 8, "bottom": 8 } },
    { "name": "dpad", "file": "dpad.png", "frame_size": [52, 52], "frames": 1, "pivot": [26, 26], "states": ["", "_pressed"] },
    { "name": "button_a", "file": "button_a.png", "frame_size": [28, 28], "frames": 1, "pivot": [14, 14], "states": ["", "_pressed"] },
    { "name": "button_b", "file": "button_b.png", "frame_size": [28, 28], "frames": 1, "pivot": [14, 14], "states": ["", "_pressed"] },
    { "name": "button_small", "file": "button_small.png", "frame_size": [20, 20], "frames": 1, "pivot": [10, 10], "states": ["", "_pressed"] },
    { "name": "button_flat", "file": "button_flat.png", "frame_size": [20, 8], "frames": 1, "pivot": [10, 4], "states": ["", "_pressed"] }
  ]
}
```

Nach dem Ablegen: `godot --headless --path . --import`.
