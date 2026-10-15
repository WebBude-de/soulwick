# Konzept Räume v2 – klare Modi, mehr Varianz, lebendige Räume

> **Status:** FREIGEGEBEN (Projektmitglied, 14.10.2026, D-120): Modi-Liste, Abgrund als Raumart gestrichen, 30–40 % Minispiele, Koop-Ideen vormerken. Look und Grundrisse folgen aus Claude Design. Löst [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md) in den Raumarten und Modi ab (was dort weiter gilt, steht in dessen Status-Kasten). Die nächsten Schritte aus §9 sind erledigt: Design-Antwort in [design/claude_design_antwort/](design/claude_design_antwort/README.md), Briefing [SPRITES_V8](design/sprites/SPRITES_V8.md), Pakete der Phasen 2b und 2c in [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) (Stand 15.10.2026).
> **Anlass:** Playtest 14.10.2026. Die Balance passt, aber es macht noch nicht richtig Spaß: Räume sind leer und zufällig, die Modi sind unklar und überschneiden sich, man sieht nicht, woher Gegner kommen.
> **Arbeitsteilung:** Dieses Dokument legt das **Gameplay** fest (was passiert, Regeln, Ablauf). **Claude Design** entwirft den **Look** dazu: Grundrisse, Wände, Deko-Gruppen, Gegner-Auftritt, Türen, UI ([design/BRIEFING_RAEUME_V2.md](design/BRIEFING_RAEUME_V2.md)). Danach schneidet Claude daraus die Pakete der Phase 2b.

## 1. Leitlinien

1. **Ein Raum, eine Aufgabe, ein Satz.** Jeder Raum ist in einem Satz erklärbar („Bring den Dorfbewohner zum Ausgang“). Keine Mischformen, keine zwei Regeln gleichzeitig.
2. **Man sieht es vorher.** Schon an der Tür erkennt man die Raumart: eigenes Symbol, eigene Farbe, eigenes Licht durch den Spalt.
3. **Einführung immer gleich (Intro-Muster):** Tür zu → kurzer Kameraschwenk auf das Ziel (1,5 s) → großes Ziel-Banner mit Satz → Countdown 3-2-1 → los. Beim ersten Mal je Spielstand zusätzlich die Erklärkarte; später nur Banner und Countdown (ca. 2 s).
4. **Fortschritt ist immer sichtbar:** eine Aufgabenleiste oben in der Mitte (Wellen 2/3, Geleit 60 %, Fahne 1/2, Zeit 0:24). Ende mit deutlichem Erfolgs- oder Misserfolgs-Moment.
5. **Misserfolg kostet nie den Run**, nur den Bonus. Erfolg gibt immer etwas Sichtbares (Bonus-Truhe, Kristalle).
6. **Immer etwas los:** lieber viele schwache Gegner als einzelne. Gegner greifen auch von hinten an (Rudel, Flankieren), damit Im-Kreis-Weglaufen nicht reicht.
7. **Gegner kommen aus sichtbaren Quellen:** Nie einfach aufploppen. Je Biom eine Quelle (siehe §5), mit 1 s Warnung.
8. **Lebendige Räume:** handgebaute Grundrisse mit Varianten statt Rechteck + Zufallsstreuung; Deko in Gruppen mit kleiner Geschichte (Claude Design).
9. **Endlos-Rhythmus:** Die ersten Räume sind leicht, aber voll; neue Modi kommen schrittweise (einer je Zyklus neu), danach gemischt.

## 2. Die Raumarten auf einen Blick

| Gruppe | Raumart | Satz für den Spieler | Ab |
| --- | --- | --- | --- |
| **Kampf** | **Säubern** | „Besiege alle Gegner.“ | Raum 1 |
| | **Arena** | „Überlebe 3 Wellen.“ | kurz vor dem 1. Boss (Raum 11–14), danach regelmäßig |
| **Minispiele** | **Geleit** (Eskorte) | „Bring den verirrten Dorfbewohner sicher zum Ausgang.“ | Zyklus 2 |
| | **Flamme hüten** (Verteidigen) | „Halte die Seelenflamme 40 s am Leben.“ | Zyklus 2 |
| | **Reliquie holen** (Capture the Flag) | „Hol die Reliquie und bring sie zum Altar.“ | Zyklus 3 |
| | **Seelen sammeln** (Zeitdruck) | „Sammle 12 Seelen, bevor sie verlöschen.“ | Zyklus 3 |
| | **Risse schließen** (Zerstören) | „Zerstöre die Risse, aus denen Gegner kommen.“ | Zyklus 4 |
| | **Jagd** (Verfolgen) | „Fang den Gekrönten, bevor er entkommt.“ | Zyklus 4 |
| | **Lichtfeuer** (Licht) | „Entzünde alle Feuer – im Dunkeln sind die Wächter unbesiegbar.“ | 2. Biom |
| | **Einsturz** (Überleben) | „Überlebe, während der Boden einbricht.“ | 2. Biom |
| **Herausforderung** | **Wagnis** (Zusatz vor einem Kampfraum) | „Nimm eine Bedingung an für Kristalle.“ | Raum 6 |
| | **Elite-Nest** (nur über Abzweigung) | „Starke Elite-Gegner, große Belohnung.“ | Raum 6 |
| **Ruhe** | **Händler, Waffenkammer, Brunnen, Altar/Pakt** | keine Gegner | Platz 4 |
| | **Prüfung** (Parcours ohne Gegner) | „Lauf durch den Parcours zur Truhe.“ | Platz 4 |
| **Höhepunkte** | **Miniboss, Boss, Lagerfeuer** | wie bisher | Platz 5, jeder 15. Raum |
| **Geheimnis** | **Geheimnische** | rissige Wand sprengen | Raum 6 |

**Gestrichen oder umgebaut:**

| Bisher | Wird |
| --- | --- |
| Raumart **Abgrund** | entfällt als eigene Art. Abgründe werden Bauteil der Grundrisse (Brücken, Kanten zum Hineinstoßen) und Kern von **Einsturz** |
| **Hinterhalt** | entfällt; die Arena bekommt das Intro-Muster |
| **Katakombe** | wird ein Grundriss (Labyrinth), passend für **Jagd** und **Seelen sammeln** |
| **Laternenträger** | geht in **Reliquie holen** auf (gleiche Mechanik: Tragen, langsamer, kein Angriff) |
| **Steinwächter** | wird Gegner in **Lichtfeuer** |
| **Fackelraum** | wird **Lichtfeuer** |
| **Totengräber** | wird Gegner-Eigenschaft der Krypta (Skelette stehen einmal wieder auf), kein eigener Modus |
| **Kopfgeld** | wird **Jagd** |
| **Seelenflamme** | wird **Flamme hüten**, mit Intro |
| **Beschwörungsrisse** | wird **Risse schließen** |

## 3. Die Modi im Detail

Jeder Modus: Ablauf in drei Schritten, Sieg, Niederlage, Bonus, Koop (2–4 Spieler), Tür-Erkennung.

### 3.1 Säubern (Kampf-Grundraum)
- **Ablauf:** Raum betreten → Gegner kommen aus den Biom-Quellen (§5) in 1–2 Schüben → alle besiegt → Tür auf.
- **Gegner:** viele schwache plus wenige stärkere; Rudel-Verhalten (§6).
- **Bonus:** keiner (Gold der Gegner); gelegentlich eine Truhe in einer Nebennische des Grundrisses.
- **Tür:** normales Biom-Tor ohne Symbol.

### 3.2 Arena
- **Ablauf:** Tür fällt zu, Gitter schließen sich, Banner „Arena – 3 Wellen“, Countdown → Welle 1 aus den Wandtoren → nächste Welle erst, wenn die laufende leer ist (Pause 2 s mit Anzeige „Welle 2/3“) → nach der letzten Welle öffnet sich das Tor zur Belohnung.
- **Gegner:** nur aus Wandtoren (sichtbar, mit Warnung); deutlich mehr als im Säubern-Raum.
- **Bonus:** Bonus-Truhe.
- **Koop:** mehr Gegner je Welle.
- **Tür:** gekreuzte Schwerter, rotes Licht.

### 3.3 Geleit (Eskorte)
- **Figur:** ein verirrter Dorfbewohner mit kleiner Laterne (passt zum Licht-Thema und zum Dorf: Gerettete tauchen später im Dorf auf). Selten (ca. 5 %) stattdessen ein **Huhn** als süße Überraschung. Endgültige Figur und Look schlägt Claude Design vor.
- **Ablauf:** Die Figur läuft langsam einen sichtbaren Pfad vom Eingang zum Ausgang → Gegner greifen bevorzugt sie an → kommt sie an, ist der Raum geschafft.
- **Niederlage:** Figur fällt → Gegner bleiben, Raum normal säubern, kein Bonus.
- **Spieler-Mittel:** Die Figur bleibt stehen, wenn ein Gegner nah ist, und läuft weiter, wenn ein Spieler daneben steht.
- **Bonus:** Bonus-Truhe; der Gerettete erscheint im Dorf (Chronik-Eintrag).
- **Koop:** ein Spieler begleitet, die anderen räumen vor.
- **Tür:** Laternen-Figur-Symbol, warmes Licht.

### 3.4 Flamme hüten (Verteidigen)
- **Ablauf:** Intro schwenkt auf die Flamme in der Raummitte, Banner „Halte die Flamme 40 s“ → Gegner kommen in kurzen Schüben und greifen die Flamme an, Leiste zeigt Flammen-HP und Zeit → nach 40 s erlöschen die Quellen, Rest besiegen.
- **Niederlage:** Flamme erlischt → Raum wird dunkler, kein Bonus.
- **Bonus:** Bonus-Truhe; volle Flamme = zusätzlich 1 Kristall.
- **Tür:** Flammen-Symbol, bläuliches Licht.

### 3.5 Reliquie holen (Capture the Flag)
- **Ablauf:** Reliquie (Banner, Laterne oder Schädel je Biom) liegt am anderen Ende, bewacht → aufnehmen mit E (Träger langsamer, kein Angriff, Dash geht) → zum Altar am Eingang bringen. Bei Treffer fällt sie hin.
- **Gegner:** jagen den Träger, kommen von hinten.
- **Varianten:** ab Zyklus 6 zwei Reliquien.
- **Bonus:** Bonus-Truhe.
- **Koop:** Träger plus Beschützer; Übergeben möglich.
- **Tür:** Banner-Symbol.

### 3.6 Seelen sammeln (Zeitdruck)
- **Ablauf:** Seelen-Lichter erscheinen nacheinander an Plätzen im Raum (je 6 s sichtbar) → 12 einsammeln in 45 s, während Gegner nachkommen → Leiste zählt mit.
- **Niederlage:** Zeit vorbei → Rest-Gegner besiegen, kein Bonus.
- **Grundriss:** gern Labyrinth (Katakombe).
- **Bonus:** Kristalle nach Anzahl.
- **Tür:** Seelen-Symbol, türkis.

### 3.7 Risse schließen (Zerstören)
- **Ablauf:** 2–3 Risse in den Wänden spucken Gegner aus → Risse haben HP-Leisten und sind die eigentlichen Ziele → alle Risse zu, Rest besiegen.
- **Bonus:** Bonus-Truhe; schnell = Kristall.
- **Tür:** Riss-Symbol, grün.

### 3.8 Jagd (Verfolgen)
- **Ablauf:** Ein Gekrönter mit Beute sieht den Spieler und flieht zu einem Fluchtloch, das sich langsam öffnet (Zeitanzeige) → fangen, bevor er hineinspringt; Wachen stellen sich in den Weg.
- **Niederlage:** Er entkommt (ohne Beute), Rest normal.
- **Bonus:** seine Beute (viel Gold, gelegentlich ein Upgrade).
- **Tür:** Kronen-Symbol.

### 3.9 Lichtfeuer (Licht)
- **Ablauf:** dunkler Raum, 4–6 Feuerschalen → anzünden mit Treffer oder E → Steinwächter rücken im Dunkeln vor und sind nur im Licht verwundbar.
- **Sieg:** alle Feuer brennen und alle Wächter zerschlagen.
- **Bonus:** Bonus-Truhe.
- **Tür:** Feuerschalen-Symbol, sehr dunkler Spalt.

### 3.10 Einsturz (Überleben)
- **Ablauf:** Banner „Der Boden bricht – überlebe 30 s“ → der Boden bricht in sichtbar markierten Feldern nach und nach ein (Warnung 1 s, Risse), Gegner fallen mit → nach 30 s steht nur noch ein Rest-Weg zum Ausgang.
- **Gefahr:** Fallen kostet ein Herz (wie bisher). Gegner kann man in Löcher stoßen.
- **Bonus:** Bonus-Truhe am Ende des Rest-Wegs.
- **Tür:** Riss-im-Boden-Symbol.

### 3.11 Nur im Koop (vorgemerkt für MP5, nicht jetzt bauen)

Räume, die nur mit 2–4 Spielern gezogen werden; im Einzelspiel nie.

- **Doppelgänger:** Ein Mitspieler sieht für die anderen wie ein Gegner aus; wer ihn trifft, verliert den Bonus. Er muss sich durch eine Geste (Emote) oder durch das Aufheben eines Lichts zu erkennen geben.
- **Staffel:** Die Reliquie muss durch die Hände aller Spieler gehen, bevor sie auf den Altar darf.
- **Geteiltes Licht:** Nur ein Spieler trägt Licht; die anderen sehen nur in seiner Nähe und müssen zusammenbleiben.
- **Zwei Schalter:** Zwei Altäre an entgegengesetzten Enden müssen gleichzeitig gehalten werden, während Gegner beide Seiten angreifen.
- **Wettstreit:** Wer sammelt in 30 s die meisten Seelen? Der Gewinner wählt zuerst die Belohnung (freundlich, kein Schaden zwischen Spielern).
- **Rettung:** Ein Spieler wird zu Beginn gefangen (Käfig); die anderen müssen den Schlüssel holen.

## 4. Zyklus-Rhythmus und Häufigkeiten (TESTWERTE)

Ein Zyklus hat weiter 5 Plätze: 1 Kampf · 2 Kampf · 3 Kampf + Upgrade · 4 Ruhe/Prüfung · 5 Miniboss; jeder 15. Raum Boss, danach Lagerfeuer.

| Platz | Zyklus 1 (Raum 1–5) | ab Zyklus 2 |
| --- | --- | --- |
| 1 | Säubern | Säubern |
| 2 | Säubern | Säubern oder Minispiel |
| 3 | Säubern (mit Upgrade) | Säubern, Arena (ab Raum 11) oder Minispiel |
| 4 | Ruhe | Ruhe / Prüfung |
| 5 | Miniboss | Miniboss |

- **Anteil (freigegeben):** hauptsächlich Kämpfen; **30–40 % der Kampfräume ab Zyklus 2 sind Minispiele** (TESTWERT 35 %), verteilt auf die Plätze 1–3, höchstens 2 je Zyklus.
- **Neue Modi:** jeder Modus erscheint zum ersten Mal an einem festen Punkt (Tabelle §2), danach zufällig; nie zweimal derselbe Modus hintereinander, kein Modus zweimal im selben Zyklus.
- **Arena:** höchstens eine je Zyklus, erstmals Raum 11–14.
- **Abzweigung** (ab Raum 6, höchstens 1 je Zyklus): zwei Türen mit sichtbarem Modus-Symbol. Der Spieler wählt zwischen zwei Modi (z. B. Jagd oder Geleit) oder Elite-Nest gegen sicheren Weg. Beide Räume sind schon da und liegen im Dunkeln; nichts ploppt auf.

## 5. Woher die Gegner kommen

| Biom | Quelle im Boden/Raum | Auftritt (Warnung 1 s) |
| --- | --- | --- |
| Krypta | Gräber, Sarkophage | Erde bricht auf, Hand greift heraus, Skelett steigt hoch |
| Schleimgrotte | Schleimpfützen | Pfütze blubbert, Schleim springt heraus |
| Schattenreich | Schattenrisse am Boden | Riss leuchtet, Gestalt zieht sich hoch |
| Glutkammer | Lava-Spalten | Glut glüht auf, Gegner steigt aus der Glut |
| **Arena (alle)** | Wandtore | Gitter hebt sich, Gegner tritt heraus |

Quellen sind feste Teile des Grundrisses (nicht zufällig), meist an den Rändern und **hinter** dem Spieler, damit man nicht nur nach vorn kämpft. Die bisherigen Spawnpunkte werden zu diesen Quellen.

## 6. Gegner-Verhalten (mehr los, von hinten)

- **Mehr, aber schwächere Gegner:** ca. 1,5–2× so viele je Raum, einzeln schwächer; die ersten Räume leicht (Balance-Agent misst, D-118).
- **Slime-Bande:** Slimes springen in kleinen Rudeln (3–5) im Takt hintereinander, kreisen den Spieler ein und landen auch hinter ihm.
- **Flankieren:** Nahkämpfer verteilen sich auf mehrere Seiten statt hintereinander herzulaufen; ein Teil schneidet den Weg ab.
- **Fernkämpfer** halten Abstand und wechseln die Seite.
- Ziel: Im-Kreis-Weglaufen funktioniert nicht mehr, man muss sich stellen.

## 7. Was bleibt aus v1

- Ruhe-Räume (Händler, Waffenkammer, Brunnen, Altar/Pakt), Prüfungen, Miniboss, Boss, Lagerfeuer, Geheimnische, Wagnis, Elite-Nest: bleiben, bekommen das Intro-Muster, Tür-Erkennung und neue Grundrisse.
- Wegführung (Ausgänge an allen Seiten, Abzweigungen): bleibt; Abzweigungen zeigen künftig Modus-Symbole.

## 8. Entscheidungen des Projektmitglieds (14.10.2026)

1. Modi-Liste passt.
2. Eskorte: Huhn war nur eine Idee; passender ist z. B. ein Bewohner → verirrter Dorfbewohner, Huhn als seltene Überraschung; Claude Design darf Besseres vorschlagen.
3. Hauptsächlich Kämpfen, 30–40 % Minispiele.
4. Abgrund als eigene Raumart gestrichen.
5. Koop-exklusive Ideen vormerken (§3.11).

## 9. Nächste Schritte

1. Projektmitglied gibt dieses Konzept frei (oder ändert es).
2. Claude Design entwirft dazu den Look (Briefing §4) → Ablage in `docs/design/claude_design_antwort/`.
3. Claude macht daraus `SPRITES_V8.md`, D-Einträge und die Pakete der Phase 2b (u. a. Wand-System, Grundrisse und Deko, Gegner-Quellen, Intro-Muster und Aufgabenleiste, je Modus ein Paket, Gegner-Verhalten, Türen, Dorf, UI).
