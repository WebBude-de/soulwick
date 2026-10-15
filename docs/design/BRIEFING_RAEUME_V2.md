# Briefing für Claude Design – Soulwick: Räume, Raumarten und Look neu denken

> **Status 15.10.2026: erledigt.** Claude Design hat geantwortet ([claude_design_antwort/](claude_design_antwort/README.md)); daraus sind D-120 bis D-144, die Pakete der Phasen 2b und 2c in [ROADMAP_AUSBAU.md](../ROADMAP_AUSBAU.md) und die Briefings [SPRITES_V8](sprites/SPRITES_V8.md) und [SPRITES_V9](sprites/SPRITES_V9.md) entstanden. Das Briefing bleibt als Anfrage zum Nachlesen.
>
> **Für Claude Design.** Eigenständig lesbar. Dazu gehören das Gameplay-Konzept [../KONZEPT_RAEUME_V2.md](../KONZEPT_RAEUME_V2.md) (zuerst lesen) und die Bilder in `docs/design/szenen/` (Übersicht und Beobachtungen: `szenen/INDEX.md`). Die Bilder zeigen den **heutigen** Stand mit allen Schwächen.
> **Stand:** 14.10.2026 · Projektmitglied + Claude (Entwicklung)

## 1. Das Spiel in drei Sätzen

Soulwick ist ein 2D-Top-down-Dungeon-Roguelite in Pixel-Art mit leichter Schrägsicht (3/4), allein oder später im Koop mit 2–4 Freunden, auf PC und Handy. Man startet im Dorf, steigt in einen endlosen, dunklen Dungeon, kämpft sich Raum für Raum durch vier Biome (Krypta, Schleimgrotte, Schattenreich, Glutkammer), sammelt Upgrades und stirbt irgendwann. Das Licht ist das Thema: Der Held trägt einen Lichtkreis, um ihn herum ist es dunkel („Das letzte Licht im endlosen Dunkel“).

## 2. Was uns stört (Projektmitglied, Playtest 14.10.2026)

- **Gameplay macht noch nicht richtig Spaß** – die Balance passt, aber es fehlt das Interessante. Jeder Raum soll sich wie eine kleine eigene Aufgabe anfühlen.
- **Minispiel-Räume statt blasser Modi:** Die heutigen Raum-Modi (Varianten) wirken nicht cool, zu ähnlich und überschneiden sich. Gewünscht sind **klare Minispiele zwischendurch**, z. B. **Capture the Flag**, **jemanden beschützen** (z. B. ein Huhn, das durch den Raum muss), Rennen, Sammeln unter Zeitdruck. Im späteren Koop auch Ideen mit Twist (z. B. ein Mitspieler sieht für die anderen wie ein Gegner aus). Jedes Minispiel soll in einem Satz verständlich sein und sich stark von den anderen abheben.
- **Gute Ansätze besser einführen:** „Seelenflamme beschützen“ ist im Kern schon so ein Minispiel, wird aber nicht gut eingeführt; man versteht beim Betreten nicht, was zu tun ist. Gesucht ist ein **Einführungs-Muster für alle Minispiele**: z. B. Raum zeigt die Aufgabe, bevor es losgeht (kurzer Kameraschwenk auf die Flamme, großes Ziel-Banner, Pfeil/Markierung, Countdown 3-2-1), klare Anzeige von Fortschritt und Gefahr (HP der Flamme, Zeit), deutliches Erfolgs-/Misserfolgs-Ende.
- **Arena nicht verständlich:** Beim Betreten wurde die Arena nicht angekündigt; erst als etwas aus der Wand kam, war klar, dass es eine Arena ist. Dann stand nach einem einzigen Kill „Welle 2 von 2“ da – das fühlte sich falsch an. Gewünscht: klare Ankündigung beim Betreten (Raum schließt sich, „Arena – 3 Wellen“, Countdown), sichtbare Wellen-Anzeige mit Fortschritt, deutlicher Übergang zwischen den Wellen; Arenen sind der „hier ist richtig was los“-Raum und kommen erst kurz vor dem ersten Boss oder danach.
- **Zu leer:** Ein Gegner und weiter in den nächsten Raum ist zu wenig; es soll immer etwas los sein (gern viele schwache Gegner am Anfang statt einzelner).
- **Woher kommen die Gegner?** Es muss deutlich sein, wo Gegner herkommen (sichtbare Quelle, Ankündigung).
- **Fackeln und Deko** wirken zufällig platziert.
- **Zwei Wege:** Bei einer Abzweigung ploppt der neue Raum plötzlich auf; das soll vorbereitet wirken (der Raum ist schon da, liegt im Dunkeln, oder eine schöne Übergangsanimation).
- **Zu zufällig:** Pflanzen, Steine, Fallen und Kisten wirken hingestreut, manchmal liegen Steine parallel nebeneinander, Fallen stehen ohne Grund im Weg.
- **Zu starr und eckig:** Am Ende sind es rechteckige Räume mit großen, leeren Flächen; die Wege sind „quadratisch“. Es fehlt das Lebendige.
- **Raumarten unklar:** Die Arten unterscheiden sich zu wenig, man versteht die Unterschiede nicht. Sie sollen sich **stark** unterscheiden: im Aussehen, im Ablauf, im Gefühl.
- **Gegner-Auftritt:** Gegner tauchen einfach auf. Besser: aus dem Boden kriechen, aus der Wand brechen, aus Särgen steigen … und in der Arena **nur** aus den Wänden.
- **Hinterhalt:** „Gegner brechen aus der Wand“ war unverständlich und sah nicht gut aus.
- **Abgrund-Räume:** machen keinen Spaß, wirken wie leere Fläche mit Loch.
- **Wände:** Wände sollen **überall einheitlich schräg (3/4-Sicht)** zu sehen sein, auch die Seitenwände, nicht teils flach von oben und teils mit Vorderseite. Einbauten in der Wand (rissige Geheimwand, Nischen, Tore) müssen bündig in der Mauerlinie sitzen; heute ragt z. B. die rissige Wand als Block über die Mauer hinaus und Nischen-Stücke stehen wie Fremdkörper im Raum.
- **Türen und Übergänge:** Torbögen wirken oben abgeschnitten, Türen passen nicht ganz in die Wand, Seitentüren sehen wie Leitern aus, Gänge zwischen Räumen sind langweilig.
- **Dorf und Dungeon-Eingang:** sollen deutlich schöner werden.
- **UI:** wirkt insgesamt langweilig; ein UI-Rework ist gewünscht.

## 3. Was es heute gibt (zum Verstehen der Bilder)

**Ablauf eines Zyklus (5 Räume, Biomwechsel alle 15 Räume):** Kampf → Kampf → Kampf mit Upgrade → Spezialraum → Miniboss; jeder 15. Raum ist ein Boss, danach ein Lagerfeuer als Rast vor dem nächsten Biom. Räume liegen als Kette aneinander, verbunden durch kurze Gänge mit Türen; Ausgänge oben, links oder rechts.

| Raumart heute | Was passiert | Wie es aussieht |
| --- | --- | --- |
| **Normaler Kampfraum** | Gegner besiegen, Tür geht auf | Vorlage aus 6 Formen (Rechteck, L, Kreuz, Ring, Zwei Kammern, Säulenhalle) in S/M/L + zufällig gestreute „Zutaten“ (Deckung, Fallen, Innenmauer-Stücke, Lichtinseln, Fässer) |
| **Katakombe** | wie normal, Gänge 1 Tile breit, Truhe in der tiefsten Sackgasse | Labyrinth aus schmalen Gängen |
| **Arena** | 2–3 Wellen, Gegner treten aus Wandtoren | Rechteck/Kreuz/Säulenhalle mit Gittertoren in der Wand |
| **Hinterhalt** (Arena-Variante) | Raum wirkt leer, Tür schließt, Gegner brechen aus den Wänden | wie Arena |
| **Abgrund** | Löcher und Brücken; Fallen kostet ein Herz; Gegner kann man hineinstoßen | Rechteck mit großem Loch, Brücken, Inseln |
| **Kampf-Varianten** (ab Raum 6, ca. jeder 5. Kampfraum) | Seelenflamme beschützen · Beschwörungsrisse schließen · Totengräber (Skelette stehen wieder auf) · Kopfgeld (Gekrönter flieht) · Steinwächter (erstarren im Licht) · Laternenträger (Laterne zum Sockel tragen) · Fackelraum (Fackeln zünden) · Elite-Nest | normale Kampfraum-Formen mit einem Zusatzobjekt |
| **Wagnis-Altar** | vor dem Raum eine Bedingung annehmen (z. B. kein Treffer) → Kristalle | Altar neben dem Eingang |
| **Spezialräume** | Händler, Waffenwahl, Brunnen (Heilung), Upgrade-Altar, Pakt-Altar (Upgrade gegen Fluch), Prüfung (Parcours: Spießrutenlauf, Lichtlauf, Bröckelboden) | kleines Rechteck mit einem Objekt in der Mitte |
| **Miniboss / Boss** | Champion bzw. Boss mit Intro | etwas größere Rechtecke |
| **Lagerfeuer** | Rast nach dem Boss, Portal ins Dorf | kleiner Raum mit Feuer |
| **Abzweigung** | zwei Türen, eine wählen (z. B. Elite-Nest gegen sicheren Weg) | zwei Türen mit Symbol |
| **Geheimnische** | rissige Wand sprengen → Truhe/Kristalle/Händler | Nische hinter der Nordwand |

**Befunde aus der Galerie** (Details je Bild in `szenen/INDEX.md`):

- Spielansicht fast schwarz: Gegner, Boss und Ziele außerhalb des Lichtkreises unsichtbar (011, 024, 104, 110) – Dunkelheit soll Stimmung machen, nicht die Übersicht nehmen.
- Banner, Welt-Beschriftungen und HUD überdecken einander und das Wichtige (026, 034, 076, 087, 114, 139).
- Alle Spezialräume nutzen denselben leeren Raum, alle Bossräume denselben Grundriss mit vier Säulen (075–083, 094–097).
- Arena-Tore kleben außen im Fels, Hinterhalt-Ausbrüche sind lila Blöcke in jedem Biom (057–062, 117, 124).
- Zutaten im Raster oder als Klumpen, Fallen im einzigen Gang oder vor der Tür (037, 040, 049, 056, 064, 066, 068, 071).

**Unser eigener Befund:** Die Arten unterscheiden sich vor allem in **Regeln**, kaum im **Raum selbst**. Fast alles läuft auf „Rechteck + Zufallsstreuung“ hinaus; deshalb wirkt es repetitiv und beliebig.

## 4. Was wir von dir brauchen

Bitte Bilder (Mockups im Spielstil) und kurze Texte, aus denen wir Pakete für die Umsetzung schneiden können.

1. **Look der neuen Raumarten (das Wichtigste):** Das **Gameplay ist schon geplant** in [../KONZEPT_RAEUME_V2.md](../KONZEPT_RAEUME_V2.md) (Säubern, Arena, Minispiele wie Geleit (Eskorte), Flamme hüten, Reliquie holen/Capture the Flag, Seelen sammeln, Risse schließen, Jagd, Lichtfeuer, Einsturz; dazu Ruhe-Räume, Prüfung, Boss). Bitte lies es zuerst. Je Raumart von dir:
   - Mockup des Raums im Spiel, gern in zwei Biomen;
   - wie der Raum **gebaut** ist (Grundriss, Wege, besondere Objekte wie Geleit-Pfad, Reliquien-Altar, Feuerschalen, Einbruchfelder);
   - wie die Gegner auftauchen (Quellen je Biom, KONZEPT §5);
   - Licht, Farbe, Stimmung;
   - **Tür-Erkennung:** Symbol und Lichtfarbe an der Tür;
   - das **Intro-Muster** (Kameraschwenk, Ziel-Banner, Countdown) und die **Aufgabenleiste** oben (Wellen, Zeit, HP von Flamme/Geleit-Figur) als UI-Mockup.
   - **Geleit-Figur:** Vorschläge, wen man begleitet (verirrter Dorfbewohner mit Laterne als Ausgangsidee, selten ein Huhn als Überraschung) – passend zu Licht-Thema und Dorf.
   Verbesserungen am Gameplay sind willkommen – dann bitte als kurze Notiz „Vorschlag Gameplay“, damit wir sie bewusst entscheiden.
2. **Raumstrukturen:** **10–15 Grundriss-Ideen** als Skizze auf einem 32-px-Raster (ca. 15×9 bis 25×15 Kacheln), die lebendig wirken: keine reinen Rechtecke, bewusste Wege, Engstellen, Plätze, Nischen, erhöhte Bereiche, Wasser/Schlamm, Ruinen, Brücken. Dazu, **wie Deko mit Absicht** gesetzt wird (Gruppen und Geschichten statt Streuung: z. B. „eingestürzte Säule mit Geröllfächer“, „Opferstelle mit Kerzen“, „Schleimpfütze unter tropfender Decke“).
3. **Gegner-Auftritt:** 3–5 Arten, wie Gegner erscheinen (aus dem Boden, aus Wänden, aus Särgen/Kokons, aus Schatten), je mit kurzer Ablaufskizze (Warnung → Erscheinen → Angriff), damit man es versteht.
4. **Wand-System:** ein einheitlicher Look für alle Wände in 3/4-Sicht – Nord-, Süd-, West- und Ostwand, Innenmauern, Ecken, Säulen – und wie Einbauten (Türen, Tore, rissige Geheimwand, Nischen, Wandfackeln) bündig darin sitzen. Gern als Tile-Set-Skizze mit allen Teilen.
5. **Türen, Durchgänge, Portale:** Wie Räume schöner verbunden werden (Torbögen, die sauber in der Wand sitzen, Seitentüren, Treppen, Gänge mit Charakter), und wie man **an der Tür** sieht, was dahinter kommt.
6. **Dorf und Dungeon-Eingang:** Ideen, wie das Dorf lebendiger und der Eingang in den Dungeon eindrucksvoller wird.
7. **UI-Rework:** eine Richtung für HUD, Dialoge (Upgrade-Wahl, Händler, Lagerfeuer), Banner und Menüs, die weniger langweilig ist und zum Spiel passt.

## 5. Leitplanken

- **Raster und Maßstab:** Kacheln 32×32 px, im Spiel doppelt gezeichnet; Figuren ca. 32 px hoch; Mauern mit Krone und einer Reihe Vorderseite (3/4-Sicht).
- **Palette und Kontur:** wie in `docs/HANDOUT.md` (Kontur `#1c1a2b`, dunkle Violett-/Grautöne, warme Lichtakzente); vier Biome mit eigener Farbe (Krypta Stein/Violett, Schleimgrotte Grün, Schattenreich Tiefviolett/Kristall, Glutkammer Glut/Orange).
- **Lesbarkeit:** Kämpfe müssen klar bleiben (Warnkreise, Projektile, Gegner im Dunkeln erkennbar); Räume nicht vollstopfen.
- **Kurze Runs:** ein Raum dauert 20–60 s.
- **Koop später (2–4 Spieler):** Räume müssen für mehrere Spieler funktionieren (Platz, keine Ein-Spieler-Rätsel).
- **Handy später:** Steuerung einfach, Details groß genug.
- **Machbarkeit:** Räume werden aus Vorlagen gebaut (Godot-TileMap + Objekte). Handgemachte Grundrisse mit Varianten sind gut machbar; Ideen, die nur mit freier 3D-Geometrie gehen, eher nicht.

## 6. Form und Ablage der Antwort

**Ablage:** alle Ergebnisse (Bilder, Texte, Exporte) nach `docs/design/claude_design_antwort/` im Spiel-Repository. Dateinamen frei, gern mit Nummer und Thema (z. B. `01_raumarten.md`, `02_grundriss_krypta_halle.png`).

- Mockups als Bilder, gern mehrere Varianten.
- Je Raumart und Grundriss ein kurzer Steckbrief (Name, Fantasie, Bau, Gegner-Auftritt, Belohnung, Erkennungsmerkmal).
- Grundrisse als Raster-Skizze mit Legende (Boden, Mauer, Loch, Wasser, Deko-Gruppe, Spawn-Art, Tür).
- Noch offene Grafik-Wünsche aus [../SPRITES_V6.md](sprites/SPRITES_V6.md) (Mauer-Autotile) und [../SPRITES_V7.md](sprites/SPRITES_V7.md) (Seitentüren, Fall-Farbmaske) bitte nicht einzeln liefern, sondern ins neue Wand- und Tür-System einarbeiten.
- Am Ende eine Liste, welche neuen Grafiken nötig wären (Datei, Größe, Frames), damit wir daraus ein `SPRITES_V8.md` machen können.
