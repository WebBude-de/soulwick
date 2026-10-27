# Grafik-Briefing V13 – Release 1.0: Flint, Rang, Talentbaum, Zuhause, drei Säulen

> **Für Claude Design.** Das ist das **einzige offene Briefing** (D-193): Alles, was für die Vollversion fehlt, steht hier – das Neue aus dem Kern-Umbau ([KONZEPT.md](../../KONZEPT.md), D-194) und die noch offenen Teile der älteren Briefings (Teil D). Ältere, gelieferte Briefings liegen in [delivered/](delivered/) und gelten nur noch als Namensregeln.
> **Stand:** 22.10.2026 · **offen** · Lieferung wie immer nach `_inbox/`, Ablage unter `art/` mit **genau** diesen Namen; liegt eine Datei mit dem Namen da, übernimmt der Code sie, bis dahin zeichnet er Platzhalter. Nach dem Ablegen: `godot --headless --path . --import`.
> **Reihenfolge für Claude Design:** zuerst **Teil A** (Konzeptblätter und Mockups, das Projektmitglied wählt aus), dann **Teil B** in der Reihenfolge der Abschnitte, Teil D jederzeit nebenbei. **Teil C** füllen die Agenten beim Bauen.

## Stil für alles (D-174, [HANDOUT.md](../../HANDOUT.md))

- **Moderne Pixel-Art, warm und lebendig**, nicht „retro“: genug Zwischenbilder, Squash and Stretch in den Frames, Nachschwingen (Flamme, Stoff, Federn), klare Silhouetten, freundliche große Augen. Vorbilder für das Gefühl: Eastward, Celeste, Dead Cells; Maskottchen-Wirkung wie die Crewmates aus Among Us.
- Dungeon atmosphärisch und dunkel, Dorf und Zuhause süß und gemütlich; harmlos (Zielgruppe ab 13, Jüngere spielen mit): kein Blut.
- Kein Anti-Aliasing, PNG mit Transparenz, Kontur 1 px `#1c1a2b`, Palette des Handouts (Gold `#f2cf4a`, Text `#e9e4d2`, Panel `#2a2638`/`#3b3650`, Kanten `#5d577a`/`#8f88ad`, Seelen-Violett `#a66ef0`, Kristall `#dcbcff`), Blick nach rechts (links spiegelt der Code).
- Animationen als waagerechte Streifen `<name>_<animation>_<n>f.png`; zu jeder Figur ein `<name>.json` mit Frame-Größe, Pivot, Ankern und fps (wie `art/characters/npcs/chicken.json`).
- **Kein Licht einmalen** auf Spielgrafik: Lichtschein und Glühen macht das Licht-System. Flammen selbst dürfen hell sein (`#fff3c4` Kern, `#ffd166`, `#ff8a3c`, Glut `#e04e2a`). Ausnahme: große Illustrationen für Menü und Stores (B2).
- UI-Icons 16×16 mit 1 px Luft, auf dunklem Panel lesbar; Spielmaßstab 32-px-Kacheln, Spielfiguren 32×32.

## Teil A – Konzeptblätter und Mockups zuerst

Mockups sind Orientierung, keine pixelgenaue Vorlage ([design/README.md](../README.md)); Maße in Mockup-Pixeln 480×270 (das Spiel rechnet hoch). Ablage `docs/design/responses/` (Bilder) mit einer Zeile in [responses/README.md](../responses/README.md).

| # | Datei | Inhalt |
| --- | --- | --- |
| A1 | `art/companions/flint/flint_concept_sheet.png` (frei, z. B. 384×192) | **Flint in drei Entwürfen** nebeneinander, je groß (≈ 64 px) und in Spielgröße (16×16), dazu je eine Pose mit dem Huhn: (a) kleiner Wachs-Stummel mit Gesicht und Stummelbeinchen, Docht mit Flamme oben; (b) etwas schlankere, höhere Kerze, nur wenn er so sympathisch bleibt (Projektmitglied: „lieber etwas höher als schmaler, damit er nicht wie ein Quadrat wirkt“); (c) rundes Wachs-Tröpfchen mit Docht-Antenne. Gemeinsam: Flamme als Erkennungszeichen, **Flamme orange** (`#fff3c4` Kern, `#ffd166`, `#ff8a3c`, Glut `#e04e2a`, D-198), Körper warmes Weiß/Creme; entschieden: die **höhere, schlanke Kerze**, im Spiel etwa 12 px hoch (D-205). Keine schwebende Seele (D-175). |
| A2 | `responses/13_flint_erklaert.png` (**geliefert 22.10.2026 (V13b)**, dazu `20_flint_erklaert_ingame.png`, `20_flint_massstab.png`; nur Vorlage, Flamme darin noch violett) | **„Flint erklärt“:** Spielbild Dorf von oben; Flint ist aus der Welt in die Ecke **unten rechts** ins UI geflogen, dort groß (≈ 48×48) in einem runden oder Kerzen-Rahmen, links daneben seine Sprechblase mit zwei Zeilen und „Weiter ▸“, oben dezent „Überspringen“. Zweites Bild: dieselbe Szene als Hochkant-Handy (Flint über dem Controller). Drittes Bild: Geleit-Raum im Dungeon, Kamera zeigt den Weg des Dorfbewohners mit gestrichelter Lichtspur, Flint sagt „Er hat 5 Leben – beschützt ihn!“. |
| A3 | `responses/14_zuhause_talentbaum.png` (**geliefert 22.10.2026**, dazu `14b_zuhause_cozy.png`) | **Zuhause innen** (gemütliche Stube: Holzboden, Fenster mit Mondlicht, Kamin, Bett, Spiegel, in der Mitte ein **Kerzen-Altar**) und daneben der **Talentbaum** als Vollbild-Dialog: drei Pfade als Kerzenäste nebeneinander – **Wind** (Tempo, türkis-weiß), **Glut** (Kraft, orange-rot), **Seele** (Zauber, violett) –, je vier Ränge von unten nach oben, Knoten als kleine Flammen (aus, verfügbar, gesetzt, Schlussstein), oben „Talentpunkte: 3“, unten „Umskillen (kostenlos)“. |
| A4 | `responses/15_dorf_drei_saeulen.png` (**geliefert 22.10.2026**) | **Dorf mit den drei Säulen**, auf einen Blick erkennbar: Schmiede (Amboss, Funken, Schild mit Schwert), Handelsposten (Waage, Kristall, Stoffbahnen), Zuhause (warmes Fenster, Kerze im Fenster, Tür offen). Je ein hängendes Schild mit eigenem Symbol und Farbe (Schmiede Gold, Handelsposten Kristall-Violett, Zuhause warmes Orange); Flint fliegt dazwischen. |
| A5 | `responses/16_rang_und_seelentor.png` (**geliefert 22.10.2026**) | **Rang und Extraktion:** (1) Dungeon-Eingang mit Anzeige „Deine Gefahr“ (keine Wahl, D-196): großes Rang-Abzeichen „Kerze II“, darunter „Gefahrenstufe 4 · +20 % Beute“; daneben dieselbe Anzeige im Koop mit den kleinen Abzeichen aller Spieler und der Gruppen-Stufe; (2) Seelentor-Dialog im Dungeon: links „Jetzt sichern: 240 Gold · 3 Kristalle“, rechts „Weiter: Tiefenbonus +40 %“; (3) Run-Ende „Rang gestiegen!“ mit Abzeichen, das aufglüht, und XP-Balken mit „+1 Talentpunkt“. |
| A6 | `responses/17_uebungsgang.png` (**geliefert 22.10.2026**, dazu `17b_uebungsgang_spielansicht.png`) | **Übungsgang:** kleiner Übungshof vor dem Dungeon (Fackeln, Strohpuppen, eine Pfeilfalle, eine Lücke mit Sprungstück in Seitenansicht, eine Puppe mit Holzschild), Schilder mit Tastensymbolen, Flint zeigt auf die nächste Station. |
| A7 | `responses/18_rang_abzeichen.png` (**geliefert 22.10.2026**) | **Rang-Abzeichen im Licht-Motiv** als Entwurfsblatt, je 32×32 und 16×16, mit Stufenmarken I–III: **Funke** (ein einzelner Funke), **Kerze** (kleine Kerze), **Flamme** (große Flamme), **Laterne**, **Leuchtfeuer** (Feuerschale mit Strahlen), **Seelenmeister** (violett-goldene Seelenflamme mit Krone). Das Licht wird von Rang zu Rang größer und wärmer, die Form bleibt auch farbenblind unterscheidbar; zwei Varianten zur Auswahl. |
| A8 | `responses/19_sturmlauf.png` (**geliefert 22.10.2026 (V13b)**, ohne Zeit und Medaillen) | **Sturmlauf in Seitenansicht:** Figur im Sprint mit Geschwindigkeitslinien und Nachbild auf einer Rampe, darüber der schnelle Weg mit Boost-Feld und Sprungfeder, unten der sichere Weg; zwei Skelette fliegen weggeschleudert aus dem Bild; oben Mitte Kombo „×7“ (keine Zeit); zweites Bild Zielbogen mit Ergebnisbanner (Münzen) und Krone über dem Ersten im Koop. Drittes Bild: Sprungprobe Stufe 3 (bewegte Plattform über Säge, Kippplattformen, Wandsprung-Schacht nach oben). |

## Teil B – Sprites für den Kern-Umbau

### B1 Flint im Spiel (Paket WK1, nach der Wahl in A1)

> **Ersetzt durch D-217 (26.10.2026):** Vorlage für Flint ist die **Website-Figur** (`soulwick-platform/apps/web/src/components/wick/wick-figure.tsx`, `wick.css`): Umriss `#1c1a2b`, Wachs `#efe6cf` mit weißen Glanzpixeln links und Schatten `#b9b3c9` rechts, kleine schmale Augen hoch oben, rosa Wangen `#f0648c`, kleiner Mund, zwei Füßchen, Docht `#3b3650`, Flamme `#ff8a3c`/`#ffb54a`/`#fff3c4`. Die Begleiter-Bilder kommen aus **`tools/generate_flint.py`** (Spielgröße nach D-205, Frames 32×32, Pivot (16,30), Blick nach links, Anker je Frame, Flammenmasken für alle Animationen); Schein und Funken macht der Code. Die V13c-Bilder sind ersetzt. Neue Flint-Grafik von Claude Design muss diese Vorlage treffen.

> **geliefert 22.10.2026 (V13c)**: schlanke Kerze mit oranger Flamme (D-198, D-205), Animationen laut `flint.json`: `idle_4f`, `move_6f`, `cast_4f`, `talk_4f`, `joy_4f`, `curious_4f`, `pulse_6f`, `point_4f`, `scared_4f`, `sad_4f`, `blink_2f`, `dim_4f`, `hurt_3f`, `sleep_2f`, Flammenmasken für `idle`, `move`, `cast`, `pulse`. Abweichend von der Tabelle: andere Frame-Zahlen und fps (der Code liest sie aus `flint.json`), Anker `flame` (8,3) und `hat` (8,4) fest statt je Frame. Reste älterer Fassungen (`idle_6f`, `joy_8f`, `pulse_8f`, `sleep_4f` und ihre Masken) nicht übernommen.

**Ablage** `art/companions/flint/` (nicht `art/characters/wick/`, dort liegt die heutige Spielfigur mit der ID `wick`). Frames **16×16**, **Pivot (8,15)**, Blick nach rechts; Schweben, Wippen und Schatten macht der Code, also in allen Frames dieselbe Grundhöhe. **Anker im JSON je Frame:** `flame` (Mitte der Flamme = Lichtquelle, Zauber-Ursprung) und `head` (Oberkante, für Hüte).

| Datei | Frames | fps | Schleife | Inhalt |
| --- | --- | --- | --- | --- |
| `flint_idle_6f.png` | 6 | 6 | ja | Schweben und Atmen, Flamme flackert, ab und zu ein Blinzeln |
| `flint_move_6f.png` | 6 | 10 | ja | Vorausfliegen, leicht nach vorn geneigt, die Flamme zieht nach hinten |
| `flint_joy_8f.png` | 8 | 12 | nein | Freude: Hüpfer mit Squash and Stretch, Augen zu Bögen, zwei, drei Funken; endet im Idle-Frame 1 |
| `flint_pulse_8f.png` | 8 | 12 | nein | Licht-Puls: holt Luft, Flamme wird groß und hell und fällt zurück (Lagerfeuer, Rang-Aufstieg) |
| `flint_cast_6f.png` | 6 | 14 | nein | **Zauber:** streckt die Ärmchen vor, die Flamme schießt kurz nach vorn; der Code setzt den Zauber-Effekt an `flame` |
| `flint_point_4f.png` | 4 | 8 | ja | zeigt mit einem Ärmchen nach rechts (Erklärungen, Übungsgang) |
| `flint_scared_4f.png` | 4 | 8 | ja | Angst (Boss, Dunkelheit): duckt sich, Flamme klein und zitternd |
| `flint_sad_4f.png` | 4 | 6 | ja | traurig neben dem Spieler „am Boden“ |
| `flint_sleep_4f.png` | 4 | 3 | ja | schläft im Dorf und im Zuhause, Flamme ganz klein |
| `flint.json` | – | – | – | Frame-Größe, Pivot, Anker `flame` und `head` je Frame, fps |
| `flint_flame_mask_6f.png` | 6 | – | – | nur die Flammenpixel aus `idle` in Graustufen (hell = Kern), sonst durchsichtig, gleicher Pivot; der Code färbt damit Kosmetik-Flammen. Gern auch für `move`, `joy`, `pulse`, `cast` (`flint_flame_mask_<anim>_<n>f.png`) |

### B2 Flint erklärt und Flint in groß (Pakete WK8, LK5)

> **Ersetzt durch D-217 (26.10.2026):** Die Porträts `flint_portrait_<laune>_<n>f.png` sind die Website-Figur zweifach (32×48 im 48×48-Rahmen, Blick nach links) und kommen aus **`tools/generate_flint.py`**; Schein und Funken im Ring macht der Code. Rahmen, Sprechblase und Pfeil bleiben wie geliefert. Das Maskottchen in `art/ui/mascot/` zeigt noch die alte Form (siehe Teil C, LK8) und muss neu nach der Vorlage kommen.

> **geliefert 22.10.2026 (V13b)**: `speech_bubble.png`, `speech_bubble_tail.png`, `guide_next_4f.png`. **geliefert 22.10.2026 (V13c)**: alle Porträt-Streifen (dazu `flint_portrait_neutral_4f`; fps laut `flint_guide_portraits.json`: talk 8, sonst 4), runder `guide_frame.png` (Mitte 48×48 frei) und das Maskottchen (`art/ui/mascot/*`; `flint_chicken_group_512.png` ist 640×384).

| Datei | Größe | Frames | Inhalt |
| --- | --- | --- | --- |
| `art/ui/flint_guide/flint_portrait_talk_6f.png` | 48×48 je Frame | 6 (10 fps, Schleife) | Flint groß für die Ecke unten rechts, Mund auf und zu, Flamme lebt; transparenter Hintergrund |
| `art/ui/flint_guide/flint_portrait_<laune>_4f.png` für `happy`, `worried`, `point`, `proud` | 48×48 | 4 (8 fps, Schleife) | Launen für die Erklärungen: freut sich, sorgt sich (Gefahr), zeigt nach links oben (auf das Erklärte), stolz (Rang-Aufstieg) |
| `art/ui/flint_guide/guide_frame.png` | 56×56 | 1 | Rahmen um das Porträt (rund oder Kerzenhalter-Form), Mitte durchsichtig |
| `art/ui/flint_guide/speech_bubble.png` | 24×24, **9-Slice** (Rand 8 px) | 1 | Sprechblase im Panel-Stil, warm, mit Spitze nach rechts unten (die Spitze als eigenes Teil `speech_bubble_tail.png`, 8×8) |
| `art/ui/flint_guide/guide_next_4f.png` | 8×8 | 4 (6 fps) | kleiner pulsierender Pfeil „Weiter“ |
| `art/ui/mascot/flint_menu_idle_8f.png` | 96×96 | 8 (8 fps, Schleife) | Flint groß im Hauptmenü, Pivot unten Mitte · **geliefert 27.10.2026 (V13d)** |
| `art/ui/mascot/flint_wave_6f.png` | 96×96 | 6 (10 fps) | winkt einmal (erster Start, Rückkehr ins Dorf) |
| `art/ui/mascot/flint_hero.png` (+ `flint_hero_512.png` ×4) | 128×128 | 1 | Heldenpose: hält die eigene Flamme wie eine Fackel hoch; Store und Keyart (eingemaltes Licht erlaubt) |
| `art/ui/mascot/flint_chicken_group.png` (+ ×4) | 160×96 | 1 | Flint und Huhn zusammen, fröhlich; Store, Ladebildschirm, Run-Ende |
| `art/ui/mascot/flint_icon_32.png` | 32×32 | 1 | Kopf und Flamme als Symbol (Lobby, Benachrichtigungen) |

### B3 Rang und Gefahr (Pakete KE1, KE2, KE3)

> **geliefert 22.10.2026** (alles aus der Tabelle).

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/ui/ranks/rank_<id>.png` für `spark`, `candle`, `flame`, `lantern`, `beacon`, `soul_master` | 32×32 | Abzeichen nach der Wahl in A7 (Funke, Kerze, Flamme, Laterne, Leuchtfeuer, Seelenmeister); Licht wächst mit dem Rang, Form klar unterscheidbar |
| `art/ui/ranks/rank_<id>_16.png` | 16×16 | kleine Fassung für Lobby-Platz, Gildenliste, Rangliste |
| `art/ui/ranks/rank_pips.png` | 3 × 8×8 | Stufenmarke I, II, III (der Code setzt sie unter das Abzeichen) |
| `art/ui/ranks/rank_soul_master_glow_4f.png` | 4 × 32×32 | Flackern der Seelenmeister-Flamme |
| `art/ui/ranks/rank_up_burst_8f.png` | 8 × 64×64 | Aufglühen beim Rang-Aufstieg (Strahlen und Funken), Pivot Mitte |
| `art/ui/icon_danger.png` | 16×16 | Symbol der Gefahrenstufe (Totenkopf mit kleiner Flamme) |
| `art/ui/icon_talent_point.png` | 16×16 | Talentpunkt (kleine Kerzenflamme mit Funkel) |

### B4 Seelentor und Extraktion (Paket KE3)

> **geliefert 22.10.2026** (alles aus der Tabelle).

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/environment/props/soul_gate_idle_8f.png` | 8 × 48×64, Pivot unten Mitte | **Seelentor** statt des heutigen `exit_portal_6f.png`: steinerner Bogen mit Seelen-Violett und Gold, wirbelnder Kern, kleine Seelen steigen auf. Darf größer und feierlicher sein als heute, weil es jetzt die wichtigste Entscheidung im Run ist |
| `art/environment/props/soul_gate_open_6f.png` | 6 × 48×64 | Tor erscheint (Kern entfaltet sich aus einem Funken) |
| `art/effects/soul_gate_enter_8f.png` | 8 × 48×48 | Spieler wird ins Tor gezogen (Lichtsäule, Funken) |
| `art/effects/return_stone_cast_8f.png` | 8 × 48×48 | Rückkehrstein zerbricht und öffnet ein Tor |
| `art/ui/icon_secure.png`, `art/ui/icon_depth_bonus.png` | 16×16 | „Jetzt sichern“ (Truhe mit Schloss), „Tiefenbonus“ (Pfeil nach unten mit Funkel) für den Tor-Dialog |

### B5 Talentbaum und Zauber (Pakete KE6, KE7, KE8)

> **geliefert 22.10.2026**: Talentbaum-UI, 16 Talent-Icons, fünf `spell_<id>.png`, `spell_slot.png`, alle Effekt-Streifen. Nicht übernommen (laut Teil C KE7 nicht nötig): `spell_cooldown_mask.png`, `touch/icon_spell.png`, `input/input_q.png`.

**Talentbaum-UI** (`art/ui/talents/`):

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `path_wind.png`, `path_ember.png`, `path_soul.png` | 24×24 | Pfad-Symbole: Feder mit Windlinie (türkis-weiß), Glut-Herz (orange-rot), Seelenflamme (violett) |
| `node_locked.png`, `node_available.png`, `node_taken.png`, `node_capstone.png` | 22×22 | Knotenrahmen: kalt und dunkel, glimmend mit Rand, brennend, große Schlussstein-Kerze; Icon kommt mittig darauf |
| `node_taken_glow_4f.png` | 4 × 22×22 | Flackern eines gesetzten Knotens |
| `branch_<pfad>.png` für `wind`, `ember`, `soul` | 8×8, kachelbar senkrecht | Ast bzw. Wachsfaden zwischen den Knoten in der Pfadfarbe (der Code kachelt ihn) |

**Talent-Icons** (`art/ui/talents/talent_<id>.png`, je 16×16): `light_foot` (Schuh mit Windlinie), `dash_training` (Schuh mit Pfeil), `swift_blade` (Dolch mit Tempo-Strichen), `evasion` (Silhouette mit Nachbild), `double_dash` (zwei Pfeile), `wind_runner` (Lichtspur), `vitality` (Herz mit Plus), `might` (Hammer mit Funken), `steadfast` (Fuß auf Stein), `shield_breaker` (gebrochener Schild), `second_heart` (zwei Herzen), `ember_heart` (glühendes Herz), `spell_power` (Flamme mit Plus), `focus` (Sanduhr mit Flamme), `staff_master` (Stab mit Stern), `second_spell_slot` (zwei Flammen).

**Zauber** – HUD-Symbol (`art/ui/spells/spell_<id>.png`, 16×16) und Effekt (`art/effects/spells/`), Pivot jeweils Mitte, Effekte ohne eingemaltes Licht-Glühen nach außen (Licht macht der Code):

| Zauber | Symbol | Effekt-Datei | Größe, Frames | Inhalt |
| --- | --- | --- | --- | --- |
| Lichtblitz | `spell_light_flash.png` | `light_flash_6f.png` | 6 × 96×96, 18 fps | Ring aus weißem Licht dehnt sich aus, Funken |
| Seelenschild | `spell_soul_shield.png` | `soul_shield_6f.png` + `soul_shield_loop_4f.png` | 6 × 40×40, Schleife 4 × 40×40 | violette Blase um die Figur, schließt sich und schimmert |
| Flammenring | `spell_flame_ring.png` | `flame_ring_8f.png` | 8 × 96×96, 16 fps | Feuerring von der Mitte nach außen |
| Irrlichter | `spell_will_o_wisp.png` | `wisp_4f.png` + `wisp_trail_3f.png` | 4 × 10×10, Spur 3 × 8×8 | kleine Lichtkugel mit Gesicht, Spur dahinter |
| Heilfunke | `spell_heal_spark.png` | `heal_spark_8f.png` | 8 × 64×64 | grüngoldene Funken steigen auf, kleines Herz |

Dazu: `art/ui/spells/spell_slot.png` (20×20, Rahmen im HUD neben den Waffen), `spell_cooldown_mask.png` (20×20, der Code dreht ihn als Uhr), `art/ui/touch/icon_spell.png` (Touch-Knopf im Stil von SPRITES_V10 §1), `art/ui/input/input_q.png` (Tastenkappe Q wie die vorhandenen Kappen; falls die Belegung anders wird, sagt Teil C es).

### B6 Zuhause innen (Pakete KE8, WK7)

> **geliefert 22.10.2026** (alles aus der Tabelle und `home_door_open.png`); `home_interior_tiles.png` kam als 256×64 (nur Zeile 1 belegt).

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/environment/home/home_interior_tiles.png` | 256×96 (8×3 Kacheln à 32) | Holzdielen A/B, Teppichkante, Wand mit Holzvertäfelung (vorn, Ecken links/rechts), Fenster mit Mondlicht (2 Kacheln), Tür nach draußen |
| `art/environment/home/candle_altar_idle_6f.png` | 6 × 32×48, Pivot unten Mitte | **Kerzen-Altar** mit drei Kerzen in Pfadfarben (türkis, orange, violett), Flammen leben; hier sitzt der Talentbaum |
| `art/environment/home/candle_altar_ready_4f.png` | 4 × 32×48 | Altar leuchtet stärker, wenn Talentpunkte frei sind |
| `art/environment/home/fireplace_6f.png` | 6 × 64×64 | Kamin mit Feuer (gemütlich, Flint schläft gern davor) |
| `art/environment/home/bed.png`, `chest.png`, `rug_round.png`, `shelf.png`, `plant_pot.png` | 64×48, 32×32, 64×32, 32×48, 16×32 | Grundmöbel; später kaufbar und frei stellbar (WK7), darum je eine Draufsicht mit sauberem Fuß |
| `art/environment/home/pet_bed.png` | 32×16 | Körbchen für Flint (später Pets) |

Der Spiegel ist da (`mirror.png`, SPRITES_V10 §7c). Außen: `art/environment/buildings/home.png` bekommt eine **offene Tür** als zweiten Zustand `home_door_open.png` (gleiche Größe wie `home.png`, nur Tür offen, warmes Licht im Türrahmen).

### B7 Schmiede und Handelsposten (Pakete KE4, KE5)

> **geliefert 22.10.2026** (Schmiede, Handelsposten, drei Schilder).

**Schmiede** (`art/ui/forge/`, 16×16, wenn nicht anders genannt): `forge_arsenal.png` (Waffenständer), `forge_second_slot.png` (zwei Waffen gekreuzt), `forge_smith.png` (Hammer auf Amboss mit Funken), `forge_shield_plate.png` (Schildplatte), `forge_lantern.png` (Laterne), `weapon_level_pips.png` (5 × 6×6, Stufenmarken I–V), `masterwork_glint_6f.png` (6 × 16×16, Glanz über Waffen-Icons der Stufe V). Die Waffen-Icons gibt es (`icon_sword.png` usw.).

**Handelsposten** (`art/ui/trading/`, 16×16): Proviant `boost_gold_rain.png` (Münzen regnen aus einer Wolke), `boost_lucky_amulet.png` (Kleeblatt-Amulett), `boost_clear_sight.png` (offenes Auge mit Funkel), `boost_healing_potion.png` (Trank, rot-rosa), `boost_soul_anchor.png` (Anker mit Seele), `boost_return_stone.png` (Runenstein mit Tor-Zeichen), `boost_keen_nose.png` (Lupe mit Funkel); Handelsstufen `trade_slot.png` (Rucksack mit Plus), `trade_luck.png` (Würfel mit Stern, **kein** Glücksspiel-Motiv wie Spielautomat), `trade_merchant_friend.png` (Handschlag).

**Dorf-Schilder:** Die drei Säulen-Schilder bekommen nach A4 eine einheitliche Familie: `art/ui/sign_forge.png`, `sign_trading.png`, `sign_home.png` neu im gleichen Format wie heute (gleiche Größe, gleiche JSON-Namen), Farbe je Säule (Gold, Kristall-Violett, warmes Orange).

### B8 Übungsgang (Paket WK10)

> **geliefert 22.10.2026** (alles aus der Tabelle).

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/environment/tutorial/training_dummy_idle_2f.png`, `_hit_4f.png`, `_break_6f.png` | 32×32, Pivot (16,30) | Strohpuppe auf Pfahl: wippt, wird getroffen (Stroh fliegt), fällt um |
| `art/environment/tutorial/training_dummy_shield_idle_2f.png`, `_block_4f.png` | 32×32 | Puppe mit Holzschild: blockt normale Treffer, das Spezial (Rechtsklick) bricht den Schild |
| `art/environment/tutorial/station_sign.png` | 24×32 | Holzschild auf Pfahl, leere Fläche 16×12 für ein Eingabe-Symbol (der Code setzt es) |
| `art/environment/tutorial/station_flag_2f.png` | 2 × 16×24 | Fähnchen „Station geschafft“ (zu, wehend) |
| `art/environment/tutorial/tutorial_gate.png` | 64×48 | Tor am Ende des Übungsgangs mit Schild „Dungeon“ (Torbogen-Regeln wie SPRITES_V10 §9: höchstens 48 hoch) |

### B9 Kosmetik und Huhn (Pakete WK2, WK3)

> **geliefert 22.10.2026**: Hüte der Figur (`art/cosmetics/hats/`) und Symbole (`art/ui/cosmetics/`). Flint-Hüte und Huhn mit Flint **nicht übernommen** (Flint-Form neu, D-198); offen. **geliefert 22.10.2026 (V13b)**: sechs Flint-Hüte als Zugabe (`flint_hat_{tophat,crown,wizard,beanie,leaf,horns}.png`, 16×16, Anker `hat` (8,4)); die drei Partnerlook-Hüte für Flint und das Huhn mit Flint (Flamme violett) weiter offen. **geliefert 22.10.2026 (V13c)** (Flint-Teil): `flint_hat_{candle_crown,chicken,flower_wreath}.png` (16×16 auf der hohen Form, Anker `hat` (8,4)) und das Huhn mit Flint (`chicken_flint_{ride_6f,peck_10f,nap_4f}.png`, abweichend Frames 32×32, Pivot (16,30), fps laut `chicken_flint.json`). Hüte und Symbole der Figur für den Partnerlook weiter offen.

**Drei Hüte als Partnerlook** (Figur und Flint, ein Motiv in zwei Größen). Ein Hut ist ein Einzelbild, Pivot unten Mitte, Unterkante sitzt 2 px tief; passt auf alle vier Figuren (`wick` = Wick, `ember`, `moss`, `frost`), benutzt **keine** Schlüsselfarben der Figuren (Haare `#c7542e`, Kleidung `#3690da`, Haut `#f3c9a3`, Akzent `#3f3b58`), höchstens 12 px über dem Kopf.

| Thema | Figur `art/cosmetics/hats/` | Flint `art/cosmetics/flint_hats/` | Symbol `art/ui/cosmetics/` |
| --- | --- | --- | --- |
| Hühnermütze (gestrickt, roter Kamm, kleiner Schnabel) | `hat_chicken.png` (16×14) | `flint_hat_chicken.png` (10×8) | `icon_hat_chicken.png` (16×16) |
| Kerzenkrone (Krone mit drei Kerzen statt Zacken) | `hat_candle_crown.png` (16×12) | `flint_hat_candle_crown.png` (10×7) | `icon_hat_candle_crown.png` |
| Blütenkranz (Gelb, Rosa `#f0648c`, Weiß, Blätter) | `hat_flower_wreath.png` (16×8) | `flint_hat_flower_wreath.png` (10×5) | `icon_hat_flower_wreath.png` |

Optional: Rückenansicht `hat_<thema>_back.png` fürs Klettern.

**Huhn mit Flint** (`art/characters/npcs/`, Frames 32×24, Pivot (16,22)): `chicken_flint_ride_6f.png` (Flint reitet, 10 fps, Schleife), `chicken_flint_peck_10f.png` (Huhn pickt nach der Flamme, Flint springt hoch, Schnabel kurz rußig, 12 fps), `chicken_flint_nap_4f.png` (kuscheln und schlafen, 3 fps), dazu `chicken_flint.json`.

### B10 Seitenansicht 2.0 (Pakete SV1–SV5, D-195)

> **Seit D-216 (26.10.2026):** Boost-Feld, Zielbogen, Startbogen und Krone werden nicht mehr gebraucht (Hindernislauf statt Sturmlauf; auch A8 ist damit gegenstandslos). Die Dateien bleiben liegen, nicht neu bestellen.

> **geliefert 22.10.2026**: Umgebung, `bat`, `shield_bearer`, Tempo-Effekte, `crown.png`. **geliefert 22.10.2026 (V13b)**: `player_sprint_6f`/`player_stomp_3f` mit Masken, `<id>_sprint_6f`/`<id>_stomp_3f` (ersetzen die vorläufigen), `spike_hedgehog_*` neu (`idle_4f`, `walk_6f`, `death_6f`, `refuse_3f`).

Kacheln 32×32 wie die bestehende Seitenansicht (`art/environment/side/`), je Biom (`crypt`, `slime_grotto`, `ember_forge`, `shadow_realm`) wo `<biom>` steht.

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/characters/player/player_sprint_6f.png` + Maske, je Figur `<id>_sprint_6f.png` | 6 × 32×32, Pivot (16,30), 14 fps | Sprint bei vollem Schwung: weit vorgebeugt, Arme hinten, Haare und Schal wehen |
| `art/characters/player/player_stomp_3f.png` + Maske, je Figur `<id>_stomp_3f.png` | 3 × 32×32 | Stampfen: Füße nach unten, Aufprall, Rückfeder |
| `art/environment/side/moving_platform_<biom>.png` | 96×16 | bewegte Plattform (Stein oder Holz mit Kette/Schiene), kachelbar in 32er-Stücken |
| `art/environment/side/spring_4f.png` | 4 × 32×32 | Sprungfeder: ruhig, gedrückt, schnellt hoch, schwingt nach |
| `art/environment/side/tilt_platform_<biom>_4f.png` | 4 × 64×16 | Kippplattform: ruhig, wackelt, kippt, fällt |
| `art/environment/side/saw_8f.png`, `saw_rail.png` | 8 × 32×32, Schiene 32×8 kachelbar | Säge auf Schiene, dreht sich |
| `art/environment/side/collapse_bridge_<biom>_6f.png` | 6 × 32×16 | Brückenstück, das hinter dem Spieler einstürzt |
| `art/environment/side/boost_pad_4f.png` | 4 × 32×8 | Boost-Feld im Boden mit Pfeilen, pulsiert in Seelen-Violett |
| `art/environment/side/slope_<biom>.png` | 32×32 und 64×32 | Schrägen 45° und 22,5° (auf und ab) passend zu `rock_blob_<biom>_soft` |
| `art/environment/side/checkpoint_lantern_2f.png` | 2 × 16×32 | Laterne als Rücksetzpunkt (aus, an) |
| `art/environment/side/rush_finish_arch.png`, `rush_start_gate.png` | 64×48 | Zielbogen mit Flagge und Startbogen des Sturmlaufs (höchstens 48 hoch) |
| `art/characters/enemies/<id>/<id>_walk_4f.png` und `<id>_death_5f.png` für `bat` (fliegt), `spike_hedgehog`, `shield_bearer` | je 32×32, Pivot (16,30) | neue Seiten-Gegner (SV4): Fledermaus im Sprungbogen, Stachel-Igel (Stacheln oben, nicht stampfbar), Schildträger (Schild vorn) |
| `art/effects/speed_lines_4f.png`, `side_afterimage.png`, `side_stomp_burst_5f.png`, `side_boost_flash_4f.png` | 64×32 / 32×32 / 32×16 / 32×32 | Tempo-Effekte (SV5) |
| `art/ui/rush/crown.png` | 16×12 | Krone für den Ersten im Ziel (Koop), im Ergebnisbanner und kurz über der Figur |

## Teil C – Nachträge der Agenten (jederzeit)

**Regel für alle Agenten (AGENTS.md §8):** Fehlt beim Bauen eine Grafik, trägt der Agent hier **sofort** eine Zeile ein – Datei, Größe, Frames, Beschreibung, für welches Paket – und baut bis zur Lieferung einen Platzhalter aus Code. Der Bericht nennt die Zeile unter „Grafik nötig“. Das Projektmitglied gibt den Teil C bei der nächsten Runde an Claude Design.

| Paket | Datei | Größe, Frames | Beschreibung | eingetragen |
| --- | --- | --- | --- | --- |
| WK1 | `art/companions/flint/flint_curious_4f.png` (Eintrag in `flint.json`, Anker `flame` und `head` je Frame) | 16×16, 4 Frames, 8 fps, Schleife, Pivot (8,15) | **Neugier** (Geheimnis in der Nähe, KONZEPT §7.1; fehlt in §B1): Flint neigt sich nach rechts vor, Kopf leicht schief, große Augen, Flamme zuckt neugierig nach vorn; dieselbe Grundhöhe wie `idle`. Bis dahin zeigt der Code `idle` mit Neigung | 22.10.2026 · **geliefert 22.10.2026 (V13c)** (5 fps, Anker fest) |
| WK8 | `art/ui/flint_guide/flint_portrait_<laune>_<n>f.png` (Ergänzung zu §B2, keine neue Datei) | 48×48 je Frame, wie §B2 | **Blickrichtung links:** Flint sitzt unten rechts und schaut zur Sprechblase links von ihm (bei `point` zeigt das Ärmchen nach links oben). Figur mittig mit 4 px Luft zum Rand, damit sie in den runden Rahmen `guide_frame.png` (56×56, Mitte 48×48 frei) passt; kein Rahmen und kein Hintergrund im Porträt. Bis zur Lieferung zeigt der Code die Spielkerze dreifach vergrößert und gespiegelt im gezeichneten Ring | 22.10.2026 · **geliefert 22.10.2026 (V13c)** |
| KE6 | `art/effects/talents/ember_wave_6f.png` | 6 × 128×128, 16 fps, Pivot Mitte | Glutherz: orange-rote Glutwelle, die als Ring von der Figur nach außen läuft (Radius 2,5 Kacheln im Spiel, der Code skaliert), Funken und Asche, ohne eingemaltes Leuchten (Licht macht der Code) | 22.10.2026 · **geliefert 22.10.2026 (V13c)** (12 fps) |
| KE6 | `art/effects/talents/wind_trail_4f.png` | 4 × 32×16, kachelbar waagerecht, Schleife 8 fps | Windläufer: türkis-weiße Lichtspur mit Windlinien, die der Dash am Boden hinterlässt; der Code kachelt sie entlang des Dashs und blendet sie über 2 s aus | 22.10.2026 · **geliefert 22.10.2026 (V13c)** (10 fps) |
| KE7 | Korrektur zu §B5: `art/ui/input/input_q.png`, `art/ui/spells/spell_cooldown_mask.png`, `art/ui/touch/icon_spell.png` | – | **Nicht malen:** Zaubern liegt nicht auf Q (Q wechselt schon die Waffe), sondern auf **F** (Gamepad RB); Buchstaben zeigt das Spiel als Text-Kappe, eine Bild-Kappe braucht es nicht. Die Abklingzeit-Uhr im HUD zeichnet der Code über dem Symbol. Der Touch-Zauberknopf zeigt das Symbol des ausgerüsteten Zaubers (`spell_<id>.png`), ein eigenes `icon_spell.png` ist nur Rückfall und nicht nötig. Gebraucht werden aus §B5 die fünf `spell_<id>.png`, `spell_slot.png` und die Effekt-Streifen | 22.10.2026 · **geliefert 22.10.2026** (die drei Dateien nicht übernommen) |
| Meldung #214a0ff5 (rooms-dev) | `art/environment/trials/pendulum_blade_8f.png` (Ersatz) | 8 × **64×64** (statt 32×64), Pivot Mitte oben (32,2), 8 fps | Pendelklinge der Prüfung „Spießrutenlauf“: Kette mit Sichelklinge, Frames 0 und 4 ganz ausgeschwungen (± 25°), 2 und 6 hängend. Die gelieferten 32 px breiten Frames schneiden die Klinge in den ausgeschwungenen Frames ab („immer noch ständig abgeschnitten“). Bis dahin zeigt der Code nur den hängenden Frame 2 und dreht ihn um den Ankerpunkt | 22.10.2026 · **geliefert 22.10.2026 (V13b)** |
| Meldung #5724ea7c (rooms-dev) | `art/environment/doors/door_frame_boss.png` (Ersatz) | 64×**60** (statt 64×56), Pivot wie bisher (Fuß des Torbogens) | Bosstor: der Bogen reicht bis an die Bildoberkante, die Kontur über dem Bogen fehlt („Torrahmen abgeschnitten“). Bitte 4 px Luft oben mit geschlossener Kontur `#1c1a2b`; die tiefe Version `door_frame_boss_low.png` (64×48) ebenso. Bis dahin zieht der Code die oberste Zeile als Kontur nach | 22.10.2026 · **geliefert 22.10.2026 (V13b)** (mit `door_frame_boss_low.png`) |
| SV4 | Ergänzung zu §B10: `art/characters/enemies/bat/bat.json`, `spike_hedgehog/spike_hedgehog.json`, `shield_bearer/shield_bearer.json` | Pivot (16,30), fps je Animation | Zu den drei neuen Seiten-Gegnern je eine JSON wie `chicken.json` (Pivot = Fußpunkt; bei der Fledermaus die Unterkante des Körpers, sie fliegt). `idle` ist freiwillig, ohne `idle` nimmt der Code `walk` (bei der Fledermaus der Flug-Loop). Bis zur Lieferung zeichnet der Code Platzhalter (Fledermaus mit Flügelschlag, Igel mit Stacheln, Skelett stahlblau mit Schild) | 22.10.2026 · **geliefert 22.10.2026**; `spike_hedgehog.json` **geliefert 22.10.2026 (V13b)** |
| SV4 | `art/characters/enemies/spike_hedgehog/spike_hedgehog_refuse_3f.png` | 3 × 32×32, Pivot (16,30), 12 fps, einmal | Stachel-Igel stellt die Stacheln auf (Stampfen oder Umrennen abgelehnt, der Spieler nimmt Schaden): Frame 1 duckt sich, 2 Stacheln lang und gespreizt, 3 zurück. Bis dahin zeichnet der Code die Stacheln kurz länger | 22.10.2026 · **geliefert 22.10.2026 (V13b)** (10 fps) |
| SV4 | `art/characters/enemies/shield_bearer/shield_bearer_refuse_3f.png` | 3 × 32×32, Pivot (16,30), 12 fps, einmal | Schildträger stößt den Schild nach vorn (Umrennen abgelehnt, der Spieler prallt ab): Ausholen, Stoß mit Funken am Schildrand, zurück. Bis dahin blitzt die Figur auf | 22.10.2026 · **geliefert 22.10.2026 (V13b)** (abweichend: Schild über den Kopf mit Blitz, 10 fps) |
| CR6 (D-205) | `art/environment/height/platform_front_<biom>.png`, `platform_top_<biom>.png`, `stairs_half_<biom>.png` für `crypt`, `slime_grotto`, `shadow_realm`, `ember_forge` | Vorderkante 32×16 (kachelbar waagerecht) oder 128×16 (links, Mitte, rechts, einzeln: die Enden einer Reihe mit Kontur), Fläche 32×32 (kachelbar, mit 2-px-Lichtkante nach Süden), Treppe 32×16 (zwei Stufen à 8 px) | Plattformen und Emporen in **halber Höhe** (16 px statt einer ganzen Wand), Biomfarben wie `rock_blob_<biom>_soft`; Lichtkante oben, Schatten am Fuß (den Fußschatten zeichnet der Code, nicht ins Bild malen). Die Vorderkante liegt in der oberen Hälfte der Klippenreihe, die Leiter (`ladder.png`, untere 16 px) steht davor. Bis zur Lieferung zeichnet der Code Platzhalter in den Felsfarben des Bioms (`PlateauArt`) | 22.10.2026 · Platzhalter gebaut (CR6) · **geliefert 27.10.2026 (V13d)** |
| WK7 (D-205) | **Möbel-Katalog** → **Teil E** (E1 Möbel, E2 Dorf-Deko) | je Möbel Draufsicht mit sauberem Fuß und `footprint` im JSON | viele Varianten je Möbelart (Betten, Sessel, Regale, Tische, Teppiche, Pflanzen, Lampen, Bilder) in mehreren Stilen; Startmöblierung „basic cozy“ aus Antwort 20 §1 zuerst | 22.10.2026 |
| KE8 (D-205) | `art/environment/home/home_interior_tiles.png` Zeile 2 und 3 (Nachlieferung, gleiche Datei 256×96) | 8×3 Kacheln à 32×32 | Geliefert ist nur Zeile 1 (Dielen, Teppichkante, Wand vorn, Ecken, Fenster) und die Tür bei (0,32). Es fehlen: **Seitenwand links/rechts** (Holzbalken senkrecht, 32×32), **Wandsockel unten** (Abschluss der Stube nach Süden mit Türlücke), **Fußleiste** unter der Wandvertäfelung, **Dielen C** (Astloch) und **Schwelle** vor der Tür. Bis dahin zeichnet der Code Seitenwände und Sockel als dunkle Balken | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| KE8 (D-205) | `art/environment/home/nightstand.png`, `armchair.png`, `bookshelf_full.png`, `wall_picture.png`, `broom.png`, `window_sill_flower.png` (Eintrag je Teil in `home_props.json`, Pivot unten Mitte, `footprint` in Kacheln) | 16×24, 32×32, 32×48, 24×16, 8×24, 24×12 | Startmöblierung „basic cozy“ aus Antwort 20 §1: Nachttisch mit kleiner Lampe (Lampe leuchtet `#ffd166`), Ohrensessel vor dem Kamin (rot wie im Mockup 14b), volles Bücherregal, kleines gerahmtes Dorfbild, Besen in der Ecke, Fensterbank mit Blume. Bis dahin zeichnet der Code einfache Platzhalter in denselben Maßen | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| KE8 (D-205) | `art/environment/home/home_window_night.png`, `home_window_day.png` | je 48×40 | Fenster der Stube: nachts Mond und 2–3 Sterne, am Tag Hellblau mit Vögeln (Antwort 20 §1). Bis dahin nimmt der Code die Fenster-Kacheln `window_a/b` und tönt sie am Tag heller | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| WK10 | `art/environment/tutorial/training_dummy_shield_break_6f.png` (Eintrag in `tutorial.json` wie `training_dummy_break`) | 6 × 32×32, Pivot (16,30), 8 fps, einmal | Ergänzung zu §B8: die Puppe mit Holzschild **zerbricht** (Station 4, das Spezial trifft): Frame 1–2 der Schild splittert (Bretter und Nagel fliegen nach rechts), 3–6 die Puppe kippt um und bleibt liegen wie bei `training_dummy_break` (letzter Frame liegend, leicht verblasst). Bis dahin zeichnet der Code einen Platzhalter (Pfahl kippt, Brett daneben) | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| KE5 (Integration) | `art/ui/touch/icon_return_stone.png` | 16×16 | Touch-Knopf „Rückkehrstein einsetzen“ (Runenstein mit Tor-Zeichen, im Stil der Touch-Knöpfe aus SPRITES_V10 §1); bis dahin zeichnet der Knopf `art/ui/trading/boost_return_stone.png` | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #a8a87397 (enemies-dev, Glutgolem) | `art/projectiles/lava_ball_4f.png` | 4 × 16×16, Pivot (8,8), 10 fps, Schleife | **Lava-Ball** des Glutgolems im Flug (Bogenwurf): glühender Klumpen mit dunkler Kruste, die aufreißt, Funken hinten; ohne eingemaltes Leuchten (Licht und Bogen macht der Code, er skaliert ×3 und zeichnet einen Bodenschatten). Bis dahin zeichnet der Code eine orange Kugel mit gelbem Kern | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #a8a87397 (enemies-dev, Glutgolem) | `art/effects/lava_impact_6f.png` | 6 × 64×64, Pivot Mitte, 14 fps, einmal | **Aufschlag** des Lava-Balls: Lava spritzt kreisförmig auseinander, Krustenbrocken und Tropfen fliegen, letzter Frame fast leer. Der Code skaliert auf den Aufschlagkreis (Radius ~46 px). Bis dahin nimmt der Code die Explosion `explosion_6f.png` in Orange | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #a8a87397 (enemies-dev, Glutgolem) | `art/effects/lava_pool_4f.png` | 4 × 32×32, Pivot Mitte, 5 fps, Schleife | **Lavapfütze** nach dem Aufschlag (Bodenschaden, 2,5–3,5 s): flache, unregelmäßige Glutlache mit dunklem Krustenrand, Blasen platzen; Draufsicht, kachelt nicht. Der Code skaliert ×3 (~96 px) und blendet sie am Ende aus. Bis dahin zeichnet der Code eine orange Lache mit Rand | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #a8a87397 (enemies-dev, Glutgolem) | `art/effects/stomp_ring_6f.png` | 6 × 128×128, Pivot Mitte, 14 fps, einmal | **Stampf-Ring** (betäubt kurz): Bodenwelle aus Rissen, Staub und Glutfunken läuft vom Golem als Ring nach außen (Radius ~150 px im Spiel, der Code skaliert), ohne eingemaltes Leuchten. Bis dahin zeichnet der Code einen braun-orangen Ring (`RingWave`) | 22.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #587a95a9 (player-dev, WK8) | `art/ui/flint_guide/flint_portrait_<laune>_<n>f.png` (Ersatz aller sechs Streifen: talk, neutral, happy, worried, point, proud) | 48×48 je Frame wie §B2, Frames und fps wie geliefert | **Flamme oben abgeschnitten** („Flamme abgeschnitten“): In den V13c-Porträts beginnt die Flamme in Zeile 2 ohne obere Kontur, sie läuft flach aus dem Bild. Bitte die Flamme ganz zeigen, mit geschlossener Spitze und Kontur `#1c1a2b`, oben mindestens 2 px Luft; Flint dafür etwas tiefer oder minimal kleiner setzen (Füße höchstens bis Zeile 46). Bis dahin schiebt der Code jeden Frame 1 px nach unten und setzt eine 3-Zeilen-Kappe in den Farben der obersten Flammenzeile auf (`FlintPortraitArt.close_cut_flames`); eine gelieferte geschlossene Flamme bleibt unverändert | 23.10.2026 · **erledigt 26.10.2026 durch D-217** (Porträts aus `tools/generate_flint.py`, Reparatur entfernt) |
| LK8 (player-dev, D-217) | `art/cosmetics/flint_hats/flint_hat_*.png` (alle neun, Ersatz, gleiche Namen) und `flint_hats.json` | je 16×16, Pivot unten Mitte, Anker `hat` neu | **Flint-Hüte auf die Website-Figur:** Die V13b/V13c-Hüte passen auf die alte schmale Kerze. Flint im Spiel ist jetzt 8 px breit (Kontur oben 6 px), Oberkante der Kontur bei (16,18) im 32×32-Frame, Docht in Spalte 16, Flamme 7 px hoch darüber: Hut 8–10 px breit, sitzt auf der Oberkante und lässt Docht und Flamme frei (Loch oder seitlich schräg). Vorlage: `art/companions/flint/flint_idle_36f.png` Frame 0. Hüte werden im Code noch nicht gezeichnet | 26.10.2026 · **geliefert 27.10.2026 (V13d)** |
| LK8 (player-dev, D-217) | `art/characters/npcs/chicken_flint_{ride_6f,peck_10f,nap_4f}.png` (Ersatz, gleiche Namen und Frames) | wie geliefert (32×32, Pivot (16,30)) | **Huhn mit Flint** zeigt noch die alte Kerze: Flint als Website-Figur in Spielgröße (wie `art/companions/flint/flint_idle_36f.png`: Umriss, Glanz links, Schatten rechts, kleine Augen, rosa Wangen, Füßchen, dreistufige Flamme), sonst unverändert. Im Code noch nicht benutzt | 26.10.2026 · **geliefert 27.10.2026 (V13d)** |
| LK8 (player-dev, D-217) | `art/ui/mascot/flint_menu_idle_8f.png`, `flint_wave_6f.png`, `flint_hero.png` (+ `_512`), `flint_chicken_group.png` (+ `_512`), `flint_icon_32.png` (Ersatz, gleiche Namen und Größen) | wie §B2 | **Maskottchen nach der Website-Figur** (V13c: große dunkle Augen, rissiges Wachs, Flamme abgeschnitten): dieselbe Figur wie `wick-figure.tsx` in groß, gern ganzzahlig vergrößert (Raster 16×24 ×4 = 64×96 passt in den 96er-Frame) oder fein nachgezeichnet im selben Stil, Flamme ganz mit Luft nach oben; kein eingemaltes Licht außer beim Hero. Alternativ kann `tools/generate_flint.py` Menü-Streifen und Symbol erzeugen, sobald der Ordner freigegeben ist. Im Code noch nicht benutzt (LK5) | 26.10.2026 · **geliefert 27.10.2026 (V13d)** |
| WK12 (village-dev) | `art/environment/village/animal_heart.png` | 8×7, 1 Frame | **Herz** über einem Dorftier, das man streichelt oder füttert: rundes Pixel-Herz in Rosa `#f0648c` mit hellem Glanzpunkt oben links, Kontur `#1c1a2b`. Der Code lässt es pixelweise aufsteigen und in Stufen ausblenden (×2). Bis dahin zeichnet der Code genau dieses Herz (`VillageAnimal.HEART_ROWS`) | 23.10.2026 · Platzhalter gebaut · **geliefert 27.10.2026 (V13d)** |
| WK12 (village-dev) | `art/characters/npcs/chicken_react_4f.png` (Eintrag in `chicken.json`, Animation `react`) | 4 × 16×16, Pivot (8,14), 8 fps, Schleife | **Huhn wird gefüttert:** pickt schnell die Körner vor sich auf (Kopf runter, hoch), plustert sich einmal stolz auf, Flügel kurz gelupft. Füße in allen Frames auf y = 14. Bis dahin zeigt der Code `idle` (pickt langsam), einen Hüpfer und „Gack!“ | 23.10.2026 · Platzhalter (idle) · **geliefert 27.10.2026 (V13d)** |
| WK12 (village-dev) | `art/characters/npcs/cat_react_4f.png` (Eintrag in `cat.json`, Animation `react`) | 4 × 16×16, Pivot (8,14), 6 fps, Schleife | **Katze wird gestreichelt:** sitzt, Augen zu (zufriedene Striche), schmiegt den Kopf zur Seite, Schwanz ringelt sich langsam, 1 px Atmen. Unterkante y = 14. Bis dahin zeigt der Code `idle`, zwei Herzen und „Schnurr …“ | 23.10.2026 · Platzhalter (idle) · **geliefert 27.10.2026 (V13d)** |
| WK12 (village-dev) | `art/characters/npcs/dog_idle_4f.png`, `dog_walk_6f.png`, `dog_react_4f.png`, `dog.json` (wie `cat.json`) | je 16×16 (oder 20×16), Pivot (8,14), idle 4 fps, walk 10 fps, react 8 fps | **Dorfhund** (drittes Dorftier, „weitere Tiere“ aus D-196): kleiner, freundlicher Hund mit Schlappohren, warmes Braun/Creme; `idle` sitzt und wedelt, `walk` trabt, `react` (gestreichelt) hüpft vor Freude, Zunge raus, Schwanz wedelt schnell. Läuft am Feld im Südosten. Ohne `dog_idle_*` erscheint er nicht (kein Platzhalter) | 23.10.2026 · **geliefert 27.10.2026 (V13d)** |
| Meldung #b28a0f5e (rooms-dev) | `art/environment/props/soul_gate_idle_8f.png`, `soul_gate_open_6f.png` (Ersatz, gleiche Namen) | 8 bzw. 6 × 48×64, Pivot unten Mitte (24,63) wie bisher | **Seelentor mit Tiefe** („sieht so 2D aus“): das gelieferte Tor ist eine flache Vorderansicht. Bitte in der Draufsicht-Perspektive der Räume: die Pfeiler zeigen ihre Oberseite (2–3 px Lichtkante), das Tor steht auf einem **Steinsockel mit einer Stufe**, dessen Oberseite man sieht (Fuß 40–44 px breit, unterste 6 px), der Wirbel liegt etwas zurückgesetzt im Bogen. Keinen Bodenschatten und kein Bodenlicht malen: den Schatten am Fuß und den violetten Lichtschein auf dem Boden davor zeichnet der Code (`SoulGate.SHADOW_HALF_WIDTH`, `FloorGlow`). Bis dahin zeigt der Code das gelieferte Tor mit Schatten und Bodenlicht | 23.10.2026 · Platzhalter (Schatten, Bodenlicht) · **geliefert 27.10.2026 (V13d)** |

## Teil D – Noch offen aus älteren Briefings

Gleicher Inhalt wie in den alten Briefings, hier gesammelt, damit es nur eine Liste gibt. Hintergrund und Maße der Nachbarteile stehen im genannten alten Briefing in [delivered/](delivered/).

### D1 Räume v2 (früher SPRITES_V8)

| Datei | Größe | Beschreibung |
| --- | --- | --- |
| `art/environment/doors/door_frame_boss_<biom>.png` | **64×48** (Torbogen-Regel aus D3) | Bosstor je Biom (heute ein graues Tor, nur eingefärbt) |
| `art/environment/doors/door_boss_chains_4f.png` | 4 × 64×48 | Ketten des Bosstors, die beim Öffnen rasseln und fallen |
| `art/environment/corridors/corridor_<biom>_{straight,stairs,niche}.png` | je 96×64 | Gänge zwischen den Räumen: gerade, mit Höhenversatz, mit Nische und Tropfstelle |
| `art/environment/village/dungeon_entrance_v2.png` | 96×80, Pivot (48,80) | Ruine mit Treppe nach unten, Ketten, Seelen-Rune (`responses/06_dorf.md`); Fackelflammen bei (35,51) und (61,51), Raben auf dem Sturz bei ca. (48,18) |
| `art/environment/village/entrance_flame_bowl_6f.png` | 6 × 32×32, Pivot unten Mitte | Seelenflammen-Becken vor dem Eingang |
| `art/environment/village/ravens_4f.png` | 4 × 32×16 | Raben: sitzen, picken, Flügel oben, Flügel unten |
| `art/environment/village/village_tiles_v2.png` | 256×32 (8 Kacheln) | Pflaster A/B, Felskante A/B (nur Zeile 6–28 fest), Treppe links/rechts, Steinplatten A/B |
| `art/environment/village/chronicle_board.png` | 24×30 | leere Kreidetafel auf Staffelei vor der Chronik; Schieferfläche x3–20 / y3–16 |
| `art/ui/taskbar_frame.png` | 48×24 (9-Slice) | Rahmen der Aufgabenleiste |
| `art/ui/banner_stripe.png` | 8×32 | Farbstreifen links am Banner (in Modusfarbe getönt) |
| `art/ui/countdown_digits.png` | 3 × 24×32 | große Ziffern 3, 2, 1 |
| `art/ui/objective_icons.png` | 10 × 16×16 | Aufgabenleisten-Icons (wie `door_mode_symbols`, farbig) |
| `art/characters/npcs/lost_chicken_lantern_idle_4f.png`, `_walk_4f.png` | 16×16 | Huhn mit Laterne am Hals (seltene Geleit-Figur) |
| `art/environment/objectives/relic_pedestal_<biom>.png` | 32×32 | Podest der Reliquie je Biom |
| `art/environment/trials/collapse_marker_4f.png` | 4 × 32×32 | Einbruch-Warnmarke: Risse und rotes Glühen |
| `art/environment/spawn/spawn_<biom>_idle_4f.png` | 4 × 32×32 | Ruhezustand der Gegnerquellen, leichtes Glimmen |
| `art/environment/deco/puddle_4f.png` | 4 × 32×32 | Pfütze unter der Tropfstelle |
| `art/environment/deco/dust_fall_4f.png` | 4 × 16×16 | Staub an der eingestürzten Säule |
| `art/environment/deco/gravestone.png` | 32×32 | einzelner Grabstein für Opferstellen (kein Quellen-Grab) |
| `art/environment/deco/shallow_water_edge.png` | 4 × 32×32 | weicher Rand für Wasserbecken (heute eckig) |

### D2 Makeover (früher SPRITES_V9 §1, §3, §6, §7)

- **Fels-Innenecken, Nachlieferung:** Das Set `rock_blob_<biom>_soft_inner.png` ist eingebaut, aber abgeschaltet (`RockTerrain.USE_DELIVERED_INNER = false`), weil die Bögen 4–8 px neben dem Eckpunkt liegen statt die geraden Randbänder fortzusetzen, und `fill_left/right/both` nach außen gewölbt sind. Gewünscht: Bogen genau dort, wo das obere und das seitliche Band enden (Band 2 px hell + 2 px mittel, Innenradius 4 px), Füllkacheln als Hohlkehle (konkav, Radius 5 px) in den Farben von `rock_blob_<biom>_soft.png`.
- **Wasser und Fels-Deko:** `water_glint_4f.png` (optional, 4 × 32×32), `deco_group_large_<biom>_{1,2}.png` (96×64), `fog_floor_4f.png` (4 × 64×32), `wall_cracked_<biom>_soft.png` und `wall_niche_soft.png` (32×48, Fels statt Ziegel an Geheimnischen), `abyss_tiles_<biom>_soft.png` (wie `abyss_tiles_crypt_soft`), `wall_breach_cave_<biom>_6f.png` (wie `wall_breach_6f`, Fels statt Mauerrahmen).
- **Seitenansicht Runde 2:** `player_double_jump_4f.png` + Maske (4 × 32×32, Pivot (16,30), zusammengerollt, keine Drehung einmalen), `player_wall_slide_2f.png` + Maske (Wand links bei x ≈ 4), `art/effects/side_jump_puff_4f.png` (4 × 32×16), `side_land_dust_5f.png` (5 × 48×16), `side_double_jump_ring_5f.png` (5 × 32×16), `side_wall_dust_3f.png` (3 × 16×16); dazu je Figur `<id>_double_jump_4f.png`, `<id>_wall_slide_2f.png`.
- **Höhe (optional):** `stairs_cut_<biom>_soft.png` (32×32), `plateau_floor_<biom>.png` (32×32, kachelbar), später `player_climb_top_4f.png` + Maske (Klettern von oben, Rücken zur Kamera).

### D3 Eingabe, Torbögen, Hochkant (früher SPRITES_V10 §2, §9, §10)

- **14 Eingabe-Symbole neu:** `input_pad_a`, `_b`, `_x`, `_y`, `input_pad_lb`, `_rb`, `_lt`, `_rt` (Buchstaben in einer 3×5-Pixelschrift wie der Platzhalter), `input_gesture_tap`, `_hold`, `_swipe` (Hand mit erkennbaren Fingern), `input_escape` (Kappe mit Pfeil), `input_pad_select` (zwei Rechtecke), `input_touch_interact` (Hand statt Oval). Maße und Kappenfarben wie in [delivered/SPRITES_V10.md](delivered/SPRITES_V10.md) §2.
- **Niedrige Torbögen** (`art/environment/doors/`, höchstens 48 px hoch, Pivot (32,47), Türkachel bei (16,16)–(47,47)): `door_frame_boss_low.png` (64×48, Schädel und Krone ganz im Bild; **geliefert 22.10.2026 (V13b)**), `door_frame_<biom>_soft_low.png` für alle vier Biome (runde Öffnung, Scheitel bei y 6–8), optional `tunnel_shade_arch_low.png`.
- **Hochkant-Controller** (`art/ui/touch/`, deckend, Pivot Mitte, Palette Gehäuse `#2b2540`): `portrait_panel.png` (24×24, 9-Slice Rand 8), `dpad.png` und `dpad_pressed.png` (52×52, Arme 16 breit, 18 lang), `button_a(_pressed).png` und `button_b(_pressed).png` (28×28, Gold bzw. Violett), `button_small(_pressed).png` (20×20), `button_flat(_pressed).png` (20×8). Keine Buchstaben in die Knöpfe malen. Genaue Beschreibung und JSON: [delivered/SPRITES_V10.md](delivered/SPRITES_V10.md) §10.

### D4 Kleinkram (früher SPRITES_V5 §7)

- `art/effects/nova_ring_6f.png`: Frames 5–6 sind innen schwarz gefüllt; der Code filtert es, ein sauberer Neuexport (innen transparent) ist willkommen.

## Teil E – Einrichten: Möbel-Katalog (WK7) und Dorf-Deko (WK5)

**Wofür:** Spieler richten ihr Zuhause ein und schmücken ihr Dorf (D-202, D-205: „Später kann man ganz nice Möbelstücke holen, dann müssen ganz viele generiert werden, verschiedene Varianten“). Gekauft wird mit Gold, gestellt auf einem Raster (32 px), gedreht und wieder weggeräumt. Stil wie die gelieferte Stube (`art/environment/home/*`): gemütlich, warm, Holz und Stoff, klare Kontur `#1c1a2b`, **kein eingemaltes Licht** (Lampen und Kerzen leuchten über das Licht-System).

**Regeln für jedes Teil:**
- Draufsicht schräg von vorn wie die Stube, Fuß unten sauber (Kontaktlinie zum Boden), Pivot unten Mitte.
- Größe in ganzen Kacheln: 1×1, 2×1, 1×2, 2×2, 3×2 (32 px je Kachel); Höhe darf über die Kachel hinausragen (z. B. Regal 32×64).
- **Drehen:** je Teil zwei Ansichten, `_front` und `_side` (die Gegenseite spiegelt der Code); runde oder symmetrische Teile nur `_front`.
- Zu jeder Gruppe ein JSON (`furniture_<gruppe>.json`) mit je Teil: `name`, `file`, `frame_size`, `pivot`, `footprint` (Kacheln breit × tief), `blocks` (ja/nein: Spieler läuft drum herum), `light` (optional: Punkt und Farbe, wenn es leuchtet), `anim` (optional, z. B. Kaminfeuer 6f).
- **Varianten:** jede Möbelart in **drei Stilen**: `rustic` (helles Holz, Leinen), `cozy` (dunkles Holz, warme Stoffe, Kissen), `soul` (Seelen-Violett `#a66ef0` und Gold `#f2cf4a` als Akzent, edel) – das ist der Sammel-Anreiz.
- Ablage `art/environment/home/furniture/<gruppe>/<art>_<stil>_<ansicht>.png`, z. B. `seating/armchair_cozy_front.png`.

### E1 Möbel für das Zuhause (Innenraum 960×576)

| Gruppe | Arten (je 3 Stile × 2 Ansichten) | Kacheln |
| --- | --- | --- |
| `beds` | Bett einzeln, Bett breit, Hängematte | 2×3, 3×3, 3×1 |
| `seating` | Sessel, Stuhl, Bank, Sitzkissen, Sofa | 1×1, 1×1, 2×1, 1×1, 3×1 |
| `tables` | Esstisch, Nachttisch, Schreibtisch, Teetisch rund | 2×2, 1×1, 2×1, 1×1 |
| `storage` | Truhe, Kommode, Regal leer, Regal voll (Bücher, Gläser), Kleiderschrank | 1×1, 2×1, 1×1 (32×64), 1×1 (32×64), 2×1 (64×64) |
| `light` | Stehlampe, Kerzenständer, Laterne, Wandleuchte, Lichterkette (Wand) | 1×1, 1×1, 1×1, Wand 1, Wand 2 |
| `rugs` | Teppich rund, rechteckig klein, rechteckig groß, Läufer | 2×2, 2×1, 3×2, 3×1 (flach, nicht blockierend) |
| `wall` | Bild (3 Motive: Dorf, Flint, Huhn), Spiegel klein, Regalbrett, Uhr, Wandteppich | Wand 1–2 |
| `plants` | Topfpflanze klein, groß, Hängepflanze, Blumenkasten am Fenster | 1×1 |
| `cozy` | Kamin (2. Variante zum Kamin der Stube, 6f Feuer), Ofen, Lesesessel-Ecke, Körbchen für Pets (3 Größen) | 2×1, 1×1, 2×2, 1×1 |
| `fun` | Huhn-Plüsch, Flint-Kerzenhalter, Pokal, Trophäen-Wand (für Erfolge, ER1), Weltkarte | 1×1, Wand |

Dazu je Stil eine **Tapete/Wand-Variante** und ein **Boden-Variante** für `home_interior_tiles` (gleiche Kachelaufteilung wie heute), damit man die Stube umfärben kann.

### E2 Dorf-Deko (draußen, 32-px-Raster auf Wegen und Wiesen)

| Gruppe | Arten (je 2–3 Varianten) | Kacheln |
| --- | --- | --- |
| `garden` | Blumenbeet (4 Farben), Hecke gerade/Ecke, Baum klein, Busch, Kürbisse | 1×1 bis 2×1 |
| `paths` | Pflasterstein-Platte (3 Muster), Trittsteine, Holzsteg | 1×1 (flach) |
| `lights` | Laternenpfahl, Lichterkette zwischen zwei Pfosten, Feuerschale, Fackel | 1×1, 3×1 |
| `fences` | Holzzaun gerade/Ecke/Tor, Steinmauer niedrig | 1×1 |
| `water` | Brunnen klein (4f Wasser), Vogeltränke, Teich klein | 1×1, 2×2 |
| `fun` | Vogelscheuche, Bank, Wegweiser, Huhn-Statue, Flint-Statue, Banner (Gilde) | 1×1 |

**Reihenfolge:** zuerst je Gruppe ein Stil (`cozy`) als Probe, dann die anderen Stile.

## Was der Code damit macht

| Abschnitt | Paket | Einbau |
| --- | --- | --- |
| B1, B9 Hüte | WK1, WK2 | Begleiter nach `flint.json`, Licht an `flame`, Flammenfarbe über die Maske, Hüte an `head` |
| B2 | WK8, LK5 | Erklär-Ecke unten rechts, Sprechblase, Hauptmenü und Begrüßung |
| B3 | KE1, KE2 | Rang-Abzeichen in Hauptmenü, Lobby, Gilde, Rangliste, Eingang, Run-Ende |
| B4 | KE3 | Seelentor ersetzt `exit_portal_6f.png` |
| B5 | KE6–KE8 | Talentbaum-Dialog, Zauber im HUD, Effekte an Flints Flamme |
| B6 | KE8, WK7 | Innenraum-Szene des Zuhauses, Möbel |
| B7 | KE4, KE5 | Schmiede- und Handelsposten-Seiten, Dorf-Schilder |
| B8 | WK10 | Übungsgang |
| B9 Huhn | WK3 | Dorf, Ladebildschirm, Run-Ende |
| Teil D | GR1 | Austausch der Platzhalter, Schalter umlegen |
