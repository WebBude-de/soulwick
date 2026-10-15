# Konzept: Räume und Raumvielfalt

> **Status 15.10.2026: teilweise abgelöst durch [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) (D-120).** Was in v2 neu geregelt ist, gilt dort: Raumarten und Modi (Abgrund ist keine eigene Raumart mehr, Hinterhalt entfällt, Katakombe ist ein Grundriss), Kampf-Varianten aus §4 (werden zu Minispielen), Häufigkeiten aus §2 (v2 §4). **Weiter gültig** aus diesem Dokument: Wagnis-Altar (§5), Räume ohne Kampf (§6: Prüfungen, Pakt-Altar, Lagerfeuer), Wegführung (§7), Elite-Nest (§4.8) sowie die Ausgestaltungen D-109, D-112, D-113, D-117, soweit D-120 sie nicht ändert. Pakete und Haken stehen in [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md), nicht in §9.
>
> **Zweck:** Ausformuliertes Raumkonzept für Strang A ([ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md)). Ersetzt die Ideensammlung vom 14.10.2026.
> **Stand:** 14.10.2026 · **Status:** vom Projektmitglied bestätigt, übernommen als **D-100 bis D-105** und als Phase 2 in ROADMAP_AUSBAU; Werte sind `TESTWERT`, Punkte mit `OFFEN` brauchen noch eine Teamentscheidung. Änderungen an D-005 und D-086 sind in Abschnitt 9 als D-Entwürfe gesammelt.
> **Grundlage:** D-005 (Fünf-Raum-Zyklus), D-084 (Koop-Skalierung), D-086 (Raumarten), D-095 (Ziehung), KONZEPT_ENDLOS (Zyklen, Biome).

## Inhalt

1. Leitlinien
2. Wie oft kommt was? (Häufigkeiten)
3. Normale Kampfräume: Raumarten, Formen, Zutaten
4. Kampf-Varianten
5. Wagnis-Altar (Raum-Modifikator)
6. Räume ohne Kampf
7. Wegführung
8. Verworfene Ideen und ihr Verbleib
9. Reihenfolge, Pakete und D-Entwürfe

---

## 1. Leitlinien

- **Kämpfen ist der Kern.** Der allergrößte Teil der Räume sind Kampfräume. Räume ohne Kampf sind seltene Atempausen (Abschnitt 2).
- **Keine Raumnamen im Spiel.** Der Spieler sieht nie „Arena“ oder „Abgrund“. Namen gibt es nur in Code und Doku. Abwechslung entsteht aus **Form × Größe × Zutaten × Biom × Variante**.
- **Eigene Raumart nur bei eigenem Gameplay.** Ein anderer Grundriss (Innenmauern, Säulen, Gänge) ist eine **Form** des normalen Kampfraums, keine eigene Raumart. Eigene Raumarten sind nur Arena (Wellen) und Abgrund (Fallen, Springen).
- **Wiederholbar statt auswendig lernbar.** Kein Quiz, keine festen Abfolgen. Alles, was nicht Kampf ist, ist Geschick, Timing oder Entscheidung und wird über den Dungeon-RNG je Raum neu gewürfelt.
- **Dunkelheit nutzen.** Der Lichtkreis ist das Alleinstellungsmerkmal von Soulwick. Räume, die mit Sicht spielen, haben Vorrang.
- **Koop-tauglich** (ROADMAP_MULTIPLAYER): allein lösbar, zu zweit bis viert interessanter, nie „einer wartet“.
- **Belohnung vor dem Risiko sichtbar** (Truhe hinter der Falle, Symbol über der Tür, Text am Altar).
- **Keine neue Taste.** Alles läuft über Bewegung, Angriff, Dash und E.

---

## 2. Wie oft kommt was? (Häufigkeiten, `TESTWERT`)

Der Fünf-Raum-Zyklus (D-005) bleibt unverändert:

| Platz im Zyklus | Inhalt nach diesem Konzept |
| --- | --- |
| 1, 2 | Kampfraum: normal **oder** Kampf-Variante |
| 3 | Kampfraum: normal **oder** Kampf-Variante, danach Upgrade-Auswahl (wie bisher) |
| 4 | Spezialraum (gewichtete Ziehung, siehe unten) |
| 5 | Miniboss, auf 15/30/45 Boss |
| nach jedem Boss | **Lagerfeuer** als Zwischenraum, zählt **nicht** als Raum |

### Kampfräume (Plätze 1–3)

| Regel | Wert |
| --- | --- |
| Raum 1–5 | nur normale Kampfräume, keine Abgründe, keine Varianten (Einstieg) |
| Ab Raum 6: normaler Kampfraum | **80 %** |
| Ab Raum 6: Kampf-Variante | **20 %**, nie zwei Varianten direkt hintereinander |
| Raumart des normalen Kampfraums | Normal 40 % · Arena 35 % · Abgrund 25 % (Gewichte aus D-086, kein Abgrund zweimal hintereinander) |
| Wagnis-Altar am Eingang | **12 %** der Kampfräume ab Raum 6 |
| Rissige Wand zu einem Geheimraum | **1 von 8** Kampfräumen ab Raum 6 |

### Spezialraum (Platz 4)

Statt gleichgewichtet (PRD 4.1) **gewichtet**, der unmittelbar vorherige Typ wiederholt sich weiterhin nicht. Die 30-%-Portalchance bleibt.

| Typ | Gewicht |
| --- | --- |
| Shop | 35 |
| Waffenauswahl | 20 |
| Brunnen | 15 |
| Extra-Upgrade (davon ⅓ als **Pakt-Altar**) | 15 |
| **Prüfungsraum** (Geschick, neu) | 15 |
| Gefangener (erst mit Strang B) | später 5, andere Gewichte anteilig kürzen |

### Ergebnis

Neue Räume ohne Kampf (Prüfung, Pakt, Lagerfeuer) kommen im Schnitt **etwa jeder 10. Raum**, zufällig verteilt: pro 15 Räume ca. 0,6 aus dem Spezialraum-Platz plus ein Lagerfeuer nach dem Boss. Shop, Waffenauswahl, Brunnen und Extra-Upgrade bleiben wie bisher auf Platz 4.

---

## 3. Normale Kampfräume

### 3.1 Raumarten

| Raumart (Code-ID) | Gameplay | Paket |
| --- | --- | --- |
| **Normal** (`normal`) | alle Gegner auf einmal besiegen, wie bisher; Grundriss kommt aus der Form (3.2) | A3 |
| **Arena** (`arena`) | groß und offen, 2–3 Wellen aus verschiedenen Richtungen, wenig Deckung | A5 |
| **Abgrund** (`chasm`) | Brücken, Plattformen, 1-Tile-Lücken per Dash, Herunterfallen | A4 |

Die frühere Raumart **„Strukturiert“ entfällt**: Innenmauern, Säulen und Engstellen sind Formen und Zutaten des normalen Kampfraums, weil sich das Gameplay darin nicht ändert.

**Arena-Wellen:** Welle 2 startet, wenn von Welle 1 höchstens ein Gegner übrig ist. Gegner betreten den Raum aus Wandlöchern oder Toren an mindestens zwei Seiten. Spawnpunkte haben ein Mindestabstand zum Spieler (`TESTWERT` 96 px). Die Variante **Hinterhalt** ist Teil der Arena: Der Raum wirkt leer, erst beim Schließen der Tür brechen die Gegner aus allen Wänden.

**Abgrund** (D-086): Springen = Dash, überquert Lücken bis 1 Tile. Herunterfallen kostet ein ganzes Herz (2 HP), Rücksetzen an die letzte sichere Stelle. Gegner meiden Abgründe, können aber durch starken Rückstoß hineinfallen (nicht Champions, Golems, Bosse).

### 3.2 Formen (Grundriss der Raumvorlage)

Jede Form gibt es in **S/M/L** (D-084: 1–2 Spieler S/M, 3–4 Spieler L) und mit 5–14 Spawnpunkten (D-086).

| Form | Spielgefühl | Raumarten | Wann |
| --- | --- | --- | --- |
| Rechteck | Basis | alle | A3 |
| **L-Form** | Gegner kommen um die Ecke | Normal, Abgrund | A3 |
| **Kreuz** | vier Arme, Gegner aus allen Richtungen, Mitte gefährlich | Normal, Arena | A3 |
| **Ring** um einen massiven Block | Kreisen; Fernkämpfer verlieren Sicht | Normal, Abgrund (Ring um ein Loch) | A3 |
| **Zwei Kammern** mit schmalem Durchgang | Engpass halten oder durchbrechen | Normal | A3 |
| **Säulenhalle** | Deckung, Bogen-Duelle | Normal, Arena | A3 |
| **Katakombe** (ersetzt „Labyrinth“) | enge Gänge, man sieht nur den Lichtkreis; Sackgassen mit 2–3 Gegnern im Hinterhalt, in der tiefsten Sackgasse eine Truhe | Normal, nur M/L | A3, später |
| **Langer Korridor** (quer) | Gegner reihen sich auf, gut für Durchschlag | Normal, Arena | später |
| **Höhle** (unregelmäßig) | organische Ränder, Nischen | nur Schleimgrotte | später |

Die **Katakombe** ist bewusst klein gehalten: höchstens zwei Sackgassen, der Ausgang ist vom Eingang aus nie weiter als zwei Abzweigungen entfernt. So entsteht Spannung im Dunkeln, aber kein langes Suchen. Die Erreichbarkeitsprüfung aus A1 gilt für alle Formen.

### 3.3 Zutaten

Ein **Zutaten-Streuer je Biom** verteilt Elemente in die Form. Pro Raum werden 2–3 Zutaten gezogen, nie alle.

| Zutat | Wirkung | Biome | Wann |
| --- | --- | --- | --- |
| **Deckung** (Kisten, Fässer, zerstörbar) | blockt Geschosse; enthält selten Gold oder ein Herz | alle | A3 |
| **Fallengruppen** | Zonen meiden, Gegner hineinlocken; Stachel (Krypta), Gift (Grotte), Schatten-Dornen (Schattenreich), Lava (Glutkammer) | alle | A3 |
| **Innenmauern und Säulen** | Deckung, getrennte Bereiche, Sichtlinien brechen | alle | A3 |
| **Engstellen und Nischen** | zurückziehen, Gegner bündeln | alle | A3 |
| **Lichtinseln und Dunkelzonen** | Fackeln/Kristalle erweitern die Sicht, Dunkelzonen verkleinern sie | alle | A3 |
| **Explosionsfässer** | Kettenreaktion, trifft auch den Spieler; öffnen rissige Wände | Krypta, Glutkammer | A3 |
| **Wellen aus mehreren Richtungen** | Kampf bleibt in Bewegung | Arena | A5 |
| **Wasser/Schlamm** | verlangsamt Spieler und Gegner (`TESTWERT` −30 %), Dash nicht | Grotte, Krypta | später |
| **Kleine Abgrundlöcher** | Gegner hineinstoßen, selbst aufpassen | alle außer Raum 1–5 | mit A4 |
| **Zerstörbare Wände** | Einstieg zu Geheimräumen (Abschnitt 7.3) | alle | mit Geheimräumen |

### 3.4 Unsichtbare Variation

- **Gegnergruppen nach Thema:** gemischt (Standard), nur Fernkämpfer, nur Schwärme (Slimes). Die Gegnerwahrscheinlichkeiten aus PRD 4.2 bleiben im Mittel erhalten.
- **Stiller Raum:** gelegentlich nur 1–2 starke Gegner statt vieler schwacher (`TESTWERT` 8 % der Kampfräume ab Raum 6, gleiche Gesamt-HP).
- **Ausgangsseite:** oben, links oder rechts (Abschnitt 7.1).

---

## 4. Kampf-Varianten

Ersetzen einen normalen Kampfraum (20 % ab Raum 6). Der Raum gilt wie jeder Kampfraum als abgeschlossen, wenn alle Gegner besiegt sind. Auf Platz 3 folgt danach wie gewohnt die Upgrade-Auswahl. Die **Zusatzbelohnung** (Bonus-Truhe) gibt es nur bei Erfolg; Misserfolg kostet nie den Run.

### 4.1 Seelenflamme beschützen ★

- Eine Seelenflamme steht in der Raummitte. Gegner kommen in Wellen für **40 s** (`TESTWERT`), danach müssen die restlichen Gegner besiegt werden.
- Gegner greifen bevorzugt die Flamme an (`TESTWERT` 70 % der Gegner wählen die Flamme als Ziel). Die Flamme hat eine eigene HP-Leiste.
- Flamme überlebt → Bonus-Truhe. Flamme erlischt → keine Bonus-Truhe, der Raum wird dunkler, der Kampf geht weiter.
- **Koop:** einer verteidigt, andere fangen Gegner ab.
- Alle Biome. Aufwand M.

### 4.2 Beschwörungsrisse ★

- 2–3 Risse in der Wand oder Totems im Raum beschwören alle **4 s** einen Gegner, solange weniger als **6** leben (`TESTWERT`).
- Risse haben HP und eine Leiste. Ein zerstörter Riss stoppt. Raum geschafft, wenn alle Risse und alle Gegner weg sind.
- Die Frage an den Spieler: Risse zuerst oder Gegner? Gute Plätze für Magierstab-AOE und Durchschlag.
- Alle Biome, Optik je Biom. Aufwand S–M.

### 4.3 Steinwächter ★ (Licht)

- 2–4 Wächterstatuen bewegen sich **nur außerhalb eines Lichtkreises**. Im Licht erstarren sie und sind verwundbar; im Dunkeln sind sie unverwundbar und rücken vor.
- Dazu normale Gegner. Man muss die Wächter im Licht halten und gleichzeitig kämpfen.
- Lichtinseln (Fackeln, Kristalle) zählen auch. **Koop:** Jeder Spieler hat einen eigenen Lichtkreis (D-084), also deckt jeder einen Winkel ab.
- Krypta und Schattenreich. Aufwand M. Braucht eine saubere Abfrage „Punkt liegt im Licht“, die auch im Multiplayer stimmt.

### 4.4 Laternenträger (Licht, Koop)

- Der Raum ist dunkel. Eine Seelenlaterne muss vom Eingang zum Sockel am Ausgang gebracht werden; erst dann öffnet der Ausgang.
- Aufnehmen und Ablegen mit **E**. Der Träger hat einen deutlich größeren Lichtkreis, ist langsamer (`TESTWERT` −25 %), kann nicht angreifen, aber dashen. Allein legt man die Laterne zum Kämpfen ab.
- Gegner kommen aus der Dunkelheit, bevorzugt zum Träger.
- **Koop:** einer trägt, die anderen eskortieren; alle bleiben beschäftigt.
- Alle Biome, am stärksten im Schattenreich. Aufwand M.

### 4.5 Totengräber (Krypta)

- Besiegte Skelette hinterlassen einen Knochenhaufen. Wird er nicht innerhalb von **5 s** zerstört (drüberlaufen, Dash, jeder Treffer), steht das Skelett mit **50 % HP** wieder auf.
- Jedes Skelett steht höchstens einmal wieder auf. Gold-Drop erst beim endgültigen Tod.
- Nur Krypta. Aufwand S (Logik an einem Gegnertyp).

### 4.6 Kopfgeld

- Ein Gegner trägt eine Goldkrone. Sobald er den Spieler sieht, flieht er zu einem Fluchtloch.
- Erwischt man ihn innerhalb von **12 s** → Bonus-Truhe. Entkommt er, ist er weg; der Raum wird trotzdem normal abgeschlossen.
- Lässt sich mit jeder Form kombinieren. Aufwand S.

### 4.7 Fackelraum (Schattenreich)

- Der Raum ist bis auf den Lichtkreis komplett dunkel. Unbeleuchtete Fackeln stehen verteilt; Treffer oder **E** zündet sie an, jede vergrößert die Sicht dauerhaft.
- Gegner im Fackellicht verursachen **−20 % Schaden** (`TESTWERT`).
- Nur Schattenreich, als Variante oder als starke Ausprägung der Zutat „Lichtinseln“. Aufwand M.

### 4.8 Elite-Nest

- Nur 2–3 Elites oder Champions, dafür **doppelte Kristalle**.
- Kommt **nur über Abzweigungen** (Abschnitt 7.2), nie zufällig, damit es eine bewusste Wahl bleibt.
- Aufwand S, sobald Abzweigungen stehen.

---

## 5. Wagnis-Altar (Raum-Modifikator)

Kein eigener Raum, sondern ein Altar direkt hinter dem Eingang eines normalen Kampfraums (12 % ab Raum 6). Fasst „Herausforderungs-Altar“ und „Fluchkammer“ zusammen.

- Der Altar zeigt **eine** Bedingung und die Belohnung. Annehmen mit **E**, solange die Tür noch offen ist; ignorieren = normaler Raum.
- **Prüfung** (Ziel): kein Treffer · unter 30 s · nur mit der Zweitwaffe.
- **Fluch** (Erschwernis): Lichtkreis −40 % · Gegner +15 % Tempo · keine Heilung in diesem Raum.
- Belohnung bei Erfolg: seltenes Upgrade oder Kristall (`OFFEN`, siehe Abschnitt 9). Bei Misserfolg: nichts, keine Strafe über die Erschwernis hinaus.
- **Koop:** Bedingung gilt für die Gruppe („kein Treffer“ = kein Spieler wird getroffen).
- Aufwand S.

---

## 6. Räume ohne Kampf

Selten (Abschnitt 2). Alle sind **freiwillig**: Der Ausgang ist immer ohne Risiko erreichbar, das Angebot liegt daneben.

### 6.1 Prüfungsräume (neuer Spezialraum-Typ)

Gemeinsamer Aufbau: Eingang → direkter Weg zum Ausgang → abzweigender **Parcours**, an dessen Ende eine von Anfang an sichtbare Truhe steht. Fehler kosten Schaden (meist ½ Herz), nie den Run. Wer **makellos** durchkommt, bekommt zusätzlich etwas (`TESTWERT`: +1 Kristall). Timing und Positionen werden je Raum neu gewürfelt.

| Prüfung | Ablauf | Wann |
| --- | --- | --- |
| **Spießrutenlauf** | Gang mit Stacheln, Flammenstößen und Pendelklingen im wechselnden Takt; nutzt die Fallen der Biome | zuerst |
| **Bröckelboden** | Boden bricht kurz nach dem Betreten hinter einem weg und wird Abgrund; sprinten, dashen, Weg wählen. Fallen = Regel aus A4 | nach A4 |
| **Lichtlauf** | Fackeln entlang des Weges erlöschen nacheinander; im Dunkeln verliert man ½ Herz pro 2 s. Nächste Fackel erreichen, bevor die eigene ausgeht | danach |

**Koop:** Jeder läuft selbst; die Truhe öffnet, sobald mindestens einer ankommt, „makellos“ zählt für jeden einzeln.

### 6.2 Pakt-Altar (Variante des Extra-Upgrade-Raums)

- In ⅓ der Extra-Upgrade-Räume steht statt der normalen Auswahl ein Pakt-Altar.
- Wahl: **normales Extra-Upgrade** oder **Pakt**: ein Upgrade aus einer besseren Auswahl (z. B. ein Stack mehr oder ein seltenes) gegen einen **Fluch für den restlichen Run**.
- Flüche (`TESTWERT`): −1 Max-Herz · Gegner +10 % Tempo · Lichtkreis −20 % · Brunnen heilen nur halb.
- Flüche erscheinen in der Tab-Übersicht. **Koop:** Pakt gilt nur für den Spieler, der ihn schließt.
- Aufwand S.

### 6.3 Lagerfeuer (Zwischenraum nach jedem Boss)

Fasst „Übergangsraum zwischen Biomen“ und „Ruheplatz“ zusammen.

- Kommt nach jedem Boss (15, 30, 45). Zählt **nicht** als Raum: kein Einfluss auf Raumnummer, Skalierung oder die Heilung alle fünf Räume.
- Die Tiles gehen vom alten ins neue Biom über (z. B. Krypta-Steine mit Moos und Schleimpfützen). Die Musik klingt aus, die neue Geräuschkulisse setzt ein.
- Am Feuer **eine** Wahl: heilen (`TESTWERT` +4 HP, bis Max-HP) **oder** ein vorhandenes stapelbares Upgrade um einen Stack stärken.
- Nach Raum 45 findet hier die Wahl Ausstieg/Endlos statt.
- **Koop:** Jeder wählt für sich.
- Aufwand S–M.

### 6.4 Gefangener (später, mit Strang B)

- Spezialraum: Ein Gefangener sitzt in einer Zelle, bewacht von 2–3 Wärtern (kleiner Kampf, freiwillig).
- Befreit taucht er im Dorf auf und schaltet einen Händler oder eine Verbesserung frei. Jeder Gefangene nur einmal pro Spielstand.
- Brücke zwischen Dungeon und Meta-Progression. Erst einplanen, wenn Strang B (Dorf, D-087) diese Freischaltungen kennt.

---

## 7. Wegführung

### 7.1 Ausgänge an allen Seiten

- Der Ausgang liegt oben, links oder rechts, nie auf der Eingangsseite. Der Dungeon schlängelt sich.
- Raumvorlagen bekommen Türpositionen an mehreren Seiten; der Generator wählt Eingang (passend zum vorherigen Ausgang) und Ausgang.
- Betrifft das Aneinanderhängen der Räume in `dungeon_manager.gd`. Da höchstens drei Rauminstanzen gleichzeitig existieren, muss der Generator nur Überlappungen mit den noch existierenden Räumen prüfen.
- Voraussetzung für Abzweigungen. Aufwand M–L.

### 7.2 Abzweigungen

- Gelegentlich (`TESTWERT` höchstens einmal pro Zyklus, ab Raum 6) hat ein Raum **zwei Ausgänge mit Symbol** darüber. Beide führen zum **nächsten Raum (n+1)**; Zyklus, Raumnummer und Skalierung bleiben gleich.
- Varianten:
  - **Vor Platz 4:** zwei Spezialraum-Typen zur Wahl (z. B. 🛒 Shop vs. ✦ Prüfung).
  - **Vor einem Kampfraum:** ⚔ Elite-Nest (mehr Kristalle) vs. normaler Kampfraum.
  - **?** unbekannt: zufällige Kampf-Variante.
- **Koop:** Die Tür öffnet, wenn alle davor stehen; bei Uneinigkeit nach 10 s die Tür mit mehr Spielern, bei Gleichstand zufällig.
- Aufwand L (Vorschau-Symbole, Zyklusplanung).

### 7.3 Geheimräume

- Eine rissige Wand (feiner Riss, leichte Staubpartikel) lässt sich durch Explosionen öffnen: Explosionsfass, „Explosiver Treffer“, Magierstab-AOE, später schwere Waffen.
- Dahinter eine kleine Nische, kein eigener Raum: Truhe, Kristall oder selten ein wandernder Händler (Preise `OFFEN`).
- Zählt nicht als Raum. Aufwand M.

---

## 8. Verworfene Ideen und ihr Verbleib

| Idee | Warum nicht als Raum | Verbleib |
| --- | --- | --- |
| Labyrinth als eigene Raumart | führt zu langem Suchen, Koop-Spieler verlieren sich | als **Katakombe**-Form des normalen Kampfraums (3.2) |
| „Strukturiert“ als eigene Raumart | gleiches Gameplay wie der normale Kampfraum | als Formen und Zutaten (3.2, 3.3) |
| Druckplatten in Zufallsfolge | Merken statt Geschick, Wartezeit im Koop | – |
| Glücksspiel-Statue | reiner Zufall; Goldwerte noch `OFFEN` | – |
| Spiegelraum (Doppelgänger) | Aufwand L für einen seltenen Raum | Idee für einen späteren Boss |
| Die Flut kommt | drei Biom-Varianten, teuer | Gefühl wird durch **Bröckelboden** abgedeckt |
| Geschoss-Ausweichen | allein ohne Kampf schnell langweilig | Muster für Bossphasen |
| Mimic-Schatzkammer | braucht neuen Gegner mit Grafik | Mimic später als normaler Gegner in Truhen-Nischen |
| Seelenbrunnen | dritter Raum für Heilung | als Option im Brunnen, sobald Kristalle im Run eine Rolle spielen |
| Herausforderungs-Altar, Fluchkammer | – | zusammengelegt zum **Wagnis-Altar** (5) |
| Übergangsraum, Ruheplatz | – | zusammengelegt zum **Lagerfeuer** (6.3) |
| Hinterhalt / Belagerung | – | Variante der **Arena** (3.1) |

---

## 9. Reihenfolge, Pakete und D-Entwürfe

### 9.1 Pakete

Paketnummern ab A6 sind Vorschläge und werden beim Eintrag in ROADMAP_AUSBAU angepasst.

| Reihenfolge | Paket | Inhalt | Berührt Spieler-Code? |
| --- | --- | --- | --- |
| 1 | **A3 Formen & Zutaten** | Rechteck, L, Kreuz, Ring, zwei Kammern, Säulenhalle, Katakombe in S/M/L; Zutaten-Streuer je Biom (Deckung, Fallen, Engstellen, Lichtinseln, Explosionsfässer); stiller Raum, Gegnergruppen nach Thema | nein |
| 2 | **A5 Arena mit Wellen** | Wellen, Spawn aus Wandlöchern, Hinterhalt | nein |
| 3 | **A6 Lagerfeuer** | Zwischenraum nach Bossen, Biom-Übergangstiles, Musikwechsel | wenig |
| 4 | **A7 Kampf-Varianten I + Wagnis-Altar** | Seelenflamme, Beschwörungsrisse, Totengräber, Kopfgeld, Wagnis-Altar | wenig |
| – | *MP1 Multiplayer-Fundament* | | |
| 5 | **A4 Abgrund & Brücken** | Raumart Abgrund, Zutat Abgrundlöcher | ja (Fallen) |
| 6 | **A8 Neue Spezialräume** | gewichtete Ziehung, Prüfungsräume (Spießrutenlauf, Bröckelboden, Lichtlauf), Pakt-Altar | wenig |
| 7 | **A9 Licht-Varianten** | Steinwächter, Laternenträger, Fackelraum; Abfrage „im Licht“ mit mehreren Lichtkreisen | wenig |
| 8 | **A10 Wegführung** | Ausgänge an allen Seiten → Abzweigungen + Elite-Nest → Geheimräume | nein |
| später | | Korridor, Höhle, Wasser/Schlamm; Gefangener (mit Strang B) | |

Begründung der Reihenfolge: Zuerst kommt, was viele Räume sofort anders aussehen lässt und den Spieler-Code nicht anfasst. Die Licht-Varianten kommen nach MP1, weil sie mit mehreren Lichtkreisen funktionieren müssen. Die Wegführung ist der größte Umbau und kommt zuletzt.

### 9.2 Technische Leitplanken

- Raumvorlagen als `.tscn` mit Metadaten in einer typisierten `Resource` (`RoomTemplate`: Raumart, Form, Größe, Türseiten, Spawnpunkte, erlaubte Biome). Kein JSON (TECHSTACK).
- Zutaten als `IngredientSet`-Resource je Biom; der Streuer platziert nur auf freien, erreichbaren Tiles und prüft danach die Erreichbarkeit (A1).
- Kampf-Varianten als eigene Raum-Skripte mit gemeinsamer Schnittstelle (Start, Abschluss, Bonus erfüllt ja/nein), damit der `DungeonManager` sie wie normale Kampfräume behandelt.
- Alle Zufallsentscheidungen über den Dungeon-RNG, damit ein Run mit gleichem Seed reproduzierbar ist (wichtig für Tests und Koop).
- Raum- und Variantengewichte als `.tres`, damit Balancing ohne Code-Änderung geht.

### 9.3 D-Entwürfe

| Entwurf | Inhalt | Ändert |
| --- | --- | --- |
| D-A | Raumart „Strukturiert“ entfällt; Raumarten sind **Normal / Arena / Abgrund**, Grundrisse sind Formen des normalen Kampfraums; Raumnamen werden im Spiel nie angezeigt | D-086, PRD 7.4 |
| D-B | Ab Raum 6 sind **20 %** der Kampfräume Kampf-Varianten, nie zwei hintereinander | neu |
| D-C | Spezialräume werden **gewichtet** gezogen (Tabelle Abschnitt 2), neuer Typ Prüfungsraum | D-005, PRD 4.1 |
| D-D | **Lagerfeuer** nach jedem Boss als Zwischenraum außerhalb der Raumzählung | D-005 |
| D-E | **Wagnis-Altar** als Modifikator auf normalen Kampfräumen (12 %) | neu |
| D-F | Abzweigungen führen immer zu Raum n+1; Zyklus bleibt unverändert | neu |

### 9.4 Offene Fragen

- **Bonus-Belohnungen** (Bonus-Truhe, Wagnis-Altar, Prüfung): Upgrade, Kristalle oder Wahl? Vorschlag: Truhen geben eine Upgrade-Auswahl, „makellos“ und Wagnis-Altar geben Kristalle. Gold vorerst nicht, solange die Goldwerte `OFFEN` sind.
- **Lagerfeuer und Portal:** Gibt es am Lagerfeuer zusätzlich ein Exit-Portal (auch auf 15 und 30)?
- **Koop-Skalierung der Varianten:** Seelenflamme-HP, Anzahl Risse und Wächter nach Spielerzahl wie Champion-HP (D-084) oder eigene Faktoren?
- **Katakombe** schon in A3 oder erst nach den übrigen Formen?