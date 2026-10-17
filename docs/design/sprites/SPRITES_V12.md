# Grafik-Briefing V12 – Soulwick: Wick, Huhn und erste Kosmetik

> **Für Claude Design.** Wick ist das neue Maskottchen von Soulwick (D-175): ein kleines Docht-Wesen (eine lebende Kerze mit Flamme), im Spiel der persönliche Begleiter jedes Spielers ab dem ersten Start. Das Huhn ist das Neben-Maskottchen. Dazu die ersten Kosmetik-Teile, mit denen das Kosmetik-System getestet wird. Konzept: [KONZEPT_BEGLEITER_KOSMETIK.md](../../KONZEPT_BEGLEITER_KOSMETIK.md), Pakete WK1–WK4 in [ROADMAP.md](../../ROADMAP.md).
> **Stand:** 17.10.2026 · **offen** · Ablage unter `art/` mit genau diesen Namen (Lieferung wie immer nach `_inbox/`). Liefert ihr eine Datei, übernimmt der Code sie; bis dahin zeichnet er Platzhalter.
> **Website-Grafiken** mit Wick (Startseite, Vorschaubilder, Social) bekommen ein **eigenes Briefing im Plattform-Repo** (`soulwick-platform`, Website-Grafiken unter `apps/web/public/brand/` als WebP); hier nur Spiel und Stores.

## Stil (D-174)

- **Moderne Pixel-Art, warm und lebendig** – wie heute gemacht, nicht „retro“: weiche Bewegung mit genug Zwischenbildern, Squash and Stretch in den Frames, Nachschwingen (Flamme, Ohren, Federn), klare Silhouette, freundliche große Augen. Vorbilder für das Gefühl: Eastward, Celeste; für Maskottchen-Wirkung: die Crewmates aus Among Us (einfache Form, sofort wiedererkennbar, auch als winziges Icon).
- Regeln aus [HANDOUT.md](../../HANDOUT.md): kein Anti-Aliasing, PNG mit Transparenz, Kontur 1 px `#1c1a2b`, Palette des Handouts, Blick nach rechts (links spiegelt der Code), Animationen als waagerechte Streifen `<name>_<animation>_<n>f.png`, zu jeder Figur ein `<name>.json` mit Frame-Größe, Pivot, Ankern und fps (wie `art/characters/npcs/chicken.json`).
- **Kein Licht einmalen:** Lichtschein und Glühen um die Flamme macht das Licht-System des Spiels. Die Flamme selbst darf hell sein (`#fff3c4` Kern, `#ffd166`, `#ff8a3c`, Glut `#e04e2a`).
- Harmlos und niedlich (Zielgruppe ab 13, Jüngere spielen mit, D-173): kein Blut, keine Gewalt-Gags.

## 0. Konzeptblatt zuerst (Aussehen ist OFFEN, D-175)

| Datei | Größe | Inhalt |
| --- | --- | --- |
| `art/companions/wick/wick_concept_sheet.png` | frei, z. B. 384×192 | **drei Entwürfe** für Wick nebeneinander, je groß (≈ 64 px hoch) und in Spielgröße (16×16), dazu je eine Pose mit dem Huhn. Richtungen zum Ausprobieren, alle als Docht-Wesen (Wachs-Körper, Docht, Flamme; keine schwebende Seele, D-175): (a) kleiner Wachs-Stummel mit Gesicht und Stummelbeinchen, Docht mit Flamme oben; (b) wie (a), aber eine etwas schlankere, höhere Kerze – nur, wenn Wick damit genauso sympathisch bleibt (Projektmitglied 17.10.2026: „Vielleicht machst du die Kerze etwas dünner … aber dann sieht er auch nicht mehr so sympathisch aus“); (c) rundes Wachs-Tröpfchen mit Docht-Antenne. Gemeinsam: Flamme als Erkennungszeichen, warmes Weiß/Creme als Körper, ein Akzent im Seelen-Violett `#a66ef0`. |

Das Projektmitglied wählt einen Entwurf; alle weiteren Teile entstehen danach in diesem Stil.

## 1. Wick im Spiel (Begleiter)

**Ablage:** `art/companions/wick/` (neuer Ordner für Begleiter und spätere Pets; nicht `art/characters/wick/`, weil die heutige Standard-Spielfigur schon die ID `wick` trägt und Figuren unter `art/characters/<id>/` liegen, D-175 OFFEN).

**Maße:** Frames **16×16** (wie Huhn und Mini-Schleim; die Spielfigur ist 32×32, Wick reicht ihr etwa bis zur Hüfte). **Pivot (8,15)**, Blick nach rechts. Das Schweben und Wippen über dem Boden macht der Code, ebenso den Schatten; bitte in allen Frames dieselbe Grundhöhe zeichnen. **Anker im JSON:** `flame` (Mitte der Flamme, Lichtquelle) und `head` (Oberkante des Kopfs, für Hüte) je Frame.

| Datei | Frames | fps | Schleife | Inhalt |
| --- | --- | --- | --- | --- |
| `art/companions/wick/wick_idle_6f.png` | 6 | 6 | ja | Schweben und Atmen, Flamme flackert, ab und zu ein Blinzeln |
| `art/companions/wick/wick_move_6f.png` | 6 | 10 | ja | Schweben bzw. Hüpfen nach vorn, leicht nach vorn geneigt, die Flamme zieht nach hinten |
| `art/companions/wick/wick_joy_8f.png` | 8 | 12 | nein | Freude: kleiner Hüpfer mit Squash and Stretch, Augen zu Bögen, zwei, drei Funken; endet im Idle-Frame 1 |
| `art/companions/wick/wick_pulse_8f.png` | 8 | 12 | nein | Licht-Puls: Wick holt Luft, die Flamme wird groß und hell und fällt zurück; endet im Idle-Frame 1 |
| `art/companions/wick/wick_scared_4f.png` *(optional)* | 4 | 8 | ja | Angst (Boss-Auftritt, Dunkelheit): duckt sich, Flamme klein und zitternd |
| `art/companions/wick/wick_sleep_4f.png` *(optional)* | 4 | 3 | ja | schläft im Dorf, Flamme ganz klein, ein „z“ ist nicht nötig |
| `art/companions/wick/wick_sad_4f.png` *(optional)* | 4 | 6 | ja | traurig neben dem Spieler „am Boden“ (Koop) |
| `art/companions/wick/wick.json` | – | – | – | Frame-Größe, Pivot, Anker `flame` und `head` je Frame, fps |

**Flamme getrennt (für Kosmetik-Flammenfarben):**

| Datei | Größe | Frames | Inhalt |
| --- | --- | --- | --- |
| `art/companions/wick/wick_flame_mask_6f.png` | 16×16 | 6 | nur die Flammenpixel aus `wick_idle_6f` in Graustufen (hell = Kern), alles andere durchsichtig, gleicher Pivot. Der Code färbt damit die Flamme um (z. B. Türkis, Gold); die normalen Streifen behalten die warme Standardflamme. Für `move`, `joy`, `pulse` gern ebenso (`wick_flame_mask_<anim>_<n>f.png`), sonst nimmt der Code die Idle-Maske. |

## 2. Wick als Maskottchen in groß (Menü und Stores)

Für Hauptmenü, Ladebildschirm, Store-Bilder und Trailer. **Illustration im Pixel-Stil, modern**: gleiche Pixelgröße überall, keine weichen Verläufe, aber gern viele Details, sattes Licht auf der Figur (eingemalt ist hier erlaubt, weil kein Licht-System darüber liegt).

| Datei | Größe | Frames | Inhalt |
| --- | --- | --- | --- |
| `art/ui/mascot/wick_menu_idle_8f.png` | 96×96 je Frame | 8 (8 fps, Schleife) | Wick groß im Hauptmenü: schwebt, Flamme flackert, blinzelt; transparenter Hintergrund, Pivot unten Mitte. Der Code zeichnet ×2 bzw. ×3. |
| `art/ui/mascot/wick_wave_6f.png` | 96×96 je Frame | 6 (10 fps, keine Schleife) | winkt einmal (Begrüßung beim ersten Start, Rückkehr ins Dorf) |
| `art/ui/mascot/wick_hero.png` | 128×128, ausgeliefert zusätzlich ×4 als `wick_hero_512.png` | 1 | Heldenpose: hält die eigene Flamme hoch wie eine Fackel, Funken; für Store-Grafiken und Keyart |
| `art/ui/mascot/wick_chicken_group.png` | 160×96, ausgeliefert zusätzlich ×4 | 1 | Wick und das Huhn zusammen, fröhlich, für Store-Bilder, Ladebildschirm und Run-Ende |
| `art/ui/mascot/wick_icon_32.png` | 32×32 | 1 | nur Kopf und Flamme, als kleines Symbol (Lobby, Benachrichtigungen, Favicon-Kandidat) |

Store-Größen (Kapseln, Feature-Grafik) bleiben wie in [SPRITES_V11.md](SPRITES_V11.md); ob Wick dort in neue Fassungen kommt, entscheidet das Projektmitglied nach der Lieferung.

## 3. Huhn mit Wick (Gags)

Das vorhandene Huhn (`art/characters/npcs/chicken_*`, 16×16, Pivot (8,14)) bleibt; neu sind gemeinsame Szenen. Frames **32×24**, Pivot **(16,22)**, beide Figuren im Stil von §0/§1.

| Datei | Frames | fps | Schleife | Inhalt |
| --- | --- | --- | --- | --- |
| `art/characters/npcs/chicken_wick_ride_6f.png` | 6 | 10 | ja | Wick reitet auf dem laufenden Huhn, wackelt mit, Flamme weht nach hinten |
| `art/characters/npcs/chicken_wick_peck_10f.png` | 10 | 12 | nein | Das Huhn pickt nach Wicks Flamme, Wick springt erschrocken hoch, das Huhn hat kurz eine rußige Schnabelspitze und schüttelt sich; endet friedlich nebeneinander |
| `art/characters/npcs/chicken_wick_nap_4f.png` | 4 | 3 | ja | beide schlafen aneinander gekuschelt, Wicks Flamme ganz klein |
| `art/characters/npcs/chicken_wick.json` | – | – | – | Frame-Größe, Pivot, fps je Animation |

## 4. Erste Kosmetik: drei Hüte als Partnerlook

Drei Themen, je ein Hut für die **Spielfigur** und einer für **Wick** (gleiches Motiv, zwei Größen). Damit testet der Code Anker, Ebenen und Anprobieren; die Teile werden später freispielbar (Konzept §5).

**Regeln:** Ein Hut ist **ein Einzelbild**; der Code setzt ihn je Frame auf den Kopf (Spielfigur: oberster deckender Punkt des Kopfs; Wick: Anker `head`). Pivot **unten Mitte**, die Unterkante sitzt 2 px tief auf dem Kopf. Hüte passen auf alle vier Figuren (`wick`, `ember`, `moss`, `frost`, [SPRITES_V10.md](SPRITES_V10.md) §7a) und benutzen **keine** Schlüsselfarben der Figuren (Haare `#c7542e`, Kleidung `#3690da`, Haut `#f3c9a3`, Akzent `#3f3b58`), damit das Umfärben sie nicht erfasst. Kein Hut höher als 12 px über dem Kopf (Namensschild und Lichtkreis sind darauf eingestellt).

| Thema | Spielfigur `art/cosmetics/hats/` | Wick `art/cosmetics/wick_hats/` | Symbol `art/ui/cosmetics/` | Beschreibung |
| --- | --- | --- | --- | --- |
| Hühnermütze | `hat_chicken.png` (16×14) | `wick_hat_chicken.png` (10×8) | `icon_hat_chicken.png` (16×16) | gestrickte Mütze in Hühnerform mit rotem Kamm und kleinem Schnabel vorn; der Gag zum Neben-Maskottchen |
| Kerzenkrone | `hat_candle_crown.png` (16×12) | `wick_hat_candle_crown.png` (10×7) | `icon_hat_candle_crown.png` (16×16) | goldene Krone mit drei kleinen Kerzen statt Zacken (Flammen als helle Pixel, kein Lichtschein); das Soulwick-Motiv |
| Blütenkranz | `hat_flower_wreath.png` (16×8) | `wick_hat_flower_wreath.png` (10×5) | `icon_hat_flower_wreath.png` (16×16) | Kranz aus kleinen Blüten (Gelb, Rosa `#f0648c`, Weiß) und Blättern; passt zum süßen Dorf (D-174) |

Optional, falls es leicht geht: dieselben drei Hüte für die Seitenansicht mit Rückenansicht (`hat_<thema>_back.png`) für das Klettern.

## Was der Code damit macht

- **Wick** (Paket WK1): Begleiter-Szene nach `wick.json`, Licht an `flame`, Flammenfarbe über `wick_flame_mask_*`; ohne Lieferung ein Platzhalter aus Code.
- **Maskottchen** (Paket LK5): Hauptmenü und Begrüßung; die ×4-Fassungen holt das Projektmitglied für Stores und Trailer.
- **Huhn mit Wick** (Paket WK3): Dorf, Ladebildschirm, Run-Ende.
- **Hüte** (Paket WK2): Kosmetik-Platz „Kopf“ für Figur und Wick, Anprobieren am Spiegel; die Symbole im Kosmetik-Menü.
- Nach dem Ablegen: `godot --headless --path . --import`.
