# Räume – Regeln für Raumarten und Minispiele (Räume v2)

> **Stand:** 22.10.2026 · **Status:** Regeln, gebaut (D-120, D-130 bis D-144); bis 22.10.2026 hieß die Datei `KONZEPT_RAEUME_V2.md` (D-193), Abschnittsnummern sind gleich geblieben, weil der Code darauf verweist. Hier stehen **Absicht und Regeln**; Abläufe und Zahlen stehen im Code (`dungeon/modes/<modus>/*_rules.gd`, `dungeon/variants/mode_registry.gd`, `variant_table.tres`, alle `TESTWERT`). Was an Räumen noch kommt: [ROADMAP.md](ROADMAP.md) Bereich C (CR1–CR4); neue Raumarten erklärt beim ersten Mal Flint (KONZEPT §7.2, Paket WK11).
> **Arbeitsteilung:** Diese Regeln legen das Gameplay fest, Claude Design den Look ([design/responses/](design/responses/README.md)).
> **Anlass:** Playtest 14.10.2026: Die Balance passte, aber Räume waren leer und zufällig, die Modi unklar, man sah nicht, woher Gegner kamen.

## 1. Leitlinien

1. **Ein Raum, eine Aufgabe, ein Satz.** Jeder Raum ist in einem Satz erklärbar („Bring den Dorfbewohner zum Ausgang“). Keine Mischformen, keine zwei Regeln gleichzeitig.
2. **Man sieht es vorher.** Schon an der Tür erkennt man die Raumart: eigenes Symbol, eigene Farbe, eigenes Licht durch den Spalt (D-137).
3. **Einführung immer gleich (Intro-Muster):** Tür zu → Kamera auf das Ziel → Ziel-Banner mit Satz → Countdown → los. Beim ersten Mal je Spielstand zusätzlich die Erklärkarte (D-133).
4. **Fortschritt ist immer sichtbar:** Aufgabenleiste oben in der Mitte; Ende mit deutlichem Erfolgs- oder Misserfolgs-Moment.
5. **Misserfolg kostet nie den Run**, nur den Bonus. Erfolg gibt immer etwas Sichtbares (Bonus-Truhe, Kristalle, D-109).
6. **Immer etwas los:** lieber viele schwache Gegner als einzelne; Gegner greifen auch von hinten an (§6).
7. **Gegner kommen aus sichtbaren Quellen,** nie einfach aufploppen (§5).
8. **Lebendige Räume:** handgebaute Grundrisse mit Varianten statt Rechteck und Zufallsstreuung; Deko in Gruppen mit kleiner Geschichte.
9. **Endlos-Rhythmus:** Die ersten Räume sind leicht, aber voll; neue Modi kommen schrittweise, danach gemischt.
10. **Wiederholbar statt auswendig lernbar** (aus v1): kein Quiz, keine festen Abfolgen; was nicht Kampf ist, ist Geschick, Timing oder Entscheidung und wird über den Dungeon-RNG je Raum neu gewürfelt.
11. **Dunkelheit und Licht nutzen** (aus v1): Der Lichtkreis ist das Motiv von Soulwick; Räume, die mit Sicht spielen, haben Vorrang. **Belohnung vor dem Risiko sichtbar** (Truhe hinter der Falle, Symbol an der Tür).
12. **Koop-tauglich:** allein lösbar, zu zweit bis viert interessanter, nie „einer wartet“ (Koop-Check in [ROADMAP.md](ROADMAP.md)).

## 2. Die Raumarten auf einen Blick

| Gruppe | Raumart | Satz für den Spieler | Ab (TESTWERT) |
| --- | --- | --- | --- |
| **Kampf** | **Säubern** | „Besiege alle Gegner.“ | Raum 1 |
| | **Arena** | „Überlebe 3 Wellen.“ | kurz vor dem 1. Boss, danach regelmäßig |
| **Minispiele** | **Geleit** | „Bring den verirrten Dorfbewohner sicher zum Ausgang.“ | Zyklus 2 |
| | **Flamme hüten** | „Halte die Seelenflamme am Leben.“ | Zyklus 2 |
| | **Reliquie holen** | „Hol die Reliquie und bring sie zum Altar.“ | Zyklus 3 |
| | **Seelen sammeln** | „Sammle die Seelen, bevor sie verlöschen.“ | Zyklus 3 |
| | **Risse schließen** | „Zerstöre die Risse, aus denen Gegner kommen.“ | 2. Biom |
| | **Jagd** | „Fang den Gekrönten, bevor er entkommt.“ | 2. Biom |
| | **Lichtfeuer** | „Entzünde alle Feuer – im Dunkeln sind die Wächter unbesiegbar.“ | 2. Biom |
| | **Einsturz** | „Überlebe, während der Boden einbricht.“ | 2. Biom |
| **Herausforderung** | **Wagnis** (Zusatz vor einem Kampfraum) | „Nimm eine Bedingung an für Kristalle.“ | Raum 6 |
| | **Elite-Nest** (nur über Abzweigung) | „Starke Elite-Gegner, große Belohnung.“ | Raum 6 |
| **Ruhe** | **Händler, Waffenauswahl, Brunnen, Altar/Pakt** | keine Gegner | Platz 4 |
| | **Prüfung** (Parcours ohne Gegner) | „Lauf durch den Parcours zur Truhe.“ | Platz 4 |
| **Höhepunkte** | **Miniboss, Boss, Lagerfeuer** | – | Platz 5, jeder 15. Raum |
| **Geheimnis** | **Geheimnische** | rissige Wand sprengen | Raum 6 |

Aus v1 umgebaut (D-120): Abgrund ist keine Raumart mehr, sondern Bauteil der Grundrisse und Kern von Einsturz; Hinterhalt entfällt; Katakombe ist ein Grundriss; Laternenträger geht in Reliquie auf, Steinwächter und Fackelraum in Lichtfeuer, Kopfgeld wird Jagd, Seelenflamme wird Flamme hüten, Beschwörungsrisse werden Risse schließen; Totengräber ist eine Eigenschaft der Krypta-Skelette.

## 3. Die Modi

Jeder Modus hat einen Ablauf in drei Schritten, Sieg, Niederlage (nur Bonus weg), Bonus, eine Koop-Rolle und ein Tür-Symbol. Abläufe und Zahlen: `dungeon/modes/<modus>/`.

### 3.1 Säubern

Grundraum: Gegner aus den Biom-Quellen in 1–2 Schüben, alle besiegt → Tür auf. Kein Bonus außer gelegentlicher Truhe in einer Nebennische.

### 3.2 Arena

Wellen nur aus Wandtoren, deutlich mehr Gegner, Pause mit „Welle n/N“ zwischen den Wellen, Bonus-Truhe am Ende.

### 3.3 Geleit

Ein verirrter Dorfbewohner mit Laterne (selten ein Huhn) läuft zum Ausgang; Gegner zielen auf ihn, er bleibt bei Gefahr stehen und läuft schneller, wenn ein Spieler daneben ist. Gerettete tauchen im Dorf auf (D-138). Koop: einer begleitet, die anderen räumen vor.

### 3.4 Flamme hüten

Eine Seelenflamme in der Mitte eine feste Zeit verteidigen; ihr Licht schrumpft mit ihren HP. Erlischt sie, wird der Raum dunkler.

### 3.5 Reliquie holen

Reliquie aufnehmen (Träger langsamer, kein Angriff), zum Altar bringen; bei Treffer fällt sie. Koop: Träger plus Beschützer, Übergeben möglich.

### 3.6 Seelen sammeln

Seelen erscheinen nacheinander an festen Plätzen und verlöschen wieder; einsammeln unter Zeitdruck, Kristalle nach Anzahl. Passt zur Katakombe.

### 3.7 Risse schließen

Wandrisse spucken Gegner aus und sind selbst das Ziel; schnell = Kristall.

### 3.8 Jagd

Ein Gekrönter flieht zu einem Fluchtloch, Wachen stellen sich in den Weg; gefangen = seine Beute.

### 3.9 Lichtfeuer

Dunkler Raum, Feuerschalen anzünden; Steinwächter sind nur im Licht verwundbar.

### 3.10 Einsturz

Der Boden bricht in angekündigten Feldern ein, Gegner fallen mit; am Ende bleibt ein Restweg zur Truhe. Fallen kostet ein Herz.

### 3.11 Nur im Koop (vorgemerkt für MP5, nicht gebaut)

Räume, die nur mit 2–4 Spielern gezogen werden; im Einzelspiel nie.

- **Doppelgänger:** Ein Mitspieler sieht für die anderen wie ein Gegner aus; wer ihn trifft, verliert den Bonus. Er gibt sich durch eine Geste (Emote) oder das Aufheben eines Lichts zu erkennen.
- **Staffel:** Die Reliquie muss durch die Hände aller Spieler gehen, bevor sie auf den Altar darf.
- **Geteiltes Licht:** Nur ein Spieler trägt Licht; die anderen sehen nur in seiner Nähe und müssen zusammenbleiben.
- **Zwei Schalter:** Zwei Altäre an entgegengesetzten Enden müssen gleichzeitig gehalten werden, während Gegner beide Seiten angreifen.
- **Wettstreit:** Wer sammelt in 30 s die meisten Seelen? Der Gewinner wählt zuerst die Belohnung (freundlich, kein Schaden zwischen Spielern).
- **Rettung:** Ein Spieler wird zu Beginn gefangen (Käfig); die anderen holen den Schlüssel.

Die Minispiele sind auch die Grundlage des Party-Modus ([KONZEPT.md](KONZEPT.md), D-179).

## 4. Zyklus-Rhythmus und Häufigkeiten

Ein Zyklus hat fünf Plätze: Kampf · Kampf · Kampf mit Upgrade-Wahl · Ruhe oder Prüfung · Miniboss; jeder 15. Raum Boss, danach Lagerfeuer.

- Im ersten Zyklus nur Säubern.
- Ab Zyklus 2 sind **30–40 % der Kampfräume Minispiele** (freigegeben, D-120), höchstens 2 je Zyklus.
- Jeder Modus erscheint zum ersten Mal an einem festen Punkt (Tabelle §2), danach zufällig; nie derselbe Modus zweimal hintereinander, keiner zweimal im Zyklus.
- Arena höchstens einmal je Zyklus.
- Abzweigung höchstens einmal je Zyklus: zwei Türen mit sichtbarem Modus-Symbol; beide Räume sind schon gebaut und liegen im Dunkeln, nichts ploppt auf (D-105, D-137).

## 5. Woher die Gegner kommen

Je Biom eine eigene Quelle als fester Teil des Grundrisses, meist an den Rändern und **hinter** dem Spieler, damit man nicht nur nach vorn kämpft; 1 s Warnung mit Licht und Ton (D-132): Krypta Gräber und Sarkophage, Schleimgrotte Pfützen, Schattenreich Bodenrisse, Glutkammer Lavaspalten, Arena Wandtore.

## 6. Gegner-Verhalten

Mehr, aber einzeln schwächere Gegner; Slimes springen in Rudeln und landen auch hinter dem Spieler, Nahkämpfer verteilen sich und schneiden den Weg ab, Fernkämpfer wechseln die Seite (D-118, D-130). Ziel: Im-Kreis-Weglaufen funktioniert nicht, man muss sich stellen.

## 7. Aus v1 weiter gültig

Wagnis-Altar (D-104), Prüfungsräume und Pakt-Altar (D-112), Lagerfeuer nach jedem Boss (D-103), Wegführung mit Ausgängen an mehreren Seiten, Abzweigungen und Geheimnischen (D-105, D-117), Belohnungen (D-109). Alle bekommen Intro-Muster, Tür-Erkennung und Grundrisse aus Plänen.

**Verworfen** (mit Grund): Druckplatten in Zufallsfolge (Merken statt Geschick, Warten im Koop) · Glücksspiel-Statue (reiner Zufall) · Spiegelraum (zu teuer für einen seltenen Raum, Idee für einen Boss) · „Die Flut kommt“ (deckt Einsturz ab) · Geschoss-Ausweichen als Raum (Muster für Bossphasen) · Seelenbrunnen (dritter Heilraum).

## 8. Offen

- **Geleit im Koop:** Die Rettung landet heute nur im Spielstand des Hosts (MULTIPLAYER.md §3e). OFFEN, ob jeder Spieler sie bekommt (mit CR3 klären).
- Koop-Räume (§3.11), Koop-Skalierung der Minispiele und spätere Grundrisse stehen als Pakete CR2–CR4 in [ROADMAP.md](ROADMAP.md).

## 9. Seitenansicht: Hindernislauf (D-216)

Zwischen manchen Räumen liegt ein **Hindernislauf** in Seitenansicht (D-144, D-216): ein kleines Jump-and-Run-Level von etwa einer Minute (Bot 45–75 s). Es gibt nur diese eine Art; die Namen „Sprungprobe“ und „Sturmlauf“ entfallen.

- **Häufigkeit:** auf dem Weg in jeden Champion-Raum (Platz 5 im Zyklus), hinter dem Lagerfeuer und auf dem Leiter-Weg (mit Truhe), sonst nie (D-216); nie in den Boss oder aus ihm, nie zweimal hintereinander; „Seitenwege auslassen“ schaltet alle ab.
- **Ablauf:** Einstieg (leichter Teil) → zwei Wege (oben schwer mit mehr Münzen, unten sicher; Schrägen und Rampen) → Laterne → schwerer Teil mit den Elementen der Stufe → Schluss-Sprung zur Tür. Ende immer an der Tür.
- **Stufen:** Stufe 1 (Raum 1–15) eine Besonderheit im schweren Teil, Stufe 2 (16–45) zwei, Stufe 3 (ab 46 oder Gefahr 6) drei mit schmalen Plattformen und zeitkritischen Teilen. Elemente: bewegte Plattform, Sprungfeder, Kippplattform, Säge auf Schiene, einstürzende Brücke, Doppelsprung-Lücke, Wandsprung-Schacht.
- **Gegner sind Hindernisse:** besiegen nur durch Stampfen oder Waffe; Berührung von der Seite kostet Schaden, egal wie schnell. Keine Gegnerketten, kein Umrennen, kein Dash in der Seitenansicht.
- **Bewegung:** Schwung beim Durchlaufen (1,3× → 2,0×), keine Boost-Felder; Sprung, Doppelsprung, Wandsprung, Leitern.
- **Fairness:** kein blinder Sprung (Kamera schaut voraus), neues Element zuerst einzeln, Laternen als Rücksetzpunkt, Grube 1 Herz; `SideBot` muss jeden Lauf schaffen (side check).
- **Belohnung:** Münzen auf dem Weg (oben mehr) und die goldene Münze, zusammen etwa ein Kampfraum (D-144); Truhe nur auf dem Leiter-Weg. Keine Kombo, kein Zielbogen, kein Ergebnisbanner, keine Krone (Krone im Koop → BACKLOG).
