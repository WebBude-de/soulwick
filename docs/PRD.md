# PRD – Designziele und Spielregeln

> **Stand:** 22.10.2026 · **Gilt für:** das Spiel in diesem Repository; API, Website und Admin-Panel: `soulwick-platform/docs/PRD.md`.
> **Was hier steht:** Designziele, die Regeln des Spiels mit ihrem Grund und was bewusst nicht kommt (D-178). Was Soulwick ist und für wen: [PRODUKT.md](PRODUKT.md). Zahlen und Beschlüsse: [DECISIONS.md](DECISIONS.md). Was gebaut ist und mit welchen Werten: der Code (`*.tres`, Konstanten mit `TESTWERT`). Begriffe: [GLOSSAR.md](GLOSSAR.md).
> **Leseregel:** `TESTWERT` = vorläufige Zahl · `VORGESCHLAGEN` = braucht Bestätigung · `OFFEN` = nicht entschieden, nicht still festlegen.

## 1. Zweck

Ein wiederholbarer Kern-Loop (Dorf → Run → Rückkehr), dessen Kampf-, Upgrade- und Goldregeln eindeutig sind und der mit Inhalten (Räume, Gegner, Waffen, Modi) wächst, ohne dass der Kern neu gebaut wird.

## 2. Designziele

1. **Direkte Steuerung:** Bewegen, Zielen, Angreifen und Dash fühlen sich präzise an, mit Maus und Tastatur, Gamepad und Touch (D-012, D-155, D-163, D-168).
2. **Bedeutsame Run-Entscheidungen:** zwei Waffenslots, kombinierbare Upgrades, freiwillige Spezialräume und Abzweigungen; Gold ist eine Entscheidung (§4.6).
3. **Nachvollziehbare Regeln:** Schaden, Schild, Treffer und Gold folgen fester Rechenlogik (DECISIONS §6); die Anzeige zeigt dieselben Werte, mit denen gerechnet wird (D-034).
4. **Wiederverwendbarer Inhalt:** Räume, Gegner, Waffen und Modi sind Daten oder Szenen, kein Umbau des Kerns (D-045).
5. **Ein Raum, eine Aufgabe:** Jeder Raum ist in einem Satz erklärbar und kündigt sich an der Tür an (D-120, [RAEUME.md](RAEUME.md)).
6. **Koop von Anfang an mitgedacht:** Neuer Spielcode folgt den Leitplanken aus D-088 ([AGENTS.md](../AGENTS.md) §6).

## 3. Kern-Loop

**Vollversion (D-194, KONZEPT §1):** Dorf (ausgeben, umskillen) → Dungeon mit der eigenen Gefahrenstufe → tiefer oder durchs Seelentor raus → Gold, Kristalle, XP → Level, Rang, nächster Run. Bis der Umbau gebaut ist, gilt der heutige Ablauf: Im Dorf den Eingang benutzen → der Run beginnt ohne die Ausrüstung des letzten Runs, aber mit den Dorf-Verbesserungen → Räume im Fünferzyklus, alle 15 Räume ein Boss, danach Lagerfeuer und neues Biom (D-073, D-103) → per Portal aussteigen oder sterben → Gold und Kristalle im Dorf ausgeben → nächster Run.

## 4. Regeln und ihr Grund

### 4.1 Dungeon

- Der Fünferzyklus (Kampf, Kampf, Kampf mit Upgrade-Wahl, Spezialraum, Miniboss bzw. Boss) bleibt fest (D-002, D-003): Man weiß, wann die nächste Belohnung und die nächste Gefahr kommen.
- Der Dungeon endet nie (D-073); die Schwierigkeit steigt je Fünferblock (Werte in `enemies/enemy_scaling.gd`, D-074, D-154).
- Spezialräume sind freiwillig, Minispiele kosten bei Misserfolg nur den Bonus, nie den Run (D-005, D-120): Risiko ist eine Wahl, keine Falle.
- Ein Kampf beginnt erst beim Betreten und genau einmal; höchstens drei Räume leben gleichzeitig (D-007, D-008).

### 4.2 Gegner

- Gegner kündigen Angriffe an und kommen aus sichtbaren Quellen mit Warnung (D-021, D-132): Jeder Treffer soll vermeidbar sein.
- Dieselbe Angriffsinstanz trifft ein Ziel nur einmal (Hit-ID); allgemeine Unverwundbarkeit nach Treffern gibt es für Gegner nicht (D-020).
- Lieber viele schwache Gegner als wenige starke, auch von hinten (D-118, D-130): Im-Kreis-Weglaufen reicht nicht.

### 4.3 Spieler

- Herzen statt Zahlen: 1 Herz = 2 HP, Anzeige in halben Herzen, Start mit drei (D-013). Schaden ist auf einen Blick lesbar.
- Schild vor HP, ohne passive Regeneration, mit Softcap statt harter Grenze (D-014, D-074): stark, aber nicht unsterblich.
- Jeder wirksame Treffer gibt kurz Treffer-Unverwundbarkeit, Dash schützt unabhängig davon (D-016, D-017): keine Treffer-Ketten, keine geteilten Schutz-Timer.

### 4.4 Waffen

- Zwei Slots, eine aktive Waffe, kein Typ doppelt (D-022): Abwechslung statt Stapeln derselben Waffe.
- Seltenheit hat keine spielerische Wirkung (D-035). Waffen und Werte: `weapons/data/*.tres`.

### 4.5 Upgrades

- Upgrades gelten runweit und überstehen Waffenwechsel (D-027): Der Build gehört dem Spieler, nicht der Waffe.
- Sekundäreffekte lösen keine weiteren Sekundäreffekte aus; Kills daraus geben trotzdem ihre Belohnung (D-030 bis D-032): keine Endlosketten.
- Was nicht gilt (am Limit, schon im Besitz), wird weggelassen statt ersetzt (D-027, D-036): kein Scheinangebot.
- Liste und Werte: `upgrades/data/*.tres`. Neue Upgrade-Arten nur per Entscheidung (§6).

### 4.6 Gold und Run-Ende

- **Portal 100 %, Tod oder Abbruch 50 %** (aufgerundet), jeder Run wird genau einmal ausgezahlt (D-039, D-062). Grund: Weitergehen ist ein Risiko, ein Tod aber kein Totalverlust; das Portal ist die bewusste Entscheidung „jetzt sichern“. Die Folge steht an jeder dieser Entscheidungen im Spiel. **Vollversion:** Extraktion wird zur Wette – Tod 25 %, Seelentor spätestens jeden zweiten Zyklus, Tiefenbonus (Vorschlag, KONZEPT §2, Paket KE3).
- Käufe sind atomar: Gold weg und Ware da, oder nichts (D-038).
- Im Koop ist das Run-Gold eine gemeinsame Kasse; Waffen und Upgrades bleiben je Spieler (D-081).

### 4.7 Pause, Sprache, Speichern

- Im Einzelspiel pausieren Menüs die ganze Simulation (D-043); im Koop pausiert nichts, wer ein Menü offen hat, ist geschützt (D-085, D-123).
- Gespeichert werden nur dauerhafte Werte; ein Run wird nach einem Neustart nicht fortgesetzt (D-040).
- Alle Texte über Übersetzungsschlüssel, Englisch Standard, Deutsch zweite Sprache (D-111, [SPRACHEN.md](SPRACHEN.md)).

### 4.8 Dorf und Meta-Progression

- Das Dorf erklärt sich selbst: Jedes Gebäude sagt beim ersten Besuch in einem Satz, wofür es da ist; Verbesserungen zeigen konkrete Werte; Inhalte werden schrittweise freigeschaltet (D-087).
- Dorf-Boni gelten heute nur im Einzelspiel; im Koop starten alle ohne eigene Boni (D-081). **Vollversion (D-194):** Im Schnellen Spiel bringt jeder seinen Solo-Charakter mit, in Gilden-Runs spielt man einen eigenen Gilden-Charakter je Gilde; fair über die Gruppen-Gefahrenstufe (KONZEPT §9).
- Drei Säulen: Schmiede = Waffen und Ausrüstung (Gold), Handelsposten = Glück und Meta (Kristalle), Zuhause = Talentbaum (Level); die Schwierigkeit wächst mit Level und Können (Gefahrenstufe, Rang) (D-194).
- Das Dorf ist süß, gemütlich und lebendig, ein Ort zum Verschönern und Zeigen (D-174, D-175).

## 5. Abnahme

Ein Inhalt ist fertig, wenn er im Run vorkommt, die Regeln aus §4 einhält und mit Tests belegt ist ([AGENTS.md](../AGENTS.md) §6 Regel 8 und §7). Abgehakt wird in der jeweiligen Roadmap mit Datum.

## 6. Bewusst nicht vorgesehen

- Waffen-Seltenheiten mit spielerischer Wirkung (D-035).
- Neue Upgrade-Arten neben Attribut, Mechanik und Effekt ohne Entscheidung, insbesondere Feuer- oder Gift-Statussysteme (D-026).
- Rüstung, Resistenzen, kritische Treffer (D-019).
- Fortsetzen eines unterbrochenen Runs (D-040).
- Verkauf von Stärke, Gold oder Kristallen; Lootboxen (D-176).
- Endgültig ausbalancierte Zahlen: Alles bleibt `TESTWERT`, bis das Team es festlegt (D-064).

## 7. Ausbau

Plan der Vollversion: [ROADMAP.md](ROADMAP.md) (D-193). Konzept für Ungebautes: [KONZEPT.md](KONZEPT.md) (D-194).

- **7.1 Koop:** 2–4 Spieler mit Raumcode über den eigenen Relay; ein Spieler ist Host und rechnet die Welt, Spiellogik gibt es nur im Spiel (D-119). Mehr Gegner und HP je weiterem Spieler, Wiederbeleben durch Danebenstehen, jeder hat seinen Lichtkreis (D-084, D-126). Technik und Regeln für neuen Code: [MULTIPLAYER.md](MULTIPLAYER.md).
- **7.2 Gilden und Ranglisten:** Schnelles Spiel ohne Bindung oder Gilde (D-080, D-147); Ranglisten nach höchstem Raum, bei Gleichstand nach Zeit (D-082). Daten auf dem Server (`soulwick-platform`); das Spiel bleibt ohne Server spielbar (D-083).
- **7.3 Veröffentlichung:** gemeinsamer Release auf allen Versionen – Browser (kostenlos), Steam, Android und iOS – mit Crossplay über alle (D-108, D-176, D-179; ersetzt die Reihenfolge Steam → Android → iOS aus D-119). Plan: [ROADMAP.md](ROADMAP.md), Stores: [STORES.md](STORES.md), Builds: [RELEASE.md](RELEASE.md).

## 8. Begriffe der Regeln

Spielbegriffe stehen im [GLOSSAR.md](GLOSSAR.md); hier nur die technischen Begriffe der Regeln oben.

| Begriff | Bedeutung |
| --- | --- |
| **Resource** | typisierte Godot-Definition (`.tres`), nicht der Laufzeitzustand |
| **Hit-ID** | eindeutige Kennung einer Angriffsinstanz gegen Mehrfachtreffer |
| **I-Frames** | Zeitfenster, in dem normale Treffer blockiert sind |
| **Softcap** | verringerte Wirkung oberhalb einer Schwelle statt harter Obergrenze |
| **Primär-, Sekundäreffekt** | direkter Angriff bzw. Flächentreffer des Stabs; davon ausgelöster Zusatzeffekt ohne weitere Kette |
